// OverlayGeometryTests — locks the Pomodoro color-bar geometry and color resolution that the
// user-POV pass validated on screen (text item + top-edge red/green strips). The on-screen
// rendering is alpha-blended over the wallpaper and not eyeballable; these assert the pure
// math behind it, mirroring pomodoor.lua's `pom_draw_on_menu` (used strip left, remaining
// strip right, both at the top edge, height = indicator_height ratio of the menubar).

import XCTest
import AppKit
@testable import ZTCore
@testable import ZTSystem

final class OverlayGeometryTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)

    func testBarSplitsByRemainingRatio() {
        // Half elapsed: used and remaining each span half the width, adjacent, no gap/overlap.
        let (used, remaining) = PomodoroBar.layout(timeLeft: 50, maxTime: 100, heightRatio: 0.2,
                                                   fullFrame: screen, menubarHeight: 24)
        XCTAssertEqual(used.x, 0)
        XCTAssertEqual(used.w, 900, accuracy: 0.001)
        XCTAssertEqual(remaining.x, 900, accuracy: 0.001)   // remaining starts where used ends
        XCTAssertEqual(remaining.w, 900, accuracy: 0.001)
        XCTAssertEqual(used.w + remaining.w, screen.width, accuracy: 0.001)
    }

    func testBarSitsAtTopEdgeWithMenubarRatioHeight() {
        let (used, remaining) = PomodoroBar.layout(timeLeft: 99, maxTime: 100, heightRatio: 0.2,
                                                   fullFrame: screen, menubarHeight: 25)
        // Top edge (CG y=0) and height = 0.2 * 25 = 5.
        XCTAssertEqual(used.y, 0)
        XCTAssertEqual(remaining.y, 0)
        XCTAssertEqual(used.h, 5, accuracy: 0.001)
        XCTAssertEqual(remaining.h, 5, accuracy: 0.001)
    }

    func testBarHeightHasTwoPixelFloor() {
        // A tiny ratio still yields a visible 2px strip rather than a zero-height invisible one.
        let (used, _) = PomodoroBar.layout(timeLeft: 1, maxTime: 100, heightRatio: 0.01,
                                           fullFrame: screen, menubarHeight: 24)
        XCTAssertEqual(used.h, 2, accuracy: 0.001)
    }

    func testFullRemainingHasNoUsedStrip() {
        let (used, remaining) = PomodoroBar.layout(timeLeft: 100, maxTime: 100, heightRatio: 0.2,
                                                   fullFrame: screen, menubarHeight: 24)
        XCTAssertEqual(used.w, 0, accuracy: 0.001)
        XCTAssertEqual(remaining.w, screen.width, accuracy: 0.001)
    }

    func testColorNamesResolveToSystemColors() {
        XCTAssertEqual(PomodoroBar.color(named: "green"), .systemGreen)
        XCTAssertEqual(PomodoroBar.color(named: "RED"), .systemRed)   // case-insensitive
        XCTAssertEqual(PomodoroBar.color(named: "totally-unknown"), .gray)   // safe fallback
    }

    func testFlipPlacesTopEdgeRectAtTopOfScreen() {
        // The most likely silent regression: a top-left CG rect at y=0 must map to the top of
        // the NS (bottom-left) screen, i.e. NS y = primaryHeight - h.
        let r = ZTRect(x: 0, y: 0, w: 100, h: 5)
        let ns = CoordConvert.nsFrame(fromCG: r)
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        try? XCTSkipUnless(primaryHeight > 0, "no main display")
        XCTAssertEqual(ns.maxY, primaryHeight, accuracy: 0.001)   // top edge flush to screen top
        XCTAssertEqual(ns.minX, 0, accuracy: 0.001)
    }
}
