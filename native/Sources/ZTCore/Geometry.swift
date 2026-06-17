// Geometry.swift — framework-free value types consumed by the pure algorithms.
// Kept in top-left CG coordinates end-to-end (matching the Lua implementation and the
// macOS Accessibility / CGWindowList APIs). NSScreen's bottom-left frame is converted
// only at the system-adapter boundary, never here.

/// A rectangle in top-left-origin coordinates.
public struct ZTRect: Equatable, Codable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
}

/// Whether two rects overlap. Mirrors `check_overlap` in modules/layout_solver.lua:
/// edge-touching does NOT count as overlap.
@inlinable
public func rectsOverlap(_ a: ZTRect, _ b: ZTRect) -> Bool {
    return !(a.x >= b.x + b.w ||
             a.x + a.w <= b.x ||
             a.y >= b.y + b.h ||
             a.y + a.h <= b.y)
}
