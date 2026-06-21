#!/usr/bin/env bash
# package_app.sh — shared core for the three .app package builders (package_dev/mas/public.sh).
# Builds ZoneTilerWM.app for one VARIANT, threading the ZT_PRIVATE_APIS gate correctly into BOTH the
# SwiftPM package targets (via the ZT_PRIVATE_APIS env var → Package.swift) and the app target.
#
# Don't call this directly — use:
#   ./package_dev.sh      debug, private APIs ON, dev-signed, arm64 (fast local install)
#   ./package_public.sh   release, private APIs ON (off by default at runtime), universal, zipped
#   ./package_mas.sh      release, NO private APIs (verified MAS-clean), universal, zipped
#
# Inputs (env): ZT_VARIANT=dev|mas|public (required), ZT_VERSION (default = project.yml),
#               ZT_SIGN_ID (default "ZoneTilerWM Dev"; "-" forces ad-hoc), ZT_SKIP_TESTS=1 to skip.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
export PATH="/opt/homebrew/bin:$PATH"

VARIANT="${ZT_VARIANT:?set ZT_VARIANT=dev|mas|public (use package_dev/mas/public.sh)}"
DEFAULT_VERSION="$(awk -F'"' '/MARKETING_VERSION:/{print $2; exit}' project.yml)"
VERSION="${ZT_VERSION:-${DEFAULT_VERSION:-0.0.0}}"

command -v xcodegen >/dev/null || { echo "error: xcodegen not found (brew install xcodegen)" >&2; exit 1; }

# --- per-variant matrix -----------------------------------------------------------------------------
case "$VARIANT" in
  dev)    CONFIG=Debug;   PRIVATE=1; ARCHS="arm64";          UNIVERSAL=0; LEAKGUARD=0; ZIP=0 ;;
  public) CONFIG=Release; PRIVATE=1; ARCHS="arm64 x86_64";   UNIVERSAL=1; LEAKGUARD=0; ZIP=1 ;;
  mas)    CONFIG=Release; PRIVATE=0; ARCHS="arm64 x86_64";   UNIVERSAL=1; LEAKGUARD=1; ZIP=1 ;;
  *) echo "error: ZT_VARIANT must be dev|mas|public (got '$VARIANT')" >&2; exit 1 ;;
esac

# The private-API gate. Setting ZT_PRIVATE_APIS makes Package.swift add `-DZT_PRIVATE_APIS` to the
# package targets (ZTSystem) when xcodebuild / swift build evaluate the manifest. mas leaves it unset.
SWIFTPM_PRIVATE=""           # extra flags for the helper-tool swift builds
APP_PRIVATE_FLAGS=""         # OTHER_SWIFT_FLAGS for the app target (future-proof; zt-agent has no #if yet)
if [ "$PRIVATE" = "1" ]; then
  export ZT_PRIVATE_APIS=1
  SWIFTPM_PRIVATE="-Xswiftc -DZT_PRIVATE_APIS"
  APP_PRIVATE_FLAGS="-D ZT_PRIVATE_APIS"
else
  unset ZT_PRIVATE_APIS || true
fi

BUILD_ROOT="/tmp/ZoneTilerWM/$VARIANT"   # per-variant DerivedData so the SwiftPM manifest cache can't cross variants
DERIVED="$BUILD_ROOT/DerivedData"
APP="$DERIVED/Build/Products/$CONFIG/ZoneTilerWM.app"
OUT="$BUILD_ROOT/dist"
STAGE="$BUILD_ROOT/stage/ZoneTilerWM-$VERSION"
ZIPF="$OUT/ZoneTilerWM-$VERSION-$VARIANT.zip"

echo "▶ package $VARIANT — $CONFIG, private-APIs=$PRIVATE, archs=[$ARCHS], v$VERSION"

# --- signing identity (mirrors build_package.sh) ----------------------------------------------------
SIGN_ID="${ZT_SIGN_ID:-ZoneTilerWM Dev}"
if [ "$SIGN_ID" = "-" ]; then
  echo "==> Signing ad-hoc"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
  echo "==> Signing with: $SIGN_ID"
else
  echo "==> Identity '$SIGN_ID' not found — falling back to ad-hoc"
  SIGN_ID="-"
fi

# --- tests (skippable for fast dev iteration) -------------------------------------------------------
if [ "${ZT_SKIP_TESTS:-0}" = "1" ] || [ "$VARIANT" = "dev" ]; then
  echo "==> Skipping tests (dev / ZT_SKIP_TESTS)"
else
  echo "==> Tests"
  make verify
fi

echo "==> xcodegen generate"
xcodegen generate

echo "==> xcodebuild ($CONFIG)"
ARCH_ARGS=()
[ "$UNIVERSAL" = "1" ] && ARCH_ARGS=(ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
xcodebuild -project ZoneTilerWM.xcodeproj -scheme ZoneTilerWM \
  -configuration "$CONFIG" -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" \
  ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} \
  OTHER_SWIFT_FLAGS="\$(inherited) $APP_PRIVATE_FLAGS" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_ID" \
  build

[ -d "$APP" ] || { echo "error: build did not produce $APP" >&2; exit 1; }

# --- bundle the helper tools (zt-mcp, zonetiler-cli) inside the .app --------------------------------
# (SwiftPM products, not built by xcodebuild — build them at the same arch/flags and copy in.)
echo "==> Bundling helpers (zt-mcp, zonetiler-cli)"
HELPER_ARCH=()
[ "$UNIVERSAL" = "1" ] && HELPER_ARCH=(--arch arm64 --arch x86_64)
HELPER_CONFIG="release"; [ "$CONFIG" = "Debug" ] && HELPER_CONFIG="debug"
# shellcheck disable=SC2086
swift build -c "$HELPER_CONFIG" ${HELPER_ARCH[@]+"${HELPER_ARCH[@]}"} $SWIFTPM_PRIVATE --product zt-mcp
# shellcheck disable=SC2086
swift build -c "$HELPER_CONFIG" ${HELPER_ARCH[@]+"${HELPER_ARCH[@]}"} $SWIFTPM_PRIVATE --product zonetiler-cli
# shellcheck disable=SC2086
HELPER_BIN="$(swift build -c "$HELPER_CONFIG" ${HELPER_ARCH[@]+"${HELPER_ARCH[@]}"} --show-bin-path)"
ditto "$HELPER_BIN/zt-mcp" "$APP/Contents/MacOS/zt-mcp"
ditto "$HELPER_BIN/zonetiler-cli" "$APP/Contents/MacOS/zonetiler-cli"
codesign --force --sign "$SIGN_ID" "$APP/Contents/MacOS/zt-mcp"
codesign --force --sign "$SIGN_ID" "$APP/Contents/MacOS/zonetiler-cli"
codesign --force --sign "$SIGN_ID" "$APP"   # re-sign the bundle to cover the added binaries

BINARIES=("$APP/Contents/MacOS/ZoneTilerWM" "$APP/Contents/MacOS/zt-mcp" "$APP/Contents/MacOS/zonetiler-cli")

# --- MAS leak guard: fail loudly if any private symbol slipped into a strict build ------------------
if [ "$LEAKGUARD" = "1" ]; then
  echo "==> MAS leak guard (no private CGS/AX symbols)"
  for b in "${BINARIES[@]}"; do
    LEAKS="$(nm "$b" 2>/dev/null | grep -E "_CGSDefaultConnection|CGSCopyManagedDisplaySpaces|_AXUIElementGetWindow" || true)"
    if [ -n "$LEAKS" ]; then
      echo "✗ ERROR: private symbols in $(basename "$b") — NOT MAS-clean:" >&2; echo "$LEAKS" >&2; exit 1
    fi
  done
  echo "    ✓ no private symbols linked"
fi

# --- universal slice check (release variants) -------------------------------------------------------
if [ "$UNIVERSAL" = "1" ]; then
  echo "==> Verifying universal slices (lipo)"
  for b in "${BINARIES[@]}"; do
    archs="$(lipo -archs "$b" 2>/dev/null || true)"
    case "$archs" in
      *arm64*x86_64* | *x86_64*arm64*) echo "    $(basename "$b"): $archs" ;;
      *) echo "error: $(basename "$b") is not universal (got '$archs')" >&2; exit 1 ;;
    esac
  done
fi

# --- stage, then emit zip and/or dmg ----------------------------------------------------------------
# ZT_DMG=1 also builds a drag-to-Applications .dmg (the friendly hand-off format; works for any
# variant). Unsigned/ad-hoc builds are still Gatekeeper-quarantined on another Mac — the INSTALL note
# spells out the one-time right-click->Open / xattr step, since we have no Apple notarization (§B).
DMG="${ZT_DMG:-0}"
DMGF="$OUT/ZoneTilerWM-$VERSION-$VARIANT.dmg"
if [ "$ZIP" = "1" ] || [ "$DMG" = "1" ]; then
  echo "==> Staging"
  rm -rf "$STAGE"; mkdir -p "$STAGE" "$OUT"
  ditto "$APP" "$STAGE/ZoneTilerWM.app"
  {
    echo "ZoneTilerWM $VERSION ($VARIANT build)"
    echo "Menu-bar tiling window manager for macOS 13+. No Dock icon."
    echo
    echo "Install: drag ZoneTilerWM.app onto the Applications folder."
    echo
    echo "First launch (this build is NOT notarized, so Gatekeeper blocks a plain double-click):"
    echo "  - Right-click ZoneTilerWM.app -> Open -> Open  (only needed the first time), OR"
    echo "  - run once:  xattr -dr com.apple.quarantine /Applications/ZoneTilerWM.app"
    echo
    echo "Then launch it and follow the welcome window to grant Accessibility"
    echo "(System Settings -> Privacy & Security -> Accessibility). Window tiling enables itself the"
    echo "moment the toggle flips — no relaunch needed."
    if [ "$VARIANT" = "public" ]; then
      echo
      echo "Experimental real macOS Spaces (private APIs) are compiled in but OFF by default —"
      echo "enable with [ui] experimental_real_spaces = true in ~/.config/ZoneTilerWM/config.toml."
    fi
  } > "$STAGE/INSTALL.txt"
fi
if [ "$ZIP" = "1" ]; then
  echo "==> Zipping"
  rm -f "$ZIPF"
  ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$ZIPF"
fi
if [ "$DMG" = "1" ]; then
  echo "==> Building DMG (hdiutil)"
  ln -sfn /Applications "$STAGE/Applications"   # drag-to-install target (added after the zip)
  rm -f "$DMGF"
  hdiutil create -volname "ZoneTilerWM $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMGF" >/dev/null
fi

echo "==> Done ($VARIANT)"
echo "    app: $APP"
[ "$ZIP" = "1" ] && echo "    zip: $ZIPF"
[ "$DMG" = "1" ] && echo "    dmg: $DMGF"
if [ "$VARIANT" = "mas" ]; then
  echo
  echo "NOTE: this is a verified MAS-CLEAN build, but a real App Store SUBMISSION still needs an Apple"
  echo "Developer account: App Sandbox + entitlements (Accessibility, Apple Events), an Apple"
  echo "Distribution signing identity + provisioning, and notarization. Deferred (ROADMAP §B)."
fi
