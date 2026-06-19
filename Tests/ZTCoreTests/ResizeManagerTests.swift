// ResizeManagerTests — adjust/clamp/reset, serialization round-trip via an in-memory
// Storage, and integration with ZoneCalculator (an offset actually shifts a tile boundary).

import XCTest
import Foundation
@testable import ZTCore

private final class MemoryStorage: Storage {
    var blobs: [String: Data] = [:]
    func load<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        blobs[key].flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
    @discardableResult
    func save<T: Encodable>(_ key: String, _ value: T) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        blobs[key] = data
        return true
    }
}

final class ResizeManagerTests: XCTestCase {

    func testDefaultOffsetIsZero() {
        let rm = ResizeManager()
        XCTAssertEqual(rm.getOffset(monitor: "M1", axis: "x", index: 1), 0)
    }

    func testAdjustStepsAndClamps() {
        let rm = ResizeManager()
        rm.adjust(monitor: "M1", axis: "x", index: 1, delta: 1)
        XCTAssertEqual(rm.getOffset(monitor: "M1", axis: "x", index: 1), 0.02, accuracy: 1e-12)
        // Clamp at +0.4.
        rm.adjust(monitor: "M1", axis: "x", index: 1, delta: 100)
        XCTAssertEqual(rm.getOffset(monitor: "M1", axis: "x", index: 1), 0.4, accuracy: 1e-12)
        // Clamp at -0.4.
        rm.adjust(monitor: "M1", axis: "x", index: 1, delta: -100)
        XCTAssertEqual(rm.getOffset(monitor: "M1", axis: "x", index: 1), -0.4, accuracy: 1e-12)
    }

    func testReset() {
        let rm = ResizeManager()
        rm.adjust(monitor: "M1", axis: "y", index: 2, delta: 3)
        rm.reset(monitor: "M1")
        XCTAssertEqual(rm.getOffset(monitor: "M1", axis: "y", index: 2), 0)
    }

    func testSerializationRoundTrip() {
        let store = MemoryStorage()
        let rm = ResizeManager()
        rm.adjust(monitor: "M1", axis: "x", index: 1, delta: 2)   // 0.04
        rm.adjust(monitor: "M2", axis: "y", index: 3, delta: -1)  // -0.02
        XCTAssertTrue(rm.save(to: store))

        let restored = ResizeManager()
        restored.load(from: store)
        XCTAssertEqual(restored.getOffset(monitor: "M1", axis: "x", index: 1), 0.04, accuracy: 1e-12)
        XCTAssertEqual(restored.getOffset(monitor: "M2", axis: "y", index: 3), -0.02, accuracy: 1e-12)
        XCTAssertEqual(restored.getOffset(monitor: "M1", axis: "y", index: 1), 0)
    }

    func testOffsetShiftsZoneCalculatorTileBoundary() {
        let zc = ZoneConfig(
            grids: ["2x2": GridConfig(cols: 2, rows: 2)],
            layouts: ["2x2": ["y": ["a1"]]],   // top-left cell of a 2x2 grid
            margins: Margins(enabled: false, size: 0, screen_edge: false))
        let screen = ZoneCalculator.ScreenInfo(name: "Internal", frame: ZTRect(x: 0, y: 0, w: 1000, h: 1000))

        // Baseline: column boundary at the midpoint -> tile width 500.
        let base = ZoneCalculator.computeZones(screen: screen, config: zc).zones["y"]![0]
        XCTAssertEqual(base.w, 500, accuracy: 1e-9)

        // Push the x=1 grid line right by +10% (delta 5 * 2%) -> width 600.
        let rm = ResizeManager()
        rm.adjust(monitor: "M1", axis: "x", index: 1, delta: 5)
        let shifted = ZoneCalculator.computeZones(
            screen: screen, config: zc, offsets: rm.offsetProvider(monitor: "M1")).zones["y"]![0]
        XCTAssertEqual(shifted.w, 600, accuracy: 1e-9)
    }
}
