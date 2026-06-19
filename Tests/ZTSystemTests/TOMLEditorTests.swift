// TOMLEditorTests — surgical edits change only the target line and preserve comments;
// the rest of the real config.toml stays byte-identical and still parses.

import XCTest
@testable import ZTCore
@testable import ZTSystem

final class TOMLEditorTests: XCTestCase {

    private func realConfig() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("config.toml")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Number of lines that differ between two TOML strings.
    private func changedLineCount(_ a: String, _ b: String) -> Int {
        let la = a.components(separatedBy: "\n"), lb = b.components(separatedBy: "\n")
        guard la.count == lb.count else { return max(la.count, lb.count) }
        return zip(la, lb).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
    }

    func testEditScalarChangesOnlyOneLine() throws {
        let original = try realConfig()
        let edited = try XCTUnwrap(
            TOMLEditor.setValue(original, section: "tiler", key: "placement_strategy", rawValue: "\"rotate\""))
        XCTAssertTrue(edited.contains("placement_strategy = \"rotate\""))
        XCTAssertFalse(edited.contains("\"largest_free_space\""))
        XCTAssertEqual(changedLineCount(original, edited), 1)
    }

    func testEditInSubsection() throws {
        let original = try realConfig()
        let edited = try XCTUnwrap(
            TOMLEditor.setValue(original, section: "tiler.margins", key: "size", rawValue: "10"))
        XCTAssertTrue(edited.contains("size = 10"))
        XCTAssertEqual(changedLineCount(original, edited), 1)
    }

    func testPreservesTrailingComment() throws {
        let original = try realConfig()
        let edited = try XCTUnwrap(
            TOMLEditor.setValue(original, section: "tiler", key: "reposition_on_screen_change", rawValue: "false"))
        // The inline comment must survive.
        XCTAssertTrue(edited.contains(
            "reposition_on_screen_change = false # Reposition windows when screen configuration changes"))
        XCTAssertEqual(changedLineCount(original, edited), 1)
    }

    func testLayoutEditorWritePreservesCommentAndReparses() throws {
        // Mirrors SettingsModel.setLayoutZone: replace a layout zone's inline array in a quoted
        // subsection, keeping the trailing comment, and re-parse with the new tiles.
        let original = try realConfig()
        let edited = try XCTUnwrap(
            TOMLEditor.setValue(original, section: "tiler.layouts.\"2x2\"", key: "h",
                                rawValue: "[\"a1\", \"a2\"]"))
        XCTAssertTrue(edited.contains("\"h\" = [\"a1\", \"a2\"] # Left tile"),
                      "the zone array changes but the inline comment survives")
        XCTAssertEqual(changedLineCount(original, edited), 1)
        let cfg = try ConfigLoader.load(tomlString: edited, homeDirectory: "/Users/test")
        XCTAssertEqual(cfg.zoneConfig.layouts["2x2"]?["h"], ["a1", "a2"])
        XCTAssertEqual(cfg.zoneConfig.layouts["2x2"]?["j"], ["a1:b2"])   // sibling untouched
    }

    func testSetOrAppendNewSectionAtEOF() throws {
        let original = try realConfig()
        // A monitor not present in custom_screens → new section appended at EOF.
        let edited = TOMLEditor.setOrAppend(original, section: "tiler.custom_screens.\"Test Display\"",
                                            key: "layout", rawValue: "\"3x2\"")
        XCTAssertTrue(edited.hasPrefix(original), "appended at EOF; original content byte-identical")
        XCTAssertTrue(edited.contains("[tiler.custom_screens.\"Test Display\"]"))
        XCTAssertTrue(edited.contains("layout = \"3x2\""))
        let cfg = try ConfigLoader.load(tomlString: edited, homeDirectory: "/Users/test")
        XCTAssertEqual(cfg.zoneConfig.custom_screens?["Test Display"]?.layout, "3x2")
    }

    func testSetOrAppendExistingKeyReplacesInPlace() throws {
        let original = try realConfig()
        let edited = TOMLEditor.setOrAppend(original, section: "tiler.margins", key: "size", rawValue: "12")
        XCTAssertTrue(edited.contains("size = 12"))
        XCTAssertEqual(changedLineCount(original, edited), 1)   // replaced, not appended
    }

    func testRemoveKeyDropsOnlyThatLine() throws {
        let original = try realConfig()
        // appCuts has "e" = "Finder"; removing it should delete just that line and re-parse.
        let edited = try XCTUnwrap(TOMLEditor.removeKey(original, section: "appCuts", key: "e"))
        XCTAssertFalse(edited.contains("\"e\" = \"Finder\""))
        XCTAssertEqual(original.components(separatedBy: "\n").count - 1,
                       edited.components(separatedBy: "\n").count)   // exactly one line removed
        let cfg = try ConfigLoader.load(tomlString: edited, homeDirectory: "/Users/test")
        XCTAssertNil(cfg.appCuts.apps["e"])
        XCTAssertEqual(cfg.appCuts.apps["w"], "Signal")   // sibling intact
    }

    func testRemoveKeyMissingReturnsNil() throws {
        let original = try realConfig()
        XCTAssertNil(TOMLEditor.removeKey(original, section: "appCuts", key: "nonesuch"))
    }

    func testMissingKeyReturnsNil() throws {
        let original = try realConfig()
        XCTAssertNil(TOMLEditor.setValue(original, section: "tiler", key: "no_such_key", rawValue: "1"))
    }

    func testEditedConfigStillParsesWithNewValue() throws {
        let original = try realConfig()
        let edited = try XCTUnwrap(
            TOMLEditor.setValue(original, section: "tiler", key: "auto_tiling_mode", rawValue: "\"session\""))
        let cfg = try ConfigLoader.load(tomlString: edited, homeDirectory: "/Users/test")
        XCTAssertEqual(cfg.autoTilingMode, "session")
        // An untouched value is intact.
        XCTAssertEqual(cfg.workingSetMaxCapacity, 6)
    }
}
