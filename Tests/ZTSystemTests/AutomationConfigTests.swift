// AutomationConfigTests — the `[automation] enabled` toggle round-trips, defaulting on when
// absent (so the MCP/CLI surface works out of the box). (Prepared; iterated in the final pass.)

import XCTest
@testable import ZTCore
@testable import ZTSystem

final class AutomationConfigTests: XCTestCase {

    private func repoConfig() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("config.toml")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testDefaultsTrueWhenSectionAbsent() throws {
        // The repo template has no [automation] section.
        let cfg = try ConfigLoader.load(tomlString: try repoConfig(), homeDirectory: "/Users/test")
        XCTAssertTrue(cfg.automationEnabled)
    }

    func testRespectsExplicitFalse() throws {
        let text = try repoConfig() + "\n[automation]\nenabled = false\n"
        let cfg = try ConfigLoader.load(tomlString: text, homeDirectory: "/Users/test")
        XCTAssertFalse(cfg.automationEnabled)
    }

    func testRespectsExplicitTrue() throws {
        let text = try repoConfig() + "\n[automation]\nenabled = true\n"
        let cfg = try ConfigLoader.load(tomlString: text, homeDirectory: "/Users/test")
        XCTAssertTrue(cfg.automationEnabled)
    }
}
