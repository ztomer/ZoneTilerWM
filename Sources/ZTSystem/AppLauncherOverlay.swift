// AppLauncherOverlay.swift — the app-launcher cheat-sheet: hold the app-launcher modifier and a
// compact KEYBOARD palette appears showing each assigned shortcut on its real key (the key glyph + the
// app it launches). Floats over the LIVE desktop (no dim).
//
// The live overlay renders each keycap as a real macOS 26 Liquid Glass element (NSGlassEffectView)
// inside an NSGlassEffectContainerView — so the chips LENS the desktop behind them and merge fluidly
// when close (the "liquid", not a flat frosted slab). The key glyph + app name sit inside each chip's
// contentView. The headless render harness can't composite glass, so renderPNG falls back to drawing
// opaque dark keycaps. Purely visual — the launch is the existing modifier+key hotkey.

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

            let size = NSRect(origin: .zero, size: nsFrame.size)
            w.contentView = caps.isEmpty ? NSView(frame: size)
                                         : AppLauncherOverlay.glassChips(caps: caps, bounds: size)
            w.alphaValue = 0
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.12; w.animator().alphaValue = 1 }
            self.window = w
        }
    }

    /// A Liquid-Glass keyboard: one NSGlassEffectView chip per shortcut, merged in a container.
    private static func glassChips(caps: [AppLauncherHUD.Cap], bounds: NSRect) -> NSView {
        let cellW = AppLauncherView.cellW, cellH = AppLauncherView.cellH
        let pad = AppLauncherView.pad, inset = AppLauncherView.inset
        let minRow = caps.map(\.row).min() ?? 0, minCol = caps.map(\.col).min() ?? 0
        let size = AppLauncherView.panelSize(for: caps)
        let gx = bounds.midX - size.width / 2 + pad, gy = bounds.midY - size.height / 2 + pad
        let (container, content) = LiquidGlass.container(frame: bounds, spacing: 22)   // > chip gap → chips bridge
        for cap in caps {
            let x = gx + (cap.col - minCol) * cellW + inset
            let y = gy + Double(cap.row - minRow) * cellH + inset
            let label = KeycapLabel(); label.cap = cap
            let chip = LiquidGlass.chip(frame: NSRect(x: x, y: y, width: cellW - inset * 2, height: cellH - inset * 2),
                                        cornerRadius: 16, tint: NSColor.black.withAlphaComponent(0.12),
                                        clear: true, content: label)
            content.addSubview(chip)
        }
        return container
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

    /// Deterministic windowless render → PNG (QA / render harness / tests). Draws opaque dark keycaps
    /// (the live overlay uses Liquid Glass, which can't composite offscreen).
    public static func renderPNG(caps: [AppLauncherHUD.Cap], screenCGFrame: ZTRect,
                                 backdrop: NSColor = NSColor(white: 0.42, alpha: 1),
                                 backdropImage: NSImage? = nil) -> Data? {
        let size = NSSize(width: screenCGFrame.w, height: screenCGFrame.h)
        let view = AppLauncherView(frame: NSRect(origin: .zero, size: size))
        view.drawsPanelBackground = true
        view.caps = caps
        return OverlayRender.png(of: view, size: size, backdrop: backdrop, backdropImage: backdropImage)
    }
}

/// Top-left-origin container so glass-chip frames match the keyboard layout math.

/// The label that sits INSIDE a glass chip: the key glyph (amber) over the app name (white).
private final class KeycapLabel: NSView {
    var cap: AppLauncherHUD.Cap? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let cap else { return }
        let amber = NSColor(red: 0.95, green: 0.72, blue: 0.24, alpha: 1.0)
        let key = cap.key.uppercased() as NSString
        let keyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 23, weight: .bold), .foregroundColor: amber]
        let ks = key.size(withAttributes: keyAttrs)
        key.draw(at: NSPoint(x: bounds.midX - ks.width / 2, y: 8), withAttributes: keyAttrs)

        let trunc = NSMutableParagraphStyle(); trunc.lineBreakMode = .byTruncatingTail; trunc.alignment = .center
        let app = (cap.label) as NSString
        let appAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white, .paragraphStyle: trunc,
            .shadow: { let s = NSShadow(); s.shadowColor = .black; s.shadowBlurRadius = 2; return s }()]
        app.draw(in: NSRect(x: 2, y: ks.height + 14, width: bounds.width - 4, height: 18), withAttributes: appAttrs)
    }
}

private final class AppLauncherView: NSView {
    var caps: [AppLauncherHUD.Cap] = [] { didSet { needsDisplay = true } }
    var drawsPanelBackground = true
    override var isFlipped: Bool { true }

    static let cellW = 122.0, cellH = 80.0, pad = 28.0, inset = 6.0   // wider → fits long app names
    static let panelCorner: CGFloat = 24

    static func panelSize(for caps: [AppLauncherHUD.Cap]) -> NSSize {
        guard !caps.isEmpty else { return .zero }
        let minRow = caps.map(\.row).min()!, maxRow = caps.map(\.row).max()!
        let minCol = caps.map(\.col).min()!, maxCol = caps.map(\.col).max()!
        let gridW = (maxCol - minCol + 1) * cellW, gridH = Double(maxRow - minRow + 1) * cellH
        return NSSize(width: gridW + pad * 2, height: gridH + pad * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !caps.isEmpty else { return }
        let amber = NSColor(red: 0.92, green: 0.68, blue: 0.20, alpha: 1.0)
        let cellW = Self.cellW, cellH = Self.cellH, pad = Self.pad, inset = Self.inset
        let minRow = caps.map(\.row).min()!, minCol = caps.map(\.col).min()!
        let size = Self.panelSize(for: caps)
        let ox = bounds.midX - size.width / 2, oy = bounds.midY - size.height / 2

        if drawsPanelBackground {
            let panel = NSBezierPath(roundedRect: NSRect(x: ox, y: oy, width: size.width, height: size.height),
                                     xRadius: Self.panelCorner, yRadius: Self.panelCorner)
            NSColor.black.withAlphaComponent(0.58).setFill(); panel.fill()
            amber.withAlphaComponent(0.22).setStroke(); panel.lineWidth = 1; panel.stroke()
        }

        let gx = ox + pad, gy = oy + pad
        let keyFont = NSFont.monospacedSystemFont(ofSize: 23, weight: .bold)
        let appFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let trunc = NSMutableParagraphStyle(); trunc.lineBreakMode = .byTruncatingTail; trunc.alignment = .center
        for cap in caps {
            let x = gx + (cap.col - minCol) * cellW, y = gy + Double(cap.row - minRow) * cellH
            let r = NSRect(x: x + inset, y: y + inset, width: cellW - inset * 2, height: cellH - inset * 2)
            let bg = NSBezierPath(roundedRect: r, xRadius: 11, yRadius: 11)
            NSColor.black.withAlphaComponent(0.55).setFill(); bg.fill()
            amber.withAlphaComponent(0.7).setStroke(); bg.lineWidth = 1; bg.stroke()
            let key = cap.key.uppercased() as NSString
            let keyAttrs: [NSAttributedString.Key: Any] = [.font: keyFont, .foregroundColor: amber]
            let ks = key.size(withAttributes: keyAttrs)
            key.draw(at: NSPoint(x: r.midX - ks.width / 2, y: r.minY + 9), withAttributes: keyAttrs)
            let app = cap.label as NSString
            let appAttrs: [NSAttributedString.Key: Any] = [
                .font: appFont, .foregroundColor: NSColor(white: 0.95, alpha: 1), .paragraphStyle: trunc]
            app.draw(in: NSRect(x: r.minX + 6, y: r.minY + ks.height + 16, width: r.width - 12, height: 18),
                     withAttributes: appAttrs)
        }
    }
}
