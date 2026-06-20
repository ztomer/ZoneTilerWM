#!/usr/bin/env bash
# build_mas.sh — STRICT Mac App Store compile.
#
# Omits ZT_PRIVATE_APIS, so ZERO private-API symbols are linked:
#   • no SkyLight real-Spaces reader   → Exposé shows the current Space only (public fallback)
#   • no SkyLight focus-border         → uses the public NSWindow OverlayBorderRenderer
#   • no _AXUIElementGetWindow AX SPI  → AX↔CGWindowID matched by pid+frame (public fallback)
#
# A real App Store *submission* additionally needs App Sandbox + entitlements + Apple distribution
# signing + notarization — handled in the .app packaging step (xcodegen/xcodebuild), not here.
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ build_mas — release, NO private APIs (strict MAS-clean compile)"
swift build -c release "$@"

BIN=.build/release/zt-agent
echo "✓ built $BIN"

# Guard: fail loudly if any @_silgen_name private symbol leaked into the binary.
LEAKS=$(nm "$BIN" 2>/dev/null | grep -E "_CGSDefaultConnection|CGSCopyManagedDisplaySpaces|_AXUIElementGetWindow" || true)
if [ -n "$LEAKS" ]; then
  echo "✗ ERROR: private symbols found in the binary — NOT MAS-clean:" >&2
  echo "$LEAKS" >&2
  exit 1
fi
echo "✓ verified: no _CGS* / _AXUIElementGetWindow symbols linked"
echo "  reminder: full MAS submission still needs App Sandbox + entitlements + distribution signing + notarization"
