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
            w.orderFront(nil)
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
}

private final class ZoneHUDView: NSView {
    private struct Chip { let key: String; let rect: ZTRect }   // screen-local, deoverlapped
    private var chips: [Chip] = []
    override var isFlipped: Bool { true }   // top-left origin to match CG coords

    /// Place a de-overlapped key chip at each zone's centre (screen-local coords).
    func setCells(_ cells: [ZoneHUD.Cell], screenOrigin: (x: Double, y: Double)) {
        let chipW = 36.0, chipH = 30.0
        let wanted = cells.map { c -> ZTRect in
            let cx = c.rect.x - screenOrigin.x + c.rect.w / 2
            let cy = c.rect.y - screenOrigin.y + c.rect.h / 2
            return ZTRect(x: cx - chipW / 2, y: cy - chipH / 2, w: chipW, h: chipH)
        }
        let placed = WindowHints.deoverlap(wanted, gap: 4)
        chips = zip(cells, placed).map { Chip(key: $0.0.key, rect: $0.1) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.12).setFill()   // light dim for contrast; no amber wash
        bounds.fill()
        for chip in chips {
            let r = NSRect(x: chip.rect.x, y: chip.rect.y, width: chip.rect.w, height: chip.rect.h)
            let bg = NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7)
            NSColor.black.withAlphaComponent(0.62).setFill(); bg.fill()
            NSColor(red: 0.98, green: 0.70, blue: 0.20, alpha: 0.95).setStroke(); bg.lineWidth = 1.5; bg.stroke()
            let label = chip.key.uppercased() as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
        }
    }
}
