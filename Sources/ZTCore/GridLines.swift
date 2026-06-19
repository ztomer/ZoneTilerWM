// GridLines.swift — pure geometry for the resize-mode grid overlay and for choosing which
// interior grid line a resize nudge targets. Mirrors grid_overlay.lua's get_line_pos: an
// interior line i (1..count-1) sits at (i/count)*total plus the ResizeManager offset for that
// axis/index (a fraction of total). Top-left CG coords; the overlay flips for NSWindow.

public enum GridLines {

    /// Absolute positions (frame-relative → screen-absolute) of the interior grid lines.
    /// `offset(axis, index)` is the ResizeManager fraction for that line. Returns vertical line
    /// x's (axis "x", from cols) and horizontal line y's (axis "y", from rows).
    public static func positions(frame: ZTRect, cols: Int, rows: Int,
                                 offset: (_ axis: String, _ index: Int) -> Double)
        -> (vertical: [Double], horizontal: [Double]) {
        var vertical: [Double] = []
        if cols > 1 {
            for i in 1..<cols {
                let base = (Double(i) / Double(cols)) * frame.w
                vertical.append(frame.x + base + offset("x", i) * frame.w)
            }
        }
        var horizontal: [Double] = []
        if rows > 1 {
            for i in 1..<rows {
                let base = (Double(i) / Double(rows)) * frame.h
                horizontal.append(frame.y + base + offset("y", i) * frame.h)
            }
        }
        return (vertical, horizontal)
    }

    /// The interior line index (1..count-1) nearest a point, for picking which line a nudge
    /// adjusts. Uses default (offset-free) positions so the choice is stable during a session.
    /// Returns nil when there is no interior line (count <= 1).
    public static func nearestInteriorIndex(to point: Double, start: Double, total: Double, count: Int) -> Int? {
        guard count > 1, total > 0 else { return nil }
        let cell = total / Double(count)
        // Round the point to the closest interior boundary, then clamp to [1, count-1].
        let raw = Int((point - start) / cell + 0.5)
        return min(count - 1, max(1, raw))
    }
}
