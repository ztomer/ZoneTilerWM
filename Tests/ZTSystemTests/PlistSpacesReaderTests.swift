import XCTest
@testable import ZTSystem

/// Parser tests against captured com.apple.spaces.plist shapes. The `Monitors` array carries one
/// live entry per connected display plus stale entries (empty `Spaces`) for displays that have been
/// disconnected — the parser must keep only connected, non-empty displays and remap "Main".
final class PlistSpacesReaderTests: XCTestCase {
    private let mainUUID = "AAAA-MAIN"
    private let extUUID = "28C4B833-90AA-4E99-BB6D-E0AB6998CA79"

    private func space(_ id: Int, uuid: String = "", type: Int = 0) -> [String: Any] {
        ["ManagedSpaceID": id, "id64": id, "type": type, "uuid": uuid]
    }
    private func monitor(_ ident: String, spaces: [[String: Any]], current: Int?) -> [String: Any] {
        var m: [String: Any] = ["Display Identifier": ident, "Spaces": spaces]
        if let current { m["Current Space"] = space(current) }
        return m
    }

    /// Two displays: primary stored as "Main" (→ remapped to its UUID) with 2 Spaces, plus an external
    /// display with 1. Current flags follow the per-monitor "Current Space".
    func testTwoDisplaysMainRemappedAndCurrentFlagged() {
        let monitors = [
            monitor("Main", spaces: [space(1), space(3, uuid: "S3")], current: 1),
            monitor(extUUID, spaces: [space(1384, uuid: "S1384")], current: 1384),
        ]
        let out = PlistSpacesReader.parse(monitors: monitors, mainDisplayUUID: mainUUID,
                                          connected: [mainUUID, extUUID])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[mainUUID]?.map(\.id), [1, 3])
        XCTAssertEqual(out[mainUUID]?.map(\.isCurrent), [true, false])
        XCTAssertEqual(out[extUUID]?.map(\.id), [1384])
        XCTAssertEqual(out[extUUID]?.first?.isCurrent, true)
        XCTAssertEqual(out[mainUUID]?[1].uuid, "S3")          // non-default Space keeps its uuid
    }

    /// Stale entries: disconnected displays appear with empty `Spaces` (and remembered ones that ARE
    /// non-empty but not currently connected) — both must be dropped.
    func testDropsStaleAndDisconnectedDisplays() {
        let monitors = [
            monitor("Main", spaces: [space(1)], current: 1),
            monitor("30EF4B6E-DEAD", spaces: [], current: nil),            // sleeping/collapsed: empty
            monitor("D468D53C-GONE", spaces: [space(99, uuid: "X")], current: 99),  // remembered but unplugged
        ]
        let out = PlistSpacesReader.parse(monitors: monitors, mainDisplayUUID: mainUUID,
                                          connected: [mainUUID])           // only the main display is live
        XCTAssertEqual(Array(out.keys), [mainUUID])
        XCTAssertNil(out["D468D53C-GONE"])
    }

    /// A full-screen-app Space (type 4) is flagged; normal Spaces (type 0) are not.
    func testFullscreenTypeFlagged() {
        let monitors = [monitor("Main", spaces: [space(1), space(7, uuid: "FS", type: 4)], current: 1)]
        let out = PlistSpacesReader.parse(monitors: monitors, mainDisplayUUID: mainUUID, connected: [mainUUID])
        XCTAssertEqual(out[mainUUID]?.map(\.isFullscreen), [false, true])
    }

    /// Empty Monitors, or a display with no current match, must not crash and must not invent a current.
    func testNoCurrentWhenUnmatchedAndEmptyInput() {
        XCTAssertTrue(PlistSpacesReader.parse(monitors: [], mainDisplayUUID: mainUUID, connected: [mainUUID]).isEmpty)
        let monitors = [monitor("Main", spaces: [space(1), space(2)], current: 999)]  // current not in list
        let out = PlistSpacesReader.parse(monitors: monitors, mainDisplayUUID: mainUUID, connected: [mainUUID])
        XCTAssertEqual(out[mainUUID]?.allSatisfy { !$0.isCurrent }, true)
    }

    /// Falls back to id64 when ManagedSpaceID is absent, and to -1 when neither is present.
    func testIdFallbacks() {
        let monitors = [["Display Identifier": "Main",
                         "Spaces": [["id64": 42, "type": 0], ["type": 0]],
                         "Current Space": ["ManagedSpaceID": 42]]]
        let out = PlistSpacesReader.parse(monitors: monitors, mainDisplayUUID: mainUUID, connected: [mainUUID])
        XCTAssertEqual(out[mainUUID]?.map(\.id), [42, -1])
        XCTAssertEqual(out[mainUUID]?.first?.isCurrent, true)
    }

    /// Duplicate non-empty entries for one display (defensive): first wins, no double-grouping.
    func testDuplicateDisplayFirstWins() {
        let monitors = [
            monitor("Main", spaces: [space(1), space(2)], current: 1),
            monitor("Main", spaces: [space(5)], current: 5),
        ]
        let out = PlistSpacesReader.parse(monitors: monitors, mainDisplayUUID: mainUUID, connected: [mainUUID])
        XCTAssertEqual(out[mainUUID]?.map(\.id), [1, 2])
    }
}
