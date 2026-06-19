// BreakScreenTests — pure trigger + copy for the retro break overlay.

import XCTest
@testable import ZTCore

final class BreakScreenTests: XCTestCase {

    func testPresentsOnlyOnWorkCompletedWhenEnabled() {
        XCTAssertTrue(BreakScreen.shouldPresent(.workCompleted, enabled: true))
        XCTAssertFalse(BreakScreen.shouldPresent(.restCompleted, enabled: true))   // end of a break, not start
        XCTAssertFalse(BreakScreen.shouldPresent(nil, enabled: true))
        XCTAssertFalse(BreakScreen.shouldPresent(.workCompleted, enabled: false))  // gated off
    }

    func testMessageFormatsMinutesAndSeconds() {
        let m = BreakScreen.message(restSec: 300, workCount: 3)
        XCTAssertEqual(m.title, "BREAK TIME")
        XCTAssertEqual(m.subtitle, "STEP AWAY · 5 MIN · SESSION #3")

        let s = BreakScreen.message(restSec: 45, workCount: 1)
        XCTAssertEqual(s.subtitle, "STEP AWAY · 45 SEC · SESSION #1")
    }
}
