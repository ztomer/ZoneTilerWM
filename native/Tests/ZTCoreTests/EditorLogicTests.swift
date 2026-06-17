// EditorLogicTests — pure logic behind the ZTUI v2 editors (grid-cell notation + keybind
// alias matching). The SwiftUI views are validated by screenshots; this locks the data rules.

import XCTest
@testable import ZTCore

final class EditorLogicTests: XCTestCase {

    // MARK: GridCells

    func testParseSingleCell() {
        XCTAssertEqual(GridCells.parse("a1"), GridCells.Span(c0: 0, r0: 1, c1: 0, r1: 1))
        XCTAssertEqual(GridCells.parse("d3"), GridCells.Span(c0: 3, r0: 3, c1: 3, r1: 3))
    }

    func testParseRange() {
        XCTAssertEqual(GridCells.parse("a1:b2"), GridCells.Span(c0: 0, r0: 1, c1: 1, r1: 2))
        XCTAssertEqual(GridCells.parse("b1:c3"), GridCells.Span(c0: 1, r0: 1, c1: 2, r1: 3))
    }

    func testNamedTileIsNotASpan() {
        XCTAssertNil(GridCells.parse("center"))
        XCTAssertNil(GridCells.parse("right-half"))
    }

    func testFormatCollapsesSingleCellAndRoundTrips() {
        XCTAssertEqual(GridCells.format(GridCells.Span(c0: 0, r0: 1, c1: 0, r1: 1)), "a1")
        XCTAssertEqual(GridCells.format(GridCells.Span(c0: 0, r0: 1, c1: 1, r1: 2)), "a1:b2")
        for t in ["a1", "a1:b2", "b1:c3", "d2:d3"] {
            XCTAssertEqual(GridCells.format(GridCells.parse(t)!), t, "round-trip \(t)")
        }
    }

    func testSpanNormalizesCornerOrder() {
        // Selecting bottom-right then top-left still yields a normalized span.
        let s = GridCells.Span(c0: 1, r0: 2, c1: 0, r1: 1)
        XCTAssertEqual(GridCells.format(s), "a1:b2")
    }

    // MARK: Keybinding alias matching

    func testAliasExactMatch() {
        let aliases = ["mash": ["ctrl", "cmd"], "HYPER": ["shift", "ctrl", "alt", "cmd"],
                       "mash_shift": ["shift", "ctrl", "cmd"]]
        XCTAssertEqual(Keybinding.alias(forModifiers: ["cmd", "ctrl"], aliases: aliases), "mash") // order-independent
        XCTAssertEqual(Keybinding.alias(forModifiers: ["shift", "ctrl", "alt", "cmd"], aliases: aliases), "HYPER")
        XCTAssertNil(Keybinding.alias(forModifiers: ["cmd"], aliases: aliases))   // no alias is just cmd
    }
}
