#!/usr/bin/env bash
# run.sh — build and launch the zt-agent menubar app in the foreground (Ctrl-C to quit).
# Kills any running instance first (it holds global hotkeys).
#
# The live config is always ~/.config/ZoneTilerWM/config.toml. The optional path arg is only a
# ONE-TIME migration source: on first run it seeds that file (defaults to the repo config.toml);
# afterwards the agent reads/writes ~/.config and the arg is ignored. To re-seed from the repo,
# delete ~/.config/ZoneTilerWM/config.toml first.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SEED="${1:-$ROOT/config.toml}"

"$ROOT/build.sh"
pkill -x zt-agent 2>/dev/null || true
sleep 0.3

echo "zt-agent: launching (live config: ~/.config/ZoneTilerWM/config.toml; first-run seed: $SEED)"
exec "$ROOT/native/.build/debug/zt-agent" "$SEED"
