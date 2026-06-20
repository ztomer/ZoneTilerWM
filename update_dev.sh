#!/usr/bin/env bash
# update_dev.sh — rebuild the DEV .app (package_dev.sh) and (re)install it into /Applications,
# overwriting any existing copy. The quick "rebuild + reinstall locally" loop. Args pass through to
# package_dev.sh (e.g. ZT_VERSION=…). Dev variant is dev-signed (keeps the Accessibility grant) and
# links private APIs — NOT App-Store-safe.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# Where package_dev.sh leaves the bundle (Debug DerivedData; see package_app.sh: BUILD_ROOT/DERIVED).
APP_SRC="/tmp/ZoneTilerWM/dev/DerivedData/Build/Products/Debug/ZoneTilerWM.app"
DEST="/Applications/ZoneTilerWM.app"

echo "→ building dev .app (package_dev.sh)"
"$ROOT/package_dev.sh" "$@"

[ -d "$APP_SRC" ] || { echo "✗ dev .app not found at $APP_SRC" >&2; exit 1; }

# Quit a running installed copy so we can overwrite cleanly (ignore if it isn't running).
echo "→ quitting any running /Applications copy"
osascript -e 'tell application "ZoneTilerWM" to quit' >/dev/null 2>&1 || true
pkill -f "/Applications/ZoneTilerWM.app/Contents/MacOS/ZoneTilerWM" 2>/dev/null || true
sleep 1

echo "→ installing → $DEST (overwriting)"
rm -rf "$DEST"
ditto "$APP_SRC" "$DEST"

echo "✓ installed $DEST"
echo "  (first run only, if Gatekeeper complains: xattr -dr com.apple.quarantine \"$DEST\")"
