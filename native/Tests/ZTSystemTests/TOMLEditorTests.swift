// TOMLEditorTests — surgical edits change only the target line and preserve comments;
// the rest of the real config.toml stays byte-identical and still parses.

import XCTest
@testable import ZTCore
@testable import ZTSystem

final class TOMLEditorTests: XCTestCase {

    private func realConfig() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
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
