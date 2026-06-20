// AutoTiler.swift — faithful port of modules/auto_tiler.lua's planning logic
// (auto_tiler.tile_all_windows minus the live-system I/O). Produces the list of moves that
// would be applied, given a static snapshot of screens, windows, z-order, focus, memory,
// and a clock. Orchestrates the already-ported ZoneCalculator + LayoutSolver.
//
// Passes (per the Lua cascade): focused-anchor → (per monitor) working-set cull →
// greedy-memory → CSP solver (+ BSP subdivide) → limbo stack → fill-gaps → dedup.
// Determinism: mirrors the Lua determinism fixes (total-order sorts, injected `now`).

import Foundation

public enum AutoTiler {

    public struct Screen {
        public let uuid: String
        public let name: String
        public let frame: ZTRect
        public init(uuid: String, name: String, frame: ZTRect) {
            self.uuid = uuid; self.name = name; self.frame = frame
        }
    }

    public struct Window {
        public let id: Int
        public let app: String
        public let monitor: String
        public let frame: ZTRect
        public let lastFocusedTime: Int
        public let isStandard: Bool
        public let isMinimized: Bool
        public init(id: Int, app: String, monitor: String, frame: ZTRect,
                    lastFocusedTime: Int, isStandard: Bool = true, isMinimized: Bool = false) {
            self.id = id; self.app = app; self.monitor = monitor; self.frame = frame
            self.lastFocusedTime = lastFocusedTime
            self.isStandard = isStandard; self.isMinimized = isMinimized
        }
    }

    public struct Config {
        public var centerZones: [String]
        public var workingSetTimeLimit: Int
        public var workingSetMaxCapacity: Int
        public var mode: String                  // "usage" | "session"
        public var weights: CostWeights
        public var zoneConfig: ZoneConfig
        public init(centerZones: [String], workingSetTimeLimit: Int, workingSetMaxCapacity: Int,
                    mode: String, weights: CostWeights, zoneConfig: ZoneConfig) {
            self.centerZones = centerZones
            self.workingSetTimeLimit = workingSetTimeLimit
            self.workingSetMaxCapacity = workingSetMaxCapacity
            self.mode = mode; self.weights = weights; self.zoneConfig = zoneConfig
        }
    }

    public struct PlannedMove: Equatable {
        public let windowId: Int
        public let monitorId: String
        public let zoneKey: String
        public let tileIndex: TileIndex
        public let rect: ZTRect
    }

    private final class Move {
        let windowId: Int
        var monitorId: String
        var zoneKey: String
        var tileIndex: TileIndex
        var rect: ZTRect
        init(_ id: Int, _ mid: String, _ zone: String, _ tile: TileIndex, _ rect: ZTRect) {
            windowId = id; monitorId = mid; zoneKey = zone; tileIndex = tile; self.rect = rect
        }
    }

    private struct Occ { let frame: ZTRect; let id: Int }

    // calculate_overlap_ratio — overlap area relative to r1's area (clamped, 0 if disjoint).
    private static func overlapRatio(_ r1: ZTRect, _ r2: ZTRect) -> Double {
        let xo = max(0, min(r1.x + r1.w, r2.x + r2.w) - max(r1.x, r2.x))
        let yo = max(0, min(r1.y + r1.h, r2.y + r2.h) - max(r1.y, r2.y))
        if xo <= 0 || yo <= 0 { return 0 }
        let area = r1.w * r1.h
        return area == 0 ? 0 : (xo * yo) / area
    }

    private static let solverZoneKeys = ["h", "j", "k", "l", "i", "u", "y", "o", "n", "m"]
    // Max distinct candidate tiles handed to the CSP solver. Bounds its node count so it can't exhaust
    // maxChecks and return a partial placement; well above a 12-cell grid, so coverage is unaffected.
    private static let solverTileCap = 16

    public static func plan(config: Config,
                            screens: [Screen],
                            windows: [Window],
                            zOrder: [Int],
                            focusedId: Int?,
                            memory: [String: [MemoryPref]],
                            now: Int,
                            centerTileIndex: Int = 0) -> [PlannedMove] {

        let windowById = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })

        // Zones + detected layout/grid per monitor.
        var zonesByMid: [String: [String: [ZTRect]]] = [:]
        var gridByMid: [String: GridConfig] = [:]    // detected layout's grid (may be absent)
        var screenByMid: [String: Screen] = [:]
        for s in screens {
            let info = ZoneCalculator.ScreenInfo(name: s.name, frame: s.frame)
            zonesByMid[s.uuid] = ZoneCalculator.computeZones(screen: info, config: config.zoneConfig).zones
            if let lk = ZoneCalculator.layoutKey(for: info, config: config.zoneConfig) {
                gridByMid[s.uuid] = config.zoneConfig.grids[lk]
            }
            screenByMid[s.uuid] = s
        }

        var occupiedByMid: [String: [Occ]] = [:]
        for s in screens { occupiedByMid[s.uuid] = [] }

        var moves: [Move] = []
        var processed = Set<Int>()
        var anchorRect: ZTRect?
        var anchorMid: String?    // the focused window's monitor — anchorRect is in ITS coord space

        // ---- Pass: focused anchor — the focused window goes to the first center zone. `centerTileIndex`
        // cycles through that zone's tiles on repeated auto-tiles (so pressing it again rotates the
        // centre window's size/shape, like the manual zone cycle), wrapping deterministically.
        if let fid = focusedId, let fw = windowById[fid],
           fw.isStandard, !fw.isMinimized, screenByMid[fw.monitor] != nil,
           let selected = config.centerZones.first,
           let tiles = zonesByMid[fw.monitor]?[selected], !tiles.isEmpty {
            let idx = ((centerTileIndex % tiles.count) + tiles.count) % tiles.count   // safe wrap
            let rect = tiles[idx]
            anchorRect = rect
            anchorMid = fw.monitor
            moves.append(Move(fid, fw.monitor, selected, .int(idx + 1), rect))
            occupiedByMid[fw.monitor]?.append(Occ(frame: rect, id: fid))
            processed.insert(fid)
        }

        // Group remaining windows by monitor.
        var windowsByMonitor: [String: [Window]] = [:]
        for w in windows where !processed.contains(w.id) && screenByMid[w.monitor] != nil {
            windowsByMonitor[w.monitor, default: []].append(w)
        }

        let zMap = Dictionary(uniqueKeysWithValues: zOrder.enumerated().map { ($0.element, $0.offset + 1) })

        for mid in windowsByMonitor.keys.sorted() {
            let monitorWindows = windowsByMonitor[mid]!
            let (working, limbo) = cull(monitorWindows, zMap: zMap, now: now, config: config, memory: memory)

            // ---- Pass: greedy memory.
            for w in working where !processed.contains(w.id) {
                for pref in memory[w.app] ?? [] {
                    guard let tiles = zonesByMid[mid]?[pref.zone_key],
                          let ti = pref.tile_index.numericValue else { continue }
                    let idx = Int(ti)
                    guard idx >= 1, idx <= tiles.count else { continue }
                    let rect = tiles[idx - 1]
                    let blocked = (occupiedByMid[mid] ?? []).contains { overlapRatio(rect, $0.frame) > 0.05 }
                    if !blocked {
                        moves.append(Move(w.id, mid, pref.zone_key, pref.tile_index, rect))
                        occupiedByMid[mid]?.append(Occ(frame: rect, id: w.id))
                        processed.insert(w.id)
                        break
                    }
                }
            }

            // ---- Pass: CSP solver (+ BSP subdivide) for the still-unplaced.
            let unplaced = working.filter { !processed.contains($0.id) }
            if !unplaced.isEmpty, let screen = screenByMid[mid] {
                var available: [(rect: ZTRect, zone: String, tile: TileIndex)] = []
                for zk in solverZoneKeys {
                    guard let tiles = zonesByMid[mid]?[zk] else { continue }
                    for (i, t) in tiles.enumerated() {
                        let blocked = (occupiedByMid[mid] ?? []).contains { overlapRatio(t, $0.frame) > 0.05 }
                        if !blocked { available.append((t, zk, .int(i + 1))) }
                    }
                }
                available.sort { a, b in
                    let aa = a.rect.w * a.rect.h, ab = b.rect.w * b.rect.h
                    if aa != ab { return aa > ab }
                    if a.zone != b.zone { return a.zone < b.zone }
                    return a.tile.sortKey < b.tile.sortKey
                }
                // Drop geometrically-identical candidates: many zones resolve to the SAME rect (in the
                // 4x3 layout "i"/"l"/"," all start at d1:d3), which triples the solver's branching factor
                // for no benefit and can blow its node budget (maxChecks) on dense layouts — exhausting
                // the budget returns a partial assignment that leaves the desktop half-tiled. Keeping one
                // representative per distinct rect (the sort makes it deterministic) keeps the solver fast.
                var seen: [ZTRect] = []
                available = available.filter { c in
                    if seen.contains(where: { abs($0.x - c.rect.x) < 1 && abs($0.y - c.rect.y) < 1
                        && abs($0.w - c.rect.w) < 1 && abs($0.h - c.rect.h) < 1 }) { return false }
                    seen.append(c.rect); return true
                }
                // Hard-cap the candidate set so the CSP's node budget can't be exhausted (which would
                // truncate to a partial, gap-leaving placement). The list is area-sorted, so we keep the
                // biggest/most-useful tiles; stretch-to-fill absorbs any slack a smaller set leaves.
                if available.count > solverTileCap { available = Array(available.prefix(solverTileCap)) }
                if !available.isEmpty && unplaced.count > available.count {
                    subdivide(&available, required: unplaced.count)
                }
                if !available.isEmpty {
                    let snaps = unplaced.map {
                        WindowSnapshot(id: String($0.id), w: $0.frame.w, h: $0.frame.h, memory: memory[$0.app])
                    }
                    let specs = available.map { TileSpec(zone: $0.zone, idx: $0.tile, rect: $0.rect) }
                    let solved = LayoutSolver.solve(windows: snaps, tiles: specs,
                                                    screen: screen.frame, weights: config.weights)
                    for mv in solved {
                        let w = unplaced[mv.windowIndex]
                        let t = available[mv.tileIndex]
                        moves.append(Move(w.id, mid, t.zone, t.tile, t.rect))
                        occupiedByMid[mid]?.append(Occ(frame: t.rect, id: w.id))
                        processed.insert(w.id)
                    }
                }
            }

            // ---- Pass: limbo stack.
            // anchorRect is in the FOCUSED monitor's coord space, so only reuse it for that monitor;
            // every other monitor stacks on its OWN "j" tile (else cross-monitor coords leak — latent
            // since the live caller passes a single screen, but the loop supports >1).
            let limboRect = (mid == anchorMid ? anchorRect : nil)
                ?? zonesByMid[mid]?["j"]?.first ?? ZTRect(x: 0, y: 0, w: 100, h: 100)
            for w in limbo where !processed.contains(w.id) {
                // NOTE: limbo windows are intentionally NOT added to occupiedByMid — they share one
                // stacked rect, and fillGaps is then free to upgrade them onto otherwise-empty tiles
                // (so parked windows fill real estate rather than hide under the stack).
                moves.append(Move(w.id, mid, "limbo", .int(1), limboRect))
                processed.insert(w.id)
            }
        }

        fillGaps(moves: moves, occupiedByMid: occupiedByMid,
                 screenByMid: screenByMid, zonesByMid: zonesByMid, gridByMid: gridByMid)

        // Final pass: grow placed windows into any remaining empty space so the desktop is actually
        // filled (a lone focused window in the center "j" zone, or an odd window count, otherwise
        // leaves whole columns/cells empty). Keeps the configured inter-window margin.
        let m = config.zoneConfig.margins
        stretchToFill(moves: moves, screenByMid: screenByMid,
                      gap: (m?.enabled == true) ? (m?.size ?? 0) : 0)

        // Dedup: last move per window wins (mirrors _execute_moves).
        var byId: [Int: Move] = [:]
        for m in moves { byId[m.windowId] = m }
        return byId.values
            .map { PlannedMove(windowId: $0.windowId, monitorId: $0.monitorId,
                               zoneKey: $0.zoneKey, tileIndex: $0.tileIndex, rect: $0.rect) }
            .sorted { $0.windowId < $1.windowId }
    }

    // _pass_working_set_cull
    private static func cull(_ windows: [Window], zMap: [Int: Int], now: Int,
                             config: Config, memory: [String: [MemoryPref]]) -> (working: [Window], limbo: [Window]) {
        var active: [Window] = []
        var limbo: [Window] = []
        for w in windows {
            if (now - w.lastFocusedTime) > config.workingSetTimeLimit { limbo.append(w) }
            else { active.append(w) }
        }
        var usage: [Int: Int] = [:]
        for w in active { usage[w.id] = (memory[w.app] ?? []).reduce(0) { $0 + ($1.count ?? 0) } }
        func z(_ id: Int) -> Int { zMap[id] ?? 9999 }
        active.sort { a, b in
            let ua = usage[a.id] ?? 0, ub = usage[b.id] ?? 0
            if config.mode == "usage" {
                if ua != ub { return ua > ub }
                if z(a.id) != z(b.id) { return z(a.id) < z(b.id) }
                return a.id < b.id
            } else {
                if z(a.id) != z(b.id) { return z(a.id) < z(b.id) }
                if ua != ub { return ua > ub }
                return a.id < b.id
            }
        }
        var working: [Window] = []
        for (i, w) in active.enumerated() {
            if i < config.workingSetMaxCapacity { working.append(w) } else { limbo.append(w) }
        }
        return (working, limbo)
    }

    // _subdivide_tiles_to_fit (BSP)
    private static func subdivide(_ available: inout [(rect: ZTRect, zone: String, tile: TileIndex)],
                                  required: Int) {
        var iters = 0
        while available.count < required && available.count > 0 && iters < 20 {
            iters += 1
            var largestIdx = 0
            var largestArea = 0.0
            for (i, t) in available.enumerated() {
                let a = t.rect.w * t.rect.h
                if a > largestArea { largestArea = a; largestIdx = i }
            }
            let largest = available[largestIdx]
            if largest.rect.w < 250 && largest.rect.h < 250 { break }
            available.remove(at: largestIdx)
            var r1 = largest.rect, r2 = largest.rect
            if largest.rect.w > largest.rect.h {
                let w1 = floor(largest.rect.w / 2)
                r1.w = w1; r2.w = largest.rect.w - w1; r2.x = largest.rect.x + w1
            } else {
                let h1 = floor(largest.rect.h / 2)
                r1.h = h1; r2.h = largest.rect.h - h1; r2.y = largest.rect.y + h1
            }
            available.append((r1, largest.zone, .string(largest.tile.sortKey + "a")))
            available.append((r2, largest.zone, .string(largest.tile.sortKey + "b")))
        }
    }

    // _pass_fill_gaps — grid-occupancy gap filling (upgrades windows to larger free tiles).
    // `moves` is passed by value but `Move` is a CLASS, so this mutates the caller's Move objects in
    // place (rect/zoneKey/tileIndex) — the array copy shares the references on purpose; the caller reads
    // the upgraded placements after this returns. (Not `inout` because we never reassign the array.)
    private static func fillGaps(moves: [Move], occupiedByMid: [String: [Occ]],
                                 screenByMid: [String: Screen],
                                 zonesByMid: [String: [String: [ZTRect]]],
                                 gridByMid: [String: GridConfig]) {
        func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { max(lo, min(hi, v)) }

        for mid in occupiedByMid.keys.sorted() {
            guard let screen = screenByMid[mid] else { continue }
            let sf = screen.frame
            let totalArea = sf.w * sf.h
            let occRects = occupiedByMid[mid] ?? []
            let occupiedArea = occRects.reduce(0) { $0 + $1.frame.w * $1.frame.h }
            if (totalArea - occupiedArea) < totalArea * 0.1 { continue }
            guard let grid = gridByMid[mid] else { continue }
            let cols = grid.cols, rows = grid.rows
            let cellW = sf.w / Double(cols), cellH = sf.h / Double(rows)

            // grid[c-1][r-1] occupancy
            var occGrid = Array(repeating: Array(repeating: false, count: rows), count: cols)
            for occ in occRects {
                let r = occ.frame
                let x1 = max(0, r.x - sf.x), y1 = max(0, r.y - sf.y)
                let x2 = x1 + r.w, y2 = y1 + r.h
                let c1 = clamp(Int(floor(x1 / cellW)) + 1, 1, cols)
                let c2 = clamp(Int(floor((x2 - 1) / cellW)) + 1, 1, cols)
                let r1 = clamp(Int(floor(y1 / cellH)) + 1, 1, rows)
                let r2 = clamp(Int(floor((y2 - 1) / cellH)) + 1, 1, rows)
                for c in c1...c2 { for ro in r1...r2 { occGrid[c - 1][ro - 1] = true } }
            }

            // Tile grid span (relative to screen origin).
            func span(_ t: ZTRect) -> (Int, Int, Int, Int) {
                let tx = t.x - sf.x, ty = t.y - sf.y
                let c1 = clamp(Int(floor(tx / cellW)) + 1, 1, cols)
                let c2 = clamp(Int(floor((tx + t.w - 1) / cellW)) + 1, 1, cols)
                let r1 = clamp(Int(floor(ty / cellH)) + 1, 1, rows)
                let r2 = clamp(Int(floor((ty + t.h - 1) / cellH)) + 1, 1, rows)
                return (c1, c2, r1, r2)
            }
            func isSpanOccupied(_ c1: Int, _ c2: Int, _ r1: Int, _ r2: Int) -> Bool {
                for c in c1...c2 { for ro in r1...r2 { if occGrid[c - 1][ro - 1] { return true } } }
                return false
            }

            var allTiles: [(rect: ZTRect, zone: String, tile: TileIndex, area: Double)] = []
            for zk in solverZoneKeys {
                guard let tiles = zonesByMid[mid]?[zk] else { continue }
                for (i, t) in tiles.enumerated() {
                    let (c1, c2, r1, r2) = span(t)
                    if !isSpanOccupied(c1, c2, r1, r2) {
                        allTiles.append((t, zk, .int(i + 1), t.w * t.h))
                    }
                }
            }
            if allTiles.isEmpty { continue }
            allTiles.sort { a, b in
                if a.area != b.area { return a.area > b.area }
                if a.zone != b.zone { return a.zone < b.zone }
                return a.tile.sortKey < b.tile.sortKey
            }

            let maxIter = cols * rows
            var improved = true
            var iter = 0
            while improved && iter < maxIter {
                improved = false
                iter += 1
                var sortedMoves = moves.filter { $0.monitorId == mid }
                    .map { (move: $0, area: $0.rect.w * $0.rect.h) }
                sortedMoves.sort { a, b in
                    if a.area != b.area { return a.area < b.area }
                    return a.move.windowId < b.move.windowId
                }
                var usedTiles = Set<Int>()
                for entry in sortedMoves {
                    let m = entry.move
                    let currentArea = entry.area
                    for (tileIdx, tile) in allTiles.enumerated() {
                        if usedTiles.contains(tileIdx) { continue }
                        if tile.area > currentArea {
                            let (c1, c2, r1, r2) = span(tile.rect)
                            if isSpanOccupied(c1, c2, r1, r2) { continue }
                            m.rect = tile.rect
                            m.zoneKey = tile.zone
                            m.tileIndex = tile.tile
                            usedTiles.insert(tileIdx)
                            improved = true
                            for c in c1...c2 { for ro in r1...r2 { occGrid[c - 1][ro - 1] = true } }
                            break
                        }
                    }
                }
            }
        }
    }

    // _pass_stretch_to_fill — grow each placed window outward into adjacent empty space so the desktop
    // is fully used (a single centered window, or an odd count that leaves a column/cell empty). Each
    // window expands left/right/up/down until it is `gap` px from the nearest placed neighbour that
    // shares that edge's span, or `gap` px from the screen edge. Windows are grown in a deterministic
    // order (top-left first) and treated as obstacles once grown, so results never overlap. Limbo
    // windows (stacked, not on the grid) are left alone. Mutates the Move objects in place.
    private static func stretchToFill(moves: [Move], screenByMid: [String: Screen], gap: Double) {
        for mid in screenByMid.keys.sorted() {
            guard let sf = screenByMid[mid]?.frame else { continue }
            let placed = moves.filter { $0.monitorId == mid && $0.zoneKey != "limbo" }
            guard placed.count > 0 else { continue }
            let order = placed.sorted { a, b in
                if a.rect.y != b.rect.y { return a.rect.y < b.rect.y }
                if a.rect.x != b.rect.x { return a.rect.x < b.rect.x }
                return a.windowId < b.windowId
            }
            for mv in order {
                var r = mv.rect
                let others = placed.filter { $0.windowId != mv.windowId }   // current (possibly-grown) rects
                func vSpan(_ o: ZTRect) -> Bool { o.y < r.y + r.h && o.y + o.h > r.y }
                func hSpan(_ o: ZTRect) -> Bool { o.x < r.x + r.w && o.x + o.w > r.x }
                // Left: nearest right-edge of a window to our left that shares our vertical span.
                let left = others.filter { vSpan($0.rect) && $0.rect.x + $0.rect.w <= r.x + 0.5 }
                    .map { $0.rect.x + $0.rect.w + gap }.max() ?? (sf.x + gap)
                let newX = min(r.x, max(left, sf.x + gap))
                r.w += r.x - newX; r.x = newX
                // Right: nearest left-edge of a window to our right.
                let right = others.filter { vSpan($0.rect) && $0.rect.x >= r.x + r.w - 0.5 }
                    .map { $0.rect.x - gap }.min() ?? (sf.x + sf.w - gap)
                r.w = max(r.w, min(right, sf.x + sf.w - gap) - r.x)
                // Up: nearest bottom-edge of a window above us that shares our (now-grown) horizontal span.
                let up = others.filter { hSpan($0.rect) && $0.rect.y + $0.rect.h <= r.y + 0.5 }
                    .map { $0.rect.y + $0.rect.h + gap }.max() ?? (sf.y + gap)
                let newY = min(r.y, max(up, sf.y + gap))
                r.h += r.y - newY; r.y = newY
                // Down: nearest top-edge of a window below us.
                let down = others.filter { hSpan($0.rect) && $0.rect.y >= r.y + r.h - 0.5 }
                    .map { $0.rect.y - gap }.min() ?? (sf.y + sf.h - gap)
                r.h = max(r.h, min(down, sf.y + sf.h - gap) - r.y)
                mv.rect = r
            }
        }
    }
}
