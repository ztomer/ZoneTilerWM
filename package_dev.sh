#!/usr/bin/env bash
# package_dev.sh — build ZoneTilerWM.app for DEVELOPMENT: Debug config, private APIs ON
# (ZT_PRIVATE_APIS; real-Spaces still runtime-gated by [ui] experimental_real_spaces), dev-signed
# with the stable "ZoneTilerWM Dev" identity (keeps the Accessibility grant across rebuilds), arm64
# only for speed, no zip. The .app is left in /tmp/ZoneTilerWM/dev for a quick drag-to-/Applications.
# NOT App-Store-safe (links private symbols).
exec env ZT_VARIANT=dev "$(dirname "$0")/package_app.sh" "$@"
