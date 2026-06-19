// PlacementSuggestionsTests — pure context-aware suggestion logic.

import XCTest
@testable import ZTCore

final class PlacementSuggestionsTests: XCTestCase {

    private func win(_ id: Int, _ app: String, _ zone: String?) -> PlacementSuggestions.Window {
        PlacementSuggestions.Window(windowId: id, app: app, monitor: "1", currentZone: zone)
    }

    func testSuggestsWhenWindowIsAwayFromPreferredZone() {
        let prefs: [String: (String, Double)] = ["Slack": ("l", 9)]
        let out = PlacementSuggestions.compute(windows: [win(1, "Slack", "h")]) { app, _ in prefs[app] }
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].suggestedZone, "l")
        XCTAssertEqual(out[0].currentZone, "h")
        XCTAssertEqual(out[0].weight, 9)
    }

    func testNoSuggestionWhenAlreadyInPreferredZone() {
        let out = PlacementSuggestions.compute(windows: [win(1, "Slack", "l")]) { _, _ in ("l", 9) }
        XCTAssertTrue(out.isEmpty)
    }

    func testNoSuggestionWhenNothingLearned() {
        let out = PlacementSuggestions.compute(windows: [win(1, "Unknown", "h")]) { _, _ in nil }
        XCTAssertTrue(out.isEmpty)
    }

    func testSuggestsForWindowNotInAnyZone() {
        let out = PlacementSuggestions.compute(windows: [win(1, "Arc", nil)]) { _, _ in ("k", 3) }
        XCTAssertEqual(out.first?.currentZone, nil)
        XCTAssertEqual(out.first?.suggestedZone, "k")
    }

    func testSortedByDescendingWeightThenWindowId() {
        let prefs: [String: (String, Double)] = ["A": ("l", 2), "B": ("l", 5), "C": ("l", 5)]
        let out = PlacementSuggestions.compute(windows: [win(3, "A", "h"), win(2, "B", "h"), win(1, "C", "h")]) { app, _ in prefs[app] }
        XCTAssertEqual(out.map { $0.app }, ["C", "B", "A"])   // C=id1/w5, B=id2/w5 (tie→lower id), then A=id3/w2
    }
}
