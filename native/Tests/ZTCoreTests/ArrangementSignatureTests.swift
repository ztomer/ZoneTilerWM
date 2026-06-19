// ArrangementSignatureTests — pure arrangement signature for the state-diff event stream.

import XCTest
@testable import ZTCore

final class ArrangementSignatureTests: XCTestCase {
    private func win(_ id: Int, _ zone: String?, monitor: String = "1") -> WindowInfo {
        WindowInfo(windowId: id, app: "App\(id)", frame: ZTRect(x: 0, y: 0, w: 1, h: 1), monitor: monitor, zone: zone)
    }

    func testOrderIndependent() {
        let a = ArrangementSignature.of([win(1, "h"), win(2, "l")])
        let b = ArrangementSignature.of([win(2, "l"), win(1, "h")])
        XCTAssertEqual(a, b)
    }

    func testChangesWhenZoneChanges() {
        XCTAssertNotEqual(ArrangementSignature.of([win(1, "h")]), ArrangementSignature.of([win(1, "l")]))
    }

    func testChangesWhenWindowAddedOrRemoved() {
        XCTAssertNotEqual(ArrangementSignature.of([win(1, "h")]), ArrangementSignature.of([win(1, "h"), win(2, "l")]))
    }

    func testUnchangedByFrameJitterWithinSameZone() {
        let a = WindowInfo(windowId: 1, app: "X", frame: ZTRect(x: 0, y: 0, w: 100, h: 100), monitor: "1", zone: "h")
        let b = WindowInfo(windowId: 1, app: "X", frame: ZTRect(x: 5, y: 5, w: 120, h: 110), monitor: "1", zone: "h")
        XCTAssertEqual(ArrangementSignature.of([a]), ArrangementSignature.of([b]))   // same zone → no event
    }
}
