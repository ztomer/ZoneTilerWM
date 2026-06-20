// PlacementStrategy.swift — faithful port of modules/placement_strategy.lua.
// Picks a tile within a zone for a window, by strategy:
//   * rotate / hybrid: cycle to the next tile index.
//   * largest_free_space: pick the tile with the most unoccupied area, with cycling logic
//     when the window is already in the zone or all tiles are blocked.
// Determinism: the largest-free sort is a total order (available desc, then original index
// asc), matching the Lua fix — table.sort is unstable.

import Foundation

public enum PlacementStrategy {

    public enum Strategy {
        case rotate
        case largestFreeSpace

        /// Maps the config string (rotate/hybrid -> rotate, largest_free_space -> largest).
        public init(config: String) {
            self = (config == "largest_free_space") ? .largestFreeSpace : .rotate
        }
    }

    public struct OccupiedWindow {
        public let id: Int
        public let frame: ZTRect
        public init(id: Int, frame: ZTRect) { self.id = id; self.frame = frame }
    }

    /// Clamped intersection area (port of rectangle_intersection_area).
    static func intersectionArea(_ r1: ZTRect, _ r2: ZTRect) -> Double {
        let xOverlap = max(0, min(r1.x + r1.w, r2.x + r2.w) - max(r1.x, r2.x))
        let yOverlap = max(0, min(r1.y + r1.h, r2.y + r2.h) - max(r1.y, r2.y))
        return xOverlap * yOverlap
    }

    /// Approximate frame equality (tolerance 1.0 on every component), like Lua's tiles_equal.
    static func tilesEqual(_ a: ZTRect, _ b: ZTRect) -> Bool {
        abs(a.x - b.x) < 1.0 && abs(a.y - b.y) < 1.0 && abs(a.w - b.w) < 1.0 && abs(a.h - b.h) < 1.0
    }

    public static func findBestTile(strategy: Strategy,
                                    tiles: [ZTRect],
                                    zoneKey: String,
                                    currentFrame: ZTRect,
                                    stateZoneKey: String?,
                                    stateTileIndex: Int?,
                                    occupied: [OccupiedWindow],
                                    selfId: Int) -> ZTRect? {
        switch strategy {
        case .largestFreeSpace:
            let alreadyInZone = (stateZoneKey != nil && stateZoneKey == zoneKey)
            return largestFreeTile(tiles: tiles, currentFrame: currentFrame,
                                   stateTileIndex: stateTileIndex, alreadyInZone: alreadyInZone,
                                   occupied: occupied, selfId: selfId)
        case .rotate:
            return rotate(tiles: tiles, currentTileIndex: stateTileIndex)
        }
    }

    /// Port of find_by_rotation: cycle to (current % n) + 1 (1-based).
    static func rotate(tiles: [ZTRect], currentTileIndex: Int?) -> ZTRect? {
        if tiles.isEmpty { return nil }
        // Clamp to >= 0: Swift's % keeps the dividend's sign, so a negative stored index would make
        // `next - 1` negative and crash on tiles[negative]. (Production always passes nil here.)
        let current = max(0, currentTileIndex ?? 0)
        let next = (current % tiles.count) + 1
        return tiles[next - 1]
    }

    /// Port of find_largest_free_tile.
    static func largestFreeTile(tiles: [ZTRect], currentFrame: ZTRect,
                                stateTileIndex: Int?, alreadyInZone: Bool,
                                occupied: [OccupiedWindow], selfId: Int) -> ZTRect? {
        if tiles.isEmpty { return nil }

        struct Opt { let tile: ZTRect; let available: Double; let orig: Int }
        var opts: [Opt] = []
        for (i, candidate) in tiles.enumerated() {
            let area = candidate.w * candidate.h
            var overlap = 0.0
            for info in occupied where info.id != selfId {
                overlap += intersectionArea(candidate, info.frame)
            }
            opts.append(Opt(tile: candidate, available: area - overlap, orig: i + 1))
        }
        opts.sort { a, b in a.available != b.available ? a.available > b.available : a.orig < b.orig }

        // Current tile in original order (1-based), by frame match.
        var currentTileIdx: Int?
        for (i, t) in tiles.enumerated() where tilesEqual(t, currentFrame) { currentTileIdx = i + 1; break }

        // All tiles blocked: cycle from current, else return tile 1.
        if opts[0].available <= 0 {
            if let cti = currentTileIdx, tiles.count > 1 {
                return tiles[(cti % tiles.count) + 1 - 1]
            }
            return tiles[0]
        }

        if alreadyInZone && opts.count > 1 {
            var currentInOptions: Int?
            for (i, v) in opts.enumerated() where tilesEqual(v.tile, currentFrame) { currentInOptions = i + 1; break }
            if let cio = currentInOptions {
                let nextIdx = (cio % opts.count) + 1
                let selected = opts[nextIdx - 1].tile
                if tilesEqual(selected, currentFrame) {
                    for skip in 1...(opts.count - 1) {
                        let tryIdx = ((nextIdx + skip - 1) % opts.count) + 1
                        if tryIdx != cio && !tilesEqual(opts[tryIdx - 1].tile, currentFrame) {
                            return opts[tryIdx - 1].tile
                        }
                    }
                }
                return selected
            } else if let idx = stateTileIndex, idx >= 1, idx <= tiles.count {
                return tiles[idx - 1]
            }
        } else if !alreadyInZone && opts.count > 1 {
            if let cti = currentTileIdx {
                return tiles[(cti % tiles.count) + 1 - 1]
            }
        }

        return opts[0].tile
    }
}
