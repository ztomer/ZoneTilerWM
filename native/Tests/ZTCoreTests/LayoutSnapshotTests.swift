// LayoutSnapshotTests — pure capture + restore-planning for named layouts.

import XCTest
@testable import ZTCore

final class LayoutSnapshotTests: XCTestCase {

    private let rect = ZTRect(x: 0, y: 0, w: 100, h: 100)
    private func win(_ id: Int, _ app: String, _ mon: String, _ zone: String?) -> WindowInfo {
        WindowInfo(windowId: id, app: app, frame: rect, monitor: mon, zone: zone)
    }

    func testCaptureSkipsUnzonedAndDedupsByAppMonitor() {
        let snap = LayoutSnapshots.capture(name: "coding", from: [
            win(1, "Arc", "1", "h"),
            win(2, "Arc", "1", "k"),     // dup app+monitor → first (h) wins
            win(3, "Ghostty", "1", nil), // no zone → skipped
            win(4, "Slack", "2", "l"),
        ])
        XCTAssertEqual(snap.name, "coding")
        XCTAssertEqual(snap.assignments, [
            .init(app: "Arc", monitor: "1", zone: "h"),
            .init(app: "Slack", monitor: "2", zone: "l"),
        ])
    }

    func testCaptureCodableRoundTrip() throws {
        let snap = LayoutSnapshots.capture(name: "x", from: [win(1, "Arc", "1", "h")])
        let data = try JSONEncoder().encode(snap)
        XCTAssertEqual(try JSONDecoder().decode(LayoutSnapshot.self, from: data), snap)
    }

    func testRestorePlanPrefersSameMonitorThenAnySameApp() {
        let snap = LayoutSnapshot(name: "x", assignments: [
            .init(app: "Arc", monitor: "2", zone: "h"),
        ])
        // Two Arc windows: one on monitor 1, one on monitor 2 → pick the monitor-2 one.
        let plan = LayoutSnapshots.restorePlan(snap, current: [
            win(10, "Arc", "1", nil), win(11, "Arc", "2", nil),
        ])
        XCTAssertEqual(plan, [.init(windowId: 11, zone: "h")])
    }

    func testRestorePlanFallsBackToAnyMonitor() {
        let snap = LayoutSnapshot(name: "x", assignments: [.init(app: "Arc", monitor: "2", zone: "h")])
        let plan = LayoutSnapshots.restorePlan(snap, current: [win(10, "Arc", "1", nil)])
        XCTAssertEqual(plan, [.init(windowId: 10, zone: "h")])   // monitor moved, still matched
    }

    func testRestorePlanDoesNotReuseWindowsAndSkipsUnmatched() {
        let snap = LayoutSnapshot(name: "x", assignments: [
            .init(app: "Arc", monitor: "1", zone: "h"),
            .init(app: "Arc", monitor: "1", zone: "k"),   // needs a 2nd Arc window
            .init(app: "Mail", monitor: "1", zone: "l"),  // no Mail window → skipped
        ])
        let plan = LayoutSnapshots.restorePlan(snap, current: [
            win(10, "Arc", "1", nil), win(11, "Arc", "1", nil),
        ])
        XCTAssertEqual(plan, [.init(windowId: 10, zone: "h"), .init(windowId: 11, zone: "k")])
    }

    func testRestorePlanCaseInsensitiveApp() {
        let snap = LayoutSnapshot(name: "x", assignments: [.init(app: "arc", monitor: "1", zone: "h")])
        let plan = LayoutSnapshots.restorePlan(snap, current: [win(10, "Arc", "1", nil)])
        XCTAssertEqual(plan, [.init(windowId: 10, zone: "h")])
    }

    func testLibraryUpsertAndLookup() {
        let a = LayoutSnapshot(name: "coding", assignments: [.init(app: "Arc", monitor: "1", zone: "h")])
        let b = LayoutSnapshot(name: "coding", assignments: [.init(app: "Arc", monitor: "1", zone: "k")])
        let lib = LayoutLibrary().upserting(a).upserting(b)   // replace by name
        XCTAssertEqual(lib.snapshots.count, 1)
        XCTAssertEqual(lib.snapshot(named: "coding"), b)
        XCTAssertEqual(LayoutLibrary().upserting(a).upserting(
            LayoutSnapshot(name: "writing", assignments: [])).names, ["coding", "writing"])
    }
}
