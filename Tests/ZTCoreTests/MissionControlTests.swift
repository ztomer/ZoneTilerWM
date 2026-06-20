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

    func testBadgeCentredAndCloseTopLeft() {
        let h = MissionControl.hints(for: tiles(), badge: (34, 26), close: 22, inset: 8)
        let first = h[0]   // tile (0,0,400,300)
        XCTAssertEqual(first.badge, ZTRect(x: (400 - 34) / 2, y: (300 - 26) / 2, w: 34, h: 26))
        XCTAssertEqual(first.close, ZTRect(x: 8, y: 8, w: 22, h: 22))   // top-left inset (macOS-native side)
    }

    func testClampsBadgeAndCloseInsideTinyTile() {
        let tiny = [MissionControl.Tile(windowId: 1, frame: ZTRect(x: 0, y: 0, w: 18, h: 14))]
        let h = MissionControl.hints(for: tiny, badge: (34, 26), close: 22)
        XCTAssertEqual(h[0].badge.w, 18); XCTAssertEqual(h[0].badge.h, 14)   // clamped to the tile
        XCTAssertEqual(h[0].close.w, 14)                                     // close clamped to min dim
    }

    func testResolveTypedLabelCaseSensitive() {
        // Labels are case-significant now (uppercase is the >26-window overflow tier), so resolve must
        // be case-sensitive — typing the wrong case must NOT match a different window.
        let h = MissionControl.hints(for: tiles())                 // labels a, s, d (lowercase)
        XCTAssertEqual(MissionControl.resolve(typed: h[1].label, in: h), 20)         // exact "s"
        XCTAssertNil(MissionControl.resolve(typed: h[1].label.uppercased(), in: h))  // "S" ≠ "s"
        XCTAssertNil(MissionControl.resolve(typed: "zzz", in: h))
    }

    func testLabelsExtendBeyond26WithDigitsThenUppercase() {
        // 40 windows: every one gets a unique, non-empty single-char label (no "" collisions). The
        // 27th spills into digits, the 37th into shifted uppercase.
        let many = (0..<40).map { MissionControl.Tile(windowId: $0, frame: ZTRect(x: 0, y: 0, w: 200, h: 200)) }
        let h = MissionControl.hints(for: many)
        let labels = h.map { $0.label }
        XCTAssertEqual(labels.count, 40)
        XCTAssertFalse(labels.contains(""), "no window is left unlabeled within the 62-label pool")
        XCTAssertEqual(Set(labels).count, 40, "all labels are distinct")
        XCTAssertTrue(labels[26].first!.isNumber, "27th label is a digit (no modifier)")
        XCTAssertTrue(labels[36].first!.isUppercase, "37th label is shifted uppercase")
        // And resolve round-trips the case-significant labels exactly.
        XCTAssertEqual(MissionControl.resolve(typed: labels[36], in: h), 36)
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

    func testSpatialGridTiles() {
        let screen = ZTRect(x: 0, y: 0, w: 1000, h: 800)

        // 1. Single window on the right side of a 2x1 grid
        let rightWindow = (windowId: 10, frame: ZTRect(x: 600, y: 100, w: 300, h: 300))
        let tiles1 = MissionControl.spatialGridTiles(windows: [rightWindow], in: screen, cols: 2, rows: 1, margin: 40, gap: 20)
        XCTAssertEqual(tiles1.count, 1)
        XCTAssertEqual(tiles1[0].windowId, 10)
        XCTAssertEqual(tiles1[0].frame.x, 510) // mapped to the right-hand cell

        // 2. Overlapping/stacked windows map to separate closest cells
        let leftWin1 = (windowId: 1, frame: ZTRect(x: 100, y: 100, w: 200, h: 200))
        let leftWin2 = (windowId: 2, frame: ZTRect(x: 110, y: 110, w: 200, h: 200))
        let tiles2 = MissionControl.spatialGridTiles(windows: [leftWin1, leftWin2], in: screen, cols: 2, rows: 2, margin: 40, gap: 20)
        XCTAssertEqual(tiles2.count, 2)
        let win1Tile = tiles2.first(where: { $0.windowId == 1 })!
        let win2Tile = tiles2.first(where: { $0.windowId == 2 })!
        XCTAssertEqual(win1Tile.frame.x, 40)
        XCTAssertEqual(win2Tile.frame.x, 40)
        XCTAssertNotEqual(win1Tile.frame.y, win2Tile.frame.y)
        XCTAssert(win1Tile.frame.y == 40 || win1Tile.frame.y == 410)
        XCTAssert(win2Tile.frame.y == 40 || win2Tile.frame.y == 410)

        // 3. Fallback when grid is too small
        let tiles3 = MissionControl.spatialGridTiles(windows: [leftWin1, leftWin2], in: screen, cols: 1, rows: 1, margin: 40, gap: 20)
        XCTAssertEqual(tiles3.count, 2) // Resizes dynamically
     }

     func testHintsOverloadResolvesAppAndZone() {
         let t = [MissionControl.Tile(windowId: 99, frame: ZTRect(x: 0, y: 0, w: 200, h: 200))]
         let appNames = [99: "Ghostty"]
         let zoneKeys = [99: "h"]
         let h = MissionControl.hints(for: t, appNames: appNames, zoneKeys: zoneKeys)
         XCTAssertEqual(h.count, 1)
         XCTAssertEqual(h[0].appName, "Ghostty")
         XCTAssertEqual(h[0].zoneKey, "h")
     }

     func testCloseHitTestsTheCorrectWindow() {
        let h = MissionControl.hints(for: tiles())
        let c = h[1].close   // window 20's × button
        XCTAssertEqual(MissionControl.closeHit(at: c.x + 2, c.y + 2, in: h), 20)
        XCTAssertNil(MissionControl.closeHit(at: 5, 295, in: h))   // empty corner of tile 1, no × there
    }

    func testNavigateMovesSelectionSpatially() {
        let h = MissionControl.hints(for: tiles())   // 10=(0,0) 20=(400,0) 30=(0,300)
        XCTAssertEqual(MissionControl.navigate(from: 10, .right, in: h), 20)  // right neighbour
        XCTAssertEqual(MissionControl.navigate(from: 10, .down, in: h), 30)   // below
        XCTAssertEqual(MissionControl.navigate(from: 20, .left, in: h), 10)   // back left
        XCTAssertEqual(MissionControl.navigate(from: 10, .left, in: h), 10)   // nothing left → unchanged
        XCTAssertEqual(MissionControl.navigate(from: 10, .up, in: h), 10)     // nothing up → unchanged
        XCTAssertEqual(MissionControl.navigate(from: 999, .right, in: h), 10) // unknown → first hint
    }

    func testTileHitJumpsByClickAnywhereInTile() {
        let h = MissionControl.hints(for: tiles())
        XCTAssertEqual(h[0].frame, ZTRect(x: 0, y: 0, w: 400, h: 300))   // full tile carried on the hint
        XCTAssertEqual(MissionControl.tileHit(at: 350, 280, in: h), 10)  // inside tile 1 (not on its ×)
        XCTAssertEqual(MissionControl.tileHit(at: 700, 250, in: h), 20)  // inside tile 2
        XCTAssertNil(MissionControl.tileHit(at: 790, 590, in: h))        // outside every tile
    }
}
