// CLIFormatTests — the pure formatting/routing behind zonetiler-cli. (Prepared; iterated in the
// final consolidated test pass.)

import XCTest
@testable import ZTCore

final class CLIFormatTests: XCTestCase {

    private let rect = ZTRect(x: 5, y: 35, w: 1670, h: 1850)

    // MARK: resource name mapping

    func testResourceMapping() {
        XCTAssertEqual(CLIFormat.resource("arrangement"), .arrangement)
        XCTAssertEqual(CLIFormat.resource("zones"), .zones)
        XCTAssertEqual(CLIFormat.resource("placement-stats"), .placementStats)
        XCTAssertEqual(CLIFormat.resource("placementStats"), .placementStats)   // raw enum name too
        XCTAssertNil(CLIFormat.resource("bogus"))
    }

    func testCliNameKebabCase() {
        XCTAssertEqual(CLIFormat.cliName(.placementStats), "placement-stats")
        for q in QueryRequest.allCases {
            XCTAssertEqual(CLIFormat.resource(CLIFormat.cliName(q)), q)   // round-trip
        }
    }

    // MARK: failure detection

    func testIsFailure() {
        XCTAssertTrue(CLIFormat.isFailure(.failed(reason: .noFocusedWindow)))
        XCTAssertFalse(CLIFormat.isFailure(.zenToggled))
        XCTAssertFalse(CLIFormat.isFailure(.tiled(windowId: 1, zone: "h", tileIndex: 1, target: rect, applied: true)))
    }

    // MARK: action summaries

    func testActionSummaries() {
        XCTAssertTrue(CLIFormat.summary(.tiled(windowId: 7, zone: "h", tileIndex: 1, target: rect, applied: true))
            .contains("tiled window 7 → zone h"))
        XCTAssertEqual(CLIFormat.summary(.zenToggled), "toggled zen mode")
        XCTAssertTrue(CLIFormat.summary(.audioSwitched(deviceName: "BlackHole")).contains("BlackHole"))
        XCTAssertEqual(CLIFormat.summary(.audioSwitched(deviceName: nil)), "no audio device switched")
        XCTAssertTrue(CLIFormat.summary(.failed(reason: .agentUnavailable)).contains("not reachable"))
        XCTAssertTrue(CLIFormat.summary(.autoTiled(moves: [
            TiledMove(windowId: 1, zone: "h", tileIndex: .int(1), rect: rect)])).contains("auto-tiled 1 window"))
    }

    // MARK: query summaries

    func testQuerySummaries() {
        XCTAssertTrue(CLIFormat.summary(.zones(screens: [ScreenZones(monitor: "1", screenName: "Main", zones: ["h", "l"])]))
            .contains("monitor 1"))
        XCTAssertEqual(CLIFormat.summary(.arrangement(windows: [])), "(no windows)")
        XCTAssertEqual(CLIFormat.summary(.placementStats(stats: [])), "(no learned placements)")
        XCTAssertTrue(CLIFormat.summary(.unavailable(reason: "memory disabled")).contains("memory disabled"))
        // Empty app name (legacy/edge store entries) reads as (unknown), not blank.
        XCTAssertTrue(CLIFormat.summary(.placementStats(stats: [
            PlacementStat(app: "", monitor: "1", zone: "h", tile: .int(2), count: 5)])).contains("(unknown)"))
    }

    // MARK: usage covers the whole surface

    func testUsageListsEveryActionAndResource() {
        let usage = CLIFormat.usage()
        for spec in ActionParser.catalog { XCTAssertTrue(usage.contains(spec.name), "usage missing action \(spec.name)") }
        for q in QueryRequest.allCases { XCTAssertTrue(usage.contains(CLIFormat.cliName(q)), "usage missing resource \(q)") }
    }
}
