// FocusFollowsMouseTests — pure topmost-window-under-cursor hit test.

import XCTest
@testable import ZTCore

final class FocusFollowsMouseTests: XCTestCase {
    func testTopmostOverlappingWindowWins() {
        // front-to-back order: window 1 is on top.
        let wins: [(id: Int, frame: ZTRect)] = [
            (1, ZTRect(x: 100, y: 100, w: 400, h: 300)),
            (2, ZTRect(x: 0, y: 0, w: 800, h: 600)),
        ]
        XCTAssertEqual(FocusFollowsMouse.topWindow(at: 200, y: 200, windows: wins), 1)   // both contain → front
        XCTAssertEqual(FocusFollowsMouse.topWindow(at: 600, y: 500, windows: wins), 2)   // only the back one
    }

    func testNilWhenCursorOverNoWindow() {
        let wins: [(id: Int, frame: ZTRect)] = [(1, ZTRect(x: 0, y: 0, w: 100, h: 100))]
        XCTAssertNil(FocusFollowsMouse.topWindow(at: 500, y: 500, windows: wins))
    }

    func testHalfOpenEdges() {
        let wins: [(id: Int, frame: ZTRect)] = [(1, ZTRect(x: 0, y: 0, w: 100, h: 100))]
        XCTAssertEqual(FocusFollowsMouse.topWindow(at: 0, y: 0, windows: wins), 1)        // top-left included
        XCTAssertNil(FocusFollowsMouse.topWindow(at: 100, y: 50, windows: wins))          // right edge excluded
    }
}
