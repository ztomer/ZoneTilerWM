#!/usr/bin/env bash
# package_public.sh — build ZoneTilerWM.app for DIRECT (non-App-Store) distribution: Release,
# universal (arm64+x86_64), private APIs compiled in but OFF by default at runtime, signed + zipped
# with an INSTALL.txt. NOT App-Store-safe (links private CGS/AX symbols); use package_mas.sh for MAS.
exec env ZT_VARIANT=public "$(dirname "$0")/package_app.sh" "$@"
