#!/usr/bin/env bash
# run.sh — build and launch the zt-agent menubar app in the foreground (Ctrl-C to quit).
# Kills any running instance first (it holds global hotkeys). Optional arg: a config path
# (defaults to the repo config.toml).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${1:-$ROOT/config.toml}"

"$ROOT/build.sh"
pkill -x zt-agent 2>/dev/null || true
sleep 0.3

echo "zt-agent: launching with $CONFIG (Ctrl-C to quit)"
exec "$ROOT/native/.build/debug/zt-agent" "$CONFIG"
