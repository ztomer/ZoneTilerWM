// SmartPlacer.swift — faithful port of smart_placer.find_best_tile (modules/smart_placer.lua).
// Pure scoring: given a screen, the monitor's zones (sorted by key), and the frames of
// already-placed windows, pick the best empty/least-occupied tile for a new window.
//
// The Lua module's gating (config enabled, excluded apps, "already in a zone") and the
// window_cache occupancy read are caller concerns (smart_placer accepts an occupied-frames
// override that bypasses them); this port models the scoring core that override feeds.
// Already deterministic in Lua (zone keys iterated sorted, strict-> max selection).

import Foundation

public enum SmartPlacer {

    public struct Zone {
        public let zoneKey: String
        public let tiles: [ZTRect]
        public init(zoneKey: String, tiles: [ZTRect]) { self.zoneKey = zoneKey; self.tiles = tiles }
    }

    public struct Placement: Equatable {
        public let zoneKey: String
        public let tileIndex: Int      // 1-based, matching Lua
        public let tile: ZTRect
        public let overlapRatio: Double
    }

    /// Intersection area with CGRectIntersection semantics (zero when disjoint). Matches the
    /// hs.geometry.intersectionRect behavior the oracle injects.
    static func intersectionArea(_ a: ZTRect, _ b: ZTRect) -> Double {
        let ix = max(a.x, b.x)
        let iy = max(a.y, b.y)
        let iw = min(a.x + a.w, b.x + b.w) - ix
        let ih = min(a.y + a.h, b.y + b.h) - iy
        if iw <= 0 || ih <= 0 { return 0 }
        return iw * ih
    }

    /// `zones` must be sorted by zoneKey and exclude the "default" zone (the caller does this,
    /// mirroring the Lua sorted-key iteration). Returns nil if no tile is found.
    public static func findBestTile(screen: ZTRect, zones: [Zone], occupied: [ZTRect]) -> Placement? {
        let screenDiag = (screen.w * screen.w + screen.h * screen.h).squareRoot()
        let screenArea = screen.w * screen.h

        var best: Placement?
        var maxScore = -1.0

        for zone in zones {
            for (idx, candidate) in zone.tiles.enumerated() {
                let i = idx + 1  // 1-based tile index

                // A degenerate (zero-area) tile would make the area/AR/overlap divisions below
                // produce NaN — and `NaN > maxScore` is always false, so it'd be silently
                // skipped anyway. Skip it explicitly to keep the math finite.
                if candidate.w <= 0 || candidate.h <= 0 { continue }

                // Total overlap with already-placed windows (ignoring tiny bleeds).
                var currentOverlap = 0.0
                for occ in occupied {
                    let area = intersectionArea(candidate, occ)
                    if area <= 0 { continue }
                    let overlapPct = area / (candidate.w * candidate.h)
                    if overlapPct > 0.01 || area > 50 {
                        currentOverlap += area
                    }
                }

                // Base score: 40% area, 60% positional priority (closeness to global origin).
                let areaScore = candidate.w * candidate.h
                let tcX = candidate.x + candidate.w / 2
                let tcY = candidate.y + candidate.h / 2
                let dist = (tcX * tcX + tcY * tcY).squareRoot()
                let closeness = 1.0 - (dist / screenDiag)
                let positionScore = screenArea * closeness
                var rankedScore = (areaScore * 0.4) + (positionScore * 0.6)

                // Index penalty (prefer earlier tiles).
                let indexPenalty = 1.1 - (Double(min(i, 10)) * 0.05)
                rankedScore *= indexPenalty

                // Aspect-ratio penalty for extreme shapes.
                let ar = candidate.w / candidate.h
                if ar < 0.4 || ar > 3.5 { rankedScore *= 0.5 }

                // Continuous coverage penalty (prefer smaller tiles, keep grid open).
                let coverage = areaScore / screenArea
                rankedScore *= (1.1 - coverage)

                // Steep overlap penalty: any empty tile beats any occupied one.
                let occupancyRatio = currentOverlap / areaScore
                let overlapMultiplier = 1.0 / (1.0 + (occupancyRatio * 500))

                let finalScore = rankedScore * overlapMultiplier
                if finalScore > maxScore {
                    maxScore = finalScore
                    best = Placement(zoneKey: zone.zoneKey, tileIndex: i,
                                     tile: candidate, overlapRatio: occupancyRatio)
                }
            }
        }
        return best
    }
}
