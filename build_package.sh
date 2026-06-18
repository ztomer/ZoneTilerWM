#!/usr/bin/env bash
# build_package.sh — build ZoneTilerWM.app (Release, ad-hoc signed) and package it as a
# distributable zip. The local equivalent of .github/workflows/release.yml.
#
#   ./build_package.sh [version]
#
# version defaults to the MARKETING_VERSION in project.yml (1.0.0). Build artifacts + the zip
# go to /tmp/ZoneTilerWM (kept out of the project tree). Requires xcodegen + Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
export PATH="/opt/homebrew/bin:$PATH"

VERSION="${1:-1.0.0}"
BUILD_ROOT="/tmp/ZoneTilerWM"
DERIVED="$BUILD_ROOT/DerivedData"
APP="$DERIVED/Build/Products/Release/ZoneTilerWM.app"
OUT="$BUILD_ROOT/dist"
ZIP="$OUT/ZoneTilerWM-$VERSION.zip"

command -v xcodegen >/dev/null || { echo "error: xcodegen not found (brew install xcodegen)"; exit 1; }

# Stable local signing identity. macOS keys the Accessibility (TCC) grant to the app's code
# signature; ad-hoc signing ("-") gets a fresh hash every build, so the grant resets on every
# rebuild. Signing with a fixed self-signed cert keeps the designated requirement stable, so the
# grant survives rebuilds. Falls back to ad-hoc on a machine/CI that lacks the cert.
# (Create it once — see docs/DEV_SIGNING.md.)
SIGN_ID="${ZT_SIGN_ID:-ZoneTilerWM Dev}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
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

echo "==> Packaging $ZIP"
mkdir -p "$OUT"
rm -f "$ZIP"
# ditto preserves the bundle's symlinks / resource forks / signature (a plain zip can corrupt it).
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Done"
echo "    app: $APP"
echo "    zip: $ZIP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Authority|Signature" | sed 's/^/    /' || true
echo
echo "Locally self-signed (not Developer ID): on another Mac the user right-clicks -> Open the"
echo "first time, then grants Accessibility in System Settings -> Privacy & Security -> Accessibility."
