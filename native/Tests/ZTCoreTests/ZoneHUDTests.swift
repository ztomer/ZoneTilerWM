// ZoneHUDTests — pure layout for the zone cheat-sheet overlay.

import XCTest
@testable import ZTCore

final class ZoneHUDTests: XCTestCase {

    func testOneCellPerZoneExcludingDefault() {
        let zones: [String: [ZTRect]] = [
            "h": [ZTRect(x: 0, y: 0, w: 500, h: 1000)],
            "l": [ZTRect(x: 500, y: 0, w: 500, h: 1000)],
            "default": [ZTRect(x: 0, y: 0, w: 1000, h: 1000)],
        ]
        let cells = ZoneHUD.layout(zones: zones)
        XCTAssertEqual(cells.map { $0.key }, ["h", "l"])   // sorted, no "default"
        XCTAssertEqual(cells.first { $0.key == "h" }?.rect, ZTRect(x: 0, y: 0, w: 500, h: 1000))
    }

    func testUsesPrimaryPlacementNotCycleUnion() {
        // A zone key cycles through placements ("y" = [top-left, left-half, top-half]); the chip
        // sits at the FIRST placement (where pressing once lands it), NOT the union of the cycle —
        // the union spans most of the screen and wrongly centres the chip.
        let zones: [String: [ZTRect]] = [
            "y": [ZTRect(x: 0, y: 0, w: 300, h: 500),    // a1 — top-left (primary)
                  ZTRect(x: 0, y: 0, w: 300, h: 1000),   // a1:a2 — left half
                  ZTRect(x: 0, y: 0, w: 1000, h: 500)],  // a1:b1 — top half
        ]
        XCTAssertEqual(ZoneHUD.layout(zones: zones).first?.rect, ZTRect(x: 0, y: 0, w: 300, h: 500))
    }

    func testEmptyZonesYieldNoCells() {
        XCTAssertTrue(ZoneHUD.layout(zones: [:]).isEmpty)
        XCTAssertTrue(ZoneHUD.layout(zones: ["k": []]).isEmpty)
    }
}
