// AppLauncherOverlay.swift — the app-launcher cheat-sheet: hold the app-launcher modifier and a
// compact KEYBOARD palette appears showing each assigned shortcut on its real key (the key glyph + the
// app it launches). Floats over the LIVE desktop (no dim). The live window backs the panel with real
// macOS 26 Liquid Glass (NSGlassEffectView; NSVisualEffectView fallback); the headless render harness
// can't composite glass, so renderPNG draws an opaque dark panel instead. Purely visual — the launch
// is the existing modifier+key hotkey.

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

            let container = NSView(frame: NSRect(origin: .zero, size: nsFrame.size))
            // The panel is centred, so its rect is the same in flipped or unflipped coords.
            let size = AppLauncherView.panelSize(for: caps)
            let panel = NSRect(x: (nsFrame.width - size.width) / 2, y: (nsFrame.height - size.height) / 2,
                               width: size.width, height: size.height)
            if !caps.isEmpty {
                let glass: NSView
                if #available(macOS 26.0, *) {
                    let g = NSGlassEffectView(frame: panel)
                    g.cornerRadius = AppLauncherView.panelCorner
                    g.tintColor = NSColor.black.withAlphaComponent(0.18)
                    glass = g
                } else {
                    let g = NSVisualEffectView(frame: panel)
                    g.material = .hudWindow; g.blendingMode = .behindWindow; g.state = .active
                    g.wantsLayer = true; g.layer?.cornerRadius = AppLauncherView.panelCorner; g.layer?.masksToBounds = true
                    glass = g
                }
                container.addSubview(glass)
            }
            let view = AppLauncherView(frame: NSRect(origin: .zero, size: nsFrame.size))
            view.drawsPanelBackground = false   // the glass provides the panel; the view draws only the keycaps
            view.caps = caps
            container.addSubview(view)

            w.contentView = container
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

    /// Deterministic windowless render → PNG (QA / render harness / tests). Draws an opaque dark panel
    /// (the live overlay uses Liquid Glass, which can't be composited offscreen).
    public static func renderPNG(caps: [AppLauncherHUD.Cap], screenCGFrame: ZTRect,
                                 backdrop: NSColor = NSColor(white: 0.42, alpha: 1),
                                 backdropImage: NSImage? = nil) -> Data? {
        let size = NSSize(width: screenCGFrame.w, height: screenCGFrame.h)
        let view = AppLauncherView(frame: NSRect(origin: .zero, size: size))
        view.drawsPanelBackground = true   // no glass offscreen → draw the dark panel
        view.caps = caps
        return OverlayRender.png(of: view, size: size, backdrop: backdrop, backdropImage: backdropImage)
    }
}

private final class AppLauncherView: NSView {
    var caps: [AppLauncherHUD.Cap] = [] { didSet { needsDisplay = true } }
    var drawsPanelBackground = true
    override var isFlipped: Bool { true }

    static let cellW = 112.0, cellH = 80.0, pad = 28.0, inset = 6.0
    static let panelCorner: CGFloat = 24

    /// Panel size for `caps` (independent of where it's centred), so the live window can size the glass.
    static func panelSize(for caps: [AppLauncherHUD.Cap]) -> NSSize {
        guard !caps.isEmpty else { return .zero }
        let minRow = caps.map(\.row).min()!, maxRow = caps.map(\.row).max()!
        let minCol = caps.map(\.col).min()!, maxCol = caps.map(\.col).max()!
        let gridW = (maxCol - minCol + 1) * cellW, gridH = Double(maxRow - minRow + 1) * cellH
        return NSSize(width: gridW + pad * 2, height: gridH + pad * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !caps.isEmpty else { return }   // no desktop dim — the panel floats over the LIVE desktop
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
