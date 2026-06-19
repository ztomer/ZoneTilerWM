#!/usr/bin/env bash
# build.sh — build the native v2 package. Pass-through flags, e.g. ./build.sh -c release
set -euo pipefail
cd "$(dirname "$0")"
exec swift build "$@"
