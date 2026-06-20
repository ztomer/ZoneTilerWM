#!/usr/bin/env bash
# build_dev.sh — DEBUG build for development.
#
# Compiles in the private-API code (ZT_PRIVATE_APIS): the SkyLight real-Spaces reader, the SkyLight
# focus-border renderer, and the _AXUIElementGetWindow AX SPI. The real-Spaces FEATURE is still gated
# at RUNTIME by `[ui] experimental_real_spaces` in config (default off) — set it to true to use it.
#
# NOT App-Store-safe (links private symbols). See build_mas.sh for the strict-MAS build.
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ build_dev — debug + ZT_PRIVATE_APIS (private APIs compiled in; real-Spaces still runtime-gated)"
swift build -Xswiftc -DZT_PRIVATE_APIS "$@"
echo "✓ built .build/debug/zt-agent"
