// ClusterTests — pure window→zone matching for App-Cluster Profiles.

import XCTest
@testable import ZTCore

final class ClusterTests: XCTestCase {
    private let dev = ClusterProfile(name: "dev", placements: [
        ClusterPlacement(app: "Ghostty", zone: "h"),
        ClusterPlacement(app: "Zen", zone: "l"),
    ])

    func testMatchesRunningWindowsToZones() {
        let out = ClusterPlan.match(profile: dev, windows: [(1, "Ghostty"), (2, "Zen"), (3, "Mail")])
        XCTAssertEqual(out, [ClusterPlan.Match(windowId: 1, zone: "h"),
                             ClusterPlan.Match(windowId: 2, zone: "l")])   // Mail unmatched → skipped
    }

    func testCaseInsensitiveAndMultipleWindowsSameApp() {
        let out = ClusterPlan.match(profile: dev, windows: [(5, "ghostty"), (6, "GHOSTTY")])
        XCTAssertEqual(out.map { $0.zone }, ["h", "h"])   // both Ghostty windows → zone h
    }

    func testNoMatchesYieldsEmpty() {
        XCTAssertTrue(ClusterPlan.match(profile: dev, windows: [(1, "Safari")]).isEmpty)
    }

    func testAppsListsTheClusterApps() {
        XCTAssertEqual(ClusterPlan.apps(dev), ["Ghostty", "Zen"])
    }
}
