#!/usr/bin/env bash
# build_dist.sh — build an AD-HOC-signed, distributable ZoneTilerWM.app + zip to share with
# someone on another Mac.
#
#   ./build_dist.sh [version]
#
# Why ad-hoc and not the local `make app` / build_package.sh default? Those sign with your
# personal "ZoneTilerWM Dev" certificate, which lives only in your keychain — on a different Mac
# that signature is unknown and macOS's Accessibility (TCC) grant can misbehave. Ad-hoc signing
# has no certificate dependency: the recipient's one-time Accessibility grant works reliably.
#
# This is NOT notarized (no Apple Developer account), so the recipient must clear Gatekeeper
# quarantine once (instructions printed below). For wide distribution, set up Developer ID +
# notarization instead — see .github/workflows/release.yml.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# Delegate to build_package.sh, forcing ad-hoc signing.
ZT_SIGN_ID=- "$ROOT/build_package.sh" "$@"

cat <<'EOF'

────────────────────────────────────────────────────────────────────────────
Distributable (ad-hoc) build ready — send the zip above. The same steps below
are bundled inside the zip as INSTALL.txt for the recipient.

Recipient requirements:
  • Apple Silicon Mac  (this build is arm64-only; rebuild universal for Intel)
  • macOS 13 (Ventura) or newer

Recipient steps:
  1. Unzip, drag ZoneTilerWM.app into /Applications.
  2. Clear Gatekeeper quarantine (it is not notarized):
        xattr -dr com.apple.quarantine /Applications/ZoneTilerWM.app
     (or: try to open it, let it get blocked, then System Settings →
      Privacy & Security → "Open Anyway")
  3. Launch it — it is a menu-bar agent (no Dock icon, no window).
  4. Grant Accessibility when prompted: "Open System Settings" → toggle
     ZoneTilerWM on. If the prompt does not close after granting, quit it
     from the menu bar and relaunch once.
  5. If it's toggled ON but still can't move windows (common after installing
     a NEW version): select ZoneTilerWM in the Accessibility list, click "-"
     to remove it, then re-add ("+") or relaunch and grant again.
     Why: macOS binds the grant to the app's code signature; ad-hoc builds get
     a new signature each build, so a stale entry no longer matches the new app.
────────────────────────────────────────────────────────────────────────────
EOF
