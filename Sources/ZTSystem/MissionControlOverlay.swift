// MissionControlOverlay.swift — draws the Mission Control window hints (a label badge + a close (×)
// button per exposed window) from the pure ZTCore.MissionControl.Hint geometry. This is the DRAW +
// (deterministic) render half; the live half — detecting Exposé and reading tile rects via private
// CGS/SkyLight, then floating this above the exposé layer + capturing keys/clicks — is specced in
// docs/V6_FEATURE_PLAN.md. Mirrors ZoneHUDOverlay: a click-through borderless window, plus a static
// renderPNG for QA / Gemini grading. Coordinates: ZTRect top-left CG (CoordConvert to NS frames).

import AppKit
import ZTCore

public final class MissionControlOverlay {
    private var window: NSWindow?
    public init() {}

    /// Show the interactive overlay. Clicks are hit-tested (in MissionControl): × → onClose,
    /// anywhere else in a tile → onJump, empty space → onDismiss. Pass nil callbacks for a passive
    /// (display-only) overlay.
    public func show(_ hints: [MissionControl.Hint], screenCGFrame: ZTRect,
                     onJump: ((Int) -> Void)? = nil, onClose: ((Int) -> Void)? = nil,
                     onDismiss: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hideNow()
            let nsFrame = CoordConvert.nsFrame(fromCG: screenCGFrame)
            let w = NSWindow(contentRect: nsFrame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false; w.backgroundColor = .clear
            w.ignoresMouseEvents = (onJump == nil && onClose == nil && onDismiss == nil)
            w.level = .statusBar; w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            let view = MissionControlView(frame: NSRect(origin: .zero, size: nsFrame.size))
            view.set(hints, screenOrigin: (screenCGFrame.x, screenCGFrame.y))
            view.onJump = onJump; view.onClose = onClose; view.onDismiss = onDismiss
            w.contentView = view
            w.orderFrontRegardless()   // the agent isn't the active app
            self.window = w
        }
    }

    public func hide() {
        DispatchQueue.main.async { [weak self] in self?.hideNow() }
    }
    private func hideNow() { window?.orderOut(nil); window = nil }

    /// Deterministic windowless render (badges + × buttons) over a neutral backdrop → PNG, for QA.
    public static func renderPNG(hints: [MissionControl.Hint], screenCGFrame: ZTRect,
                                 backdrop: NSColor = NSColor(white: 0.30, alpha: 1),
                                 backdropImage: NSImage? = nil) -> Data? {
        let size = NSSize(width: screenCGFrame.w, height: screenCGFrame.h)
        let view = MissionControlView(frame: NSRect(origin: .zero, size: size))
        view.set(hints, screenOrigin: (screenCGFrame.x, screenCGFrame.y))
        return OverlayRender.png(of: view, size: size, backdrop: backdrop, backdropImage: backdropImage)
    }
}

private final class MissionControlView: NSView {
    private var hints: [MissionControl.Hint] = []
    private var origin: (x: Double, y: Double) = (0, 0)
    var onJump: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onDismiss: (() -> Void)?
    override var isFlipped: Bool { true }   // top-left origin to match CG
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func set(_ hints: [MissionControl.Hint], screenOrigin: (x: Double, y: Double)) {
        self.hints = hints; self.origin = screenOrigin
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)   // flipped (top-left) local
        let cx = Double(p.x) + origin.x, cy = Double(p.y) + origin.y   // → CG global
        if let id = MissionControl.closeHit(at: cx, cy, in: hints) { onClose?(id) }
        else if let id = MissionControl.tileHit(at: cx, cy, in: hints) { onJump?(id) }
        else { onDismiss?() }
    }

    private func local(_ r: ZTRect) -> NSRect {
        NSRect(x: r.x - origin.x, y: r.y - origin.y, width: r.w, height: r.h)
    }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor(red: 0.30, green: 0.66, blue: 1.0, alpha: 1.0)   // jump-hint blue
        for h in hints {
            // Label badge — dark chip + accent border + the key.
            let b = local(h.badge)
            let chip = NSBezierPath(roundedRect: b, xRadius: 6, yRadius: 6)
            NSColor.black.withAlphaComponent(0.85).setFill(); chip.fill()
            accent.setStroke(); chip.lineWidth = 1.5; chip.stroke()
            let label = h.label.uppercased() as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: max(11, b.height * 0.6), weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let sz = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: b.midX - sz.width / 2, y: b.midY - sz.height / 2), withAttributes: attrs)

            // Close (×) button — red disc + white cross at the tile's top-right.
            let c = local(h.close)
            let disc = NSBezierPath(ovalIn: c)
            NSColor.systemRed.withAlphaComponent(0.92).setFill(); disc.fill()
            let x = NSBezierPath(); let pad = c.width * 0.3
            x.move(to: NSPoint(x: c.minX + pad, y: c.minY + pad)); x.line(to: NSPoint(x: c.maxX - pad, y: c.maxY - pad))
            x.move(to: NSPoint(x: c.maxX - pad, y: c.minY + pad)); x.line(to: NSPoint(x: c.minX + pad, y: c.maxY - pad))
            NSColor.white.setStroke(); x.lineWidth = 1.6; x.lineCapStyle = .round; x.stroke()
        }
    }
}
