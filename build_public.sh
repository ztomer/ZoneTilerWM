#!/usr/bin/env bash
# build_public.sh — RELEASE build for direct (non-App-Store) distribution.
#
# Compiles in the private-API features (ZT_PRIVATE_APIS) so power users CAN opt into them, but they
# are OFF BY DEFAULT at runtime: real macOS Spaces require `[ui] experimental_real_spaces = true` in
# config. The SkyLight border + AX SPI are active (this build is not for the App Store anyway, so the
# more reliable private paths are used).
#
# NOT App-Store-safe — links private CGS/AX symbols. Use build_mas.sh for App Store.
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ build_public — release + ZT_PRIVATE_APIS (experimental private features available, OFF by default)"
swift build -c release -Xswiftc -DZT_PRIVATE_APIS "$@"
echo "✓ built .build/release/zt-agent   (NOT for the Mac App Store)"
