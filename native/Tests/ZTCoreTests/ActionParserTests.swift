// ActionParserTests — the parser is the single source of the URL / CLI / MCP contract.
// It is bidirectional: parse(canonical(x)) == x for every case.

import XCTest
@testable import ZTCore

final class ActionParserTests: XCTestCase {

    // MARK: contract table (happy path)

    func testParseTile() {
        XCTAssertEqual(ActionParser.parse(name: "tile", params: ["zone": "h"]),
                       .success(.tileFocusedToZone(zone: "h")))
    }

    func testParseAutotile() {
        XCTAssertEqual(ActionParser.parse(name: "autotile", params: [:]), .success(.autoTileScreen))
    }

    func testParseFocusCycle() {
        XCTAssertEqual(ActionParser.parse(name: "focus-cycle", params: ["zone": "k"]),
                       .success(.cycleFocus(zone: "k")))
    }

    func testParseFocusScreen() {
        XCTAssertEqual(ActionParser.parse(name: "focus-screen", params: ["direction": "next"]),
                       .success(.focusScreen(direction: .next)))
        XCTAssertEqual(ActionParser.parse(name: "focus-screen", params: ["direction": "previous"]),
                       .success(.focusScreen(direction: .previous)))
    }

    func testParseMoveMonitor() {
        XCTAssertEqual(ActionParser.parse(name: "move-monitor", params: ["direction": "previous"]),
                       .success(.moveFocusedToMonitor(direction: .previous)))
    }

    func testParseZen() {
        XCTAssertEqual(ActionParser.parse(name: "zen", params: [:]), .success(.toggleZen))
    }

    func testParseAudioNamed() {
        XCTAssertEqual(ActionParser.parse(name: "audio", params: ["device": "BlackHole"]),
                       .success(.switchAudio(device: .named("BlackHole"))))
    }

    func testParseAudioDefaultsToNext() {
        XCTAssertEqual(ActionParser.parse(name: "audio", params: [:]),
                       .success(.switchAudio(device: .next)))
        XCTAssertEqual(ActionParser.parse(name: "audio", params: ["device": "next"]),
                       .success(.switchAudio(device: .next)))
    }

    func testParseApp() {
        XCTAssertEqual(ActionParser.parse(name: "app", params: ["name": "Finder"]),
                       .success(.appToggle(app: "Finder")))
    }

    func testParsePomodoro() {
        XCTAssertEqual(ActionParser.parse(name: "pomodoro", params: ["command": "enable"]),
                       .success(.pomodoro(.enable)))
        XCTAssertEqual(ActionParser.parse(name: "pomodoro", params: ["command": "reset"]),
                       .success(.pomodoro(.reset)))
    }

    func testParseModeToggles() {
        XCTAssertEqual(ActionParser.parse(name: "resize-mode", params: [:]), .success(.toggleResizeMode))
        XCTAssertEqual(ActionParser.parse(name: "window-hints", params: [:]), .success(.toggleWindowHints))
    }

    func testParseReload() {
        XCTAssertEqual(ActionParser.parse(name: "reload", params: [:]), .success(.reloadConfig))
    }

    // MARK: bidirectional round-trip

    func testCanonicalRoundTripEveryCase() {
        for req in ActionRequestTests.allCases {
            let c = ActionParser.canonical(req)
            XCTAssertEqual(ActionParser.parse(name: c.name, params: c.params), .success(req),
                           "canonical round-trip failed for \(req) -> \(c)")
        }
    }

    // MARK: argv + URL surfaces

    func testParseArgv() {
        XCTAssertEqual(ActionParser.parse(argv: ["tile", "--zone", "h"]),
                       .success(.tileFocusedToZone(zone: "h")))
        XCTAssertEqual(ActionParser.parse(argv: ["audio"]),
                       .success(.switchAudio(device: .next)))
    }

    func testParseURL() {
        XCTAssertEqual(ActionParser.parse(urlPath: "tile", query: ["zone": "h"]),
                       .success(.tileFocusedToZone(zone: "h")))
    }

    // MARK: rejection

    func testUnknownNameRejected() {
        XCTAssertEqual(ActionParser.parse(name: "frobnicate", params: [:]),
                       .failure(.unsupportedAction))
    }

    func testMissingZoneRejected() {
        XCTAssertEqual(ActionParser.parse(name: "tile", params: [:]),
                       .failure(.invalidParameter("zone")))
        XCTAssertEqual(ActionParser.parse(name: "focus-cycle", params: [:]),
                       .failure(.invalidParameter("zone")))
    }

    func testBadDirectionRejected() {
        XCTAssertEqual(ActionParser.parse(name: "focus-screen", params: ["direction": "sideways"]),
                       .failure(.invalidParameter("direction")))
        XCTAssertEqual(ActionParser.parse(name: "move-monitor", params: [:]),
                       .failure(.invalidParameter("direction")))
    }

    func testBadCommandRejected() {
        XCTAssertEqual(ActionParser.parse(name: "pomodoro", params: ["command": "explode"]),
                       .failure(.invalidParameter("command")))
        XCTAssertEqual(ActionParser.parse(name: "pomodoro", params: [:]),
                       .failure(.invalidParameter("command")))
    }

    func testEmptyAppRejected() {
        XCTAssertEqual(ActionParser.parse(name: "app", params: ["name": ""]),
                       .failure(.invalidParameter("name")))
        XCTAssertEqual(ActionParser.parse(name: "app", params: [:]),
                       .failure(.invalidParameter("name")))
    }
}
