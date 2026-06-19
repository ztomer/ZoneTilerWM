// MissionControl.swift — pure geometry + resolution for the Mission Control overlay: when Mission
// Control (Exposé) is active, draw a window-hints layer over the exposed window tiles so each window
// gets a typed hint label (jump to it) and a close (×) button. This file is the PURE half — assign
// labels, place each badge + close-button rect, and resolve typed input / a click to a target
// window. Detecting that Mission Control is active and reading the exposed tiles needs private
// CGS/SkyLight calls and lives in ZTSystem/the agent (see docs/V6_FEATURE_PLAN.md); it feeds the
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

    /// What to draw + hit-test for one exposed window.
    public struct Hint: Equatable {
        public let windowId: Int
        public let label: String     // the key(s) to press to jump to this window
        public let frame: ZTRect     // the tile's full rect (click anywhere in it to jump)
        public let badge: ZTRect     // where the label chip is drawn (centred in the tile)
        public let close: ZTRect     // the (×) close-button hit rect (tile's top-right corner)
        public init(windowId: Int, label: String, frame: ZTRect, badge: ZTRect, close: ZTRect) {
            self.windowId = windowId; self.label = label; self.frame = frame; self.badge = badge; self.close = close
        }
    }

    /// Assign a hint label + badge + close-button rect to each tile. Labels come from
    /// `WindowHints.labels` (home-row first). Tiles keep the caller's order (sort by z/position
    /// before calling for stable labels). Badge + close are clamped inside small tiles.
    public static func hints(for tiles: [Tile],
                             badge: (w: Double, h: Double) = (34, 26),
                             close: Double = 22, inset: Double = 8) -> [Hint] {
        let labels = WindowHints.labels(count: tiles.count)
        return tiles.enumerated().map { i, t in
            let bw = min(badge.w, t.frame.w), bh = min(badge.h, t.frame.h)
            let badgeRect = ZTRect(x: t.frame.x + (t.frame.w - bw) / 2,
                                   y: t.frame.y + (t.frame.h - bh) / 2, w: bw, h: bh)
            let cs = min(close, t.frame.w, t.frame.h)
            let closeRect = ZTRect(x: t.frame.x + t.frame.w - cs - inset,
                                   y: t.frame.y + inset, w: cs, h: cs)
            return Hint(windowId: t.windowId, label: i < labels.count ? labels[i] : "",
                        frame: t.frame, badge: badgeRect, close: closeRect)
        }
    }

    /// The window whose hint label exactly equals `typed` (case-insensitive), or nil.
    public static func resolve(typed: String, in hints: [Hint]) -> Int? {
        let t = typed.lowercased()
        return hints.first { $0.label == t }?.windowId
    }

    /// Hints whose label starts with `prefix` (for two-key labels / live filtering as you type).
    public static func matches(prefix: String, in hints: [Hint]) -> [Hint] {
        guard !prefix.isEmpty else { return hints }
        let p = prefix.lowercased()
        return hints.filter { $0.label.hasPrefix(p) }
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
}
