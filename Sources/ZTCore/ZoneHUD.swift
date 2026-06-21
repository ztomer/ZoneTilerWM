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
    /// One cell per zone key at its PRIMARY placement (first tile). Deterministic (keys sorted).
    /// The HUD keycaps use `caps(zones:)` (smallest-tile, collision-split); this stays for callers that
    /// just want the per-key primary rect.
    public static func layout(zones: [String: [ZTRect]]) -> [Cell] {
        zones.keys.sorted().compactMap { key in
            guard key != "default", let first = zones[key]?.first else { return nil }
            return Cell(key: key, rect: first)
        }
    }

    /// Where to draw a keycap, in CG coords (the label's centre).
    public struct CapLabel: Equatable {
        public let key: String
        public let x: Double
        public let y: Double
        public init(key: String, x: Double, y: Double) { self.key = key; self.x = x; self.y = y }
    }

    /// Keycap positions for the HUD: each key centred in its SMALLEST placement (its atomic grid cell),
    /// so a label sits cleanly inside one cell instead of floating on the boundary of a big overlapping
    /// region (the "caps land between zones" bug). Keys whose smallest cell coincides (e.g. the hand-tuned
    /// 4x3 layout maps i & o → d1, "," & "." → d3) are split SIDE-BY-SIDE so both stay visible. The
    /// auto-tile-all keys (`default`, `0`) are excluded — they target the whole screen, not a spatial zone.
    /// Deterministic (keys sorted).
    public static func caps(zones: [String: [ZTRect]]) -> [CapLabel] {
        let excluded: Set<String> = ["default", "0"]
        let smalls: [(key: String, rect: ZTRect)] = zones.compactMap { key, tiles in
            guard !excluded.contains(key),
                  let s = tiles.min(by: { $0.w * $0.h < $1.w * $1.h }) else { return nil }
            return (key, s)
        }
        // Group keys whose smallest-cell centre coincides (rounded), to split collisions side-by-side.
        var groups: [String: [(key: String, rect: ZTRect)]] = [:]
        for s in smalls {
            let cx = Int((s.rect.x + s.rect.w / 2).rounded()), cy = Int((s.rect.y + s.rect.h / 2).rounded())
            groups["\(cx)|\(cy)", default: []].append(s)
        }
        var out: [CapLabel] = []
        for members in groups.values {
            let sorted = members.sorted { $0.key < $1.key }
            let n = sorted.count
            for (i, m) in sorted.enumerated() {
                let cx = m.rect.x + m.rect.w / 2, cy = m.rect.y + m.rect.h / 2
                let step = min(m.rect.w * 0.35, 58)                          // spread between split caps
                let dx = n == 1 ? 0 : (Double(i) - Double(n - 1) / 2) * step
                out.append(CapLabel(key: m.key, x: cx + dx, y: cy))
            }
        }
        return out.sorted { $0.key < $1.key }
    }

    static func boundingBox(_ rects: [ZTRect]) -> ZTRect {
        let minX = rects.map { $0.x }.min() ?? 0
        let minY = rects.map { $0.y }.min() ?? 0
        let maxX = rects.map { $0.x + $0.w }.max() ?? 0
        let maxY = rects.map { $0.y + $0.h }.max() ?? 0
        return ZTRect(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }
}
