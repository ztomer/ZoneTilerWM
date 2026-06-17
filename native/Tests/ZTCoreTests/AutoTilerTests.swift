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
}
