// RulesEngineTests — pure match logic for declarative window rules. (Prepared; iterated in the
// consolidated test pass.)

import XCTest
@testable import ZTCore

final class RulesEngineTests: XCTestCase {

    private let engine = RulesEngine(rules: [
        Rule(app: "Arc", trigger: .onOpen, action: .tileFocusedToZone(zone: "k")),
        Rule(app: "Slack", trigger: .onOpen, action: .tileFocusedToZone(zone: "l")),
        Rule(app: "Arc", trigger: .onFocus, action: .toggleZen),
    ])

    func testMatchesAppAndTrigger() {
        XCTAssertEqual(engine.matching(app: "Arc", trigger: .onOpen),
                       [Rule(app: "Arc", trigger: .onOpen, action: .tileFocusedToZone(zone: "k"))])
    }

    func testMatchIsCaseInsensitive() {
        XCTAssertEqual(engine.matching(app: "arc", trigger: .onOpen).count, 1)
        XCTAssertEqual(engine.matching(app: "ARC", trigger: .onOpen).count, 1)
    }

    func testTriggerScopesMatches() {
        XCTAssertEqual(engine.matching(app: "Arc", trigger: .onFocus),
                       [Rule(app: "Arc", trigger: .onFocus, action: .toggleZen)])
        XCTAssertTrue(engine.matching(app: "Slack", trigger: .onFocus).isEmpty)
    }

    func testNoMatchForUnknownApp() {
        XCTAssertTrue(engine.matching(app: "Finder", trigger: .onOpen).isEmpty)
    }

    func testHasRulesAndIsEmpty() {
        XCTAssertTrue(engine.hasRules(for: .onOpen))
        XCTAssertTrue(engine.hasRules(for: .onFocus))
        XCTAssertFalse(engine.hasRules(for: .onDisplayChange))
        XCTAssertFalse(engine.isEmpty)
        XCTAssertTrue(RulesEngine(rules: []).isEmpty)
        XCTAssertFalse(RulesEngine(rules: []).hasRules(for: .onOpen))
    }

    func testDeclarationOrderPreserved() {
        let multi = RulesEngine(rules: [
            Rule(app: "X", trigger: .onOpen, action: .tileFocusedToZone(zone: "h")),
            Rule(app: "X", trigger: .onOpen, action: .tileFocusedToZone(zone: "l")),
        ])
        XCTAssertEqual(multi.matching(app: "X", trigger: .onOpen).map { $0.action },
                       [.tileFocusedToZone(zone: "h"), .tileFocusedToZone(zone: "l")])
    }
}
