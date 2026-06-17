#!/usr/bin/env bash
# tools/diff_autotiler.sh — autonomous differential check for the AutoTiler port.
# Runs the Lua oracle and Swift zt-oracle (autotiler mode) over N fuzz seeds and diffs.
#
#   tools/diff_autotiler.sh [num_fuzz_seeds]   (default 300)

set -uo pipefail
cd "$(dirname "$0")/.."

N="${1:-300}"
BIN="native/.build/debug/zt-oracle"
FAILDIR="tools/fuzz_failures"

echo "Building zt-oracle..."
swift build --package-path native >/dev/null || { echo "swift build failed"; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$FAILDIR"

pass=0; fail=0

run_one() {
  local scen="$1" label="$2"
  if ! lua tools/oracle_autotiler.lua < "$scen" > "$TMP/lua.json" 2>"$TMP/err"; then
    echo "LUA ERROR  $label"; sed 's/^/  /' "$TMP/err"; fail=$((fail+1)); return
  fi
  if ! "$BIN" autotiler < "$scen" > "$TMP/swift.json" 2>"$TMP/err"; then
    echo "SWIFT ERROR $label"; sed 's/^/  /' "$TMP/err"; fail=$((fail+1)); return
  fi
  if lua tools/cmp_autotiler.lua "$TMP/lua.json" "$TMP/swift.json" 2>"$TMP/cmp"; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL  $label"
    sed 's/^/  /' "$TMP/cmp"
    cp "$scen" "$FAILDIR/autotiler_$(echo "$label" | tr ':/ ' '___').json"
  fi
}

echo "== fuzz ($N seeds) =="
for s in $(seq 1 "$N"); do
  lua tools/gen_fuzz_autotiler.lua "$s" > "$TMP/fuzz_$s.json"
  run_one "$TMP/fuzz_$s.json" "fuzz:$s"
done

echo "================================"
echo "PASS=$pass  FAIL=$fail"
[ "$fail" -eq 0 ]
