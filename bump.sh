#!/usr/bin/env bash
# bump.sh <marketing-version> <build-number> — the ONE place the app version is set.
# Rewrites Sources/ZTCore/Version.swift (the canonical Swift constant, read by AboutWindow + zt-mcp)
# AND project.yml's four Info.plist/build fields, so they can never drift. e.g. ./bump.sh 1.5.17 48
set -euo pipefail
[ $# -eq 2 ] || { echo "usage: ./bump.sh <marketing> <build>   e.g. ./bump.sh 1.5.17 48" >&2; exit 1; }
M="$1"; B="$2"
ROOT="$(cd "$(dirname "$0")" && pwd)"

cat > "$ROOT/Sources/ZTCore/Version.swift" <<SWIFT
// Version.swift — single source of truth for the app version. Generated/edited by ./bump.sh, which
// also rewrites project.yml's Info.plist values in the same step, so the version lives in ONE place
// instead of being hand-bumped across project.yml + AboutWindow + zt-mcp (review item #2). Do not
// edit by hand — run \`./bump.sh <marketing> <build>\`.
public enum ZTVersion {
    public static let marketing = "$M"
    public static let build = "$B"
}
SWIFT

perl -0pi -e "s/CFBundleShortVersionString: \"[^\"]*\"/CFBundleShortVersionString: \"$M\"/;
              s/CFBundleVersion: \"[^\"]*\"/CFBundleVersion: \"$B\"/;
              s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$M\"/;
              s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$B\"/" "$ROOT/project.yml"

echo "bumped to $M (build $B) — Version.swift + project.yml updated"
