// ZoneHUDOverlayRenderTests — the headless picker render produces a PNG, the preview fill changes the
// output, and cycling to a different placement resizes it. Pins the render plumbing the live overlay
// shares; the visual look itself is judged by screenshot QA (deterministic render harness).

import XCTest
import AppKit
@testable import ZTCore
@testable import ZTSystem

final class ZoneHUDOverlayRenderTests: XCTestCase {

    // "h" and "j" each cycle big → small (distinct atomic cells, no collision).
    private let tiles: [String: [ZTRect]] = [
        "h": [ZTRect(x: 0,   y: 0, w: 500, h: 1000), ZTRect(x: 0,   y: 0,   w: 250, h: 500)],
        "j": [ZTRect(x: 250, y: 0, w: 500, h: 1000), ZTRect(x: 250, y: 250, w: 250, h: 250)],
    ]
    private let frame = ZTRect(x: 0, y: 0, w: 1000, h: 1000)
    private func caps() -> [ZoneHUD.CapLabel] { ZoneHUD.caps(zones: tiles) }
    private func png(_ hl: (key: String, tile: Int)?, gridV: [Double] = [], gridH: [Double] = []) -> Data? {
        ZoneHUDOverlay.renderPNG(tilesByKey: tiles, caps: caps(), gridV: gridV, gridH: gridH,
                                 screenCGFrame: frame, highlight: hl)
    }

    func testRendersAPNG() {
        let data = png(nil, gridV: [500], gridH: [333, 666])
        XCTAssertNotNil(data)
        XCTAssertFalse(data!.isEmpty)
    }

    func testHighlightChangesTheRender() {
        XCTAssertNotEqual(png(nil), png((key: "j", tile: 0)),
                          "previewing a zone must change the pixels (the fill)")
    }

    func testCyclingToADifferentTileResizesTheFill() {
        XCTAssertNotEqual(png((key: "j", tile: 0)), png((key: "j", tile: 1)),
                          "re-pressing (cycling the tile) must resize the fill → different pixels")
    }

    func testUnknownHighlightMatchesNoHighlight() {
        XCTAssertEqual(png(nil), png((key: "zzz", tile: 0)),
                       "a key that matches no zone draws no fill")
    }
}
