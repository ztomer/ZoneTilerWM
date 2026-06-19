// ConfigValidatorTests — the real config is valid; crafted bad configs report problems.

import XCTest
@testable import ZTCore
@testable import ZTSystem

final class ConfigValidatorTests: XCTestCase {

    private func realConfig() throws -> ConfigLoader.LoadedConfig {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("config.toml")
        return try ConfigLoader.load(tomlString: String(contentsOf: url, encoding: .utf8),
                                     homeDirectory: "/Users/test")
    }

    func testRealConfigIsValid() throws {
        XCTAssertEqual(ConfigValidator.validate(try realConfig()), [])
    }

    func testMissingHyperAliasReported() throws {
        var cfg = try realConfig()
        cfg.aliases.removeValue(forKey: "HYPER")
        XCTAssertTrue(ConfigValidator.validate(cfg).contains { $0.contains("HYPER") })
    }

    func testEmptyGridsReported() throws {
        var cfg = try realConfig()
        cfg.zoneConfig.grids = [:]
        XCTAssertFalse(ConfigValidator.isValid(cfg))
    }
}
