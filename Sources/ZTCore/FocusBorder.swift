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
/// The stroke pattern for the focus border. Drawn by the overlay renderer (the controller routes a
/// non-solid style to the overlay backend, which has full custom-draw control).
public enum BorderLineStyle: String, Equatable, CaseIterable {
    case solid, dashed, dotted, wavy, hazard
}

public struct BorderStyle: Equatable {
    public var color: String          // config color name (e.g. "blue")
    public var width: Double          // stroke width, points
    public var cornerRadius: Double   // corner radius, points
    public var inset: Double          // how far inside the window frame to draw (points)
    public var lineStyle: BorderLineStyle   // solid / dashed / dotted / wavy / hazard

    public init(color: String = "blue", width: Double = 4, cornerRadius: Double = 9, inset: Double = 0,
                lineStyle: BorderLineStyle = .solid) {
        self.color = color; self.width = width; self.cornerRadius = cornerRadius; self.inset = inset
        self.lineStyle = lineStyle
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

/// Maps a polled window frame to the border frame to draw. The **position passes through raw**
/// (1:1, no low-pass): a window frame is a precise, discrete signal, so low-passing it only adds
/// group-delay "float" (the border drifting/settling behind the window) without removing real
/// noise. The One Euro filters are kept solely to produce a *smoothed velocity* for an optional
/// `lead` (the "motion prediction" toggle), so a nonzero lead compensates poll lag on steady
/// drags without the jitter a raw finite-difference would add. `lead == 0` → exact 1:1 mirror.
///
/// Pure value type, deterministic in `(samples, dt)`; the caller passes the inter-sample interval.
/// (The residual trailing during fast drags is polling/IPC latency — only an event-driven source,
/// e.g. window-server move notifications, removes that; see ARCHITECTURE.)
public struct FrameMotionPredictor {
    /// Seconds of velocity lead. 0 = raw 1:1 mirror (no float); >0 leads by smoothed velocity.
    public var lead: Double
    private var fx, fy, fw, fh: OneEuroFilter
    private var lastOut: ZTRect?
    private var hasSample = false

    /// `beta` is the velocity smoothing's speed-coupling term (used only for the lead's velocity).
    /// Default `lead` 0 → raw 1:1; the controller raises it when motion prediction is enabled.
    public init(lead: Double = 0, minCutoff: Double = 1.2, beta: Double = 1.0, dCutoff: Double = 1.0) {
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

    /// Feed an observed frame sampled `dt` seconds after the previous; returns the frame to draw
    /// (raw position, plus a smoothed-velocity lead when `lead > 0`).
    public mutating func process(_ frame: ZTRect, dt: Double) -> ZTRect {
        hasSample = true
        // Always advance the velocity filters (so a later lead has warm velocity), but the
        // POSITION we return is the raw sample — no low-pass, hence no float.
        let vx = fx.filter(frame.x, dt: dt).velocity
        let vy = fy.filter(frame.y, dt: dt).velocity
        let vw = fw.filter(frame.w, dt: dt).velocity
        let vh = fh.filter(frame.h, dt: dt).velocity
        let out = lead == 0 ? frame
            : ZTRect(x: frame.x + vx * lead, y: frame.y + vy * lead,
                     w: frame.w + vw * lead, h: frame.h + vh * lead)
        lastOut = out
        return out
    }
}
