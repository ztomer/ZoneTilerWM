// Cluster.swift — pure types + matching for App-Cluster Profiles: a named profile that maps apps
// to zones, so one action ("cluster name=dev") arranges a whole working context. Applying a cluster
// = launch any missing apps (NSWorkspace, 0 AX) then tile each running matching window to its zone
// (CGWindowList enumeration = 0 AX; the move is the only AX). This owns the value types + the
// window→zone matching, so it stays unit-testable; the launch/move live in the agent.

public struct ClusterPlacement: Equatable {
    public let app: String
    public let zone: String
    public let monitor: String?   // optional hint; v1 places on the window's current screen
    public init(app: String, zone: String, monitor: String? = nil) {
        self.app = app; self.zone = zone; self.monitor = monitor
    }
}

public struct ClusterProfile: Equatable {
    public let name: String
    public let placements: [ClusterPlacement]
    public init(name: String, placements: [ClusterPlacement]) {
        self.name = name; self.placements = placements
    }
}

public enum ClusterPlan {
    public struct Match: Equatable {
        public let windowId: Int
        public let zone: String
        public init(windowId: Int, zone: String) { self.windowId = windowId; self.zone = zone }
    }

    /// Window→zone placements: every running window whose app matches a placement (case-insensitive)
    /// is tiled to that placement's zone. Deterministic (input order preserved).
    public static func match(profile: ClusterProfile, windows: [(id: Int, app: String)]) -> [Match] {
        windows.compactMap { w in
            guard let p = profile.placements.first(where: { $0.app.lowercased() == w.app.lowercased() }) else { return nil }
            return Match(windowId: w.id, zone: p.zone)
        }
    }

    /// The apps a cluster wants present, for the launch-if-missing step.
    public static func apps(_ profile: ClusterProfile) -> [String] { profile.placements.map { $0.app } }
}
