// AutoTilerTests — behavioral spec for the AutoTiler port. Full Lua↔Swift parity is covered
// by tools/diff_autotiler.sh (600 fuzz seeds); these assert a few intended behaviors directly.

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
}
