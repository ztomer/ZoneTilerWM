// AutoTilerTests — behavioral spec for the AutoTiler port. Full Lua↔Swift parity was originally
// validated by the (now-removed) tools/diff_autotiler.sh differential oracle (600 fuzz seeds, Lua
// commit 34129c5); that harness was deleted with the Lua. These tests + the frozen golden corpus in
// Tests/Fixtures are now the spec.

import XCTest
@testable import ZTCore

final class AutoTilerTests: XCTestCase {

    private let screen = AutoTiler.Screen(uuid: "M1", name: "Internal",
                                          frame: ZTRect(x: 0, y: 0, w: 1512, h: 982))

    private func config() -> AutoTiler.Config {
        // Minimal 2x2 layout; "j" spans the full screen (a1:b2).
        let zc = ZoneConfig(
            grids: ["2x2": GridConfig(cols: 2, rows: 2)],
            layouts: ["2x2": ["j": ["a1:b2"], "y": ["a1"], "i": ["b1"], "n": ["a2"], ",": ["b2"]]],
            margins: Margins(enabled: false, size: 0, screen_edge: false))
        return AutoTiler.Config(centerZones: ["j", "center", "0"],
                                workingSetTimeLimit: 1800, workingSetMaxCapacity: 6,
                                mode: "usage", weights: CostWeights(), zoneConfig: zc)
    }

    func testNoWindowsNoMoves() {
        let moves = AutoTiler.plan(config: config(), screens: [screen], windows: [],
                                   zOrder: [], focusedId: nil, memory: [:], now: 10_000)
        XCTAssertTrue(moves.isEmpty)
    }

    func testFocusedWindowAnchorsToCenterZone() {
        let w = AutoTiler.Window(id: 1, app: "Safari", monitor: "M1",
                                 frame: ZTRect(x: 0, y: 0, w: 800, h: 600), lastFocusedTime: 10_000)
        let moves = AutoTiler.plan(config: config(), screens: [screen], windows: [w],
                                   zOrder: [1], focusedId: 1, memory: [:], now: 10_000)
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves.first?.zoneKey, "j")
        XCTAssertEqual(moves.first?.tileIndex, .int(1))
        XCTAssertEqual(moves.first?.rect, screen.frame)  // "j" = full screen, margins off
    }

    func testStaleWindowGoesToLimbo() {
        // Not focused, last focused well beyond the working-set time limit -> limbo.
        let w = AutoTiler.Window(id: 1, app: "Mail", monitor: "M1",
                                 frame: ZTRect(x: 0, y: 0, w: 400, h: 400), lastFocusedTime: 1_000)
        let moves = AutoTiler.plan(config: config(), screens: [screen], windows: [w],
                                   zOrder: [1], focusedId: nil, memory: [:], now: 10_000)
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves.first?.zoneKey, "limbo")
    }

    private func config(capacity: Int) -> AutoTiler.Config {
        let zc = ZoneConfig(
            grids: ["2x2": GridConfig(cols: 2, rows: 2)],
            layouts: ["2x2": ["j": ["a1:b2"], "y": ["a1"], "i": ["b1"], "n": ["a2"], ",": ["b2"]]],
            margins: Margins(enabled: false, size: 0, screen_edge: false))
        return AutoTiler.Config(centerZones: ["j", "center", "0"],
                                workingSetTimeLimit: 1800, workingSetMaxCapacity: capacity,
                                mode: "usage", weights: CostWeights(), zoneConfig: zc)
    }

    func testWorkingSetCapacityCullsExcessToLimbo() {
        // Three recent windows but capacity is 2: the lowest-priority one (no usage, last in
        // z-order) is culled to limbo; the other two are tiled into real zones.
        let wins = (1...3).map {
            AutoTiler.Window(id: $0, app: "App\($0)", monitor: "M1",
                             frame: ZTRect(x: 0, y: 0, w: 400, h: 400), lastFocusedTime: 10_000)
        }
        let moves = AutoTiler.plan(config: config(capacity: 2), screens: [screen], windows: wins,
                                   zOrder: [1, 2, 3], focusedId: nil, memory: [:], now: 10_000)
        let limbo = moves.filter { $0.zoneKey == "limbo" }.map { $0.windowId }
        XCTAssertEqual(limbo, [3], "window 3 (last in z-order, no usage) is culled past capacity 2")
        XCTAssertTrue(moves.filter { [1, 2].contains($0.windowId) }.allSatisfy { $0.zoneKey != "limbo" })
    }

    func testMemoryBiasesNonFocusedPlacement() {
        // A single non-focused, recent window with an exact memory preference for zone "i"
        // (top-right, b1) should be placed there — memoryExact dominates the cost.
        let w = AutoTiler.Window(id: 1, app: "Slack", monitor: "M1",
                                 frame: ZTRect(x: 0, y: 0, w: 756, h: 491), lastFocusedTime: 10_000)
        let memory = ["Slack": [MemoryPref(zone_key: "i", tile_index: .int(1), count: 50)]]
        let moves = AutoTiler.plan(config: config(), screens: [screen], windows: [w],
                                   zOrder: [1], focusedId: nil, memory: memory, now: 10_000)
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves.first?.zoneKey, "i")
    }

    // A second display to the RIGHT of M1 (origin x = 1512), so anything in M1's coord space is
    // distinguishable from M2's (x >= 1512).
    private let screen2 = AutoTiler.Screen(uuid: "M2", name: "External",
                                           frame: ZTRect(x: 1512, y: 0, w: 1512, h: 982))

    func testMultiMonitorLimboStaysOnItsOwnMonitor() {
        // Regression for the latent cross-monitor limbo bug: with a focused window on M1 (which sets
        // anchorRect in M1's coord space), a stale window on M2 must be stacked on M2 — NOT at M1's
        // anchor rect. The fix scopes anchorRect to the focused monitor only.
        let focused = AutoTiler.Window(id: 1, app: "Safari", monitor: "M1",
                                       frame: ZTRect(x: 0, y: 0, w: 800, h: 600), lastFocusedTime: 10_000)
        let staleOnM2 = AutoTiler.Window(id: 2, app: "Mail", monitor: "M2",
                                         frame: ZTRect(x: 1512, y: 0, w: 400, h: 400), lastFocusedTime: 1_000)
        let moves = AutoTiler.plan(config: config(), screens: [screen, screen2],
                                   windows: [focused, staleOnM2], zOrder: [1, 2],
                                   focusedId: 1, memory: [:], now: 10_000)
        let m2limbo = moves.first { $0.windowId == 2 }
        XCTAssertEqual(m2limbo?.zoneKey, "limbo")
        XCTAssertEqual(m2limbo?.monitorId, "M2")
        // The crux: M2's limbo rect is on M2 (x >= 1512), not leaked into M1's space (x == 0).
        XCTAssertGreaterThanOrEqual(m2limbo?.rect.x ?? -1, screen2.frame.x)
    }

    func testSubdivideCreatesTilesWhenWindowsExceedZones() {
        // One usable zone ("j" = full screen) but three windows → the BSP subdivider must split it into
        // enough non-overlapping tiles for the solver to place them.
        let zc = ZoneConfig(grids: ["2x2": GridConfig(cols: 2, rows: 2)],
                            layouts: ["2x2": ["j": ["a1:b2"]]],
                            margins: Margins(enabled: false, size: 0, screen_edge: false))
        let cfg = AutoTiler.Config(centerZones: ["does-not-exist"], workingSetTimeLimit: 1800,
                                   workingSetMaxCapacity: 6, mode: "usage",
                                   weights: CostWeights(), zoneConfig: zc)
        let wins = (1...3).map {
            AutoTiler.Window(id: $0, app: "App\($0)", monitor: "M1",
                             frame: ZTRect(x: 0, y: 0, w: 600, h: 500), lastFocusedTime: 10_000)
        }
        let moves = AutoTiler.plan(config: cfg, screens: [screen], windows: wins,
                                   zOrder: [1, 2, 3], focusedId: nil, memory: [:], now: 10_000)
        XCTAssertEqual(moves.count, 3, "all three windows placed into subdivided tiles")
        // Subdivide produces string tile ids ("1a"/"1b"/…); at least one placement must use one.
        XCTAssertTrue(moves.contains { if case .string = $0.tileIndex { return true }; return false },
                      "the BSP splitter ran (a split-tile id is present)")
        // The placements must be mutually non-overlapping (the split tiles are disjoint).
        for a in 0..<moves.count {
            for b in (a + 1)..<moves.count {
                XCTAssertFalse(rectsOverlap(moves[a].rect, moves[b].rect),
                               "placed windows \(moves[a].windowId)/\(moves[b].windowId) overlap")
            }
        }
    }

    func testFillGapsUpgradesToLargerFreeTile() {
        // A window parked in a quarter zone ("y" = a1) with the right half ("l" = b1:b2) free: fillGaps
        // should upgrade it onto the larger free tile rather than leave the half-screen empty.
        let zc = ZoneConfig(grids: ["2x2": GridConfig(cols: 2, rows: 2)],
                            layouts: ["2x2": ["y": ["a1"], "l": ["b1:b2"], "j": ["a1:b2"]]],
                            margins: Margins(enabled: false, size: 0, screen_edge: false))
        let cfg = AutoTiler.Config(centerZones: ["does-not-exist"], workingSetTimeLimit: 1800,
                                   workingSetMaxCapacity: 6, mode: "usage",
                                   weights: CostWeights(), zoneConfig: zc)
        let w = AutoTiler.Window(id: 1, app: "Notes", monitor: "M1",
                                 frame: ZTRect(x: 0, y: 0, w: 300, h: 300), lastFocusedTime: 10_000)
        let memory = ["Notes": [MemoryPref(zone_key: "y", tile_index: .int(1), count: 9)]]
        let moves = AutoTiler.plan(config: cfg, screens: [screen], windows: [w],
                                   zOrder: [1], focusedId: nil, memory: memory, now: 10_000)
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves.first?.zoneKey, "l", "fillGaps upgraded the quarter-tile window to the free half")
        // …then stretch-to-fill grows the lone window to the whole screen (margins off here, so full).
        XCTAssertEqual(moves.first?.rect, ZTRect(x: 0, y: 0, w: 1512, h: 982))
    }

    // Property-based fuzz: across thousands of random layouts / screen sizes / window counts / sizes /
    // margins, the stretch-to-fill pass must ALWAYS hold its safety invariants (no overlap, on-screen)
    // and its purpose (high coverage). Catches overlap/escape combos a few hand-picked cases would miss.
    func testStretchToFillInvariantsFuzz() {
        struct LCG { var s: UInt64
            mutating func u() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
            mutating func i(_ lo: Int, _ hi: Int) -> Int { lo + Int((u() >> 33)) % (hi - lo + 1) } }

        // Two real layouts spanning simple → complex.
        let l2x2: [String: [String]] = ["y": ["a1"], "h": ["a1:a2"], "n": ["a2"], "u": ["a1:b1"],
            "j": ["a1:b2"], "m": ["a2:b2"], "i": ["b1"], "k": ["b1:b2"], ",": ["b2"], "0": ["a1:b2"]]
        let l4x3: [String: [String]] = ["y": ["a1:a2", "a1"], "h": ["a1:b3", "a1:a3", "a2"], "n": ["a3"],
            "u": ["b1:b3", "b1"], "j": ["b1:c3", "b2"], "m": ["b1:b3", "b3"], "i": ["d1:d3", "d1"],
            "k": ["c1:d3", "c2"], ",": ["d1:d3", "d3"], "o": ["c1:d1"], "l": ["d1:d3", "d2"], "0": ["a1:d3"]]
        let grids = [("2x2", 2, 2, l2x2), ("4x3", 4, 3, l4x3)]

        var lcg = LCG(s: 0xDEADBEEF)
        var minCoverage = 1.0, overlaps = 0, escapes = 0
        let trials = 3000
        for _ in 0..<trials {
            let (gk, cols, rows, layout) = grids[lcg.i(0, 1)]
            let sw = Double(lcg.i(1000, 4000)), sh = Double(lcg.i(800, 2400))
            let ox = Double(lcg.i(0, 200)), oy = Double(lcg.i(0, 100))   // non-zero screen origin too
            let marginsOn = lcg.i(0, 1) == 1
            let zc = ZoneConfig(grids: [gk: GridConfig(cols: cols, rows: rows)], layouts: [gk: layout],
                                margins: Margins(enabled: marginsOn, size: Double(lcg.i(0, 12)), screen_edge: marginsOn))
            let cfg = AutoTiler.Config(centerZones: ["j", "0"], workingSetTimeLimit: 1800,
                                       workingSetMaxCapacity: 6, mode: "usage", weights: CostWeights(), zoneConfig: zc)
            let screen = AutoTiler.Screen(uuid: "S", name: "fuzz", frame: ZTRect(x: ox, y: oy, w: sw, h: sh))
            let n = lcg.i(1, 6)   // <= capacity, so nothing goes to limbo (coverage stays meaningful)
            let wins = (1...n).map { AutoTiler.Window(id: $0, app: "A\($0)", monitor: "S",
                frame: ZTRect(x: 0, y: 0, w: Double(lcg.i(200, Int(sw))), h: Double(lcg.i(200, Int(sh)))),
                lastFocusedTime: 10_000) }
            let focused = lcg.i(0, 1) == 1 ? 1 : nil
            let placed = AutoTiler.plan(config: cfg, screens: [screen], windows: wins,
                                        zOrder: Array(1...n), focusedId: focused, memory: [:], now: 10_000)
                .filter { $0.zoneKey != "limbo" }

            for a in 0..<placed.count {
                // On-screen (0.5px float tolerance).
                let r = placed[a].rect
                if r.x < screen.frame.x - 0.5 || r.y < screen.frame.y - 0.5
                    || r.x + r.w > screen.frame.x + screen.frame.w + 0.5
                    || r.y + r.h > screen.frame.y + screen.frame.h + 0.5 { escapes += 1 }
                for b in (a + 1)..<placed.count where rectsOverlap(placed[a].rect, placed[b].rect) { overlaps += 1 }
            }
            let cov = placed.reduce(0.0) { $0 + $1.rect.w * $1.rect.h } / (sw * sh)
            if !placed.isEmpty { minCoverage = min(minCoverage, cov) }
        }
        print("FUZZ \(trials) trials: overlaps=\(overlaps) escapes=\(escapes) minCoverage=\(String(format: "%.3f", minCoverage))")
        XCTAssertEqual(overlaps, 0, "stretched windows must never overlap")
        XCTAssertEqual(escapes, 0, "stretched windows must never leave the screen")
        XCTAssertGreaterThan(minCoverage, 0.80, "stretch should fill the screen well across all layouts")
    }

    func testDenseRealLayoutFillsScreenNoTruncationGaps() {
        // The real DELL 4x3 produces ~34 candidate tiles (many zones share a rect); before the dedup +
        // cap, the CSP solver exhausted its node budget on n=6 and returned a partial, gap-leaving
        // placement. With 9 windows (>capacity → limbo) the screen must still end up ~fully covered.
        let layout4x3: [String: [String]] = [
            "y": ["a1:a2", "a1", "a1:b2"], "h": ["a1:b3", "a1:a3", "a1:c3", "a2"],
            "n": ["a3", "a2:a3", "a3:b3"], "u": ["b1:b3", "b1:b2", "b1", "b1:c1"],
            "j": ["b1:c3", "b1:b3", "b2", "b1:d3"], "m": ["b1:b3", "b2:c3", "b3"],
            "i": ["d1:d3", "d1:d2", "d1"], "k": ["c1:d3", "c1:c3", "c2"],
            ",": ["d1:d3", "d2:d3", "d3"], "o": ["c1:d1", "d1", "c1:d2"],
            "l": ["d1:d3", "c1:d3", "b1:d3", "d2"], ".": ["d3", "d2:d3", "c3:d3"], "0": ["a1:d3"],
        ]
        let zc = ZoneConfig(grids: ["4x3": GridConfig(cols: 4, rows: 3)], layouts: ["4x3": layout4x3],
                            margins: Margins(enabled: true, size: 5, screen_edge: true),
                            custom_screens: ["DELL U3223QE": CustomScreen(layout: "4x3")])
        let cfg = AutoTiler.Config(centerZones: ["j", "center", "0"], workingSetTimeLimit: 1800,
                                   workingSetMaxCapacity: 6, mode: "usage", weights: CostWeights(), zoneConfig: zc)
        let screen = AutoTiler.Screen(uuid: "D", name: "DELL U3223QE", frame: ZTRect(x: 0, y: 30, w: 3360, h: 1860))
        let sizes: [(Double, Double)] = [(2400, 1500), (900, 1400), (1600, 900), (835, 1235),
                                         (1200, 800), (3000, 1800), (700, 1300), (1900, 1100), (1000, 1000)]
        let wins = sizes.enumerated().map { (i, s) in AutoTiler.Window(id: i + 1, app: "A\(i)", monitor: "D",
            frame: ZTRect(x: 0, y: 0, w: s.0, h: s.1), lastFocusedTime: 10_000) }
        let placed = AutoTiler.plan(config: cfg, screens: [screen], windows: wins,
                                    zOrder: Array(1...9), focusedId: 1, memory: [:], now: 10_000)
            .filter { $0.zoneKey != "limbo" }
        let cov = placed.reduce(0.0) { $0 + $1.rect.w * $1.rect.h } / (3360 * 1860)
        XCTAssertGreaterThan(cov, 0.95, "dense real layout must fill the screen (no truncation gaps)")
        for a in 0..<placed.count { for b in (a + 1)..<placed.count {
            XCTAssertFalse(rectsOverlap(placed[a].rect, placed[b].rect)) } }
    }

    func testStretchToFillCoversScreenWithoutOverlap() {
        // The whole point: after tiling, the desktop is actually full. Use the real DELL 4x3 layout
        // (where the focused "j" zone is only the middle half) — a single window must still fill the
        // screen, and N windows must cover ~all of it with no overlaps and the configured margin kept.
        let layout4x3: [String: [String]] = [
            "y": ["a1:a2", "a1"], "h": ["a1:b3", "a1:a3", "a2"], "n": ["a3", "a2:a3"],
            "u": ["b1:b3", "b1"], "j": ["b1:c3", "b2"], "m": ["b1:b3", "b3"],
            "i": ["d1:d3", "d1"], "k": ["c1:d3", "c2"], ",": ["d1:d3", "d3"],
            "o": ["c1:d1", "d1"], "l": ["d1:d3", "d2"], ".": ["d3"], "0": ["a1:d3"],
        ]
        let zc = ZoneConfig(grids: ["4x3": GridConfig(cols: 4, rows: 3)],
                            layouts: ["4x3": layout4x3],
                            margins: Margins(enabled: true, size: 5, screen_edge: true))
        let cfg = AutoTiler.Config(centerZones: ["j", "center", "0"], workingSetTimeLimit: 1800,
                                   workingSetMaxCapacity: 6, mode: "usage", weights: CostWeights(), zoneConfig: zc)
        let big = AutoTiler.Screen(uuid: "D", name: "DELL U3223QE", frame: ZTRect(x: 0, y: 0, w: 3840, h: 2160))
        let area = 3840.0 * 2160.0

        for n in [1, 2, 3, 6] {
            let wins = (1...n).map { AutoTiler.Window(id: $0, app: "A\($0)", monitor: "D",
                frame: ZTRect(x: 0, y: 0, w: 1200, h: 900), lastFocusedTime: 10_000) }
            let moves = AutoTiler.plan(config: cfg, screens: [big], windows: wins,
                                       zOrder: Array(1...n), focusedId: 1, memory: [:], now: 10_000)
            let placed = moves.filter { $0.zoneKey != "limbo" }
            let covered = placed.reduce(0.0) { $0 + $1.rect.w * $1.rect.h }
            XCTAssertGreaterThan(covered / area, 0.97, "n=\(n): autotile should fill ≥97% of the screen")
            // No two placed windows overlap.
            for i in 0..<placed.count {
                for j in (i + 1)..<placed.count {
                    XCTAssertFalse(rectsOverlap(placed[i].rect, placed[j].rect),
                                   "n=\(n): windows \(placed[i].windowId)/\(placed[j].windowId) overlap")
                }
            }
            // Everything stays on-screen.
            for p in placed {
                XCTAssertGreaterThanOrEqual(p.rect.x, big.frame.x - 0.5)
                XCTAssertGreaterThanOrEqual(p.rect.y, big.frame.y - 0.5)
                XCTAssertLessThanOrEqual(p.rect.x + p.rect.w, big.frame.x + big.frame.w + 0.5)
                XCTAssertLessThanOrEqual(p.rect.y + p.rect.h, big.frame.y + big.frame.h + 0.5)
            }
        }
    }
}
