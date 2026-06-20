// SpaceSwitcherTests — the pure step/direction planner for same-display Space switching.

import XCTest
@testable import ZTSystem

final class SpaceSwitcherTests: XCTestCase {

    private func sp(_ id: Int, _ display: String, current: Bool = false, fs: Bool = false) -> RealSpace {
        RealSpace(id: id, uuid: "\(id)", displayUUID: display, isCurrent: current, isFullscreen: fs)
    }

    func testPlanSameDisplayStepsAndDirection() {
        let spaces = [sp(1, "A", current: true), sp(3, "A"), sp(5, "A")]
        let right = SpaceSwitcher.plan(from: spaces[0], to: spaces[1], in: spaces)
        XCTAssertEqual(right?.steps, 1); XCTAssertEqual(right?.goRight, true)
        let left = SpaceSwitcher.plan(from: spaces[2], to: spaces[0], in: spaces)
        XCTAssertEqual(left?.steps, 2); XCTAssertEqual(left?.goRight, false)
    }

    func testPlanNilForCrossDisplayOrSameSpace() {
        let a = sp(1, "A", current: true), b = sp(2, "B")
        XCTAssertNil(SpaceSwitcher.plan(from: a, to: b, in: [a, b]))   // cross-display → keyboard fallback
        XCTAssertNil(SpaceSwitcher.plan(from: a, to: a, in: [a]))      // same space
    }

    func testPlanExcludesFullscreenFromStepCount() {
        let spaces = [sp(1, "A", current: true), sp(2, "A", fs: true), sp(3, "A")]
        // desktops are [1, 3] (fullscreen ignored) → 1 → 3 is a single step
        let p = SpaceSwitcher.plan(from: spaces[0], to: spaces[2], in: spaces)
        XCTAssertEqual(p?.steps, 1); XCTAssertEqual(p?.goRight, true)
    }
}
