// MissionControl.swift — pure geometry + resolution for the Mission Control overlay: when Mission
// Control (Exposé) is active, draw a window-hints layer over the exposed window tiles so each window
// gets a typed hint label (jump to it) and a close (×) button. This file is the PURE half — assign
// labels, place each badge + close-button rect, and resolve typed input / a click to a target
// window. Detecting that Mission Control is active and reading the exposed tiles needs private
// CGS/SkyLight calls and lives in ZTSystem/the agent (see ARCHITECTURE.md, Spaces & Exposé); it feeds the
// tiles in here and draws what comes out. Value-in/value-out, fully unit-testable.

import Foundation

public enum MissionControl {

    /// An exposed window in the Mission Control layout (id + its on-screen rect, top-left CG).
    public struct Tile: Equatable {
        public let windowId: Int
        public let frame: ZTRect
        public init(windowId: Int, frame: ZTRect) { self.windowId = windowId; self.frame = frame }
    }

    /// Pack windows into a near-square grid of tiles within `screen` (inset by `margin`, `gap`
    /// between cells), row-major. This is the layout for the custom exposé *replacement* — we
    /// enumerate all standard windows (CGWindowList, 0 AX) and arrange our own grid, sidestepping
    /// the private-API problem of reading macOS's real Mission Control layout. Pure + testable.
    public static func gridTiles(windowIds: [Int], in screen: ZTRect,
                                 margin: Double = 48, gap: Double = 24) -> [Tile] {
        let n = windowIds.count
        guard n > 0 else { return [] }
        let cols = Int(ceil(Double(n).squareRoot()))
        let rows = Int(ceil(Double(n) / Double(cols)))
        let aw = screen.w - 2 * margin, ah = screen.h - 2 * margin
        let cw = (aw - Double(cols - 1) * gap) / Double(cols)
        let ch = (ah - Double(rows - 1) * gap) / Double(rows)
        return windowIds.enumerated().map { i, id in
            let c = i % cols, r = i / cols
            return Tile(windowId: id, frame: ZTRect(
                x: screen.x + margin + Double(c) * (cw + gap),
                y: screen.y + margin + Double(r) * (ch + gap), w: cw, h: ch))
        }
    }

    /// Pack windows into a grid using a spatial matching algorithm to place previews close to
    /// their actual screen positions/zones. Pushes overlaps/stacked windows to the nearest free cell.
    public static func spatialGridTiles(
        windows: [(windowId: Int, frame: ZTRect)],
        in screen: ZTRect,
        cols: Int,
        rows: Int,
        margin: Double = 48,
        gap: Double = 24
    ) -> [Tile] {
        let n = windows.count
        guard n > 0 else { return [] }

        var finalCols = cols
        var finalRows = rows
        if finalCols * finalRows < n {
            finalCols = Int(ceil(Double(n).squareRoot()))
            finalRows = Int(ceil(Double(n) / Double(finalCols)))
        }

        let aw = screen.w - 2 * margin, ah = screen.h - 2 * margin
        let cw = (aw - Double(finalCols - 1) * gap) / Double(finalCols)
        let ch = (ah - Double(finalRows - 1) * gap) / Double(finalRows)

        struct Cell {
            let col: Int
            let row: Int
            let center: (x: Double, y: Double)
            let frame: ZTRect
        }
        var cells: [Cell] = []
        for r in 0..<finalRows {
            for c in 0..<finalCols {
                let cellFrame = ZTRect(
                    x: screen.x + margin + Double(c) * (cw + gap),
                    y: screen.y + margin + Double(r) * (ch + gap),
                    w: cw,
                    h: ch
                )
                let cellCenter = (
                    x: cellFrame.x + cellFrame.w / 2.0,
                    y: cellFrame.y + cellFrame.h / 2.0
                )
                cells.append(Cell(col: c, row: r, center: cellCenter, frame: cellFrame))
            }
        }

        struct WindowTarget {
            let windowId: Int
            let center: (x: Double, y: Double)
        }
        let targets = windows.map { w in
            WindowTarget(
                windowId: w.windowId,
                center: (
                    x: w.frame.x + w.frame.w / 2.0,
                    y: w.frame.y + w.frame.h / 2.0
                )
            )
        }

        struct MatchCandidate {
            let winIndex: Int
            let cellIndex: Int
            let distance: Double
        }
        var candidates: [MatchCandidate] = []
        for (wIdx, target) in targets.enumerated() {
            for (cIdx, cell) in cells.enumerated() {
                let dx = target.center.x - cell.center.x
                let dy = target.center.y - cell.center.y
                let dist = dx * dx + dy * dy
                candidates.append(MatchCandidate(winIndex: wIdx, cellIndex: cIdx, distance: dist))
            }
        }

        candidates.sort { $0.distance < $1.distance }

        var assignedWindows = Set<Int>()
        var assignedCells = Set<Int>()
        var tiles: [Tile] = []

        for cand in candidates {
            if !assignedWindows.contains(cand.winIndex) && !assignedCells.contains(cand.cellIndex) {
                assignedWindows.insert(cand.winIndex)
                assignedCells.insert(cand.cellIndex)
                let winId = targets[cand.winIndex].windowId
                let cell = cells[cand.cellIndex]
                tiles.append(Tile(windowId: winId, frame: cell.frame))

                if tiles.count == n {
                    break
                }
            }
        }

        let winIdOrder = windows.map { $0.windowId }
        tiles.sort { a, b in
            let idxA = winIdOrder.firstIndex(of: a.windowId) ?? 0
            let idxB = winIdOrder.firstIndex(of: b.windowId) ?? 0
            return idxA < idxB
        }

        return tiles
    }

    /// What to draw + hit-test for one exposed window.
    public struct Hint: Equatable {
        public let windowId: Int
        public let label: String     // the key(s) to press to jump to this window
        public let frame: ZTRect     // the tile's full rect (click anywhere in it to jump)
        public let badge: ZTRect     // where the label chip is drawn (centred in the tile)
        public let close: ZTRect     // the (×) close-button hit rect (tile's top-left corner)
        public let appName: String   // the application name (to load icon / display text)
        public let zoneKey: String?  // the best-match zone key on screen for color coding

        public init(windowId: Int, label: String, frame: ZTRect, badge: ZTRect, close: ZTRect) {
            self.windowId = windowId; self.label = label; self.frame = frame; self.badge = badge; self.close = close
            self.appName = ""; self.zoneKey = nil
        }

        public init(windowId: Int, label: String, frame: ZTRect, badge: ZTRect, close: ZTRect, appName: String, zoneKey: String?) {
            self.windowId = windowId; self.label = label; self.frame = frame; self.badge = badge; self.close = close
            self.appName = appName; self.zoneKey = zoneKey
        }
    }

    /// Assign a hint label + badge + close-button rect to each tile. Labels come from
    /// `WindowHints.labels` (home-row first). Tiles keep the caller's order (sort by z/position
    /// before calling for stable labels). Badge + close are clamped inside small tiles.
    public static func hints(for tiles: [Tile],
                             badge: (w: Double, h: Double) = (34, 26),
                             close: Double = 26, inset: Double = 8) -> [Hint] {
        let labels = WindowHints.labels(count: tiles.count)
        return tiles.enumerated().map { i, t in
            let bw = min(badge.w, t.frame.w), bh = min(badge.h, t.frame.h)
            let badgeRect = ZTRect(x: t.frame.x + (t.frame.w - bw) / 2,
                                   y: t.frame.y + (t.frame.h - bh) / 2, w: bw, h: bh)
            let cs = min(close, t.frame.w, t.frame.h)
            let closeRect = ZTRect(x: t.frame.x + inset,
                                   y: t.frame.y + inset, w: cs, h: cs)
            return Hint(windowId: t.windowId, label: i < labels.count ? labels[i] : "",
                        frame: t.frame, badge: badgeRect, close: closeRect,
                        appName: "", zoneKey: nil)
        }
    }

    /// Assign a hint label + badge + close-button rect to each tile, resolving app names and zones.
    public static func hints(for tiles: [Tile],
                             appNames: [Int: String],
                             zoneKeys: [Int: String?],
                             badge: (w: Double, h: Double) = (34, 26),
                             close: Double = 26, inset: Double = 8) -> [Hint] {
        let labels = WindowHints.labels(count: tiles.count)
        return tiles.enumerated().map { i, t in
            let bw = min(badge.w, t.frame.w), bh = min(badge.h, t.frame.h)
            let badgeRect = ZTRect(x: t.frame.x + (t.frame.w - bw) / 2,
                                   y: t.frame.y + (t.frame.h - bh) / 2, w: bw, h: bh)
            let cs = min(close, t.frame.w, t.frame.h)
            let closeRect = ZTRect(x: t.frame.x + inset,
                                   y: t.frame.y + inset, w: cs, h: cs)
            return Hint(windowId: t.windowId, label: i < labels.count ? labels[i] : "",
                        frame: t.frame, badge: badgeRect, close: closeRect,
                        appName: appNames[t.windowId] ?? "", zoneKey: zoneKeys[t.windowId] ?? nil)
        }
    }

    /// The window whose hint label exactly equals `typed`, or nil. CASE-SENSITIVE: labels can now be
    /// uppercase (the overflow tier past 26 windows — see `WindowHints.labelPool`), so "A" and "a" are
    /// distinct windows and must not collide.
    public static func resolve(typed: String, in hints: [Hint]) -> Int? {
        return hints.first { $0.label == typed }?.windowId
    }

    /// Hints whose label starts with `prefix` (live filtering as you type). Case-sensitive, matching
    /// `resolve` — uppercase labels are distinct from lowercase.
    public static func matches(prefix: String, in hints: [Hint]) -> [Hint] {
        guard !prefix.isEmpty else { return hints }
        return hints.filter { $0.label.hasPrefix(prefix) }
    }

    /// The window whose close-button rect contains the point (top-left CG), or nil — for clicking ×.
    public static func closeHit(at x: Double, _ y: Double, in hints: [Hint]) -> Int? {
        hints.first {
            x >= $0.close.x && x <= $0.close.x + $0.close.w &&
            y >= $0.close.y && y <= $0.close.y + $0.close.h
        }?.windowId
    }

    /// The window whose tile frame contains the point (top-left CG), or nil — click-anywhere-to-jump.
    /// Check `closeHit` first so a click on the × closes rather than jumps.
    public static func tileHit(at x: Double, _ y: Double, in hints: [Hint]) -> Int? {
        hints.first {
            x >= $0.frame.x && x <= $0.frame.x + $0.frame.w &&
            y >= $0.frame.y && y <= $0.frame.y + $0.frame.h
        }?.windowId
    }

    /// Directional move for keyboard selection (arrow keys / vim hjkl) across the exposé grid.
    public enum NavMove { case left, right, up, down }

    /// Move the selection from `windowId` to the nearest tile in `move` direction (by tile centres),
    /// keeping the current selection when nothing lies that way. Pure geometry (top-left CG space).
    /// Picks the candidate that is predominantly in the requested direction, nearest by distance —
    /// so a grid steps cell-by-cell and a sparse layout still lands somewhere sensible.
    public static func navigate(from windowId: Int, _ move: NavMove, in hints: [Hint]) -> Int {
        guard let cur = hints.first(where: { $0.windowId == windowId }) else {
            return hints.first?.windowId ?? windowId
        }
        let cx = cur.frame.x + cur.frame.w / 2, cy = cur.frame.y + cur.frame.h / 2
        var best: (id: Int, score: Double)?
        for h in hints where h.windowId != windowId {
            let dx = (h.frame.x + h.frame.w / 2) - cx
            let dy = (h.frame.y + h.frame.h / 2) - cy
            let inDir: Bool
            switch move {
            case .left:  inDir = dx < 0 && abs(dx) >= abs(dy)
            case .right: inDir = dx > 0 && abs(dx) >= abs(dy)
            case .up:    inDir = dy < 0 && abs(dy) >= abs(dx)
            case .down:  inDir = dy > 0 && abs(dy) >= abs(dx)
            }
            guard inDir else { continue }
            // Bias toward the chosen axis so a near-diagonal in-row neighbour wins over a far one.
            let axis = (move == .left || move == .right) ? abs(dx) : abs(dy)
            let off  = (move == .left || move == .right) ? abs(dy) : abs(dx)
            let score = axis + off * 2
            if best == nil || score < best!.score { best = (h.windowId, score) }
        }
        return best?.id ?? windowId
    }
}
