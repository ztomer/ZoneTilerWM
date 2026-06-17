# ZoneTilerWM — dev entry points. The v2 native port lives in native/ (Swift) with the Lua
# source in modules/ as the executable spec; tools/ holds the differential oracles.

.PHONY: verify test-swift test-lua diff probe build help

help:
	@echo "make verify      - swift tests + all differential harnesses + lua spec runner"
	@echo "make test-swift  - swift unit/golden tests (native/)"
	@echo "make test-lua    - lua spec test runner"
	@echo "make diff        - run all six Lua<->Swift differential harnesses (100 fuzz each)"
	@echo "make build       - build the native package"
	@echo "make probe       - read-only system probe (screens/windows/audio)"

verify:
	@tools/verify.sh

test-swift:
	@cd native && swift test

test-lua:
	@lua tests/test_runner.lua

diff:
	@for m in solver zones memory place strategy autotiler; do tools/diff_$$m.sh 100; done

build:
	@cd native && swift build

probe: build
	@native/.build/debug/zt-probe
