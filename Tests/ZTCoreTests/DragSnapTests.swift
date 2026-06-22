// DragSnapTests — pure target-zone selection for drag-to-snap.

import XCTest
@testable import ZTCore

final class DragSnapTests: XCTestCase {

    // a 2-up screen: left half "h", right half "l", whole-screen "default" marker.
    private let twoUp: [String: [ZTRect]] = [
        "h": [ZTRect(x: 0, y: 0, w: 500, h: 1000)],
        "l": [ZTRect(x: 500, y: 0, w: 500, h: 1000)],
        "default": [ZTRect(x: 0, y: 0, w: 1000, h: 1000)],
    ]

    func testPointInsideZonePicksThatZone() {
        XCTAssertEqual(DragSnap.target(atX: 100, y: 500, zones: twoUp), "h")
        XCTAssertEqual(DragSnap.target(atX: 900, y: 500, zones: twoUp), "l")
    }

    func testDefaultMarkerNeverChosenEvenWhenItAlsoContains() {
        // "default" (whole screen) contains every point but must be excluded; the smaller,
        // most-specific zone wins instead.
        XCTAssertEqual(DragSnap.target(atX: 250, y: 250, zones: twoUp), "h")
    }

    func testSmallestContainingZoneWins() {
        // overlapping boxes: a big "full" and a small "tl" in the top-left corner.
        let zones: [String: [ZTRect]] = [
            "full": [ZTRect(x: 0, y: 0, w: 1000, h: 1000)],
            "tl": [ZTRect(x: 0, y: 0, w: 200, h: 200)],
        ]
        XCTAssertEqual(DragSnap.target(atX: 50, y: 50, zones: zones), "tl")     // inside both → smaller
        XCTAssertEqual(DragSnap.target(atX: 600, y: 600, zones: zones), "full") // only the big one
    }

    func testDropInGapFallsBackToNearestCentre() {
        // two boxes with a gap between them; a drop in the gap snaps to the nearer centre.
        let zones: [String: [ZTRect]] = [
            "a": [ZTRect(x: 0, y: 0, w: 400, h: 1000)],     // centre x = 200
            "b": [ZTRect(x: 600, y: 0, w: 400, h: 1000)],   // centre x = 800
        ]
        XCTAssertEqual(DragSnap.target(atX: 450, y: 500, zones: zones), "a")  // gap, closer to a
        XCTAssertEqual(DragSnap.target(atX: 550, y: 500, zones: zones), "b")  // gap, closer to b
    }

    func testMultiTileZoneResolvesToActualTileNotUnionBBox() {
        // Regression for "drop on j, land in n": a keyboard-grid zone maps to SEVERAL cycle tiles.
        // "j" cycles between the top-left and bottom-RIGHT cells, so its UNION bounding box is the
        // whole screen and overlaps "n". Matching the union bbox would let the smaller "n" bbox win
        // for a drop squarely inside j's bottom-right tile. Matching the actual tile picks "j".
        let zones: [String: [ZTRect]] = [
            "j": [ZTRect(x: 0, y: 0, w: 300, h: 300),        // top-left cell
                  ZTRect(x: 700, y: 700, w: 300, h: 300)],   // bottom-right cell (cycle target)
            "n": [ZTRect(x: 350, y: 350, w: 300, h: 300)],   // centre cell — inside j's union bbox
            "default": [ZTRect(x: 0, y: 0, w: 1000, h: 1000)],
        ]
        // Drop in the middle of j's bottom-right tile → must be "j", not "n".
        XCTAssertEqual(DragSnap.target(atX: 850, y: 850, zones: zones), "j")
        // Drop in n's centre cell → "n".
        XCTAssertEqual(DragSnap.target(atX: 500, y: 500, zones: zones), "n")
    }

    func testNoZonesReturnsNil() {
        XCTAssertNil(DragSnap.target(atX: 10, y: 10, zones: [:]))
        XCTAssertNil(DragSnap.target(atX: 10, y: 10, zones: ["default": [ZTRect(x: 0, y: 0, w: 10, h: 10)]]))
        XCTAssertNil(DragSnap.target(atX: 10, y: 10, zones: ["k": []]))
    }

    func testDeterministicTieBreakOnSortedKey() {
        // two identical boxes → equal area, equal distance → lexicographically smallest key.
        let zones: [String: [ZTRect]] = [
            "z": [ZTRect(x: 0, y: 0, w: 100, h: 100)],
            "a": [ZTRect(x: 0, y: 0, w: 100, h: 100)],
        ]
        XCTAssertEqual(DragSnap.target(atX: 50, y: 50, zones: zones), "a")   // inside both, tie → "a"
        XCTAssertEqual(DragSnap.target(atX: 999, y: 999, zones: zones), "a") // outside both, tie → "a"
    }
}
