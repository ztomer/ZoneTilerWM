#!/usr/bin/env bash
# tools/diff_solver.sh — autonomous differential check for the LayoutSolver port.
# Runs the Lua oracle and the Swift zt-oracle over the corpus fixtures plus N fuzz seeds
# and diffs the results. Failing fuzz scenarios are saved to tools/fuzz_failures/ so they
# can be promoted to regression fixtures.
#
#   tools/diff_solver.sh [num_fuzz_seeds]   (default 200)

set -uo pipefail
cd "$(dirname "$0")/.."

N="${1:-200}"
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
  if ! lua tools/oracle_solver.lua < "$scen" > "$TMP/lua.json" 2>"$TMP/err"; then
    echo "LUA ERROR  $label"; sed 's/^/  /' "$TMP/err"; fail=$((fail+1)); return
  fi
  if ! "$BIN" < "$scen" > "$TMP/swift.json" 2>"$TMP/err"; then
    echo "SWIFT ERROR $label"; sed 's/^/  /' "$TMP/err"; fail=$((fail+1)); return
  fi
  if lua tools/cmp_result.lua "$TMP/lua.json" "$TMP/swift.json" 2>"$TMP/cmp"; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL  $label"
    sed 's/^/  /' "$TMP/cmp"
    cp "$scen" "$FAILDIR/$(echo "$label" | tr ':/ ' '___').json"
  fi
}

echo "== corpus fixtures =="
for f in tools/fixtures/solver/*.json; do
  case "$f" in *.out.json) continue;; esac
  run_one "$f" "corpus:$(basename "$f")"
done

echo "== fuzz ($N seeds) =="
for s in $(seq 1 "$N"); do
  lua tools/gen_fuzz.lua "$s" > "$TMP/fuzz_$s.json"
  run_one "$TMP/fuzz_$s.json" "fuzz:$s"
done

echo "================================"
echo "PASS=$pass  FAIL=$fail"
[ "$fail" -eq 0 ]
