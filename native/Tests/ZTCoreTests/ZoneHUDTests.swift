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

    func testBoundingBoxUnionsMultiTileZone() {
        let zones: [String: [ZTRect]] = [
            "j": [ZTRect(x: 0, y: 0, w: 300, h: 500), ZTRect(x: 300, y: 0, w: 200, h: 1000)],
        ]
        XCTAssertEqual(ZoneHUD.layout(zones: zones).first?.rect, ZTRect(x: 0, y: 0, w: 500, h: 1000))
    }

    func testEmptyZonesYieldNoCells() {
        XCTAssertTrue(ZoneHUD.layout(zones: [:]).isEmpty)
        XCTAssertTrue(ZoneHUD.layout(zones: ["k": []]).isEmpty)
    }
}
