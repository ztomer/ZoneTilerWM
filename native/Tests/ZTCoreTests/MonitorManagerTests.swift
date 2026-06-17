// MonitorManagerTests — stable logical-id assignment + reverse lookup.

import XCTest
@testable import ZTCore

final class MonitorManagerTests: XCTestCase {

    func testAssignsSequentialStableIds() {
        let mm = MonitorManager()
        XCTAssertEqual(mm.id(forUUID: "UUID-A"), 1)
        XCTAssertEqual(mm.id(forUUID: "UUID-B"), 2)
        // Stable on re-query (no new id).
        XCTAssertEqual(mm.id(forUUID: "UUID-A"), 1)
        XCTAssertEqual(mm.id(forUUID: "UUID-C"), 3)
    }

    func testReverseLookup() {
        let mm = MonitorManager()
        _ = mm.id(forUUID: "UUID-A")
        _ = mm.id(forUUID: "UUID-B")
        XCTAssertEqual(mm.uuid(forId: 2), "UUID-B")
        XCTAssertNil(mm.uuid(forId: 99))
    }

    func testReregisterPreservesIds() {
        let mm = MonitorManager()
        _ = mm.id(forUUID: "UUID-A")  // 1
        _ = mm.id(forUUID: "UUID-B")  // 2
        mm.reregister(uuids: ["UUID-B", "UUID-A", "UUID-C"])  // C is new -> 3
        XCTAssertEqual(mm.id(forUUID: "UUID-A"), 1)
        XCTAssertEqual(mm.id(forUUID: "UUID-B"), 2)
        XCTAssertEqual(mm.id(forUUID: "UUID-C"), 3)
    }
}
