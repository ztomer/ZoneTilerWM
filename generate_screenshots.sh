#!/usr/bin/env bash
# generate_screenshots.sh — build and render all settings tabs to PNG for visual QA.
set -euo pipefail
cd "$(dirname "$0")"

echo "Building zt-agent..."
swift build

OUT_DIR="/Users/ztomer/.gemini/antigravity/brain/f1789969-f518-4101-ac66-5631a66e1ec4/screenshots"
mkdir -p "$OUT_DIR"

TABS=(
  "general"
  "tiling"
  "layouts"
  "previews"
  "keys"
  "io"
  "apps"
  "pomodoro"
  "appearance"
  "automation"
  "advanced"
  "icons"
)

for tab in "${TABS[@]}"; do
  echo "Rendering settings tab: $tab -> ${OUT_DIR}/${tab}.png"
  # Run the debug agent in UI render mode. It will write the PNG and exit immediately (0).
  ZT_RENDER_UI="${tab}:${OUT_DIR}/${tab}.png" .build/debug/zt-agent
done

echo "All settings tabs rendered successfully to: $OUT_DIR"
