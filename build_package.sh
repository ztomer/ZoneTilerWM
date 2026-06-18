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

echo "==> Tests"
make verify

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building ZoneTilerWM.app (Release, version $VERSION)"
xcodebuild -project ZoneTilerWM.xcodeproj -scheme ZoneTilerWM \
  -configuration Release -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" \
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
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Signature" | sed 's/^/    /' || true
echo
echo "Ad-hoc signed: on another Mac, the user right-clicks the app -> Open the first time,"
echo "then grants Accessibility in System Settings -> Privacy & Security -> Accessibility."
