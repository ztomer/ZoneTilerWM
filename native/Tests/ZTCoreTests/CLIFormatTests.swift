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

    // MARK: every action-result case formats to a sensible, non-empty line

    func testEveryActionSummaryCase() {
        let move = TiledMove(windowId: 3, zone: "k", tileIndex: .int(2), rect: rect)
        let cases: [(ActionResult, String)] = [
            (.focusCycled(focusedWindowId: 9), "focused window 9"),
            (.focusCycled(focusedWindowId: nil), "no window to focus"),
            (.screenFocused(focusedWindowId: 4), "adjacent screen"),
            (.screenFocused(focusedWindowId: nil), "no adjacent-screen window"),
            (.monitorMoved(windowId: 2, zone: "l", tileIndex: 1, target: rect, applied: true), "monitor zone l"),
            (.windowMoved(windowId: 5, target: rect, applied: false), "moved window 5 [not applied]"),
            (.swapped(windowA: 1, windowB: 2, applied: true), "swapped windows 1 ↔ 2"),
            (.floatToggled(windowId: 6, floating: true), "floated"),
            (.floatToggled(windowId: 6, floating: false), "unfloated"),
            (.appToggled(app: "Finder"), "toggled app Finder"),
            (.pomodoroUpdated(active: true, phase: "work", timeLeftSec: 90), "pomodoro work: 90s left"),
            (.pomodoroUpdated(active: false, phase: "work", timeLeftSec: 0), "pomodoro off"),
            (.modeToggled(mode: .resize), "toggled resize mode"),
            (.configReloaded(ok: true), "config reloaded"),
            (.configReloaded(ok: false), "config reload failed"),
            (.layoutSaved(name: "dev", windowCount: 1), "saved layout 'dev' (1 window)"),
            (.layoutApplied(name: "dev", moved: 2), "applied layout 'dev' (2 windows moved)"),
            (.synced(direction: "export", files: []), "nothing to copy"),
            (.synced(direction: "export", files: ["a.json"]), "1 file (a.json)"),
            (.suggestionsApplied(moves: []), "no suggestions to apply"),
            (.suggestionsApplied(moves: [move]), "applied 1 suggestion"),
            (.scratchpadToggled(summoned: true, apps: ["Notes"]), "scratchpad summoned: Notes"),
            (.clusterApplied(name: "dev", moves: [move, move]), "cluster 'dev': arranged 2 windows"),
            (.sandboxToggled(active: true, hidden: 3), "sandbox on — hid 3 apps"),
            (.sandboxToggled(active: false, hidden: 1), "sandbox off — restored 1 app"),
        ]
        for (result, needle) in cases {
            XCTAssertTrue(CLIFormat.summary(result).contains(needle),
                          "summary(\(result)) missing '\(needle)' — got '\(CLIFormat.summary(result))'")
        }
    }

    func testEveryQuerySummaryCase() {
        XCTAssertTrue(CLIFormat.summary(.arrangement(windows: [
            WindowInfo(windowId: 8, app: "Safari", frame: rect, monitor: "1", zone: "h")])).contains("Safari#8"))
        XCTAssertTrue(CLIFormat.summary(.suggestions(suggestions: [
            PlacementSuggestion(windowId: 8, app: "Safari", monitor: "1",
                                currentZone: "h", suggestedZone: "l", weight: 2.5)])).contains("→ l"))
        XCTAssertEqual(CLIFormat.summary(.suggestions(suggestions: [])), "(no suggestions — every window is in its usual zone)")
    }

    // MARK: usage covers the whole surface

    func testUsageListsEveryActionAndResource() {
        let usage = CLIFormat.usage()
        for spec in ActionParser.catalog { XCTAssertTrue(usage.contains(spec.name), "usage missing action \(spec.name)") }
        for q in QueryRequest.allCases { XCTAssertTrue(usage.contains(CLIFormat.cliName(q)), "usage missing resource \(q)") }
    }
}
