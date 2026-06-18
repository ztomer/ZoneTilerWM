// FocusBorder.swift — pure model for the focus-follow window border (a colored outline drawn
// around the focused window). Framework-free: the visual style, the OS rendering boundary
// (a protocol conformed in ZTSystem), the backend choice, and the motion predictor that
// compensates for the lag inherent in observing a window's frame *after* it has moved.
//
// Why a predictor: we learn a window's new frame by sampling it (CGWindowList, zero AX), which
// always trails the live window by a frame or two during a drag / tile animation. Extrapolating
// the frame forward by a short, clamped horizon lets the border keep pace instead of rubber-
// banding behind. At rest the prediction collapses to the exact observed frame (no jitter).

// MARK: - Style + backend

/// Visual style of the border. `color` is a config color *name* (resolved to a concrete color
/// at the system boundary), matching the Pomodoro color set.
public struct BorderStyle: Equatable {
    public var color: String          // config color name (e.g. "blue")
    public var width: Double          // stroke width, points
    public var cornerRadius: Double   // corner radius, points
    public var inset: Double          // how far inside the window frame to draw (points)

    public init(color: String = "blue", width: Double = 4, cornerRadius: Double = 9, inset: Double = 0) {
        self.color = color; self.width = width; self.cornerRadius = cornerRadius; self.inset = inset
    }
}

/// The two rendering backends.
/// - `overlay`: a public-API borderless `NSWindow` that tracks the focused window. Robust and
///   App-Store-safe, but a hair slower and can't draw above every system layer.
/// - `skylight`: a window created directly on the window server via private SkyLight APIs —
///   lower latency, draws across spaces and above everything (the technique JankyBorders uses,
///   reimplemented from scratch here so no GPL code is involved).
public enum BorderBackend: String, Equatable, CaseIterable {
    case overlay
    case skylight
}

/// OS rendering boundary. Conformed in ZTSystem; ZTCore coordination drives it with value
/// frames so no AppKit leaks into the pure layer.
public protocol BorderRenderer: AnyObject {
    /// Show/move the focused-window border to `frame` (top-left CG coords). `nil` hides it.
    func render(frame: ZTRect?, style: BorderStyle)
}

// MARK: - Motion predictor

/// Linear, clamped motion predictor. Feed it timestamped observed frames; ask for the predicted
/// frame at a target time. Velocity is a smoothed finite difference of consecutive samples;
/// extrapolation is clamped to `maxLead` (so a fast fling can't overshoot) and collapses to the
/// exact last frame once motion drops below `restEpsilon` (so a still window doesn't shimmer).
///
/// Pure value type, deterministic in `(samples, query time)` — the caller supplies a monotonic
/// clock, keeping ZTCore framework-free and the behavior fully unit-testable.
public struct FrameMotionPredictor {
    /// Max seconds to extrapolate beyond the last sample (the lag we're compensating for).
    public var maxLead: Double
    /// Velocity smoothing in [0, 1): weight kept on the previous velocity estimate each sample.
    /// 0 = react instantly (use the raw last-diff); higher = steadier but laggier.
    public var smoothing: Double
    /// Speed (points/second, max component) below which the window is treated as at rest.
    public var restEpsilon: Double

    private struct Vel { var x, y, w, h: Double }
    private var last: (frame: ZTRect, t: Double)?
    private var vel = Vel(x: 0, y: 0, w: 0, h: 0)

    public init(maxLead: Double = 0.05, smoothing: Double = 0.3, restEpsilon: Double = 2) {
        self.maxLead = maxLead
        self.smoothing = smoothing
        self.restEpsilon = restEpsilon
    }

    /// Clear all history (call on focus change so the new window doesn't inherit old velocity).
    public mutating func reset() {
        last = nil
        vel = Vel(x: 0, y: 0, w: 0, h: 0)
    }

    public var lastFrame: ZTRect? { last?.frame }

    /// Record an observed frame at monotonic time `t` (seconds).
    public mutating func record(_ frame: ZTRect, at t: Double) {
        defer { last = (frame, t) }
        guard let prev = last else { return }
        let dt = t - prev.t
        guard dt > 1e-4 else { return }   // drop duplicate / zero-dt samples
        let inst = Vel(x: (frame.x - prev.frame.x) / dt,
                       y: (frame.y - prev.frame.y) / dt,
                       w: (frame.w - prev.frame.w) / dt,
                       h: (frame.h - prev.frame.h) / dt)
        let s = min(max(smoothing, 0), 0.99)
        vel = Vel(x: s * vel.x + (1 - s) * inst.x,
                  y: s * vel.y + (1 - s) * inst.y,
                  w: s * vel.w + (1 - s) * inst.w,
                  h: s * vel.h + (1 - s) * inst.h)
    }

    /// Predicted frame at time `t`. Returns the last observed frame when at rest (or with a
    /// single sample), and `nil` when there's no history at all.
    public func predicted(at t: Double) -> ZTRect? {
        guard let last else { return nil }
        let speed = max(abs(vel.x), abs(vel.y), abs(vel.w), abs(vel.h))
        guard speed > restEpsilon else { return last.frame }
        let lead = min(max(t - last.t, 0), maxLead)
        return ZTRect(x: last.frame.x + vel.x * lead,
                      y: last.frame.y + vel.y * lead,
                      w: last.frame.w + vel.w * lead,
                      h: last.frame.h + vel.h * lead)
    }
}
