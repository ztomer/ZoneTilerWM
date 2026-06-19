// DragSnap.swift — pure target-zone selection for drag-to-snap. Given the cursor location at
// drop time and the screen's computed zones, decide which zone the dragged window should snap to:
// the smallest zone region whose bounding box CONTAINS the point (most specific wins), else — when
// the drop lands in a gap/margin — the zone whose centre is nearest. The "default" marker is
// excluded. The passive mouse monitor, the live drag tracking and the actual move live in the
// agent; this is just the geometry decision, so it is fully unit-testable.

public enum DragSnap {
    /// The zone key to snap to for a drop at (x, y) in top-left CG coordinates, or nil if the
    /// screen has no zones. Deterministic: ties (equal area / equal distance) break on sorted key.
    public static func target(atX x: Double, y: Double, zones: [String: [ZTRect]]) -> String? {
        let boxes: [(key: String, box: ZTRect)] = zones.compactMap { key, tiles in
            guard key != "default", !tiles.isEmpty else { return nil }
            return (key, ZoneHUD.boundingBox(tiles))
        }
        guard !boxes.isEmpty else { return nil }

        let containing = boxes.filter { contains($0.box, x: x, y: y) }
        if !containing.isEmpty {
            return containing.min { lhs, rhs in
                let la = area(lhs.box), ra = area(rhs.box)
                return la != ra ? la < ra : lhs.key < rhs.key
            }!.key
        }
        return boxes.min { lhs, rhs in
            let ld = dist2(lhs.box, x: x, y: y), rd = dist2(rhs.box, x: x, y: y)
            return ld != rd ? ld < rd : lhs.key < rhs.key
        }!.key
    }

    // half-open on the far edges so adjacent boxes don't both claim a shared boundary point
    private static func contains(_ r: ZTRect, x: Double, y: Double) -> Bool {
        x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h
    }
    private static func area(_ r: ZTRect) -> Double { r.w * r.h }
    private static func dist2(_ r: ZTRect, x: Double, y: Double) -> Double {
        let cx = r.x + r.w / 2, cy = r.y + r.h / 2
        return (cx - x) * (cx - x) + (cy - y) * (cy - y)
    }
}
