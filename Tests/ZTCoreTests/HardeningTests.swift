// HardeningTests — degenerate / malformed-input guards added in the hardening pass. These
// inputs never arise from real AX frames or valid configs, but the algorithms must stay
// finite and non-crashing on them (no Inf/NaN, no silent mis-parse).

import XCTest
@testable import ZTCore

final class HardeningTests: XCTestCase {

    private let screen = ZTRect(x: 0, y: 0, w: 1000, h: 1000)
    private func tile(_ r: ZTRect) -> TileSpec { TileSpec(zone: "j", idx: .int(1), rect: r) }

    // MARK: - ZoneCalculator grid-coord parsing (anchored regex)

    func testGridCoordsRejectsMalformed() {
        // Well-formed still parses.
        XCTAssertNotNil(ZoneCalculator.parseGridCoords("a1"))
        XCTAssertNotNil(ZoneCalculator.parseGridCoords("a1:b2"))
        XCTAssertNotNil(ZoneCalculator.parseGridCoords("d12"))
        // Malformed now returns nil (previously "abc1" mis-parsed as c1, "a1:2" as a single cell).
        XCTAssertNil(ZoneCalculator.parseGridCoords("abc1"))
        XCTAssertNil(ZoneCalculator.parseGridCoords("a1:2"))
        XCTAssertNil(ZoneCalculator.parseGridCoords("a1:"))
        XCTAssertNil(ZoneCalculator.parseGridCoords("1a"))
        XCTAssertNil(ZoneCalculator.parseGridCoords(""))
        XCTAssertNil(ZoneCalculator.parseGridCoords("nonsense"))
    }

    func testGridCoordsValuesUnchanged() {
        let r = ZoneCalculator.parseGridCoords("a1:b2")
        XCTAssertEqual(r?.colStart, 1); XCTAssertEqual(r?.rowStart, 1)
        XCTAssertEqual(r?.colEnd, 2); XCTAssertEqual(r?.rowEnd, 2)
        let single = ZoneCalculator.parseGridCoords("c3")
        XCTAssertEqual(single?.colStart, 3); XCTAssertEqual(single?.colEnd, 3)
        XCTAssertEqual(single?.rowStart, 3); XCTAssertEqual(single?.rowEnd, 3)
    }

    // MARK: - LayoutSolver cost stays finite on degenerate dims

    func testAssignmentCostFiniteForZeroDimensions() {
        let t = tile(ZTRect(x: 0, y: 0, w: 500, h: 500))
        // Zero-height window (winAR would be Inf without the guard).
        let c1 = LayoutSolver.assignmentCost(window: WindowSnapshot(id: "x", w: 100, h: 0),
                                             tile: t, screen: screen, windowRank: 1, weights: CostWeights())
        XCTAssertTrue(c1.isFinite)
        // Zero-area screen (every area ratio would be NaN).
        let c2 = LayoutSolver.assignmentCost(window: WindowSnapshot(id: "x", w: 100, h: 100),
                                             tile: t, screen: ZTRect(x: 0, y: 0, w: 0, h: 0),
                                             windowRank: 1, weights: CostWeights())
        XCTAssertTrue(c2.isFinite)
    }

    func testSolveFiniteCostsWithDegenerateWindow() {
        let moves = LayoutSolver.solve(
            windows: [WindowSnapshot(id: "x", w: 100, h: 0)],
            tiles: [TileSpec(zone: "j", idx: .int(1), rect: ZTRect(x: 0, y: 0, w: 500, h: 500))],
            screen: screen)
        XCTAssertTrue(moves.allSatisfy { $0.cost.isFinite })
    }

    // MARK: - SmartPlacer skips zero-area tiles

    func testSmartPlacerSkipsZeroAreaTile() {
        let zones = [SmartPlacer.Zone(zoneKey: "j", tiles: [
            ZTRect(x: 0, y: 0, w: 0, h: 0),       // degenerate — must be skipped
            ZTRect(x: 0, y: 0, w: 500, h: 500),   // the real choice
        ])]
        let p = SmartPlacer.findBestTile(screen: screen, zones: zones, occupied: [])
        XCTAssertEqual(p?.tile, ZTRect(x: 0, y: 0, w: 500, h: 500))
        XCTAssertTrue((p?.overlapRatio ?? 0).isFinite)
    }

    // MARK: - WindowMemory doesn't poison the mean on zero screen height

    func testWindowMemoryFiniteMeanOnZeroScreenHeight() {
        let mem = WindowMemory()
        mem.positionWindow(windowId: 1, app: "A", monitor: "1", zone: "j", tile: .int(1),
                           winW: 500, winH: 400, screenW: 1000, screenH: 0)
        mem.flush(windowId: 1)
        let r = mem.rankedPreferences(app: "A", monitor: "1").first
        XCTAssertNotNil(r)
        XCTAssertTrue((r?.meanArea ?? 0).isFinite)
        XCTAssertEqual(r?.meanArea, 0)   // the degenerate sample contributes 0, not Inf
    }
}
