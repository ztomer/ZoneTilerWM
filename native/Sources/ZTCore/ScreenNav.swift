// ScreenNav.swift — pure multi-monitor navigation logic (ports the index math in
// tiler.lua focus_next/prev_screen + window_actions.move_window_to_monitor's screen pick and
// placement cascade). The live focus/move is the WindowSystem boundary; this is the decision.
//
// Screens are put in a deterministic order (by frame position: left-to-right, then
// top-to-bottom) rather than relying on enumeration order, so "next/previous" is stable.

public enum ScreenNav {

    public enum Direction { case next, previous }

    /// Deterministic screen order: ascending x, then ascending y.
    public static func ordered(_ screens: [ScreenSnapshot]) -> [ScreenSnapshot] {
        screens.sorted { a, b in
            a.frame.x != b.frame.x ? a.frame.x < b.frame.x : a.frame.y < b.frame.y
        }
    }

    /// Index of the next/previous screen, wrapping around. Returns nil if fewer than 2 screens
    /// or the current uuid isn't found.
    public static func targetIndex(orderedUUIDs: [String], current: String, direction: Direction) -> Int? {
        guard orderedUUIDs.count >= 2, let i = orderedUUIDs.firstIndex(of: current) else { return nil }
        switch direction {
        case .next:     return (i + 1) % orderedUUIDs.count
        case .previous: return (i - 1 + orderedUUIDs.count) % orderedUUIDs.count
        }
    }

    /// Where to place a window arriving on the target monitor (port of move_window_to_monitor's
    /// strategy cascade, minus strategy 2 "maintain live tiler state" which the native side
    /// doesn't track yet):
    ///   1. the app's remembered (zone, tile) if that zone/tile exists on the target,
    ///   3. else the first available default zone ("0","j") at tile 1,
    ///   4. else nil → caller moves the window to the screen untiled.
    public static func monitorPlacement(targetZones: [String: [ZTRect]],
                                        remembered: (zone: String, tile: Int)?,
                                        defaultZones: [String] = ["0", "j"]) -> (zone: String, tile: Int)? {
        if let r = remembered, let tiles = targetZones[r.zone], r.tile >= 1, r.tile <= tiles.count {
            return (r.zone, r.tile)
        }
        for dz in defaultZones {
            if let tiles = targetZones[dz], !tiles.isEmpty { return (dz, 1) }
        }
        return nil
    }
}
