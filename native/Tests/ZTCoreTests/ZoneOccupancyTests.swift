// ZoneOccupancyTests — locks the IoU zone-matching used by the arrangement resource. The key
// regression: a window placed exactly into a small zone must report THAT zone, not a larger
// nesting zone that also contains it (caught during live MCP validation).

import XCTest
@testable import ZTCore

final class ZoneOccupancyTests: XCTestCase {

    // A left-half tile "h" nested inside a wide left "0" tile that also contains it.
    private let zones: [String: [ZTRect]] = [
        "h": [ZTRect(x: 0, y: 0, w: 960, h: 1080)],
        "0": [ZTRect(x: 0, y: 0, w: 1280, h: 1080)],
        "l": [ZTRect(x: 960, y: 0, w: 960, h: 1080)],
    ]

    func testExactMatchPrefersTightestZoneNotContainingZone() {
        // Window sits exactly in "h"; "0" also fully contains it. IoU must pick "h".
        let win = ZTRect(x: 0, y: 0, w: 960, h: 1080)
        XCTAssertEqual(ZoneOccupancy.bestZone(window: win, zones: zones), "h")
    }

    func testWindowInWideZoneReportsThatZone() {
        let win = ZTRect(x: 0, y: 0, w: 1280, h: 1080)
        XCTAssertEqual(ZoneOccupancy.bestZone(window: win, zones: zones), "0")
    }

    func testWindowInRightHalf() {
        let win = ZTRect(x: 960, y: 0, w: 960, h: 1080)
        XCTAssertEqual(ZoneOccupancy.bestZone(window: win, zones: zones), "l")
    }

    func testFloatingWindowMatchesNoZone() {
        // A small centered window overlapping no tile well enough (IoU < 0.5).
        let win = ZTRect(x: 600, y: 400, w: 200, h: 200)
        XCTAssertNil(ZoneOccupancy.bestZone(window: win, zones: zones))
    }

    func testDefaultPseudoZoneIgnored() {
        let z = ["default": [ZTRect(x: 0, y: 0, w: 100, h: 100)], "h": [ZTRect(x: 0, y: 0, w: 100, h: 100)]]
        XCTAssertEqual(ZoneOccupancy.bestZone(window: ZTRect(x: 0, y: 0, w: 100, h: 100), zones: z), "h")
    }

    func testIoUIsSymmetricAndBounded() {
        let a = ZTRect(x: 0, y: 0, w: 100, h: 100)
        XCTAssertEqual(ZoneOccupancy.intersectionOverUnion(a, a), 1.0, accuracy: 1e-9)
        let disjoint = ZTRect(x: 200, y: 200, w: 50, h: 50)
        XCTAssertEqual(ZoneOccupancy.intersectionOverUnion(a, disjoint), 0.0, accuracy: 1e-9)
    }
}
