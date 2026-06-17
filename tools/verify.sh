#!/usr/bin/env bash
# tools/verify.sh — one command to verify the whole v2 native port:
#   1. Swift unit/golden tests (native/)
#   2. all six Lua<->Swift differential harnesses (fuzzed)
#   3. the Lua spec test runner
# Exits non-zero if anything fails. Run from anywhere.
#
#   tools/verify.sh [fuzz_seeds_per_harness]   (default 100)

set -uo pipefail
cd "$(dirname "$0")/.."
N="${1:-100}"
fail=0

echo "== swift test =="
( cd native && swift test 2>&1 | tail -1 )
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "  swift test FAILED"; fail=1; }

echo "== differential harnesses ($N fuzz seeds each) =="
for m in solver zones memory place strategy autotiler; do
  out="$(tools/diff_$m.sh "$N" 2>&1)"; status=$?
  printf "  %-10s %s\n" "$m:" "$(printf '%s' "$out" | tail -1)"
  [ "$status" -eq 0 ] || fail=1
done

echo "== lua spec runner =="
lua tests/test_runner.lua >/dev/null 2>&1
[ $? -eq 0 ] && echo "  lua runner: PASS" || { echo "  lua runner: FAIL"; fail=1; }

echo "================================"
if [ "$fail" -eq 0 ]; then echo "VERIFY: ALL GREEN"; else echo "VERIFY: FAILURES ABOVE"; fi
exit $fail
