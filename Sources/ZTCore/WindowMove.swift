// WindowMove.swift — pure geometry for directional window ops (nudge / throw / swap). The
// coordinator applies the computed frames via the WindowSystem; this is the testable math.
// Top-left CG coords throughout (y increases downward).

public enum MoveDirection: String, Codable, Equatable, CaseIterable {
    case up, down, left, right
}

public enum WindowMove {

    /// Shift `frame` by `fraction` of the screen dimension in `dir`, clamped to the screen.
    public static func nudge(_ frame: ZTRect, screen: ZTRect, _ dir: MoveDirection, fraction: Double = 0.05) -> ZTRect {
        var f = frame
        switch dir {
        case .left:  f.x -= screen.w * fraction
        case .right: f.x += screen.w * fraction
        case .up:    f.y -= screen.h * fraction
        case .down:  f.y += screen.h * fraction
        }
        return clamp(f, to: screen)
    }

    /// Snap the window's edge to the screen edge in `dir`, keeping its size.
    public static func throwTo(_ frame: ZTRect, screen: ZTRect, _ dir: MoveDirection) -> ZTRect {
        var f = frame
        switch dir {
        case .left:  f.x = screen.x
        case .right: f.x = screen.x + screen.w - f.w
        case .up:    f.y = screen.y
        case .down:  f.y = screen.y + screen.h - f.h
        }
        return clamp(f, to: screen)
    }

    /// The id of the nearest other window whose center lies in `dir` of the focused window's
    /// center (Euclidean nearest among those in that half-plane). nil if none.
    public static func swapTarget(focused: ZTRect, others: [(id: Int, frame: ZTRect)], _ dir: MoveDirection) -> Int? {
        let fx = focused.x + focused.w / 2, fy = focused.y + focused.h / 2
        var best: (id: Int, dist: Double)?
        for o in others {
            let cx = o.frame.x + o.frame.w / 2, cy = o.frame.y + o.frame.h / 2
            let inDir: Bool
            switch dir {
            case .left:  inDir = cx < fx
            case .right: inDir = cx > fx
            case .up:    inDir = cy < fy
            case .down:  inDir = cy > fy
            }
            guard inDir else { continue }
            let dx = cx - fx, dy = cy - fy
            let d = dx * dx + dy * dy
            if d < (best?.dist ?? .infinity) { best = (o.id, d) }
        }
        return best?.id
    }

    private static func clamp(_ frame: ZTRect, to s: ZTRect) -> ZTRect {
        var r = frame
        r.w = min(r.w, s.w); r.h = min(r.h, s.h)
        r.x = max(s.x, min(r.x, s.x + s.w - r.w))
        r.y = max(s.y, min(r.y, s.y + s.h - r.h))
        return r
    }
}
