// JSONFileStorageTests — round-trip + Lua-format compatibility for the JSON storage adapter.

import XCTest
@testable import ZTCore
@testable import ZTSystem

final class JSONFileStorageTests: XCTestCase {

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ztwm-tests-\(UUID().uuidString)", isDirectory: true)
        return dir
    }

    func testRoundTripWindowMemory() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = JSONFileStorage(directory: dir)

        let wm = WindowMemory()
        wm.positionWindow(windowId: 1, app: "Safari", monitor: "M1", zone: "h", tile: .int(1),
                          winW: 1000, winH: 500, screenW: 1920, screenH: 1080)
        wm.flushAll()
        let saved = wm.save()

        XCTAssertTrue(storage.save("window_positions", saved))
        let loaded = storage.load("window_positions", as: WindowMemory.SaveData.self)
        XCTAssertEqual(loaded, saved)

        // A second WindowMemory loaded from disk reproduces the state.
        let restored = WindowMemory()
        restored.load(try XCTUnwrap(loaded))
        XCTAssertEqual(restored.rememberedPosition(app: "Safari", monitor: "M1")?.zone, "h")
    }

    func testToleratesExtraTimestampKey() throws {
        // Lua's storage.save adds a `_timestamp`; loading must ignore it (unknown key).
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = """
        {"_timestamp": 1717000000,
         "positions": [{"app_name":"Code","monitor_id":"M1","zone_key":"h","tile_index":1}],
         "preferences": [{"app_name":"Code","monitor_id":"M1","zone_key":"h","tile_index":1,
                          "data":{"count":3,"mean_ar":1.5,"mean_area":0.4}}]}
        """
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try json.data(using: .utf8)!.write(to: dir.appendingPathComponent("window_positions.json"))

        let storage = JSONFileStorage(directory: dir)
        let loaded = try XCTUnwrap(storage.load("window_positions", as: WindowMemory.SaveData.self))
        XCTAssertEqual(loaded.positions.count, 1)
        XCTAssertEqual(loaded.preferences.first?.data.count, 3)
    }

    func testMissingFileReturnsNil() {
        let storage = JSONFileStorage(directory: tempDir())
        XCTAssertNil(storage.load("does_not_exist", as: WindowMemory.SaveData.self))
    }

    // Best-effort compatibility check against the user's real window memory, if present.
    func testRealWindowPositionsDecodesIfPresent() throws {
        let real = JSONFileStorage.defaultDirectory.appendingPathComponent("window_positions.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: real.path),
                          "no real window_positions.json on this machine")
        let storage = JSONFileStorage(directory: JSONFileStorage.defaultDirectory)
        let loaded = storage.load("window_positions", as: WindowMemory.SaveData.self)
        // Assert on a Bool, not the value itself: XCTAssertNotNil reflects its argument via
        // Mirror to build a description, which on a large decoded SaveData (thousands of
        // preferences) allocates heavily and can trap. We only care that it decoded.
        XCTAssertTrue(loaded != nil, "real window_positions.json should decode into SaveData")
    }
}
