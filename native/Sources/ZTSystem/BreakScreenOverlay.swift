// BreakScreenOverlay.swift — the retro Pomodoro break overlay. A full-screen, dimmed CRT-styled
// card: amber monospace headline on near-black with horizontal scanlines, so a finished work
// period reads unmistakably as "step away from the screen". Click anywhere (or the auto-dismiss
// timer) to clear it. Purely visual + opt-in; the trigger/copy is ZTCore.BreakScreen.

import AppKit
import ZTCore

public final class BreakScreenOverlay {
    private var window: NSWindow?
    public init() {}

    /// Show the overlay over `screenCGFrame` (use the FULL display frame for an immersive break).
    /// `onDismiss` fires on a click so the controller can cancel its auto-dismiss timer too.
    public func show(title: String, subtitle: String, screenCGFrame: ZTRect, onDismiss: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hideNow()
            let nsFrame = CoordConvert.nsFrame(fromCG: screenCGFrame)
            let w = NSWindow(contentRect: nsFrame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .statusBar
            w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            let view = BreakScreenView(frame: NSRect(origin: .zero, size: nsFrame.size))
            view.title = title
            view.subtitle = subtitle
            view.onDismiss = onDismiss
            w.contentView = view
            w.alphaValue = 0
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.25; w.animator().alphaValue = 1 }
            self.window = w
        }
    }

    public func hide() {
        DispatchQueue.main.async { [weak self] in
            guard let w = self?.window else { return }
            NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.18; w.animator().alphaValue = 0 },
                                                 completionHandler: { w.orderOut(nil) })
            self?.window = nil
        }
    }
    private func hideNow() { window?.orderOut(nil); window = nil }
}

private final class BreakScreenView: NSView {
    var title = ""
    var subtitle = ""
    var onDismiss: (() -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) { onDismiss?() }

    override func draw(_ dirtyRect: NSRect) {
        // Near-black dim — clearly "break mode" but not a pure blackout.
        NSColor.black.withAlphaComponent(0.92).setFill()
        bounds.fill()

        // CRT scanlines: faint horizontal lines across the whole field.
        NSColor.white.withAlphaComponent(0.035).setFill()
        var y = 0.0
        while y < bounds.height { NSRect(x: 0, y: y, width: bounds.width, height: 1).fill(); y += 3 }

        let amber = NSColor(red: 0.98, green: 0.70, blue: 0.20, alpha: 1.0)
        let titleFont = NSFont.monospacedSystemFont(ofSize: min(96, bounds.width * 0.07), weight: .bold)
        let subFont = NSFont.monospacedSystemFont(ofSize: 20, weight: .medium)

        let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: amber,
            .kern: 6, .shadow: glow(amber)]
        let subAttrs: [NSAttributedString.Key: Any] = [.font: subFont,
            .foregroundColor: amber.withAlphaComponent(0.75), .kern: 4]

        let t = title as NSString, s = subtitle as NSString
        let tSize = t.size(withAttributes: titleAttrs), sSize = s.size(withAttributes: subAttrs)
        let cx = bounds.midX, cy = bounds.midY
        t.draw(at: NSPoint(x: cx - tSize.width / 2, y: cy - tSize.height / 2 - 18), withAttributes: titleAttrs)
        s.draw(at: NSPoint(x: cx - sSize.width / 2, y: cy + tSize.height / 2 + 4), withAttributes: subAttrs)

        // hint
        let hint = "click to dismiss" as NSString
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.30), .kern: 2]
        let hSize = hint.size(withAttributes: hintAttrs)
        hint.draw(at: NSPoint(x: cx - hSize.width / 2, y: bounds.height - 48), withAttributes: hintAttrs)
    }

    private func glow(_ color: NSColor) -> NSShadow {
        let sh = NSShadow(); sh.shadowColor = color.withAlphaComponent(0.6)
        sh.shadowBlurRadius = 14; sh.shadowOffset = .zero; return sh
    }
}
