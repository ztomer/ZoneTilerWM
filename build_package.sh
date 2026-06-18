#!/usr/bin/env bash
# build_package.sh — build ZoneTilerWM.app (Release, ad-hoc signed) and package it as a
# distributable zip. The local equivalent of .github/workflows/release.yml.
#
#   ./build_package.sh [version]
#
# version defaults to the MARKETING_VERSION in project.yml (1.3.1). Build artifacts + the zip
# go to /tmp/ZoneTilerWM (kept out of the project tree). Requires xcodegen + Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
export PATH="/opt/homebrew/bin:$PATH"

# Default to the MARKETING_VERSION declared in project.yml (single source of truth), so this
# never goes stale when the version is bumped. Override by passing a version argument.
DEFAULT_VERSION="$(awk -F'"' '/MARKETING_VERSION:/{print $2; exit}' project.yml)"
VERSION="${1:-${DEFAULT_VERSION:-1.3.1}}"
BUILD_ROOT="/tmp/ZoneTilerWM"
DERIVED="$BUILD_ROOT/DerivedData"
APP="$DERIVED/Build/Products/Release/ZoneTilerWM.app"
OUT="$BUILD_ROOT/dist"
STAGE="$BUILD_ROOT/stage/ZoneTilerWM-$VERSION"
ZIP="$OUT/ZoneTilerWM-$VERSION.zip"

command -v xcodegen >/dev/null || { echo "error: xcodegen not found (brew install xcodegen)"; exit 1; }

# Stable local signing identity. macOS keys the Accessibility (TCC) grant to the app's code
# signature; ad-hoc signing ("-") gets a fresh hash every build, so the grant resets on every
# rebuild. Signing with a fixed self-signed cert keeps the designated requirement stable, so the
# grant survives rebuilds. Falls back to ad-hoc on a machine/CI that lacks the cert.
# (Create it once — see docs/DEV_SIGNING.md.)
SIGN_ID="${ZT_SIGN_ID:-ZoneTilerWM Dev}"
if [ "$SIGN_ID" = "-" ]; then
  echo "==> Signing ad-hoc (distributable build — see build_dist.sh)"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
  echo "==> Signing with stable identity: $SIGN_ID"
else
  echo "==> Identity '$SIGN_ID' not found — falling back to ad-hoc (grant resets on rebuild)"
  SIGN_ID="-"
fi

echo "==> Tests"
make verify

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building ZoneTilerWM.app (Release, version $VERSION)"
xcodebuild -project ZoneTilerWM.xcodeproj -scheme ZoneTilerWM \
  -configuration Release -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_ID" \
  build

[ -d "$APP" ] || { echo "error: build did not produce $APP"; exit 1; }

echo "==> Staging app + INSTALL.txt"
rm -rf "$STAGE"; mkdir -p "$STAGE" "$OUT"
# ditto (not cp) so the bundle's symlinks / resource forks / signature stay intact.
ditto "$APP" "$STAGE/ZoneTilerWM.app"
cat > "$STAGE/INSTALL.txt" <<EOF
ZoneTilerWM $VERSION — Installation
$(printf '=%.0s' {1..40})

ZoneTilerWM is a menu-bar tiling window manager for macOS (Apple Silicon,
macOS 13 Ventura or newer). It has no Dock icon and no main window — once
running it lives in the menu bar.

Install
-------
1. Unzip this archive (done — that's how you're reading this).
2. Drag ZoneTilerWM.app into /Applications.
3. This build is not notarized by Apple, so clear the Gatekeeper quarantine
   once. In Terminal:
       xattr -dr com.apple.quarantine /Applications/ZoneTilerWM.app
   (Or: double-click the app, let macOS block it, then open
    System Settings -> Privacy & Security and click "Open Anyway".)
4. Launch ZoneTilerWM from /Applications — look for its icon in the menu bar.
5. Grant Accessibility when prompted (needed to move other apps' windows):
   "Open System Settings" -> Privacy & Security -> Accessibility -> toggle
   ZoneTilerWM on. If the prompt doesn't close after granting, quit it from
   the menu bar and relaunch once.

Troubleshooting: Accessibility granted but windows won't move
-------------------------------------------------------------
If ZoneTilerWM is toggled ON under Privacy & Security -> Accessibility but it
still can't move windows (most common right after installing a NEW version):
   1. In that Accessibility list, select ZoneTilerWM and click the "-" button
      to remove the entry.
   2. Re-add it with "+" (choose /Applications/ZoneTilerWM.app), or just
      relaunch the app and grant again when prompted. Make sure it's toggled ON.
   3. Quit ZoneTilerWM from the menu bar and relaunch once.

Why: macOS ties the Accessibility grant to the app's exact CODE SIGNATURE, not
just its name. These builds are ad-hoc signed, so each new build has a different
signature. When you replace the app with a newer build, the old grant is bound
to the previous signature and no longer matches the running app — the toggle can
even still LOOK on while doing nothing. Removing and re-adding rebinds the grant
to the current build's signature.

Using it
--------
- <modifier>+<zone key> tiles the focused window into a zone.
- HYPER+Return auto-tiles the whole screen.
- Open Settings from the menu-bar icon to view and customize zones, keys, and
  the learned per-app layout memory. Edits to the config live-reload.

Uninstall
---------
Quit from the menu bar, then drag /Applications/ZoneTilerWM.app to the Trash.
EOF

echo "==> Packaging $ZIP"
rm -f "$ZIP"
# Zip the staging folder (app + INSTALL.txt). --keepParent puts everything under one
# ZoneTilerWM-$VERSION/ directory; ditto preserves the bundle's signature/symlinks.
ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$ZIP"

echo "==> Done"
echo "    app: $APP"
echo "    zip: $ZIP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Authority|Signature" | sed 's/^/    /' || true
echo
echo "Locally self-signed (not Developer ID): on another Mac the user right-clicks -> Open the"
echo "first time, then grants Accessibility in System Settings -> Privacy & Security -> Accessibility."
