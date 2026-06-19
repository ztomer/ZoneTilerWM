# ZoneTilerWM — dev entry points. This is a single native Swift product (SwiftPM package at the
# repo root); the original Hammerspoon/Lua implementation and its differential oracle harness were
# retired once the port reached parity (they live on in git history + the `origin` remote).

.PHONY: verify test-swift build app probe help

help:
	@echo "make verify      - swift unit + golden tests"
	@echo "make test-swift  - alias for verify"
	@echo "make build       - build the Swift package"
	@echo "make app         - build ZoneTilerWM.app (Release, ad-hoc signed) via xcodegen"
	@echo "make probe       - read-only system probe (screens/windows/audio)"

verify test-swift:
	@swift test

build:
	@swift build

# Generate the Xcode project from project.yml and build the .app bundle. Needs xcodegen
# (brew install xcodegen). Artifacts go to /tmp/ZoneTilerWM (out of the project tree).
# Signs with the stable "ZoneTilerWM Dev" identity if present (keeps the Accessibility grant
# across rebuilds — see docs/DEV_SIGNING.md), else ad-hoc. Override with ZT_SIGN_ID=...
app:
	@PATH="/opt/homebrew/bin:$$PATH" xcodegen generate
	@SIGN_ID="$${ZT_SIGN_ID:-ZoneTilerWM Dev}"; \
		security find-identity -v -p codesigning 2>/dev/null | grep -q "$$SIGN_ID" || SIGN_ID="-"; \
		echo "signing with: $$SIGN_ID"; \
		xcodebuild -project ZoneTilerWM.xcodeproj -scheme ZoneTilerWM \
			-configuration Release -derivedDataPath /tmp/ZoneTilerWM/DerivedData \
			CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$$SIGN_ID" build
	@echo "built: /tmp/ZoneTilerWM/DerivedData/Build/Products/Release/ZoneTilerWM.app"

probe: build
	@.build/debug/zt-probe
