// ZoneOccupancy.swift — pure geometry for "which zone does this window occupy?" Used by the
// read-only arrangement resource. Ranks candidate tiles by intersection-over-union so the
// tightest-fitting tile wins: a window placed exactly into a small zone is reported as that
// zone, not as a larger zone that merely contains it.

public enum ZoneOccupancy {

    /// The key of the zone whose tile best matches `window` (IoU ≥ `threshold`), or nil. The
    /// "default" pseudo-zone is ignored. Deterministic: zone keys are considered in sorted order
    /// and ties keep the first (strict-greater comparison).
    public static func bestZone(window: ZTRect, zones: [String: [ZTRect]], threshold: Double = 0.5) -> String? {
        var best: (zone: String, iou: Double)?
        for zoneKey in zones.keys.sorted() where zoneKey != "default" {
            for tile in zones[zoneKey] ?? [] {
                let iou = intersectionOverUnion(window, tile)
                if iou > (best?.iou ?? 0) { best = (zoneKey, iou) }
            }
        }
        if let best, best.iou >= threshold { return best.zone }
        return nil
    }

    /// Jaccard overlap of two rects (0 = disjoint, 1 = identical). Top-left CG coords.
    public static func intersectionOverUnion(_ a: ZTRect, _ b: ZTRect) -> Double {
        let x = max(a.x, b.x), y = max(a.y, b.y)
        let right = min(a.x + a.w, b.x + b.w), bottom = min(a.y + a.h, b.y + b.h)
        let inter = max(0, right - x) * max(0, bottom - y)
        guard inter > 0 else { return 0 }
        let union = a.w * a.h + b.w * b.h - inter
        return union > 0 ? inter / union : 0
    }
}
