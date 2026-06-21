// ZoneHUDOverlayRenderTests — the headless HUD render produces a PNG, and the tile-on-release
// highlight actually changes the output (the preview fill is drawn). Pins the render plumbing the
// live overlay shares; the visual look itself is judged by screenshot QA (deterministic render harness).

import XCTest
import AppKit
@testable import ZTCore
@testable import ZTSystem

final class ZoneHUDOverlayRenderTests: XCTestCase {

    private let cells: [ZoneHUD.Cell] = [
        .init(key: "h", rect: ZTRect(x: 0,   y: 0, w: 500, h: 1000)),
        .init(key: "j", rect: ZTRect(x: 500, y: 0, w: 500, h: 1000)),
    ]
    private let frame = ZTRect(x: 0, y: 0, w: 1000, h: 1000)

    func testRendersAPNG() {
        let data = ZoneHUDOverlay.renderPNG(cells: cells, screenCGFrame: frame)
        XCTAssertNotNil(data)
        XCTAssertFalse(data!.isEmpty)
    }

    func testHighlightChangesTheRender() {
        let plain = ZoneHUDOverlay.renderPNG(cells: cells, screenCGFrame: frame)
        let lit   = ZoneHUDOverlay.renderPNG(cells: cells, screenCGFrame: frame, highlight: "j")
        XCTAssertNotNil(plain); XCTAssertNotNil(lit)
        XCTAssertNotEqual(plain, lit, "highlighting a zone must change the rendered pixels (the fill)")
    }

    func testUnknownHighlightMatchesNoHighlight() {
        let plain = ZoneHUDOverlay.renderPNG(cells: cells, screenCGFrame: frame)
        let bogus = ZoneHUDOverlay.renderPNG(cells: cells, screenCGFrame: frame, highlight: "zzz")
        XCTAssertEqual(plain, bogus, "a key that matches no zone draws nothing extra")
    }
}
