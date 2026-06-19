// DisplayPresetTests — pure display-topology preset matching.

import XCTest
@testable import ZTCore

final class DisplayPresetTests: XCTestCase {
    private let presets = [
        DisplayPreset(displays: ["DELL U3223QE"], action: .applyLayout(name: "docked")),
        DisplayPreset(displays: [], action: .autoTileScreen),   // fallback: any
    ]

    func testMatchesSpecificWhenDisplayPresent() {
        let a = DisplayPresetEngine.match(current: ["Built-in", "DELL U3223QE"], presets: presets)
        XCTAssertEqual(a, .applyLayout(name: "docked"))
    }

    func testFallsBackToEmptyMatch() {
        let a = DisplayPresetEngine.match(current: ["Built-in Retina Display"], presets: presets)
        XCTAssertEqual(a, .autoTileScreen)   // DELL absent → the [] fallback
    }

    func testCaseInsensitive() {
        let a = DisplayPresetEngine.match(current: ["dell u3223qe"], presets: presets)
        XCTAssertEqual(a, .applyLayout(name: "docked"))
    }

    func testNoMatchWhenNoFallback() {
        let only = [DisplayPreset(displays: ["Sidecar"], action: .autoTileScreen)]
        XCTAssertNil(DisplayPresetEngine.match(current: ["Built-in"], presets: only))
    }

    func testFirstMatchWins() {
        let ordered = [
            DisplayPreset(displays: ["A", "B"], action: .applyLayout(name: "dual")),
            DisplayPreset(displays: ["A"], action: .applyLayout(name: "single")),
        ]
        XCTAssertEqual(DisplayPresetEngine.match(current: ["A", "B"], presets: ordered), .applyLayout(name: "dual"))
        XCTAssertEqual(DisplayPresetEngine.match(current: ["A"], presets: ordered), .applyLayout(name: "single"))
    }
}
