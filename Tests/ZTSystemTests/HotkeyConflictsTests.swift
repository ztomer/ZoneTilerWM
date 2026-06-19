// HotkeyConflictsTests — the conflict detector + the config-derived binding set.

import XCTest
@testable import ZTCore
@testable import ZTSystem

final class HotkeyConflictsTests: XCTestCase {

    func testFindsSameComboDifferentActions() {
        let c = HotkeyConflicts.find([
            .init(modifier: ["shift", "ctrl", "cmd"], key: "0", label: "Pomodoro reset"),
            .init(modifier: ["cmd", "shift", "ctrl"], key: "0", label: "Focus zone 0"),   // order-independent
            .init(modifier: ["ctrl", "cmd"], key: "j", label: "Tile zone j"),             // no conflict
        ])
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c[0].combo, "⇧⌃⌘0")
        XCTAssertEqual(c[0].actions, ["Focus zone 0", "Pomodoro reset"])
    }

    func testNoConflictForSameActionOrEmptyKey() {
        let c = HotkeyConflicts.find([
            .init(modifier: ["ctrl", "cmd"], key: "h", label: "Tile zone h"),
            .init(modifier: ["ctrl", "cmd"], key: "h", label: "Tile zone h"),  // dup of same action
            .init(modifier: ["shift", "ctrl", "alt", "cmd"], key: "", label: "Auto-tile global"), // empty key skipped
        ])
        XCTAssertTrue(c.isEmpty)
    }

    func testRealConfigBindingsAreConsistentlyDetected() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("config.toml")
        let cfg = try ConfigLoader.load(tomlString: String(contentsOf: url, encoding: .utf8),
                                        homeDirectory: "/Users/test")
        // Sanity: bindings are produced and conflict detection runs.
        XCTAssertFalse(cfg.allBindings().isEmpty)
        // The shipped example config must be conflict-free.
        XCTAssertEqual(cfg.hotkeyConflicts().count, 0, "example config should have no hotkey conflicts")
        // A synthetic clash injected on top of the real bindings is detected.
        var withClash = cfg.allBindings()
        withClash.append(.init(modifier: cfg.tilerModifier, key: "j", label: "Bogus duplicate"))
        XCTAssertTrue(HotkeyConflicts.find(withClash).contains { $0.actions.contains("Bogus duplicate") })
    }
}
