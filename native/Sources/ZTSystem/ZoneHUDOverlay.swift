// ZoneHUDOverlay.swift — the modifier-held zone cheat-sheet. One click-through window over the
// target screen, lightly dimmed, with a small key chip at each zone's centre showing "press this
// key → window lands roughly here". Chips are de-overlapped (reusing WindowHints.deoverlap) so
// the heavily-overlapping keyboard-grid zones don't collapse their labels into one amber mush —
// the earlier full-zone amber fills accumulated into a screen-wide wash and are gone. Purely
// visual: the actual tiling is the existing modifier+zone hotkey.

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
    public static func renderPNG(cells: [ZoneHUD.Cell], screenCGFrame: ZTRect,
                                 backdrop: NSColor = NSColor(white: 0.42, alpha: 1),
                                 backdropImage: NSImage? = nil) -> Data? {
        let size = NSSize(width: screenCGFrame.w, height: screenCGFrame.h)
        let view = ZoneHUDView(frame: NSRect(origin: .zero, size: size))
        view.setCells(cells, screenOrigin: (screenCGFrame.x, screenCGFrame.y))
        return OverlayRender.png(of: view, size: size, backdrop: backdrop, backdropImage: backdropImage)
    }
}

private final class ZoneHUDView: NSView {
    private struct Chip { let key: String; let rect: ZTRect }   // screen-local, deoverlapped
    private var chips: [Chip] = []
    override var isFlipped: Bool { true }   // top-left origin to match CG coords

    /// Place a de-overlapped key chip at each zone's centre (screen-local coords).
    func setCells(_ cells: [ZoneHUD.Cell], screenOrigin: (x: Double, y: Double)) {
        let chipW = 52.0, chipH = 44.0
        let wanted = cells.map { c -> ZTRect in
            let cx = c.rect.x - screenOrigin.x + c.rect.w / 2
            let cy = c.rect.y - screenOrigin.y + c.rect.h / 2
            return ZTRect(x: cx - chipW / 2, y: cy - chipH / 2, w: chipW, h: chipH)
        }
        let placed = WindowHints.deoverlap(wanted, gap: 6)
        chips = zip(cells, placed).map { Chip(key: $0.0.key, rect: $0.1) }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim enough that the HUD reads as a distinct mode over any workspace, while the windows
        // stay faintly visible underneath so you keep your bearings.
        NSColor.black.withAlphaComponent(0.55).setFill()
        bounds.fill()

        // CRT scanlines — same texture as the break screen, so the two overlays read as ONE
        // retro-terminal language (the Gemini grade flagged the missing texture as inconsistency).
        NSColor.white.withAlphaComponent(0.035).setFill()
        var sy = 0.0
        while sy < bounds.height { NSRect(x: 0, y: sy, width: bounds.width, height: 1).fill(); sy += 3 }

        let amber = NSColor(red: 0.98, green: 0.70, blue: 0.20, alpha: 1.0)
        for chip in chips {
            let r = NSRect(x: chip.rect.x, y: chip.rect.y, width: chip.rect.w, height: chip.rect.h)
            let bg = NSBezierPath(roundedRect: r, xRadius: 9, yRadius: 9)
            // soft amber glow so each chip lifts off the dim
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow(); glow.shadowColor = amber.withAlphaComponent(0.45)
            glow.shadowBlurRadius = 12; glow.shadowOffset = .zero; glow.set()
            NSColor.black.withAlphaComponent(0.88).setFill(); bg.fill()
            NSGraphicsContext.restoreGraphicsState()
            amber.setStroke(); bg.lineWidth = 2; bg.stroke()
            let label = chip.key.uppercased() as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .bold),
                .foregroundColor: amber,
            ]
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
        }
    }
}
