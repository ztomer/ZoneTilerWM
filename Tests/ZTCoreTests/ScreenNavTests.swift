// ScreenNavTests — pure multi-monitor nav logic. (Live multi-display behavior can't be
// validated on a single monitor; these lock the ordering + decision.)

import XCTest
@testable import ZTCore

final class ScreenNavTests: XCTestCase {

    private func screen(_ uuid: String, x: Double) -> ScreenSnapshot {
        ScreenSnapshot(uuid: uuid, name: uuid, frame: ZTRect(x: x, y: 0, w: 1000, h: 1000),
                       fullFrame: ZTRect(x: x, y: 0, w: 1000, h: 1000))
    }

    func testOrderedByPosition() {
        let s = ScreenNav.ordered([screen("C", x: 2000), screen("A", x: 0), screen("B", x: 1000)])
        XCTAssertEqual(s.map { $0.uuid }, ["A", "B", "C"])
    }

    func testNextPreviousWrap() {
        let ids = ["A", "B", "C"]
        XCTAssertEqual(ScreenNav.targetIndex(orderedUUIDs: ids, current: "A", direction: .next), 1)
        XCTAssertEqual(ScreenNav.targetIndex(orderedUUIDs: ids, current: "C", direction: .next), 0)   // wrap
        XCTAssertEqual(ScreenNav.targetIndex(orderedUUIDs: ids, current: "A", direction: .previous), 2) // wrap
        XCTAssertEqual(ScreenNav.targetIndex(orderedUUIDs: ids, current: "B", direction: .previous), 0)
    }

    func testNoTargetWhenSingleScreenOrUnknown() {
        XCTAssertNil(ScreenNav.targetIndex(orderedUUIDs: ["A"], current: "A", direction: .next))
        XCTAssertNil(ScreenNav.targetIndex(orderedUUIDs: ["A", "B"], current: "Z", direction: .next))
    }

    func testPlacementPrefersRememberedWhenValid() {
        let zones: [String: [ZTRect]] = ["j": [ZTRect(x: 0, y: 0, w: 10, h: 10)],
                                         "k": [ZTRect(x: 0, y: 0, w: 5, h: 5), ZTRect(x: 5, y: 0, w: 5, h: 5)]]
        let p = ScreenNav.monitorPlacement(targetZones: zones, remembered: ("k", 2))
        XCTAssertEqual(p?.zone, "k"); XCTAssertEqual(p?.tile, 2)
    }

    func testPlacementFallsBackToDefaultWhenRememberedMissing() {
        let zones: [String: [ZTRect]] = ["j": [ZTRect(x: 0, y: 0, w: 10, h: 10)]]
        // Remembered zone "z" not on target → default "j" tile 1 ("0" absent).
        let p = ScreenNav.monitorPlacement(targetZones: zones, remembered: ("z", 1))
        XCTAssertEqual(p?.zone, "j"); XCTAssertEqual(p?.tile, 1)
    }

    func testPlacementNilWhenNothingFits() {
        let zones: [String: [ZTRect]] = ["q": [ZTRect(x: 0, y: 0, w: 10, h: 10)]]
        XCTAssertNil(ScreenNav.monitorPlacement(targetZones: zones, remembered: nil))   // no default zones present
    }
}
