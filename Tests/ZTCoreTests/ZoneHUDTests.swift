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

    // MARK: - caps (smallest-tile keycap placement; collision-split; drop auto-tile keys)

    func testCapsCentreAtTheSmallestTileNotThePrimary() {
        // "y" cycles big→small; the cap belongs at the centre of the SMALL atomic cell, not the big one.
        let zones: [String: [ZTRect]] = [
            "y": [ZTRect(x: 0, y: 0, w: 500, h: 250),   // primary (big)
                  ZTRect(x: 0, y: 0, w: 250, h: 250)],  // smallest (the atomic cell)
        ]
        let caps = ZoneHUD.caps(zones: zones)
        XCTAssertEqual(caps.map(\.key), ["y"])
        XCTAssertEqual(caps[0].x, 125)   // centre of the 250×250 cell
        XCTAssertEqual(caps[0].y, 125)
    }

    func testCapsExcludeAutoTileKeys() {
        let zones: [String: [ZTRect]] = [
            "0": [ZTRect(x: 0, y: 0, w: 1000, h: 1000)],       // auto-tile-all — not a spatial zone
            "default": [ZTRect(x: 0, y: 0, w: 1000, h: 1000)],
            "h": [ZTRect(x: 0, y: 0, w: 250, h: 250)],
        ]
        XCTAssertEqual(ZoneHUD.caps(zones: zones).map(\.key), ["h"])
    }

    func testCapsSplitCollidingCellsSideBySideSymmetrically() {
        // The real 4x3 config reduces i & o to the same cell — both must stay visible, split horizontally.
        let cell = ZTRect(x: 750, y: 0, w: 250, h: 250)   // centre (875, 125)
        let caps = ZoneHUD.caps(zones: ["i": [cell], "o": [cell]])
        XCTAssertEqual(caps.map(\.key), ["i", "o"])
        XCTAssertEqual(caps[0].y, 125); XCTAssertEqual(caps[1].y, 125)
        XCTAssertLessThan(caps[0].x, caps[1].x)                        // i (sorted first) sits left of o
        XCTAssertEqual((caps[0].x + caps[1].x) / 2, 875, accuracy: 0.01)  // symmetric about the cell centre
    }
}
