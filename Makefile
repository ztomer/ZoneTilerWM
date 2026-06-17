# ZoneTilerWM — dev entry points. This is now a single native Swift product in native/;
# the original Hammerspoon/Lua implementation and its differential oracle harness were
# retired once the port reached parity (they live on in git history + the `origin` remote).

.PHONY: verify test-swift build probe help

help:
	@echo "make verify      - swift unit + golden tests (native/)"
	@echo "make test-swift  - alias for verify"
	@echo "make build       - build the native package"
	@echo "make probe       - read-only system probe (screens/windows/audio)"

verify test-swift:
	@cd native && swift test

build:
	@cd native && swift build

probe: build
	@native/.build/debug/zt-probe
