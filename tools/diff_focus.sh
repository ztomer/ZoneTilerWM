#!/usr/bin/env bash
# tools/diff_focus.sh — differential check for FocusManager zone collection/ordering vs Lua.
set -uo pipefail
cd "$(dirname "$0")/.."
N="${1:-300}"; BIN="native/.build/debug/zt-oracle"
echo "Building zt-oracle..."; swift build --package-path native >/dev/null || { echo "build failed"; exit 2; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; pass=0; fail=0
for s in $(seq 1 "$N"); do
  lua tools/gen_fuzz_focus.lua "$s" > "$TMP/f.json"
  lua tools/oracle_focus.lua < "$TMP/f.json" > "$TMP/lua.json" 2>"$TMP/e" || { echo "LUA ERR $s"; cat "$TMP/e"; fail=$((fail+1)); continue; }
  "$BIN" focus < "$TMP/f.json" > "$TMP/sw.json" 2>"$TMP/e" || { echo "SWIFT ERR $s"; cat "$TMP/e"; fail=$((fail+1)); continue; }
  if lua tools/cmp_focus.lua "$TMP/lua.json" "$TMP/sw.json" 2>"$TMP/c"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $s"; cat "$TMP/c"; cp "$TMP/f.json" "tools/fuzz_failures/focus_$s.json" 2>/dev/null; fi
done
echo "PASS=$pass FAIL=$fail"; [ "$fail" -eq 0 ]
