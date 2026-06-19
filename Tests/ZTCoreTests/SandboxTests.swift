// SandboxTests — pure "which apps to hide" for the session sandbox.

import XCTest
@testable import ZTCore

final class SandboxTests: XCTestCase {
    private func app(_ n: String, regular: Bool = true, hidden: Bool = false, front: Bool = false) -> Sandbox.App {
        Sandbox.App(name: n, regular: regular, hidden: hidden, frontmost: front)
    }

    func testHidesRegularVisibleNonFrontmostApps() {
        let out = Sandbox.appsToHide([
            app("Safari", front: true),     // frontmost — keep
            app("Mail"),                    // hide
            app("Notes"),                   // hide
        ], selfName: "ZoneTilerWM")
        XCTAssertEqual(out, ["Mail", "Notes"])
    }

    func testSkipsAlreadyHiddenAndAgentAndNonRegular() {
        let out = Sandbox.appsToHide([
            app("Mail", hidden: true),          // already hidden — leave (user hid it)
            app("ZoneTilerWM"),                 // the agent — never hide
            app("Spotlight", regular: false),   // not a regular app — skip
            app(""),                            // unnamed — skip
            app("Slack"),                       // hide
        ], selfName: "ZoneTilerWM")
        XCTAssertEqual(out, ["Slack"])
    }

    func testEmptyWhenNothingToHide() {
        XCTAssertTrue(Sandbox.appsToHide([app("Safari", front: true)], selfName: "ZoneTilerWM").isEmpty)
    }
}
