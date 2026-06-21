// FocusManager.swift — port of the pure focus-cycling logic in modules/focus_manager.lua.
// Determines which windows belong to a zone and in what order, and steps focus through them
// across repeated invocations. The actual window:focus() call and the flash overlay are the
// system boundary (not here); this computes the next window id to focus.

import Foundation

public enum FocusManager {

    /// A window assigned to a zone, for ordering.
    public struct ZoneWindow: Equatable {
        public let windowId: Int
        public let appName: String
        public let tileIndex: Int
        public let explicit: Bool   // assigned via window state (true) vs. detected by overlap (false)
        public let zOrder: Int
    }

    /// A window observed on the relevant screen (a snapshot; no AX here).
    public struct ScreenWindow {
        public let windowId: Int
        public let appName: String
        public let frame: ZTRect
        public let zOrder: Int
        public init(windowId: Int, appName: String, frame: ZTRect, zOrder: Int) {
            self.windowId = windowId; self.appName = appName; self.frame = frame; self.zOrder = zOrder
        }
    }

    /// Live state of a window (which monitor/zone/tile it occupies), if tiled.
    public struct WindowState {
        public let monitorId: String
        public let zoneKey: String
        public let tileIndex: Int
        public init(monitorId: String, zoneKey: String, tileIndex: Int) {
            self.monitorId = monitorId; self.zoneKey = zoneKey; self.tileIndex = tileIndex
        }
    }

    /// Percentage of rect1 covered by rect2 (port of calculate_overlap_percentage).
    static func overlapPercentage(_ r1: ZTRect, _ r2: ZTRect) -> Double {
        if r1.w <= 0 || r1.h <= 0 { return 0 }
        let xo = max(0, min(r1.x + r1.w, r2.x + r2.w) - max(r1.x, r2.x))
        let yo = max(0, min(r1.y + r1.h, r2.y + r2.h) - max(r1.y, r2.y))
        return (xo * yo) / (r1.w * r1.h)
    }

    /// Distance from a point to the nearest edge of a rect (0 when the point is inside).
    static func pointRectDistance(_ px: Double, _ py: Double, _ r: ZTRect) -> Double {
        let dx = max(0, max(r.x - px, px - (r.x + r.w)))
        let dy = max(0, max(r.y - py, py - (r.y + r.h)))
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Smallest distance from a frame's centre to any of the zone's tiles.
    static func distanceToZone(centreOf frame: ZTRect, tiles: [ZTRect]) -> Double {
        let cx = frame.x + frame.w / 2, cy = frame.y + frame.h / 2
        return tiles.map { pointRectDistance(cx, cy, $0) }.min() ?? .greatestFiniteMagnitude
    }

    /// Intersection-over-union of two rects (0 when disjoint). Rewards a *mutual* fit: high only
    /// when the two rects nearly coincide, unlike `overlapPercentage` which is 1.0 whenever the
    /// first is merely contained in the second.
    static func intersectionOverUnion(_ a: ZTRect, _ b: ZTRect) -> Double {
        let xo = max(0, min(a.x + a.w, b.x + b.w) - max(a.x, b.x))
        let yo = max(0, min(a.y + a.h, b.y + b.h) - max(a.y, b.y))
        let inter = xo * yo
        let union = a.w * a.h + b.w * b.h - inter
        return union > 0 ? inter / union : 0
    }

    /// The (zone, tile) a frame currently occupies — the basis for re-learning a manually-dragged
    /// window's zone (feedback 7b). Among the tiles the frame substantially sits in (window covered
    /// by >= threshold), it returns the one the window *fits best* (highest IoU), so a window
    /// dragged to the top-left quadrant re-learns that quadrant zone, NOT a looser half-screen zone
    /// that also contains it. Zones scan in sorted key order so ties (identical tiles in two zones)
    /// resolve deterministically; tileIndex is 1-based to match `collectZoneWindows`. Returns nil
    /// when the frame doesn't meaningfully occupy any tile (a floating / off-grid window stays
    /// un-learned rather than snapping to a spurious zone).
    public static func placement(of frame: ZTRect,
                                 zones: [String: [ZTRect]],
                                 overlapThreshold: Double) -> (zoneKey: String, tileIndex: Int)? {
        var best: (zoneKey: String, tileIndex: Int)?
        var bestIoU = 0.0
        for zoneKey in zones.keys.sorted() {
            guard let tiles = zones[zoneKey] else { continue }
            for (i, tile) in tiles.enumerated() where overlapPercentage(frame, tile) >= overlapThreshold {
                let iou = intersectionOverUnion(frame, tile)
                if iou > bestIoU { bestIoU = iou; best = (zoneKey, i + 1) }
            }
        }
        return best
    }

    /// Windows belonging to a zone, ordered intuitively (tile asc, explicit-first, z-order asc).
    /// Port of collect_zone_windows + sort_zone_windows_for_intuitive_order.
    public static func collectZoneWindows(monitorId: String,
                                          zoneKey: String,
                                          windowsOnScreen: [ScreenWindow],
                                          stateForWindow: (Int) -> WindowState?,
                                          zoneTiles: [ZTRect],
                                          overlapThreshold: Double,
                                          nearestFallback: Bool = false) -> [ZoneWindow] {
        if zoneTiles.isEmpty { return [] }
        var collected: [ZoneWindow] = []
        var added = Set<Int>()

        // Phase 1: explicitly-assigned windows (window state says this zone on this monitor).
        for w in windowsOnScreen {
            if let s = stateForWindow(w.windowId), s.monitorId == monitorId, s.zoneKey == zoneKey {
                collected.append(ZoneWindow(windowId: w.windowId, appName: w.appName,
                                            tileIndex: s.tileIndex, explicit: true, zOrder: w.zOrder))
                added.insert(w.windowId)
            }
        }
        // Phase 2: windows overlapping a tile by >= threshold (first matching tile wins).
        for w in windowsOnScreen where !added.contains(w.windowId) {
            for (i, tile) in zoneTiles.enumerated() where overlapPercentage(w.frame, tile) >= overlapThreshold {
                collected.append(ZoneWindow(windowId: w.windowId, appName: w.appName,
                                            tileIndex: i + 1, explicit: false, zOrder: w.zOrder))
                added.insert(w.windowId)
                break
            }
        }

        // Phase 3 (opt-in): nothing is assigned to or overlaps this zone → fall back to the single
        // NEAREST window, so a focus-zone press still jumps somewhere sensible instead of doing nothing
        // (feedback 7a). Distance = window centre → nearest zone tile (0 when the centre is inside).
        if nearestFallback, collected.isEmpty,
           let nearest = windowsOnScreen.min(by: {
               distanceToZone(centreOf: $0.frame, tiles: zoneTiles) < distanceToZone(centreOf: $1.frame, tiles: zoneTiles)
           }) {
            collected.append(ZoneWindow(windowId: nearest.windowId, appName: nearest.appName,
                                        tileIndex: 1, explicit: false, zOrder: nearest.zOrder))
        }

        collected.sort { a, b in
            if a.tileIndex != b.tileIndex { return a.tileIndex < b.tileIndex }
            if a.explicit != b.explicit { return a.explicit }      // explicit before detected
            if a.zOrder != b.zOrder { return a.zOrder < b.zOrder }
            return a.windowId < b.windowId                          // total-order tie-break
        }
        return collected
    }

    /// Stateful focus cycler — port of the cycle bookkeeping in cycle_windows_in_zone.
    /// Each call passes the freshly-collected ordered window ids; the cycler decides whether
    /// to rebuild its cycle list or reuse it, then steps to the next window.
    public final class Cycler {
        private var zoneKey: String?
        private var monitorId: String?
        private var order: [Int] = []
        private var index = 0

        public init() {}

        public func reset() {
            zoneKey = nil; monitorId = nil; order = []; index = 0
        }

        /// Returns the next window id to focus, or nil if the zone is empty.
        public func cycle(focusedId: Int, zoneKey: String, monitorId: String, freshOrder: [Int]) -> Int? {
            var needsRebuild = false
            if zoneKey != self.zoneKey || monitorId != self.monitorId || order.isEmpty {
                needsRebuild = true
            } else if freshOrder.count != order.count
                        || Set(freshOrder) != Set(order)
                        || !order.contains(focusedId) {
                needsRebuild = true
            }

            if needsRebuild {
                if freshOrder.isEmpty { reset(); return nil }
                self.zoneKey = zoneKey
                self.monitorId = monitorId
                order = freshOrder
                index = order.firstIndex(of: focusedId).map { $0 + 1 } ?? 0  // 1-based; 0 if absent
            }

            if order.isEmpty { return nil }
            index = (index % order.count) + 1
            return order[index - 1]
        }

        /// If a destroyed window was part of the active cycle, drop the cycle (forces rebuild).
        public func handleWindowDestroyed(_ windowId: Int) {
            if zoneKey != nil && order.contains(windowId) { reset() }
        }
    }
}
