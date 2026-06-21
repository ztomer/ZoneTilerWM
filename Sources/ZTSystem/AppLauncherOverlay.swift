// AppLauncherOverlay.swift — the app-launcher cheat-sheet: hold the app-launcher modifier and a
// compact KEYBOARD palette appears (centred, click-through, dimmed backdrop) showing each assigned
// shortcut on its real key — the key glyph + the app it launches. Same Kare amber/dark language as the
// zone HUD. Purely visual; the actual launch is the existing modifier+key hotkey.

import AppKit
import ZTCore

public final class AppLauncherOverlay {
    private var window: NSWindow?
    public init() {}

    public func show(caps: [AppLauncherHUD.Cap], screenCGFrame: ZTRect) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hideNow()
            let nsFrame = CoordConvert.nsFrame(fromCG: screenCGFrame)
            let w = NSWindow(contentRect: nsFrame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.level = .statusBar
            w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            let view = AppLauncherView(frame: NSRect(origin: .zero, size: nsFrame.size))
            view.caps = caps
            w.contentView = view
            w.alphaValue = 0
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.12; w.animator().alphaValue = 1 }
            self.window = w
        }
    }

    public func hide() {
        DispatchQueue.main.async { [weak self] in
            guard let w = self?.window else { return }
            NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.10; w.animator().alphaValue = 0 },
                                                 completionHandler: { w.orderOut(nil) })
            self?.window = nil
        }
    }
    private func hideNow() { window?.orderOut(nil); window = nil }

    /// Deterministic windowless render → PNG (QA / render harness / tests).
    public static func renderPNG(caps: [AppLauncherHUD.Cap], screenCGFrame: ZTRect,
                                 backdrop: NSColor = NSColor(white: 0.42, alpha: 1),
                                 backdropImage: NSImage? = nil) -> Data? {
        let size = NSSize(width: screenCGFrame.w, height: screenCGFrame.h)
        let view = AppLauncherView(frame: NSRect(origin: .zero, size: size))
        view.caps = caps
        return OverlayRender.png(of: view, size: size, backdrop: backdrop, backdropImage: backdropImage)
    }
}

private final class AppLauncherView: NSView {
    var caps: [AppLauncherHUD.Cap] = [] { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.20).setFill()
        bounds.fill()
        guard !caps.isEmpty else { return }

        let amber = NSColor(red: 0.92, green: 0.68, blue: 0.20, alpha: 1.0)
        let cellW = 112.0, cellH = 80.0, pad = 28.0, inset = 6.0

        // Trim to the populated rows/columns so there's no dead keyboard space, keeping the stagger.
        let minRow = caps.map(\.row).min() ?? 0, maxRow = caps.map(\.row).max() ?? 0
        let minCol = caps.map(\.col).min() ?? 0, maxCol = caps.map(\.col).max() ?? 0
        let gridW = (maxCol - minCol + 1) * cellW, gridH = Double(maxRow - minRow + 1) * cellH
        let panelW = gridW + pad * 2, panelH = gridH + pad * 2
        let ox = bounds.midX - panelW / 2, oy = bounds.midY - panelH / 2

        // Panel.
        let panel = NSBezierPath(roundedRect: NSRect(x: ox, y: oy, width: panelW, height: panelH), xRadius: 24, yRadius: 24)
        NSColor.black.withAlphaComponent(0.58).setFill(); panel.fill()
        amber.withAlphaComponent(0.22).setStroke(); panel.lineWidth = 1; panel.stroke()

        let gx = ox + pad, gy = oy + pad
        let keyFont = NSFont.monospacedSystemFont(ofSize: 23, weight: .bold)
        let appFont = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        let trunc = NSMutableParagraphStyle(); trunc.lineBreakMode = .byTruncatingTail; trunc.alignment = .center

        for cap in caps {
            let x = gx + (cap.col - minCol) * cellW, y = gy + Double(cap.row - minRow) * cellH
            let r = NSRect(x: x + inset, y: y + inset, width: cellW - inset * 2, height: cellH - inset * 2)
            let bg = NSBezierPath(roundedRect: r, xRadius: 11, yRadius: 11)
            NSColor.black.withAlphaComponent(0.8).setFill(); bg.fill()
            amber.withAlphaComponent(0.7).setStroke(); bg.lineWidth = 1; bg.stroke()

            // Key glyph (top), app name (below, truncated).
            let key = cap.key.uppercased() as NSString
            let keyAttrs: [NSAttributedString.Key: Any] = [.font: keyFont, .foregroundColor: amber]
            let ks = key.size(withAttributes: keyAttrs)
            key.draw(at: NSPoint(x: r.midX - ks.width / 2, y: r.minY + 9), withAttributes: keyAttrs)

            let app = cap.label as NSString
            let appAttrs: [NSAttributedString.Key: Any] = [
                .font: appFont, .foregroundColor: NSColor(white: 0.93, alpha: 1), .paragraphStyle: trunc]
            app.draw(in: NSRect(x: r.minX + 4, y: r.minY + ks.height + 16, width: r.width - 8, height: 18),
                     withAttributes: appAttrs)
        }
    }
}
