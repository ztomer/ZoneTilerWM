// DockPreviewTests — pure hover hit-test + preview-panel anchoring (Wave 4 DockDoor-style previews).

import XCTest
@testable import ZTCore

final class DockPreviewTests: XCTestCase {

    // A bottom Dock: three 38x50 tiles in a row near the screen's bottom edge (screen 1440x900).
    private let screen = ZTRect(x: 0, y: 0, w: 1440, h: 900)
    private let tiles = [
        DockItem(appName: "Finder", frame: ZTRect(x: 600, y: 840, w: 38, h: 50)),
        DockItem(appName: "Arc",    frame: ZTRect(x: 640, y: 840, w: 38, h: 50)),
        DockItem(appName: "Mail",   frame: ZTRect(x: 680, y: 840, w: 38, h: 50)),
    ]

    func testHitTestPicksTheTileUnderCursor() {
        XCTAssertEqual(DockPreview.item(at: (x: 658, y: 860), in: tiles)?.appName, "Arc")
        XCTAssertEqual(DockPreview.item(at: (x: 619, y: 850), in: tiles)?.appName, "Finder")
    }

    func testHitTestMissesBetweenTilesWithoutSlop() {
        // x=639 is in the 1px gap between Finder (ends 638) and Arc (starts 640).
        XCTAssertNil(DockPreview.item(at: (x: 639, y: 860), in: tiles))
    }

    func testSlopBridgesTheGapBetweenTiles() {
        XCTAssertEqual(DockPreview.item(at: (x: 639, y: 860), in: tiles, slop: 4)?.appName, "Finder")
    }

    func testBottomDockAnchorsPanelAboveAndCentred() {
        let arc = tiles[1]
        let o = DockPreview.panelOrigin(item: arc, size: (w: 300, h: 200), edge: .bottom, screen: screen, gap: 12)
        // Centred on the tile midX (659) → x = 659 - 150 = 509; above the tile top (840) → 840-12-200 = 628.
        XCTAssertEqual(o.x, 509, accuracy: 0.5)
        XCTAssertEqual(o.y, 628, accuracy: 0.5)
    }

    func testPanelClampsToScreenAtACorner() {
        // A tile at the far left: centring a wide panel would push x negative → clamp to screen.x.
        let corner = DockItem(appName: "Finder", frame: ZTRect(x: 4, y: 840, w: 38, h: 50))
        let o = DockPreview.panelOrigin(item: corner, size: (w: 300, h: 200), edge: .bottom, screen: screen)
        XCTAssertEqual(o.x, 0, accuracy: 0.5)            // clamped to the left screen edge
    }

    func testLeftDockAnchorsToTheRight() {
        let item = DockItem(appName: "Arc", frame: ZTRect(x: 0, y: 400, w: 50, h: 38))
        let o = DockPreview.panelOrigin(item: item, size: (w: 300, h: 200), edge: .left, screen: screen, gap: 12)
        XCTAssertEqual(o.x, 62, accuracy: 0.5)           // tile right (50) + gap (12)
        XCTAssertEqual(o.y, 400 + 19 - 100, accuracy: 0.5)   // vertically centred on the tile
    }

    func testRightDockAnchorsToTheLeft() {
        let item = DockItem(appName: "Arc", frame: ZTRect(x: 1390, y: 400, w: 50, h: 38))
        let o = DockPreview.panelOrigin(item: item, size: (w: 300, h: 200), edge: .right, screen: screen, gap: 12)
        XCTAssertEqual(o.x, 1390 - 12 - 300, accuracy: 0.5)  // to the left of the tile
    }

    func testOrientationParsing() {
        XCTAssertEqual(DockPreview.edge(fromOrientation: "left"), .left)
        XCTAssertEqual(DockPreview.edge(fromOrientation: "right"), .right)
        XCTAssertEqual(DockPreview.edge(fromOrientation: nil), .bottom)       // macOS default
        XCTAssertEqual(DockPreview.edge(fromOrientation: "garbage"), .bottom) // tolerant
    }
}
