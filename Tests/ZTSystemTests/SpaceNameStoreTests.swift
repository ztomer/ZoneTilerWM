// SpaceNameStoreTests — persistence + keying for user-named Spaces.

import XCTest
@testable import ZTSystem

final class SpaceNameStoreTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("spaces-\(UUID().uuidString).json")
    }
    private func sp(id: Int, uuid: String, display: String = "D1") -> RealSpace {
        RealSpace(id: id, uuid: uuid, displayUUID: display, isCurrent: false, isFullscreen: false)
    }

    func testSetGetAndPersistAcrossInstances() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let s = sp(id: 3, uuid: "ABCD")
        let store = SpaceNameStore(fileURL: url)
        XCTAssertNil(store.name(for: s))
        XCTAssertTrue(store.setName("Comms", for: s))
        XCTAssertEqual(store.name(for: s), "Comms")
        // A fresh instance reads it back from disk.
        XCTAssertEqual(SpaceNameStore(fileURL: url).name(for: s), "Comms")
    }

    func testEmptyUUIDKeyedByDisplay() {
        // The default/active space reports an empty UUID → keyed per display, so two displays' defaults
        // don't collide.
        let a = sp(id: 1, uuid: "", display: "DA")
        let b = sp(id: 9, uuid: "", display: "DB")
        XCTAssertNotEqual(SpaceNameStore.key(for: a), SpaceNameStore.key(for: b))
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let store = SpaceNameStore(fileURL: url)
        store.setName("Main", for: a)
        XCTAssertEqual(store.name(for: a), "Main")
        XCTAssertNil(store.name(for: b))
    }

    func testClearWithEmptyName() {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let s = sp(id: 2, uuid: "X")
        let store = SpaceNameStore(fileURL: url)
        store.setName("Temp", for: s); XCTAssertEqual(store.name(for: s), "Temp")
        store.setName("  ", for: s); XCTAssertNil(store.name(for: s))   // whitespace clears
    }
}
