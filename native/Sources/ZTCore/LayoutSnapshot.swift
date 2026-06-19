// LayoutSnapshot.swift — named, restorable window arrangements ("coding", "writing"). Pure
// logic: capture the current arrangement into a snapshot, and plan a restore (which window goes
// to which zone) against the live windows. The agent executes the plan via
// TilerCoordinator.moveWindow(id:toZone:) and persists snapshots via Storage.
//
// v1 scope (per the roadmap risk register): one assignment per (app, monitor) that occupies a
// zone, matched on app name. Best-effort for multi-window / Electron apps — restore re-identifies
// by app, which isn't stable for apps with several same-app windows. Single-main-window apps
// (the common case) restore reliably.

public struct LayoutSnapshot: Codable, Equatable {
    public struct Assignment: Codable, Equatable {
        public let app: String
        public let monitor: String
        public let zone: String
        public init(app: String, monitor: String, zone: String) {
            self.app = app; self.monitor = monitor; self.zone = zone
        }
    }
    public let name: String
    public let assignments: [Assignment]
    public init(name: String, assignments: [Assignment]) {
        self.name = name; self.assignments = assignments
    }
}

public enum LayoutSnapshots {

    /// Capture the current arrangement: one assignment per (app, monitor) that currently occupies
    /// a zone (windows not in a zone are skipped). The first window seen per (app, monitor) wins
    /// (pass front-to-back). Deterministic order (sorted by app then monitor).
    public static func capture(name: String, from windows: [WindowInfo]) -> LayoutSnapshot {
        var seen = Set<String>()
        var assignments: [LayoutSnapshot.Assignment] = []
        for w in windows {
            guard let zone = w.zone else { continue }
            let key = "\(w.app)\u{1f}\(w.monitor)"
            if seen.contains(key) { continue }
            seen.insert(key)
            assignments.append(.init(app: w.app, monitor: w.monitor, zone: zone))
        }
        assignments.sort { ($0.app, $0.monitor) < ($1.app, $1.monitor) }
        return LayoutSnapshot(name: name, assignments: assignments)
    }

    /// A single restore step: move `windowId` into `zone`.
    public struct Move: Equatable {
        public let windowId: Int
        public let zone: String
        public init(windowId: Int, zone: String) { self.windowId = windowId; self.zone = zone }
    }

    /// Plan a restore: map each assignment to a current window of that app — preferring one on the
    /// same monitor, else any same-app window — without reusing a window. Assignments with no
    /// matching live window are skipped (best-effort). Matching is case-insensitive on app name.
    public static func restorePlan(_ snapshot: LayoutSnapshot, current windows: [WindowInfo]) -> [Move] {
        var used = Set<Int>()
        var moves: [Move] = []
        for a in snapshot.assignments {
            let candidates = windows.filter {
                $0.app.caseInsensitiveCompare(a.app) == .orderedSame && !used.contains($0.windowId)
            }
            guard let pick = candidates.first(where: { $0.monitor == a.monitor }) ?? candidates.first else { continue }
            used.insert(pick.windowId)
            moves.append(Move(windowId: pick.windowId, zone: a.zone))
        }
        return moves
    }
}

/// The persisted library of named snapshots (one JSON file via Storage).
public struct LayoutLibrary: Codable, Equatable {
    public var snapshots: [LayoutSnapshot]
    public init(snapshots: [LayoutSnapshot] = []) { self.snapshots = snapshots }

    public func snapshot(named name: String) -> LayoutSnapshot? {
        snapshots.first { $0.name == name }
    }

    /// Insert or replace by name; returns a new library (value semantics).
    public func upserting(_ snapshot: LayoutSnapshot) -> LayoutLibrary {
        LayoutLibrary(snapshots: snapshots.filter { $0.name != snapshot.name } + [snapshot])
    }

    public var names: [String] { snapshots.map { $0.name }.sorted() }
}
