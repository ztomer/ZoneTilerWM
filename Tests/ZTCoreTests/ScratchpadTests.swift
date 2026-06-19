// ScratchpadTests — pure scratchpad toggle decision.

import XCTest
@testable import ZTCore

final class ScratchpadTests: XCTestCase {
    private let apps = ["Terminal", "Notes"]

    func testSummonWhenFrontmostNotInSet() {
        XCTAssertEqual(Scratchpad.decide(frontmost: "Safari", apps: apps), .summon)
        XCTAssertEqual(Scratchpad.decide(frontmost: nil, apps: apps), .summon)
    }

    func testDismissWhenFrontmostInSet() {
        XCTAssertEqual(Scratchpad.decide(frontmost: "Terminal", apps: apps), .dismiss)
        XCTAssertEqual(Scratchpad.decide(frontmost: "notes", apps: apps), .dismiss)   // case-insensitive
    }

    func testContains() {
        XCTAssertTrue(Scratchpad.contains("Terminal", in: apps))
        XCTAssertFalse(Scratchpad.contains("Safari", in: apps))
        XCTAssertFalse(Scratchpad.contains(nil, in: apps))
    }
}
