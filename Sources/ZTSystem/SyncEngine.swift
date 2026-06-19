// SyncEngine.swift — performs the file-based settings sync planned by ZTCore.SyncPlan. Export
// copies the live config + state into the user's synced folder; import copies them back, taking a
// timestamped backup of whatever it overwrites first (so an import is never destructive). Pure
// FileManager I/O — no network, no entitlements, no AX. Returns the ActionResult the dispatcher
// surfaces to every front-end.

import Foundation
import ZTCore

public struct SyncEngine {
    private let configDir: String
    private let stateDir: String
    private let syncFolder: () -> String?   // [sync] folder; nil/empty = disabled
    private let fm = FileManager.default

    public init(configDir: String, stateDir: String, syncFolder: @escaping () -> String?) {
        self.configDir = configDir
        self.stateDir = stateDir
        self.syncFolder = syncFolder
    }

    /// Two-phase so a mid-run failure never leaves a destination file deleted-but-not-replaced:
    ///   1. STAGE every source into a temp beside its destination — the copy (the operation that
    ///      can actually fail: disk full, source vanishing) touches NO live file.
    ///   2. COMMIT only after all staging succeeded — back up each live file to `<file>.bak`, then
    ///      atomically swap in the staged temp (replace/rename is atomic on the same volume).
    public func run(_ direction: SyncPlan.Direction) -> ActionResult {
        guard let folder = syncFolder(), !folder.isEmpty else {
            return .failed(reason: .invalidParameter("sync folder ([sync] folder) not set"))
        }
        let dir = (folder as NSString).expandingTildeInPath
        let plan = SyncPlan.plan(direction: direction, configDir: configDir, stateDir: stateDir, syncDir: dir) {
            fm.fileExists(atPath: $0)
        }

        var staged: [(copy: SyncPlan.Copy, tmp: String)] = []
        let cleanup = { staged.forEach { try? self.fm.removeItem(atPath: $0.tmp) } }

        // Phase 1 — stage (no live file is touched).
        do {
            for copy in plan {
                let dst = URL(fileURLWithPath: copy.to)
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                let tmp = copy.to + ".sync-tmp"
                try? fm.removeItem(atPath: tmp)
                try fm.copyItem(atPath: copy.from, toPath: tmp)
                staged.append((copy, tmp))
            }
        } catch {
            cleanup()
            return .failed(reason: .invalidParameter("sync \(direction.rawValue) failed while staging: \(error.localizedDescription)"))
        }

        // Phase 2 — commit (back up, then atomic swap).
        do {
            for s in staged {
                let dstURL = URL(fileURLWithPath: s.copy.to)
                let tmpURL = URL(fileURLWithPath: s.tmp)
                if fm.fileExists(atPath: s.copy.to) {
                    try? fm.removeItem(atPath: s.copy.to + ".bak")
                    try? fm.copyItem(atPath: s.copy.to, toPath: s.copy.to + ".bak")
                    _ = try fm.replaceItemAt(dstURL, withItemAt: tmpURL)   // atomic; consumes the temp
                } else {
                    try fm.moveItem(at: tmpURL, to: dstURL)                // atomic
                }
            }
        } catch {
            cleanup()
            return .failed(reason: .invalidParameter("sync \(direction.rawValue) failed while committing (prior versions kept as <file>.bak): \(error.localizedDescription)"))
        }
        return .synced(direction: direction.rawValue, files: plan.map { $0.name })
    }
}
