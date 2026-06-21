#!/usr/bin/env bash
# package_share.sh — build a .dmg you can HAND TO SOMEONE ELSE (e.g. AirDrop / upload), without an
# Apple Developer account. It's the public variant (Release, universal, private APIs compiled but OFF
# by default) but ad-hoc signed (ZT_SIGN_ID=-) instead of the local-only "ZoneTilerWM Dev" identity —
# that dev cert lives only in YOUR keychain, so a dev-signed build is rejected as "damaged" on any
# other Mac (the reason a first tester had to launch it from the command line).
#
# The result is still NOT notarized, so the recipient does a ONE-TIME Gatekeeper unblock (right-click
# -> Open, or `xattr -dr com.apple.quarantine`) — spelled out in the DMG's INSTALL.txt. A clean
# double-click experience needs Developer ID + notarization, which needs an Apple account (ROADMAP §B).
exec env ZT_VARIANT=public ZT_SIGN_ID=- ZT_DMG=1 "$(dirname "$0")/package_app.sh" "$@"
