// GridCells.swift — pure parse/format for the "a1" / "a1:b2" tile-span notation the visual
// layout editor manipulates. Columns are letters (a=0, b=1, …); rows are 1-based numbers,
// matching config.toml's [tiler.layouts.*] entries. Named tiles ("center", "right-half") are
// not cell spans and parse to nil — the editor keeps them as opaque chips.

public enum GridCells {

    /// A normalized inclusive cell span. c/r are 0-based column / 1-based row, lo <= hi.
    public struct Span: Equatable {
        public var c0: Int, r0: Int, c1: Int, r1: Int
        public init(c0: Int, r0: Int, c1: Int, r1: Int) {
            self.c0 = min(c0, c1); self.c1 = max(c0, c1)
            self.r0 = min(r0, r1); self.r1 = max(r0, r1)
        }
    }

    private static func columnIndex(_ s: Substring) -> Int? {
        guard s.count == 1, let ch = s.first, ch.isLetter, ch.isLowercase else { return nil }
        return Int(ch.asciiValue! - Character("a").asciiValue!)
    }

    private static func letter(_ i: Int) -> String {
        String(UnicodeScalar(UInt8(Character("a").asciiValue!) + UInt8(i)))
    }

    /// Parse "a1" or "a1:b2" into a Span. Returns nil for named/non-cell tiles.
    public static func parse(_ tile: String) -> Span? {
        let parts = tile.split(separator: ":", maxSplits: 1)
        func cell(_ s: Substring) -> (Int, Int)? {
            guard let letterEnd = s.firstIndex(where: { $0.isNumber }) else { return nil }
            guard let c = columnIndex(s[s.startIndex..<letterEnd]),
                  let r = Int(s[letterEnd...]), r >= 1 else { return nil }
            return (c, r)
        }
        guard let (c0, r0) = cell(parts[0]) else { return nil }
        if parts.count == 1 { return Span(c0: c0, r0: r0, c1: c0, r1: r0) }
        guard let (c1, r1) = cell(parts[1]) else { return nil }
        return Span(c0: c0, r0: r0, c1: c1, r1: r1)
    }

    /// Format a span back to "a1" (single cell) or "a1:b2" (range).
    public static func format(_ s: Span) -> String {
        let a = "\(letter(s.c0))\(s.r0)"
        if s.c0 == s.c1 && s.r0 == s.r1 { return a }
        return "\(a):\(letter(s.c1))\(s.r1)"
    }
}
