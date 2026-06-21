// AppLauncherOverlayRenderTests — the headless app-launcher palette renders a PNG.

import XCTest
import AppKit
@testable import ZTCore
@testable import ZTSystem

final class AppLauncherOverlayRenderTests: XCTestCase {

    func testRendersAPNG() {
        let caps = AppLauncherHUD.caps(apps: ["c": "Chrome", "s": "Slack", "1": "Terminal"])
        let data = AppLauncherOverlay.renderPNG(caps: caps, screenCGFrame: ZTRect(x: 0, y: 0, w: 1400, h: 900))
        XCTAssertNotNil(data)
        XCTAssertFalse(data!.isEmpty)
    }

    func testEmptyCapsStillRendersBackdrop() {
        let data = AppLauncherOverlay.renderPNG(caps: [], screenCGFrame: ZTRect(x: 0, y: 0, w: 800, h: 600))
        XCTAssertNotNil(data)
    }
}
