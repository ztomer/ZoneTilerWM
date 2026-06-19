// CommandPaletteTests — fuzzy match + command-line resolve for the action palette.

import XCTest
@testable import ZTCore

final class CommandPaletteTests: XCTestCase {

    func testEmptyQueryReturnsWholeCatalog() {
        XCTAssertEqual(CommandPalette.match("").count, ActionParser.catalog.count)
    }

    func testPrefixRanksFirst() {
        let r = CommandPalette.match("tile")
        XCTAssertEqual(r.first?.name, "tile")   // exact/prefix beats "autotile" (contains)
    }

    func testFuzzySubsequence() {
        // "wh" is a subsequence of "window-hints"; should appear.
        let names = CommandPalette.match("wh").map { $0.name }
        XCTAssertTrue(names.contains("window-hints"))
    }

    func testDescriptionFallback() {
        // "audio" appears in the audio action's description/name; "speaker"-ish words fall back.
        let names = CommandPalette.match("zen").map { $0.name }
        XCTAssertEqual(names.first, "zen")
    }

    func testNoMatch() {
        XCTAssertTrue(CommandPalette.match("zzzzx").isEmpty)
    }

    // MARK: resolve

    func testResolveNoParam() {
        XCTAssertEqual(CommandPalette.resolve("zen"), .success(.toggleZen))
        XCTAssertEqual(CommandPalette.resolve("autotile"), .success(.autoTileScreen))
    }

    func testResolvePositionalParam() {
        XCTAssertEqual(CommandPalette.resolve("tile h"), .success(.tileFocusedToZone(zone: "h")))
        XCTAssertEqual(CommandPalette.resolve("save-layout coding"), .success(.saveLayout(name: "coding")))
        XCTAssertEqual(CommandPalette.resolve("app Finder"), .success(.appToggle(app: "Finder")))
        XCTAssertEqual(CommandPalette.resolve("focus-screen next"), .success(.focusScreen(direction: .next)))
    }

    func testResolveAudioOptionalParam() {
        XCTAssertEqual(CommandPalette.resolve("audio"), .success(.switchAudio(device: .next)))
        XCTAssertEqual(CommandPalette.resolve("audio BlackHole"), .success(.switchAudio(device: .named("BlackHole"))))
    }

    func testResolveUniquePrefix() {
        // "win" uniquely prefixes "window-hints".
        XCTAssertEqual(CommandPalette.resolve("win"), .success(.toggleWindowHints))
    }

    func testResolveMissingRequiredParamFails() {
        XCTAssertEqual(CommandPalette.resolve("tile"), .failure(.invalidParameter("zone")))
    }

    func testResolveUnknownFails() {
        XCTAssertEqual(CommandPalette.resolve("frobnicate"), .failure(.unsupportedAction))
        XCTAssertEqual(CommandPalette.resolve(""), .failure(.unsupportedAction))
    }
}
