// MissionControlTests — pure overlay geometry + resolution for the Mission Control window hints.

import XCTest
@testable import ZTCore

final class MissionControlTests: XCTestCase {

    private func tiles() -> [MissionControl.Tile] {
        [MissionControl.Tile(windowId: 10, frame: ZTRect(x: 0, y: 0, w: 400, h: 300)),
         MissionControl.Tile(windowId: 20, frame: ZTRect(x: 400, y: 0, w: 400, h: 300)),
         MissionControl.Tile(windowId: 30, frame: ZTRect(x: 0, y: 300, w: 400, h: 300))]
    }

    func testAssignsHomeRowLabelsInOrder() {
        let h = MissionControl.hints(for: tiles())
        XCTAssertEqual(h.map { $0.windowId }, [10, 20, 30])
        XCTAssertEqual(h.map { $0.label }, WindowHints.labels(count: 3))   // a, s, d, …
    }

    func testBadgeCentredAndCloseTopRight() {
        let h = MissionControl.hints(for: tiles(), badge: (34, 26), close: 22, inset: 8)
        let first = h[0]   // tile (0,0,400,300)
        XCTAssertEqual(first.badge, ZTRect(x: (400 - 34) / 2, y: (300 - 26) / 2, w: 34, h: 26))
        XCTAssertEqual(first.close, ZTRect(x: 400 - 22 - 8, y: 8, w: 22, h: 22))   // top-right inset
    }

    func testClampsBadgeAndCloseInsideTinyTile() {
        let tiny = [MissionControl.Tile(windowId: 1, frame: ZTRect(x: 0, y: 0, w: 18, h: 14))]
        let h = MissionControl.hints(for: tiny, badge: (34, 26), close: 22)
        XCTAssertEqual(h[0].badge.w, 18); XCTAssertEqual(h[0].badge.h, 14)   // clamped to the tile
        XCTAssertEqual(h[0].close.w, 14)                                     // close clamped to min dim
    }

    func testResolveTypedLabelCaseInsensitive() {
        let h = MissionControl.hints(for: tiles())
        XCTAssertEqual(MissionControl.resolve(typed: h[1].label.uppercased(), in: h), 20)
        XCTAssertNil(MissionControl.resolve(typed: "zzz", in: h))
    }

    func testMatchesPrefix() {
        let h = MissionControl.hints(for: tiles())
        XCTAssertEqual(MissionControl.matches(prefix: "", in: h).count, 3)       // empty → all
        let firstLabel = h[0].label
        XCTAssertTrue(MissionControl.matches(prefix: firstLabel, in: h).contains { $0.windowId == 10 })
    }

    func testGridTilesPacksNearSquareRowMajor() {
        let screen = ZTRect(x: 0, y: 0, w: 1000, h: 800)
        let four = MissionControl.gridTiles(windowIds: [1, 2, 3, 4], in: screen, margin: 40, gap: 20)
        XCTAssertEqual(four.map { $0.windowId }, [1, 2, 3, 4])      // row-major order preserved
        // 4 → 2×2: cell w = (1000-80-20)/2 = 450, h = (800-80-20)/2 = 350
        XCTAssertEqual(four[0].frame, ZTRect(x: 40, y: 40, w: 450, h: 350))           // top-left
        XCTAssertEqual(four[1].frame, ZTRect(x: 40 + 450 + 20, y: 40, w: 450, h: 350)) // top-right
        XCTAssertEqual(four[3].frame.x, 40 + 450 + 20)                                 // bottom-right col
        XCTAssertEqual(four[3].frame.y, 40 + 350 + 20)                                 // bottom row
        // 3 windows → 2 cols, 2 rows (one empty cell); all tiles inside the screen
        let three = MissionControl.gridTiles(windowIds: [1, 2, 3], in: screen)
        XCTAssertEqual(three.count, 3)
        for t in three {
            XCTAssertGreaterThanOrEqual(t.frame.x, 0); XCTAssertLessThanOrEqual(t.frame.x + t.frame.w, 1000)
        }
        XCTAssertTrue(MissionControl.gridTiles(windowIds: [], in: screen).isEmpty)
    }

    func testCloseHitTestsTheCorrectWindow() {
        let h = MissionControl.hints(for: tiles())
        let c = h[1].close   // window 20's × button
        XCTAssertEqual(MissionControl.closeHit(at: c.x + 2, c.y + 2, in: h), 20)
        XCTAssertNil(MissionControl.closeHit(at: 5, 295, in: h))   // empty corner of tile 1, no × there
    }
}
