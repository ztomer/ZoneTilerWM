// WindowFocusTrackerTests — the passive focus-time bookkeeping that powers the auto-tiler's
// working-set cull (mirrors window_cache.lua's last_focused_time). Pure, deterministic: the
// clock is always injected.

import XCTest
@testable import ZTCore

final class WindowFocusTrackerTests: XCTestCase {

    func testRecordAndReadBack() {
        let t = WindowFocusTracker()
        t.record(id: 7, at: 100)
        XCTAssertEqual(t.lastFocused(id: 7), 100)
        XCTAssertNil(t.lastFocused(id: 8))
    }

    func testRecordOverwritesWithLaterFocus() {
        let t = WindowFocusTracker()
        t.record(id: 7, at: 100)
        t.record(id: 7, at: 250)   // re-focused later
        XCTAssertEqual(t.lastFocused(id: 7), 250)
    }

    func testRecordIfAbsentDoesNotClobberExisting() {
        let t = WindowFocusTracker()
        t.record(id: 7, at: 250)
        t.recordIfAbsent(id: 7, at: 100)   // baseline seed must not reset a known time
        XCTAssertEqual(t.lastFocused(id: 7), 250)
        t.recordIfAbsent(id: 9, at: 100)   // but it does seed an unknown window
        XCTAssertEqual(t.lastFocused(id: 9), 100)
    }

    func testForgetAndPrune() {
        let t = WindowFocusTracker()
        t.record(id: 1, at: 10); t.record(id: 2, at: 20); t.record(id: 3, at: 30)
        t.forget(id: 2)
        XCTAssertNil(t.lastFocused(id: 2))
        t.prune(keepingIds: [3])           // drop everything not currently live
        XCTAssertNil(t.lastFocused(id: 1))
        XCTAssertEqual(t.lastFocused(id: 3), 30)
    }
}
