// SyncPlan.swift — pure file-list + path logic for file-based settings sync. ZoneTilerWM syncs
// its config + learned state to/from a user-chosen folder (iCloud Drive, Dropbox, …) so the same
// preferences follow the user across machines. No entitlements, no network — just files in a
// folder the user already syncs. This computes WHICH files copy WHERE for a direction; the actual
// copy + backup (FileManager) lives in ZTSystem.SyncEngine, so this stays unit-testable.

public enum SyncPlan {
    /// The config file (lives in the config dir — `~/.config/ZoneTilerWM`).
    public static let configFiles = ["config.toml"]
    /// The learned/saved state (lives in the state dir — `[window_memory] cache_dir`, which is the
    /// same path by default but can be relocated independently of config.toml).
    public static let stateFiles = ["window_positions.json", "layouts.json"]
    /// Everything that travels between machines.
    public static var syncedFiles: [String] { configFiles + stateFiles }

    /// The sub-folder created inside the user's synced folder, so we never collide with their files.
    public static let folderName = "ZoneTilerWM"

    public enum Direction: String, Equatable { case export, `import` }

    public struct Copy: Equatable {
        public let name: String
        public let from: String
        public let to: String
        public init(name: String, from: String, to: String) { self.name = name; self.from = from; self.to = to }
    }

    /// The copy operations for `direction`. config.toml is resolved under `configDir`, the state
    /// files under `stateDir` (the two coincide by default). `exists` filters to files actually
    /// present at the source (a missing source file is simply skipped, not an error).
    public static func plan(direction: Direction, configDir: String, stateDir: String,
                            syncDir: String, exists: (String) -> Bool) -> [Copy] {
        let entries = configFiles.map { ($0, configDir) } + stateFiles.map { ($0, stateDir) }
        return entries.compactMap { name, localDir in
            let local = join(localDir, name)
            let inSync = join(join(syncDir, folderName), name)
            let (src, dst) = direction == .export ? (local, inSync) : (inSync, local)
            return exists(src) ? Copy(name: name, from: src, to: dst) : nil
        }
    }

    static func join(_ a: String, _ b: String) -> String {
        a.hasSuffix("/") ? a + b : a + "/" + b
    }
}
