// RulesConfigTests — [[rules]] parse into [Rule] via the shared ActionParser; malformed rules
// are dropped. (Prepared; iterated in the consolidated test pass.)

import XCTest
@testable import ZTCore
@testable import ZTSystem

final class RulesConfigTests: XCTestCase {

    private func repoConfig() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("config.toml")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testNoRulesSectionYieldsEmpty() throws {
        let cfg = try ConfigLoader.load(tomlString: try repoConfig(), homeDirectory: "/Users/test")
        XCTAssertTrue(cfg.rules.isEmpty)
    }

    func testTileRuleParses() throws {
        let text = try repoConfig() + """

        [[rules]]
        app = "Arc"
        trigger = "on-open"
        action = "tile"
        zone = "k"
        """
        let cfg = try ConfigLoader.load(tomlString: text, homeDirectory: "/Users/test")
        XCTAssertEqual(cfg.rules, [Rule(app: "Arc", trigger: .onOpen, action: .tileFocusedToZone(zone: "k"))])
    }

    func testMultipleRulesAndActionParams() throws {
        let text = try repoConfig() + """

        [[rules]]
        app = "Slack"
        trigger = "on-focus"
        action = "audio"
        device = "BlackHole"

        [[rules]]
        app = "Mail"
        trigger = "on-display-change"
        action = "move-monitor"
        direction = "next"
        """
        let cfg = try ConfigLoader.load(tomlString: text, homeDirectory: "/Users/test")
        XCTAssertEqual(cfg.rules, [
            Rule(app: "Slack", trigger: .onFocus, action: .switchAudio(device: .named("BlackHole"))),
            Rule(app: "Mail", trigger: .onDisplayChange, action: .moveFocusedToMonitor(direction: .next)),
        ])
    }

    func testMalformedRulesDropped() throws {
        let text = try repoConfig() + """

        [[rules]]
        app = "Bad"
        trigger = "whenever"
        action = "tile"
        zone = "k"

        [[rules]]
        app = "AlsoBad"
        trigger = "on-open"
        action = "tile"

        [[rules]]
        app = "Good"
        trigger = "on-open"
        action = "zen"
        """
        let cfg = try ConfigLoader.load(tomlString: text, homeDirectory: "/Users/test")
        // bad trigger dropped, missing required zone dropped, valid one kept.
        XCTAssertEqual(cfg.rules, [Rule(app: "Good", trigger: .onOpen, action: .toggleZen)])
    }
}
