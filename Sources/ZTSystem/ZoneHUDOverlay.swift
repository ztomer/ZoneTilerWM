// ZoneHUDOverlay.swift — the modifier-held zone cheat-sheet. One click-through window over the
// target screen, lightly dimmed, that draws the actual zone GRID: each zone's real rectangle is
// outlined at its true on-screen position with its key chip centred inside it, so it's obvious
// where pressing that key lands a window. (Earlier this de-overlapped the chips, which drifted them
// far from their zones — the rectangle outline is the honest mapping. Outlines are stroke-only so
// heavily-overlapping keyboard-grid zones read as a grid instead of accumulating into an amber
// wash.) Purely visual: the actual tiling is the existing modifier+zone hotkey.

import AppKit
import ZTCore

public final class ZoneHUDOverlay {
    private var window: NSWindow?
    public init() {}

    public func show(_ cells: [ZoneHUD.Cell], screenCGFrame: ZTRect) {
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
            let view = ZoneHUDView(frame: NSRect(origin: .zero, size: nsFrame.size))
            view.setCells(cells, screenOrigin: (screenCGFrame.x, screenCGFrame.y))
            w.contentView = view
            w.alphaValue = 0
            w.orderFrontRegardless()   // the menubar agent isn't the active app — orderFront(nil) would no-op
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.12; w.animator().alphaValue = 1 }
            self.window = w
        }
    }

    /// Preview a zone (tile-on-release): fill the named zone so it reads as "release to land here".
    /// nil clears the highlight. No-op if the overlay isn't up.
    public func highlight(_ key: String?) {
        DispatchQueue.main.async { [weak self] in
            (self?.window?.contentView as? ZoneHUDView)?.setHighlight(key)
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

    /// Deterministic windowless render of the HUD (chips at `cells`) over a neutral backdrop → PNG.
    /// `highlight` previews a zone (the tile-on-release fill), matching the live overlay.
    public static func renderPNG(cells: [ZoneHUD.Cell], screenCGFrame: ZTRect,
                                 highlight: String? = nil,
                                 backdrop: NSColor = NSColor(white: 0.42, alpha: 1),
                                 backdropImage: NSImage? = nil) -> Data? {
        let size = NSSize(width: screenCGFrame.w, height: screenCGFrame.h)
        let view = ZoneHUDView(frame: NSRect(origin: .zero, size: size))
        view.setCells(cells, screenOrigin: (screenCGFrame.x, screenCGFrame.y))
        view.setHighlight(highlight)
        return OverlayRender.png(of: view, size: size, backdrop: backdrop, backdropImage: backdropImage)
    }
}

private final class ZoneHUDView: NSView {
    private struct Zone { let key: String; let rect: ZTRect }   // screen-local zone rectangle
    private var zones: [Zone] = []
    private var highlightedKey: String?     // tile-on-release preview: the zone the window will land in
    override var isFlipped: Bool { true }   // top-left origin to match CG coords

    func setHighlight(_ key: String?) { highlightedKey = key; needsDisplay = true }

    /// Each zone's real rectangle in screen-local coords — drawn at its true position (no
    /// de-overlap drift), with its key chip centred inside.
    func setCells(_ cells: [ZoneHUD.Cell], screenOrigin: (x: Double, y: Double)) {
        zones = cells.map { c in
            Zone(key: c.key, rect: ZTRect(x: c.rect.x - screenOrigin.x, y: c.rect.y - screenOrigin.y,
                                          w: c.rect.w, h: c.rect.h))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Light dimming so the overlay remains clean and legible without obscuring the desktop windows
        NSColor.black.withAlphaComponent(0.20).setFill()
        bounds.fill()

        // Softer, desaturated gold/amber accent matching Dieter Rams principles
        let amber = NSColor(red: 0.92, green: 0.68, blue: 0.20, alpha: 1.0)

        // 1) the zone grid — outline each zone's real rectangle.
        //    Stroke-only + 2pt inset. Thin (1.0pt) and lower opacity (0.4) for a clean look.
        //    The previewed zone (tile-on-release highlight) is filled + a brighter, thicker stroke so
        //    it's unmistakable in peripheral vision which zone "release" will land the window in.
        for z in zones {
            let r = NSRect(x: z.rect.x, y: z.rect.y, width: z.rect.w, height: z.rect.h).insetBy(dx: 2, dy: 2)
            guard r.width > 4, r.height > 4 else { continue }
            let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
            if z.key == highlightedKey {
                amber.withAlphaComponent(0.22).setFill(); path.fill()
                amber.withAlphaComponent(0.95).setStroke(); path.lineWidth = 2.0; path.stroke()
            } else {
                amber.withAlphaComponent(0.4).setStroke(); path.lineWidth = 1.0; path.stroke()
            }
        }

        // 2) the key chips — centred inside each zone.
        //    No neon glows. Chips are black with 0.75 opacity and thin 1.0pt amber borders.
        let chipW = 46.0, chipH = 38.0
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 20, weight: .bold),
            .foregroundColor: amber,
        ]
        for z in zones {
            let cx = z.rect.x + z.rect.w / 2, cy = z.rect.y + z.rect.h / 2
            let r = NSRect(x: cx - chipW / 2, y: cy - chipH / 2, width: chipW, height: chipH)
            let bg = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
            NSColor.black.withAlphaComponent(0.75).setFill(); bg.fill()
            amber.withAlphaComponent(0.7).setStroke(); bg.lineWidth = 1.0; bg.stroke()
            let label = z.key.uppercased() as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
        }
    }
}
