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

    /// One cell per zone key (excluding the "default" marker), each the bounding box of that
    /// zone's tiles. Deterministic (keys sorted).
    public static func layout(zones: [String: [ZTRect]]) -> [Cell] {
        zones.keys.sorted().compactMap { key in
            guard key != "default", let tiles = zones[key], !tiles.isEmpty else { return nil }
            return Cell(key: key, rect: boundingBox(tiles))
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
