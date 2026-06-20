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
