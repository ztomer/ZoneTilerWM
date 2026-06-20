#!/usr/bin/env bash
# package_mas.sh — build ZoneTilerWM.app for the Mac App Store: Release, universal, with ZERO private
# APIs (the build is verified MAS-clean by an nm leak guard — Exposé/Spaces/border fall back to their
# public paths). Zipped. A real MAS *submission* additionally needs an Apple Developer account
# (App Sandbox + entitlements + Apple Distribution signing + notarization) — see the printed note.
exec env ZT_VARIANT=mas "$(dirname "$0")/package_app.sh" "$@"
