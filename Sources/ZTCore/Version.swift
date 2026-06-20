// Version.swift — single source of truth for the app version. Generated/edited by ./bump.sh, which
// also rewrites project.yml's Info.plist values in the same step, so the version lives in ONE place
// instead of being hand-bumped across project.yml + AboutWindow + zt-mcp (review item #2). Do not
// edit by hand — run `./bump.sh <marketing> <build>`.
public enum ZTVersion {
    public static let marketing = "2.7.1"
    public static let build = "52"
}
