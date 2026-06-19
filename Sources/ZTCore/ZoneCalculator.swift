// ZoneCalculator.swift — faithful port of modules/zone_calculator.lua.
// Layout detection (custom screens, name patterns, resolution/orientation defaults),
// grid-coordinate ("a1:b2") parsing, tile geometry with resize offsets, and margins.
// Determinism note: matches the Lua determinism fix — custom-screen and pattern matching
// iterate keys in sorted order, first match wins.
//
// Foundation is used only for NSRegularExpression (Lua-pattern emulation) — NOT AppKit.

import Foundation

public enum ZoneCalculator {

    /// A screen as the calculator sees it (top-left CG coords).
    public struct ScreenInfo {
        public var name: String
        public var frame: ZTRect
        public init(name: String, frame: ZTRect) { self.name = name; self.frame = frame }
    }

    /// Per-grid-line offset percentage, keyed by axis ("x"/"y") and 1-based line index.
    /// Mirrors resize_manager.get_offset; defaults to 0 (no adjustment).
    public typealias OffsetProvider = (_ axis: String, _ index: Int) -> Double
    public static let zeroOffsets: OffsetProvider = { _, _ in 0 }

    // MARK: - Layout detection

    /// The layout key for a screen, or nil if none resolves. Port of the detection half of
    /// `get_layout_config`.
    public static func layoutKey(for screen: ScreenInfo, config: ZoneConfig) -> String? {
        let frame = screen.frame
        let name = screen.name
        let isPortrait = frame.h > frame.w

        // 1. Custom screens (sorted keys, first match wins).
        if let custom = config.custom_screens {
            for key in custom.keys.sorted() where name == key || LuaPattern.find(name, key) {
                return custom[key]?.layout
            }
        }

        // 2. Name patterns (sorted keys, first match wins).
        if let patterns = config.screen_detection?.patterns {
            for key in patterns.keys.sorted() where LuaPattern.find(name, key) {
                return patterns[key]
            }
        }

        // 3. Resolution / orientation defaults.
        if isPortrait {
            if let portrait = config.screen_detection?.portrait {
                let largeMin = portrait.large?.min_height_for_layout_check ?? 2000
                if frame.h >= largeMin {
                    return portrait.large?.layout ?? portrait.small?.layout
                }
                return portrait.small?.layout
            }
            return frame.w >= 1440 ? "1x3" : "1x2"
        } else {
            let aspect = frame.w / frame.h
            if frame.w >= 3840 { return "4x3" }
            if frame.w >= 3440 || aspect > 2.0 { return "4x3" }
            if frame.w >= 2560 { return "3x3" }
            if frame.w >= 1920 { return "3x2" }
            return "2x2"
        }
    }

    // MARK: - Zone computation

    /// All zones for a monitor: the resolved layout key and zone-key -> tile rects.
    /// Port of `create_for_monitor` (+ get_layout_config), with the 2x2 fallback.
    public static func computeZones(screen: ScreenInfo,
                                    config: ZoneConfig,
                                    offsets: OffsetProvider = zeroOffsets)
        -> (layoutKey: String, zones: [String: [ZTRect]]) {

        var key = layoutKey(for: screen, config: config)
        var grid = key.flatMap { config.grids[$0] }
        if grid == nil || key == nil {
            grid = config.grids["2x2"]
            key = "2x2"
        }
        guard let g = grid, let layoutKey = key else { return ("", [:]) }

        let rows = g.rows, cols = g.cols
        let zoneDefs = config.layouts[layoutKey] ?? config.layouts["default"]
        guard let defs = zoneDefs else { return (layoutKey, [:]) }

        var zones: [String: [ZTRect]] = [:]
        for (zoneKey, coordsArray) in defs where zoneKey != "default" {
            var tiles: [ZTRect] = []
            for coords in coordsArray {
                if let tile = createTile(coords: coords, screen: screen.frame,
                                         rows: rows, cols: cols,
                                         margins: config.margins, offsets: offsets) {
                    tiles.append(tile)
                }
            }
            if !tiles.isEmpty { zones[zoneKey] = tiles }
        }
        return (layoutKey, zones)
    }

    // MARK: - Tile geometry

    /// Port of `create_tile`. Named positions return raw rects (no margins, matching Lua);
    /// grid coordinates go through `tileFromGrid` (which applies margins).
    static func createTile(coords: String, screen f: ZTRect, rows: Int, cols: Int,
                           margins: Margins?, offsets: OffsetProvider) -> ZTRect? {
        switch coords {
        case "full":        return f
        case "center":      return ZTRect(x: f.x + f.w / 4, y: f.y + f.h / 4, w: f.w / 2, h: f.h / 2)
        case "left-half":   return ZTRect(x: f.x, y: f.y, w: f.w / 2, h: f.h)
        case "right-half":  return ZTRect(x: f.x + f.w / 2, y: f.y, w: f.w / 2, h: f.h)
        case "top-half":    return ZTRect(x: f.x, y: f.y, w: f.w, h: f.h / 2)
        case "bottom-half": return ZTRect(x: f.x, y: f.y + f.h / 2, w: f.w, h: f.h / 2)
        default:
            guard let gc = parseGridCoords(coords) else { return nil }
            return tileFromGrid(colStart: gc.colStart, rowStart: gc.rowStart,
                                colEnd: gc.colEnd, rowEnd: gc.rowEnd,
                                screen: f, rows: rows, cols: cols,
                                margins: margins, offsets: offsets)
        }
    }

    /// Port of `create_tile_from_grid_coords`.
    static func tileFromGrid(colStart: Int, rowStart: Int, colEnd: Int, rowEnd: Int,
                             screen f: ZTRect, rows: Int, cols: Int,
                             margins: Margins?, offsets: OffsetProvider) -> ZTRect {

        func linePos(_ axis: String, _ index: Int, _ totalSize: Double, _ count: Int) -> Double {
            if index <= 0 { return 0 }
            if index >= count { return totalSize }
            let defaultPos = (Double(index) / Double(count)) * totalSize
            let offsetPct = offsets(axis, index)
            return defaultPos + offsetPct * totalSize
        }

        let xStart = linePos("x", colStart - 1, f.w, cols)
        let xEnd   = linePos("x", colEnd, f.w, cols)
        let yStart = linePos("y", rowStart - 1, f.h, rows)
        let yEnd   = linePos("y", rowEnd, f.h, rows)

        var tx = f.x + xStart
        var ty = f.y + yStart
        var tw = xEnd - xStart
        var th = yEnd - yStart

        if let m = margins, m.enabled {
            let margin = m.size
            let left   = (colStart == 1 && m.screen_edge) || colStart > 1
            let top    = (rowStart == 1 && m.screen_edge) || rowStart > 1
            let right  = (colEnd == cols && m.screen_edge) || colEnd < cols
            let bottom = (rowEnd == rows && m.screen_edge) || rowEnd < rows
            if left { tx += margin; tw -= margin }
            if top { ty += margin; th -= margin }
            if right { tw -= margin }
            if bottom { th -= margin }
        }
        return ZTRect(x: tx, y: ty, w: tw, h: th)
    }

    // MARK: - Grid coordinate parsing

    struct GridCoords { let colStart: Int; let rowStart: Int; let colEnd: Int; let rowEnd: Int }

    // Anchored: the WHOLE string must be a single "x#" cell or an "x#:y#" range — so a
    // malformed coord (e.g. "abc1", "a1:2") is rejected (nil) instead of silently parsing to a
    // plausible-but-wrong tile. Well-formed coords parse identically to before.
    private static let gridRegex = try! NSRegularExpression(
        pattern: "^([a-z])([0-9]+)(?::([a-z])([0-9]+))?$")

    /// Parses "a1", "a1:b2" → numeric grid coords; nil for anything malformed.
    static func parseGridCoords(_ s: String) -> GridCoords? {
        let ns = s as NSString
        guard let m = gridRegex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        func group(_ i: Int) -> String {
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
        let csChar = group(1), rsStr = group(2), ceChar = group(3), reStr = group(4)
        let a = Int(UnicodeScalar("a").value)
        guard let csScalar = csChar.unicodeScalars.first, let rs = Int(rsStr) else { return nil }
        let cs = Int(csScalar.value) - a + 1
        let ce: Int
        if let ceScalar = ceChar.unicodeScalars.first { ce = Int(ceScalar.value) - a + 1 } else { ce = cs }
        let re = reStr.isEmpty ? rs : (Int(reStr) ?? rs)
        return GridCoords(colStart: cs, rowStart: rs, colEnd: ce, rowEnd: re)
    }
}

/// Minimal Lua-pattern → ICU-regex translation for screen-name matching. Covers the
/// operators used by config.toml's patterns (`.`, `*`, `+`, `?`, `^`, `$`, char classes,
/// `%`-escapes, literal punctuation). `find` is unanchored, matching Lua's string.match.
enum LuaPattern {
    static func find(_ s: String, _ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: toICU(pattern)) else { return false }
        let range = NSRange(s.startIndex..., in: s)
        return regex.firstMatch(in: s, options: [], range: range) != nil
    }

    /// Regex metacharacters that are literal in Lua patterns and must be escaped for ICU.
    private static let icuSpecial: Set<Character> = ["(", ")", "{", "}", "|", "\\"]

    static func toICU(_ pattern: String) -> String {
        var out = ""
        var inClass = false
        var i = pattern.startIndex
        while i < pattern.endIndex {
            let c = pattern[i]
            switch c {
            case "%":
                // Lua escape: next char is literal.
                let next = pattern.index(after: i)
                if next < pattern.endIndex {
                    out += "\\" + String(pattern[next])
                    i = pattern.index(after: next)
                    continue
                } else {
                    out += "\\%"
                }
            case "[":
                inClass = true; out += "["
            case "]":
                inClass = false; out += "]"
            case "-":
                out += inClass ? "-" : "*?"   // Lua '-' is a lazy 0+ quantifier outside classes
            case ".", "*", "+", "?", "^", "$":
                out += String(c)
            default:
                out += icuSpecial.contains(c) ? "\\" + String(c) : String(c)
            }
            i = pattern.index(after: i)
        }
        return out
    }
}
