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

// MARK: - Motion predictor (One Euro Filter)

/// One Euro Filter on a scalar signal: an adaptive low-pass that smooths heavily when the value
/// is changing slowly (kills the per-pixel jitter of a polled, integer-quantized window frame)
/// and lightly when it's moving fast (keeps lag low during a drag). It also exposes the smoothed
/// derivative, used for a small velocity lead. See Casiez et al., "1€ Filter" (CHI 2012).
struct OneEuroFilter {
    var minCutoff: Double
    var beta: Double
    var dCutoff: Double
    private var xPrev: Double?
    private var dxPrev: Double = 0

    init(minCutoff: Double, beta: Double, dCutoff: Double) {
        self.minCutoff = minCutoff; self.beta = beta; self.dCutoff = dCutoff
    }
    mutating func reset() { xPrev = nil; dxPrev = 0 }

    private func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    /// Filter one sample taken `dt` seconds after the previous; returns the smoothed value and
    /// the smoothed velocity (units/second).
    mutating func filter(_ x: Double, dt: Double) -> (value: Double, velocity: Double) {
        guard let xp = xPrev else { xPrev = x; return (x, 0) }
        let dt = max(dt, 1e-4)
        let dx = (x - xp) / dt
        let aD = alpha(cutoff: dCutoff, dt: dt)
        dxPrev = aD * dx + (1 - aD) * dxPrev
        let cutoff = minCutoff + beta * abs(dxPrev)
        let a = alpha(cutoff: cutoff, dt: dt)
        let xhat = a * x + (1 - a) * xp
        xPrev = xhat
        return (xhat, dxPrev)
    }
}

/// Smooths a polled window frame into a jitter-free border frame, with an optional small velocity
/// lead to compensate the sampling+render lag (the "motion prediction" toggle). One Euro filter
/// per component (x/y/w/h). Pure value type, deterministic in `(samples, dt)` — the caller passes
/// the inter-sample interval, keeping ZTCore framework-free and fully unit-testable.
///
/// Replaces the earlier raw velocity-extrapolation predictor, which amplified the quantized
/// polling noise into visible jumps (validated offscreen: ~20px frame-to-frame jitter + large
/// overshoot vs. ~4px and minimal overshoot for this filter).
public struct FrameMotionPredictor {
    /// Seconds of velocity lead applied to the smoothed frame (0 = pure smoothing, no lead).
    public var lead: Double
    private var fx, fy, fw, fh: OneEuroFilter
    private var lastOut: ZTRect?
    private var hasSample = false

    /// Defaults tuned offscreen against realistic polled drag trajectories. `lead` ~ one frame.
    public init(lead: Double = 0.012, minCutoff: Double = 1.2, beta: Double = 0.06, dCutoff: Double = 1.0) {
        self.lead = lead
        fx = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
        fy = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
        fw = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
        fh = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
    }

    /// Clear all state (call on focus change so a new window doesn't inherit old motion).
    public mutating func reset() {
        fx.reset(); fy.reset(); fw.reset(); fh.reset(); lastOut = nil; hasSample = false
    }

    public var lastFrame: ZTRect? { lastOut }

    /// Feed an observed frame sampled `dt` seconds after the previous; returns the smoothed,
    /// lead-compensated frame to draw.
    public mutating func process(_ frame: ZTRect, dt: Double) -> ZTRect {
        hasSample = true
        let (x, vx) = fx.filter(frame.x, dt: dt)
        let (y, vy) = fy.filter(frame.y, dt: dt)
        let (w, vw) = fw.filter(frame.w, dt: dt)
        let (h, vh) = fh.filter(frame.h, dt: dt)
        let out = ZTRect(x: x + vx * lead, y: y + vy * lead, w: w + vw * lead, h: h + vh * lead)
        lastOut = out
        return out
    }
}
