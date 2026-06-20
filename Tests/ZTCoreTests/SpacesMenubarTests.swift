// SpacesMenubarTests — pure layout geometry for the menu-bar Spaces widget.

import XCTest
@testable import ZTCore

final class SpacesMenubarTests: XCTestCase {

    private func g(_ label: String, _ specs: [(String, Bool, Bool)]) -> SpacesMenubar.InputGroup {
        .init(monitorLabel: label, spaces: specs.map { .init(label: $0.0, isCurrent: $0.1, isFullscreen: $0.2) })
    }

    func testGroupsLaidLeftToRightWithFlatIndices() {
        let layout = SpacesMenubar.layout([
            g("DELL", [("1", true, false), ("2", false, false)]),
            g("Mon2", [("1", true, false)]),
        ])
        XCTAssertEqual(layout.groups.count, 2)
        XCTAssertEqual(layout.groups[0].cells.map { $0.index }, [0, 1])
        XCTAssertEqual(layout.groups[1].cells.map { $0.index }, [2])           // flat across groups
        XCTAssertEqual(layout.groups[0].monitorLabel, "DELL")
        // Second group starts to the right of the first group's bracket.
        XCTAssertGreaterThan(layout.groups[1].bracket.x, layout.groups[0].bracket.x + layout.groups[0].bracket.w - 0.01)
        XCTAssertEqual(layout.height, 22)
        XCTAssertGreaterThan(layout.width, 0)
    }

    func testCurrentAndFullscreenFlagsCarried() {
        let layout = SpacesMenubar.layout([g("D", [("1", true, false), ("F", false, true)])])
        XCTAssertTrue(layout.groups[0].cells[0].isCurrent)
        XCTAssertFalse(layout.groups[0].cells[1].isCurrent)
        XCTAssertTrue(layout.groups[0].cells[1].isFullscreen)
    }

    func testBracketEnclosesGlyphAndCells() {
        let layout = SpacesMenubar.layout([g("D", [("1", true, false), ("2", false, false)])])
        let grp = layout.groups[0]
        XCTAssertLessThanOrEqual(grp.bracket.x, grp.glyph.x)                              // glyph inside bracket
        let lastCell = grp.cells.last!
        XCTAssertGreaterThanOrEqual(grp.bracket.x + grp.bracket.w, lastCell.rect.x + lastCell.rect.w) // cells inside
    }

    func testHitTestReturnsFlatCellIndex() {
        let layout = SpacesMenubar.layout([
            g("D", [("1", true, false), ("2", false, false)]),
            g("M", [("1", true, false)]),
        ])
        let c2 = layout.groups[1].cells[0]   // flat index 2
        XCTAssertEqual(layout.cellIndex(at: c2.rect.x + 1, c2.rect.y + 1), 2)
        XCTAssertNil(layout.cellIndex(at: layout.width + 50, 10))   // outside
    }

    func testNearestCellSnapsAcrossGaps() {
        let layout = SpacesMenubar.layout([
            g("D", [("1", true, false), ("2", false, false)]),
            g("M", [("1", true, false)]),
        ], showGlyph: false)
        let c0 = layout.groups[0].cells[0], c1 = layout.groups[0].cells[1]
        // A point in the GAP between cell 0 and cell 1 snaps to whichever centre is closer.
        let gapX = (c0.rect.x + c0.rect.w + c1.rect.x) / 2
        XCTAssertNotNil(layout.nearestCellIndex(toX: gapX))
        // Far left maps to the first cell; far right (last group) to the last.
        XCTAssertEqual(layout.nearestCellIndex(toX: 0), 0)
        XCTAssertEqual(layout.nearestCellIndex(toX: layout.width), 2)
        XCTAssertNil(layout.nearestCellIndex(toX: layout.width + 100))   // well outside → nil
    }

    func testEmptyGroupsSkipped() {
        let layout = SpacesMenubar.layout([g("D", []), g("M", [("1", true, false)])])
        XCTAssertEqual(layout.groups.count, 1)
        XCTAssertEqual(layout.groups[0].monitorLabel, "M")
    }
}
