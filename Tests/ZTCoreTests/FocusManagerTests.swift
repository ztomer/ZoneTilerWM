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

    // MARK: - nearest-window fallback (feedback 7a: focus-zone on an empty zone jumps to the closest)

    private let cornerZone = [ZTRect(x: 0, y: 0, w: 200, h: 200)]   // top-left; the windows below miss it

    func testNearestFallbackPicksClosestWhenNoneOverlap() {
        let windows = [
            FocusManager.ScreenWindow(windowId: 1, appName: "Far",  frame: ZTRect(x: 800, y: 800, w: 150, h: 150), zOrder: 1),
            FocusManager.ScreenWindow(windowId: 2, appName: "Near", frame: ZTRect(x: 300, y: 0,   w: 150, h: 150), zOrder: 2),
        ]
        let zw = FocusManager.collectZoneWindows(
            monitorId: "M1", zoneKey: "y", windowsOnScreen: windows,
            stateForWindow: { _ in nil }, zoneTiles: cornerZone, overlapThreshold: 0.5, nearestFallback: true)
        XCTAssertEqual(zw.map { $0.windowId }, [2])    // the nearer window
        XCTAssertEqual(zw.first?.explicit, false)
    }

    func testNearestFallbackOffStaysEmpty() {
        let windows = [
            FocusManager.ScreenWindow(windowId: 1, appName: "Far", frame: ZTRect(x: 800, y: 800, w: 150, h: 150), zOrder: 1),
        ]
        let zw = FocusManager.collectZoneWindows(   // nearestFallback defaults off → no change
            monitorId: "M1", zoneKey: "y", windowsOnScreen: windows,
            stateForWindow: { _ in nil }, zoneTiles: cornerZone, overlapThreshold: 0.5)
        XCTAssertTrue(zw.isEmpty)
    }

    func testNearestFallbackNeverOverridesRealOccupants() {
        let leftHalf = [ZTRect(x: 0, y: 0, w: 500, h: 1000)]
        let windows = [
            FocusManager.ScreenWindow(windowId: 1, appName: "In",  frame: ZTRect(x: 0, y: 0, w: 500, h: 1000), zOrder: 1),
            FocusManager.ScreenWindow(windowId: 2, appName: "Out", frame: ZTRect(x: 600, y: 0, w: 300, h: 300), zOrder: 2),
        ]
        let zw = FocusManager.collectZoneWindows(
            monitorId: "M1", zoneKey: "h", windowsOnScreen: windows,
            stateForWindow: { _ in nil }, zoneTiles: leftHalf, overlapThreshold: 0.5, nearestFallback: true)
        XCTAssertEqual(zw.map { $0.windowId }, [1])    // real occupant; fallback not triggered
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

    // MARK: - placement(of:) reverse lookup (feedback 7b: re-learn a manually-dragged window's zone)

    private let twoZones: [String: [ZTRect]] = [
        "left":  [ZTRect(x: 0,   y: 0, w: 500, h: 1000)],                                   // one tile
        "right": [ZTRect(x: 500, y: 0, w: 250, h: 1000), ZTRect(x: 750, y: 0, w: 250, h: 1000)], // two tiles
    ]

    func testPlacementFindsZoneAndTileForOccupyingFrame() {
        // A window sitting on the right zone's second tile.
        let p = FocusManager.placement(of: ZTRect(x: 750, y: 0, w: 250, h: 1000),
                                       zones: twoZones, overlapThreshold: 0.5)
        XCTAssertEqual(p?.zoneKey, "right")
        XCTAssertEqual(p?.tileIndex, 2)   // 1-based, matches collectZoneWindows
    }

    func testPlacementReturnsNilForOffGridFrame() {
        // A floating window entirely below the grid (the tiles span y 0..1000) overlaps nothing.
        let p = FocusManager.placement(of: ZTRect(x: 0, y: 2000, w: 200, h: 200),
                                       zones: twoZones, overlapThreshold: 0.5)
        XCTAssertNil(p)
    }

    func testPlacementPrefersTightestFittingZoneWhenZonesNest() {
        // "half" contains the whole left edge; "quad" is just the top-left corner. A window filling
        // the corner sits in BOTH, but fits "quad" exactly — IoU must pick the tighter zone.
        let nested: [String: [ZTRect]] = [
            "half": [ZTRect(x: 0, y: 0, w: 500, h: 1000)],   // sorts first, but a loose fit
            "quad": [ZTRect(x: 0, y: 0, w: 500, h: 500)],    // the tight fit
        ]
        let p = FocusManager.placement(of: ZTRect(x: 0, y: 0, w: 500, h: 500),
                                       zones: nested, overlapThreshold: 0.5)
        XCTAssertEqual(p?.zoneKey, "quad")
        XCTAssertEqual(p?.tileIndex, 1)
    }

    func testPlacementIsDeterministicAcrossZonesByKeyOrder() {
        // A frame covering the left tile is unambiguous; "left" sorts before "right".
        let p = FocusManager.placement(of: ZTRect(x: 0, y: 0, w: 500, h: 1000),
                                       zones: twoZones, overlapThreshold: 0.5)
        XCTAssertEqual(p?.zoneKey, "left")
        XCTAssertEqual(p?.tileIndex, 1)
    }

    func testPlacementRespectsThreshold() {
        // 50% into the left tile -> below a 0.6 threshold -> no placement.
        let p = FocusManager.placement(of: ZTRect(x: 250, y: 0, w: 500, h: 1000),
                                       zones: twoZones, overlapThreshold: 0.6)
        XCTAssertNil(p)
    }
}
