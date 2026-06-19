// ZoneHUD.swift — pure layout for the modifier-held zone cheat-sheet overlay. Given the computed
// zones for a screen (key → tiles), produce one labelled cell per zone key at the centre of that
// zone's region, so the overlay can draw "press this key → window lands here". Pure; the overlay
// + the flagsChanged trigger live in the agent.

public enum ZoneHUD {
    public struct Cell: Equatable {
        public let key: String
        public let rect: ZTRect   // the zone's bounding region; the overlay labels its centre
        public init(key: String, rect: ZTRect) { self.key = key; self.rect = rect }
    }

    /// One cell per zone key (excluding the "default" marker), positioned at the zone's PRIMARY
    /// placement — its first tile. Deterministic (keys sorted).
    ///
    /// A zone key is a *cycle* of placements: e.g. `"y" = [a1, a1:a2, a1:b1]` (top-left cell →
    /// left-half → top-half) — press it repeatedly to cycle. The bounding box of the whole cycle
    /// spans most of the screen, which mis-centred the chip (the live-review bug: "y is top-left but
    /// shows in the middle"). The first tile is where pressing the key *once* lands the window, so
    /// that's where the chip belongs.
    public static func layout(zones: [String: [ZTRect]]) -> [Cell] {
        zones.keys.sorted().compactMap { key in
            guard key != "default", let first = zones[key]?.first else { return nil }
            return Cell(key: key, rect: first)
        }
    }

    static func boundingBox(_ rects: [ZTRect]) -> ZTRect {
        let minX = rects.map { $0.x }.min() ?? 0
        let minY = rects.map { $0.y }.min() ?? 0
        let maxX = rects.map { $0.x + $0.w }.max() ?? 0
        let maxY = rects.map { $0.y + $0.h }.max() ?? 0
        return ZTRect(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }
}
