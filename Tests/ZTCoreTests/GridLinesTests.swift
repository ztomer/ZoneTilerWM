// GridLinesTests — resize-overlay geometry + which interior line a nudge targets.

import XCTest
@testable import ZTCore

final class GridLinesTests: XCTestCase {

    private let frame = ZTRect(x: 0, y: 0, w: 1200, h: 900)

    func testInteriorLinesWithoutOffset() {
        let (v, h) = GridLines.positions(frame: frame, cols: 3, rows: 3) { _, _ in 0 }
        XCTAssertEqual(v, [400, 800])   // 2 vertical lines for 3 cols
        XCTAssertEqual(h, [300, 600])   // 2 horizontal lines for 3 rows
    }

    func testOffsetShiftsLine() {
        // +10% offset on vertical line index 1 shifts it right by 0.1*1200 = 120.
        let (v, _) = GridLines.positions(frame: frame, cols: 2, rows: 1) { axis, idx in
            (axis == "x" && idx == 1) ? 0.1 : 0
        }
        XCTAssertEqual(v, [600 + 120])
    }

    func testFrameOriginIsAbsolute() {
        let f = ZTRect(x: 100, y: 50, w: 1000, h: 800)
        let (v, h) = GridLines.positions(frame: f, cols: 2, rows: 2) { _, _ in 0 }
        XCTAssertEqual(v, [100 + 500])
        XCTAssertEqual(h, [50 + 400])
    }

    func testSingleColumnHasNoVerticalLines() {
        let (v, h) = GridLines.positions(frame: frame, cols: 1, rows: 2) { _, _ in 0 }
        XCTAssertTrue(v.isEmpty)
        XCTAssertEqual(h, [450])
    }

    func testNearestInteriorIndex() {
        // 4 columns over width 1200 → cell 300; interior lines at 300/600/900 (idx 1/2/3).
        XCTAssertEqual(GridLines.nearestInteriorIndex(to: 320, start: 0, total: 1200, count: 4), 1)
        XCTAssertEqual(GridLines.nearestInteriorIndex(to: 580, start: 0, total: 1200, count: 4), 2)
        XCTAssertEqual(GridLines.nearestInteriorIndex(to: 1190, start: 0, total: 1200, count: 4), 3) // clamped
        XCTAssertEqual(GridLines.nearestInteriorIndex(to: 10, start: 0, total: 1200, count: 4), 1)   // clamped
    }

    func testNearestInteriorIndexNoneForSingleCell() {
        XCTAssertNil(GridLines.nearestInteriorIndex(to: 500, start: 0, total: 1200, count: 1))
    }
}
