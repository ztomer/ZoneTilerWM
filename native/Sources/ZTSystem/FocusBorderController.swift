// FocusBorderController.swift — ZTSystem: draws a colored outline around the focused window and
// keeps it glued to that window as it moves, using ZTCore's FrameMotionPredictor to lead the
// observed (always-lagging) frame. The focused window's frame is sampled from CGWindowList
// (zero AX, per the perf budget — see CLAUDE.md). Two renderers sit behind ZTCore's
// BorderRenderer protocol; the backend is chosen by config:
//   • OverlayBorderRenderer  — a borderless NSWindow (public API; robust, App-Store-safe).
//   • SkyLightBorderRenderer — a window on the window server via private SkyLight APIs
//                              (clean-room; see SkyLightBorderRenderer.swift).
//
// Coordinates: ZTRect is top-left CG; NSWindow frames are bottom-left global (CoordConvert).

import AppKit
import ApplicationServices
import QuartzCore
import ZTCore

/// Resolve a config color name to NSColor (reuses the Pomodoro color-name set).
func borderNSColor(_ name: String) -> NSColor { PomodoroBar.color(named: name) }

// MARK: - Public overlay renderer (borderless NSWindow)

/// Draws the border as a CAShapeLayer stroke inside a transparent, click-through NSWindow that
/// is moved to follow the window. Implicit layer animations are disabled so the stroke never
/// lags behind the frame change.
final class OverlayBorderRenderer: BorderRenderer {
    private var window: NSWindow?
    private let view = BorderShapeView(frame: .zero)   // explicit designated init (sets up the layer)

    func render(frame: ZTRect?, style: BorderStyle) {
        guard let frame else { window?.orderOut(nil); return }
        // Pad the overlay so the stroke (centered on the window edge) isn't clipped.
        let pad = style.width + max(style.inset, 0) + 2
        let outer = ZTRect(x: frame.x - pad, y: frame.y - pad, w: frame.w + 2 * pad, h: frame.h + 2 * pad)
        let ns = CoordConvert.nsFrame(fromCG: outer)
        let w = window ?? makeWindow()
        w.setFrame(ns, display: false)
        view.frame = NSRect(origin: .zero, size: ns.size)
        // The window's own rect inside the padded view (symmetric padding → flip-independent),
        // grown by `inset` so a positive inset draws the border outside the window edge.
        let br = NSRect(x: pad - style.inset, y: pad - style.inset,
                        width: frame.w + 2 * style.inset, height: frame.h + 2 * style.inset)
        view.update(borderRect: br, color: borderNSColor(style.color),
                    width: CGFloat(style.width), radius: CGFloat(style.cornerRadius))
        if window == nil { w.contentView = view; window = w }
        w.orderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.ignoresMouseEvents = true
        w.level = .floating                       // above normal windows (the focused one is frontmost)
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        return w
    }
}

/// Strokes one rounded rect via draw(_:) — the proven overlay-drawing path in this codebase
/// (mirrors GridOverlayView). Immediate (no implicit animation), so updates apply on the frame
/// they're set, which is exactly what we want when following a moving window. Top-left origin
/// (isFlipped) so `borderRect` matches the CG-derived geometry.
final class BorderShapeView: NSView {
    private var borderRect: NSRect = .zero
    private var color: NSColor = .systemBlue
    private var width: CGFloat = 4
    private var radius: CGFloat = 9
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard width > 0, borderRect.width > 1, borderRect.height > 1 else { return }
        let stroke = borderRect.insetBy(dx: width / 2, dy: width / 2)   // center the stroke on the edge
        let path = NSBezierPath(roundedRect: stroke, xRadius: radius, yRadius: radius)
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    func update(borderRect: NSRect, color: NSColor, width: CGFloat, radius: CGFloat) {
        self.borderRect = borderRect; self.color = color; self.width = width; self.radius = radius
        needsDisplay = true
    }
}

// MARK: - Controller

/// Owns the active renderer + the predictor and drives them from a main-thread timer (in common
/// run-loop modes, so it keeps firing during a live window drag). Sampling the focused window
/// each tick costs zero AX calls.
public final class FocusBorderController {
    private var renderer: BorderRenderer?
    private var predictor = FrameMotionPredictor()
    private var style = BorderStyle()
    private var backend: BorderBackend = .overlay
    private var enabled = false
    private var prediction = true

    private var timer: Timer?
    private var lastFocusedID: Int?
    private var lastRendered: ZTRect?
    private var lastTick: CFTimeInterval = 0
    // While a window plays its minimize/unminimize (genie) animation the CGWindowList frame shrinks
    // toward / grows from the Dock; gluing the border to that looks broken. On the AX miniaturize/
    // deminiaturize notification we mute renders until this deadline, then resume on the next tick.
    private var suppressUntil: CFTimeInterval = 0
    private let animateSuppressSeconds = 0.6   // covers the default genie duration with margin
    private let tickInterval = 1.0 / 60.0   // fallback poll (event-driven path does the tight work)
    private let leadSeconds = 0.012         // velocity lead when prediction is on (~1 frame)

    // Event-driven tracking: AX observer on the frontmost app fires on window move/resize/focus.
    // The frame is then read from CGWindowList (zero AX) — so the only AX cost is observer setup
    // per focus change, never per move. The fallback timer covers apps that don't post these.
    private var axObserver: AXObserver?
    private var observedPID: pid_t = 0
    private var appElement: AXUIElement?
    private var wsTokens: [NSObjectProtocol] = []

    public init() {}

    /// (Re)configure from the resolved config. Safe to call repeatedly (e.g. on live reload).
    public func apply(enabled: Bool, backend: BorderBackend, style: BorderStyle, prediction: Bool) {
        self.style = style
        self.prediction = prediction
        predictor.lead = prediction ? leadSeconds : 0   // smoothing always on; lead is the toggle
        let backendChanged = backend != self.backend || renderer == nil
        self.backend = backend
        if backendChanged { swapRenderer() }
        if enabled != self.enabled {
            self.enabled = enabled
            enabled ? start() : stop()
        } else if enabled {
            // Style may have changed while running — repaint immediately at the last frame.
            if let f = lastRendered { renderer?.render(frame: f, style: self.style) }
        }
    }

    private func swapRenderer() {
        renderer?.render(frame: nil, style: style)
        switch backend {
        case .overlay:
            renderer = OverlayBorderRenderer()
        case .skylight:
            // Fall back to the overlay renderer if the private window-server path is unavailable.
            renderer = SkyLightBorderRenderer() ?? OverlayBorderRenderer()
        }
    }

    private func start() {
        stop()
        if renderer == nil { swapRenderer() }
        predictor.reset(); lastTick = 0
        retargetObserver()
        // Re-target the observer when the user switches apps.
        let nc = NSWorkspace.shared.notificationCenter
        wsTokens.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                       object: nil, queue: .main) { [weak self] _ in
            self?.retargetObserver(); self?.update()
        })
        // Fallback poll: covers focus changes and apps that don't post AX move/resize events.
        let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(t, forMode: .common)   // fire during event tracking (window drags)
        timer = t
        update()
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        let nc = NSWorkspace.shared.notificationCenter
        wsTokens.forEach { nc.removeObserver($0) }; wsTokens.removeAll()
        teardownObserver()
        lastFocusedID = nil; lastRendered = nil
        renderer?.render(frame: nil, style: style)
    }

    private func teardownObserver() {
        if let axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
        }
        axObserver = nil; appElement = nil; observedPID = 0
    }

    /// Observe the frontmost app's window move/resize/focus notifications (all on the app element,
    /// so we don't track per-window elements). Costs a handful of AX calls only on app switch.
    private func retargetObserver() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        if pid == observedPID, axObserver != nil { return }
        teardownObserver()
        observedPID = pid
        var obs: AXObserver?
        guard AXObserverCreate(pid, axBorderObserverCallback, &obs) == .success, let obs else { return }
        let el = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXWindowMovedNotification, kAXWindowResizedNotification,
                  kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
                  kAXApplicationActivatedNotification,
                  kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
            AXObserverAddNotification(obs, el, n as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        axObserver = obs; appElement = el
    }

    /// Called from both the AX event callback and the fallback timer. Reads the focused frame from
    /// CGWindowList (zero AX) and renders it (raw 1:1, plus the optional lead). Coalesced by the
    /// skip-when-unchanged check, so duplicate event+timer fires don't double-draw.
    fileprivate func update() {
        if CACurrentMediaTime() < suppressUntil { return }   // muted during a minimize/unminimize animation
        guard let cur = Self.focusedWindowFrame() else {
            if lastRendered != nil { renderer?.render(frame: nil, style: style); lastRendered = nil }
            return
        }
        let now = CACurrentMediaTime()
        if cur.id != lastFocusedID { predictor.reset(); lastFocusedID = cur.id; lastTick = 0 }
        let dt = lastTick > 0 ? (now - lastTick) : tickInterval
        lastTick = now
        let target = predictor.process(cur.frame, dt: dt)
        if let last = lastRendered, framesEqual(last, target) { return }
        renderer?.render(frame: target, style: style)
        lastRendered = target
    }

    /// A window started its minimize/unminimize animation: hide the border now and stay muted for
    /// the genie's duration so it doesn't chase the shrinking/growing frame. update() resumes after.
    fileprivate func suppressForAnimation() {
        suppressUntil = CACurrentMediaTime() + animateSuppressSeconds
        if lastRendered != nil { renderer?.render(frame: nil, style: style); lastRendered = nil }
    }

    private func framesEqual(_ a: ZTRect, _ b: ZTRect) -> Bool {
        abs(a.x - b.x) < 0.5 && abs(a.y - b.y) < 0.5 && abs(a.w - b.w) < 0.5 && abs(a.h - b.h) < 0.5
    }

    /// The focused window's frame (top-left CG) + its CGWindowID, via CGWindowList only (zero AX):
    /// the frontmost normal (layer 0) window of the frontmost application.
    static func focusedWindowFrame() -> (id: Int, frame: ZTRect)? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        for w in AXWindowSystem.onScreenWindows() where w.pid == pid && w.layer == 0 {
            // front-to-back order → first match is the focused window
            guard w.bounds.width > 1, w.bounds.height > 1 else { continue }
            return (Int(w.windowID), ZTRect(x: w.bounds.origin.x, y: w.bounds.origin.y,
                                            w: w.bounds.size.width, h: w.bounds.size.height))
        }
        return nil
    }
}

/// C callback for the AX observer — bridges back to the controller via the refcon pointer.
/// Runs on the main run loop (the observer's source is added there), so it can drive AppKit.
private func axBorderObserverCallback(_ observer: AXObserver, _ element: AXUIElement,
                                      _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let controller = Unmanaged<FocusBorderController>.fromOpaque(refcon).takeUnretainedValue()
    switch notification as String {
    case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
        controller.suppressForAnimation()
    default:
        controller.update()
    }
}
