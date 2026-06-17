// FocusManagerTests — zone-window collection/ordering and the focus cycle stepping.

import XCTest
@testable import ZTCore

final class FocusManagerTests: XCTestCase {

    private let zoneTiles = [
        ZTRect(x: 0, y: 0, w: 500, h: 1000),   // tile 1
        ZTRect(x: 500, y: 0, w: 500, h: 1000), // tile 2
    ]

    func testExplicitBeatsOverlapAndOrdersByTile() {
        // w1: explicit in tile 2; w2: overlaps tile 1 (detected); w3: explicit tile 1.
        let windows = [
            FocusManager.ScreenWindow(windowId: 1, appName: "A", frame: ZTRect(x: 500, y: 0, w: 500, h: 1000), zOrder: 1),
            FocusManager.ScreenWindow(windowId: 2, appName: "B", frame: ZTRect(x: 0, y: 0, w: 500, h: 1000), zOrder: 2),
            FocusManager.ScreenWindow(windowId: 3, appName: "C", frame: ZTRect(x: 0, y: 0, w: 500, h: 1000), zOrder: 3),
        ]
        let state: [Int: FocusManager.WindowState] = [
            1: .init(monitorId: "M1", zoneKey: "h", tileIndex: 2),
            3: .init(monitorId: "M1", zoneKey: "h", tileIndex: 1),
        ]
        let zw = FocusManager.collectZoneWindows(
            monitorId: "M1", zoneKey: "h", windowsOnScreen: windows,
            stateForWindow: { state[$0] }, zoneTiles: zoneTiles, overlapThreshold: 0.5)
        // Order: tile1 explicit (w3), tile1 detected (w2), tile2 explicit (w1).
        XCTAssertEqual(zw.map { $0.windowId }, [3, 2, 1])
        XCTAssertEqual(zw[0].explicit, true)
        XCTAssertEqual(zw[1].explicit, false)
    }

    func testOverlapThresholdExcludesLowOverlap() {
        // Straddles the boundary 50/50 -> 0.5 of itself in each tile -> below a 0.6 threshold.
        let windows = [
            FocusManager.ScreenWindow(windowId: 1, appName: "A", frame: ZTRect(x: 250, y: 0, w: 500, h: 1000), zOrder: 1),
        ]
        let zw = FocusManager.collectZoneWindows(
            monitorId: "M1", zoneKey: "h", windowsOnScreen: windows,
            stateForWindow: { _ in nil }, zoneTiles: zoneTiles, overlapThreshold: 0.6)
        XCTAssertTrue(zw.isEmpty)
    }

    func testCyclerStepsAndWraps() {
        let cy = FocusManager.Cycler()
        let order = [10, 20, 30]
        // Focused is 10 -> next 20.
        XCTAssertEqual(cy.cycle(focusedId: 10, zoneKey: "h", monitorId: "M1", freshOrder: order), 20)
        // Reuse: next 30, then wrap to 10.
        XCTAssertEqual(cy.cycle(focusedId: 20, zoneKey: "h", monitorId: "M1", freshOrder: order), 30)
        XCTAssertEqual(cy.cycle(focusedId: 30, zoneKey: "h", monitorId: "M1", freshOrder: order), 10)
    }

    func testCyclerFocusedNotInListStartsAtFirst() {
        let cy = FocusManager.Cycler()
        XCTAssertEqual(cy.cycle(focusedId: 999, zoneKey: "h", monitorId: "M1", freshOrder: [10, 20]), 10)
    }

    func testCyclerRebuildsOnWindowSetChange() {
        let cy = FocusManager.Cycler()
        _ = cy.cycle(focusedId: 10, zoneKey: "h", monitorId: "M1", freshOrder: [10, 20])
        // Set changes -> rebuild; focused 10 at index 1 -> next 20.
        XCTAssertEqual(cy.cycle(focusedId: 10, zoneKey: "h", monitorId: "M1", freshOrder: [10, 20, 30]), 20)
    }

    func testCyclerEmptyZoneReturnsNil() {
        let cy = FocusManager.Cycler()
        XCTAssertNil(cy.cycle(focusedId: 1, zoneKey: "h", monitorId: "M1", freshOrder: []))
    }
}
