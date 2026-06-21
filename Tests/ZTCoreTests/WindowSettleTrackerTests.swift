// WindowSettleTrackerTests — the pure manual-move settle detector (feedback 7b).

import XCTest
@testable import ZTCore

final class WindowSettleTrackerTests: XCTestCase {

    private func obs(_ id: Int, _ r: ZTRect) -> WindowSettleTracker.Observation { .init(id: id, frame: r) }
    private let a = ZTRect(x: 0, y: 0, w: 100, h: 100)
    private let b = ZTRect(x: 500, y: 0, w: 100, h: 100)

    func testFirstSightingDoesNotFire() {
        var t = WindowSettleTracker(settleTicks: 2)
        XCTAssertEqual(t.observe([obs(1, a)]), [])          // baseline enumeration never fires
        XCTAssertEqual(t.observe([obs(1, a)]), [])          // still resting where first seen
    }

    func testDragThenRestFiresOnceAfterSettleTicks() {
        var t = WindowSettleTracker(settleTicks: 2)
        _ = t.observe([obs(1, a)])                          // seen at rest at a
        XCTAssertEqual(t.observe([obs(1, b)]), [])          // moved to b — just changed, not settled
        XCTAssertEqual(t.observe([obs(1, b)]), [1])         // stable 2 ticks at b -> fires
        XCTAssertEqual(t.observe([obs(1, b)]), [])          // still at b -> no re-fire
        XCTAssertEqual(t.observe([obs(1, b)]), [])
    }

    func testMovingAgainFiresAgain() {
        var t = WindowSettleTracker(settleTicks: 2)
        _ = t.observe([obs(1, a)])
        _ = t.observe([obs(1, b)]); XCTAssertEqual(t.observe([obs(1, b)]), [1])   // rest at b
        XCTAssertEqual(t.observe([obs(1, a)]), [])          // moved back to a — changed
        XCTAssertEqual(t.observe([obs(1, a)]), [1])         // rest at a (a new rest) -> fires
    }

    func testDragInProgressNeverFires() {
        var t = WindowSettleTracker(settleTicks: 2)
        _ = t.observe([obs(1, a)])
        // Frame changes every tick (a live drag) -> never reaches settleTicks of stability.
        for x in stride(from: 50, through: 250, by: 50) {
            XCTAssertEqual(t.observe([obs(1, ZTRect(x: Double(x), y: 0, w: 100, h: 100))]), [])
        }
    }

    func testSubEpsilonJitterIsNotAMove() {
        var t = WindowSettleTracker(settleTicks: 2, moveEpsilon: 2.0)
        _ = t.observe([obs(1, a)])
        _ = t.observe([obs(1, b)])
        XCTAssertEqual(t.observe([obs(1, b)]), [1])         // settled at b
        // A 1px wobble (< epsilon) should NOT count as a new move, so no re-fire.
        XCTAssertEqual(t.observe([obs(1, ZTRect(x: 501, y: 0, w: 100, h: 100))]), [])
    }

    func testVanishedWindowIsForgottenAndReappearsFresh() {
        var t = WindowSettleTracker(settleTicks: 2)
        _ = t.observe([obs(1, a)])
        _ = t.observe([obs(1, b)]); XCTAssertEqual(t.observe([obs(1, b)]), [1])
        XCTAssertEqual(t.observe([]), [])                    // window 1 gone -> forgotten, no crash
        // Reappears (even at b): treated as a fresh first sighting, so it does NOT fire.
        XCTAssertEqual(t.observe([obs(1, b)]), [])
        XCTAssertEqual(t.observe([obs(1, b)]), [])
    }

    func testIndependentWindowsTrackedSeparately() {
        var t = WindowSettleTracker(settleTicks: 2)
        _ = t.observe([obs(1, a), obs(2, a)])
        _ = t.observe([obs(1, b), obs(2, a)])               // only #1 moves
        XCTAssertEqual(t.observe([obs(1, b), obs(2, a)]), [1])   // only #1 settles to a new rest
    }
}
