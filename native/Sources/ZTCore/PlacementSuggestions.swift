// PlacementSuggestions.swift — pure context-aware placement reasoning. Given the live arrangement
// (each window's app, monitor, and the zone it currently occupies) and a resolver for the learned
// preferred zone per (app, monitor), emit a suggestion for every window that's sitting somewhere
// other than where its app usually lives. No I/O, no AX — the provider feeds it CGWindowList data
// and the WindowMemory-backed resolver, so this stays fully unit-testable.

public enum PlacementSuggestions {
    public struct Window: Equatable {
        public let windowId: Int
        public let app: String
        public let monitor: String
        public let currentZone: String?
        public init(windowId: Int, app: String, monitor: String, currentZone: String?) {
            self.windowId = windowId; self.app = app; self.monitor = monitor; self.currentZone = currentZone
        }
    }

    /// One suggestion per window whose learned-preferred zone differs from where it sits now.
    /// `preferredZone` returns the top (zone, weight) for an (app, monitor) or nil if nothing learned.
    /// Sorted by descending weight (most confident first), then windowId for determinism.
    public static func compute(
        windows: [Window],
        preferredZone: (_ app: String, _ monitor: String) -> (zone: String, weight: Double)?
    ) -> [PlacementSuggestion] {
        var out: [PlacementSuggestion] = []
        for w in windows {
            guard let pref = preferredZone(w.app, w.monitor) else { continue }
            guard pref.zone != w.currentZone else { continue }   // already where it belongs
            out.append(PlacementSuggestion(windowId: w.windowId, app: w.app, monitor: w.monitor,
                                           currentZone: w.currentZone, suggestedZone: pref.zone, weight: pref.weight))
        }
        return out.sorted { a, b in a.weight != b.weight ? a.weight > b.weight : a.windowId < b.windowId }
    }
}
