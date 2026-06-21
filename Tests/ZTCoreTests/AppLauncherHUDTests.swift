// AppLauncherHUDTests — keyboard placement of app-shortcut caps.

import XCTest
@testable import ZTCore

final class AppLauncherHUDTests: XCTestCase {

    func testCapsPlaceKeysAtTheirKeyboardPosition() {
        let caps = AppLauncherHUD.caps(apps: ["q": "Xcode", "c": "Chrome"])
        XCTAssertEqual(caps, [
            .init(key: "q", label: "Xcode", row: 1, col: 0.5),    // q: row 1, index 0 + 0.5 stagger
            .init(key: "c", label: "Chrome", row: 3, col: 3.25),  // c: row 3 (z,x,c → index 2) + 1.25 stagger
        ])
    }

    func testCapsSkipUnknownKeysAndEmptyLabels() {
        let caps = AppLauncherHUD.caps(apps: ["c": "Chrome", "§": "Weird", "x": ""])
        XCTAssertEqual(caps.map(\.key), ["c"])
    }

    func testCapsOrderedTopLeftToBottomRight() {
        let caps = AppLauncherHUD.caps(apps: ["z": "A", "1": "B", "p": "C"])
        XCTAssertEqual(caps.map(\.key), ["1", "p", "z"])   // number row → home-ish → bottom row
    }

    func testEmptyAppsYieldNoCaps() {
        XCTAssertTrue(AppLauncherHUD.caps(apps: [:]).isEmpty)
    }
}
