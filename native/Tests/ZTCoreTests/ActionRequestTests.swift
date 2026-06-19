// ActionRequestTests — the action vocabulary is Codable + Equatable so every front-end
// (URL, CLI, MCP) and the agent↔shim IPC can serialize into one shared currency.

import XCTest
@testable import ZTCore

final class ActionRequestTests: XCTestCase {

    /// Every case, used as the fixture for round-trip tests here and in ActionParserTests.
    /// (A device literally named "next" is intentionally excluded — it collides with the
    /// `.next` sentinel in the canonical string form; an audio device named "next" is absurd.)
    static let allCases: [ActionRequest] = [
        .tileFocusedToZone(zone: "h"),
        .autoTileScreen,
        .cycleFocus(zone: "k"),
        .cycleZoneStack(direction: .next),
        .cycleZoneStack(direction: .previous),
        .applySuggestions,
        .scratchpad,
        .applyCluster(name: "dev"),
        .peekZone,
        .focusScreen(direction: .next),
        .focusScreen(direction: .previous),
        .moveFocusedToMonitor(direction: .next),
        .moveFocusedToMonitor(direction: .previous),
        .nudge(direction: .up),
        .throwWindow(direction: .left),
        .swap(direction: .right),
        .toggleZen,
        .toggleFloat,
        .switchAudio(device: .next),
        .switchAudio(device: .named("MacBook Pro Speakers")),
        .appToggle(app: "Finder"),
        .pomodoro(.enable),
        .pomodoro(.disable),
        .pomodoro(.reset),
        .toggleResizeMode,
        .toggleWindowHints,
        .saveLayout(name: "coding"),
        .applyLayout(name: "writing"),
        .syncExport,
        .syncImport,
        .reloadConfig,
    ]

    func testCodableRoundTripEveryCase() throws {
        let enc = JSONEncoder()
        let dec = JSONDecoder()
        for req in Self.allCases {
            let data = try enc.encode(req)
            let back = try dec.decode(ActionRequest.self, from: data)
            XCTAssertEqual(req, back, "round-trip mismatch for \(req)")
        }
    }

    func testAudioTargetNamedCarriesValue() throws {
        let data = try JSONEncoder().encode(ActionRequest.switchAudio(device: .named("BlackHole")))
        let back = try JSONDecoder().decode(ActionRequest.self, from: data)
        XCTAssertEqual(back, .switchAudio(device: .named("BlackHole")))
    }

    func testEqualityIsCaseSensitive() {
        XCTAssertNotEqual(ActionRequest.tileFocusedToZone(zone: "h"),
                          ActionRequest.tileFocusedToZone(zone: "j"))
        XCTAssertNotEqual(ActionRequest.focusScreen(direction: .next),
                          ActionRequest.focusScreen(direction: .previous))
    }
}
