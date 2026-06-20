// SpacesMenubar.swift — PURE layout geometry for the menu-bar Spaces widget (the Rams/Kare subset:
// all spaces, absolute, grouped per monitor inside a clear bracket with a leading monitor glyph;
// current space filled, others hollow; fullscreen a distinct shape). No AppKit — emits ZTRect
// geometry only; the NSStatusItem renderer (ZTSystem/agent) draws it. Mirrors how `MissionControl`
// is the pure layer under the Exposé overlay.
//
// Design rationale (see docs/ROADMAP.md §4 — Rams + Kare consult):
//   • Rams "less but better": ONE honest representation — every space, absolute, no relative view.
//   • Kare "legible at 22px": per-monitor bracket + monitor glyph so groups parse at a glance;
//     filled = current vs hollow = others is the one high-contrast state language.

public enum SpacesMenubar {

    public struct InputSpace: Equatable {
        public let label: String        // short name or number drawn in the cell
        public let isCurrent: Bool
        public let isFullscreen: Bool
        public init(label: String, isCurrent: Bool, isFullscreen: Bool = false) {
            self.label = label; self.isCurrent = isCurrent; self.isFullscreen = isFullscreen
        }
    }
    public struct InputGroup: Equatable {
        public let monitorLabel: String
        public let spaces: [InputSpace]
        public init(monitorLabel: String, spaces: [InputSpace]) {
            self.monitorLabel = monitorLabel; self.spaces = spaces
        }
    }

    public struct Cell: Equatable {
        public let index: Int            // flat index across all groups (for hit-testing → switch)
        public let label: String
        public let isCurrent: Bool
        public let isFullscreen: Bool
        public let rect: ZTRect
    }
    public struct Group: Equatable {
        public let monitorLabel: String
        public let bracket: ZTRect       // rounded enclosure drawn around the group
        public let glyph: ZTRect         // the small monitor glyph at the group's leading edge
        public let cells: [Cell]
    }
    public struct Layout: Equatable {
        public let groups: [Group]
        public let width: Double
        public let height: Double
        /// Flat cell at a point (menu-bar local coords), for click-to-switch hit-testing.
        public func cellIndex(at x: Double, _ y: Double) -> Int? {
            for g in groups { for c in g.cells {
                if x >= c.rect.x && x <= c.rect.x + c.rect.w && y >= c.rect.y && y <= c.rect.y + c.rect.h {
                    return c.index
                }
            } }
            return nil
        }

        /// Forgiving hit-test for a single-row menu-bar widget: the cell whose centre is nearest `x`
        /// (so the small gaps between cells / inside brackets aren't dead zones). Returns nil only when
        /// there are no cells or `x` is well outside the widget.
        public func nearestCellIndex(toX x: Double, slack: Double = 6) -> Int? {
            guard x >= -slack, x <= width + slack else { return nil }
            var best: (idx: Int, dist: Double)?
            for g in groups { for c in g.cells {
                let d = abs((c.rect.x + c.rect.w / 2) - x)
                if best == nil || d < best!.dist { best = (c.index, d) }
            } }
            return best?.idx
        }
    }

    /// Lay the groups out left→right. `charWidth`/`cellHPad` let the renderer match text metrics.
    /// `showGlyph` must match the renderer — when false, no leading monitor-glyph slot is reserved
    /// (otherwise there's dead space to the left of the first cell in each bracket).
    public static func layout(_ groups: [InputGroup], height: Double = 22,
                              vPad: Double = 3, charWidth: Double = 7, cellHPad: Double = 5,
                              cellGap: Double = 3, groupInnerPad: Double = 4, groupGap: Double = 9,
                              showGlyph: Bool = true) -> Layout {
        let cellH = height - 2 * vPad
        let glyphW = showGlyph ? cellH * 1.15 : 0
        func cellWidth(_ label: String) -> Double { max(cellH, 2 * cellHPad + Double(label.count) * charWidth) }

        var outGroups: [Group] = []
        var cursor = 0.0
        var flat = 0
        for g in groups where !g.spaces.isEmpty {
            let bracketX = cursor
            var x = bracketX + groupInnerPad
            let glyph = showGlyph ? ZTRect(x: x, y: vPad, w: glyphW, h: cellH) : ZTRect(x: x, y: vPad, w: 0, h: 0)
            if showGlyph { x += glyphW + cellGap }
            var cells: [Cell] = []
            for sp in g.spaces {
                let w = cellWidth(sp.label)
                cells.append(Cell(index: flat, label: sp.label, isCurrent: sp.isCurrent,
                                  isFullscreen: sp.isFullscreen, rect: ZTRect(x: x, y: vPad, w: w, h: cellH)))
                x += w + cellGap
                flat += 1
            }
            let innerRight = x - cellGap                       // drop trailing gap
            let bracketW = (innerRight + groupInnerPad) - bracketX
            let bracket = ZTRect(x: bracketX, y: vPad - 2, w: bracketW, h: cellH + 4)
            outGroups.append(Group(monitorLabel: g.monitorLabel, bracket: bracket, glyph: glyph, cells: cells))
            cursor = bracketX + bracketW + groupGap
        }
        let width = max(0, cursor - (outGroups.isEmpty ? 0 : groupGap))
        return Layout(groups: outGroups, width: width, height: height)
    }
}
