// ZoneHUDOverlay.swift — the modifier-held zone cheat-sheet. One click-through window over the
// target screen, lightly dimmed, drawing each zone's region + its key label (from ZoneHUD.layout).
// Purely visual: the actual tiling is the existing modifier+zone hotkey; this just shows the map.

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
            // Cells in screen-local top-left coords (the view is flipped).
            view.cells = cells.map { (key: $0.key,
                                      rect: ZTRect(x: $0.rect.x - screenCGFrame.x, y: $0.rect.y - screenCGFrame.y,
                                                   w: $0.rect.w, h: $0.rect.h)) }
            w.contentView = view
            w.orderFront(nil)
            self.window = w
        }
    }

    public func hide() { DispatchQueue.main.async { [weak self] in self?.hideNow() } }
    private func hideNow() { window?.orderOut(nil); window = nil }
}

private final class ZoneHUDView: NSView {
    var cells: [(key: String, rect: ZTRect)] = []
    override var isFlipped: Bool { true }   // top-left origin to match CG coords

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.20).setFill()   // light dim so labels read on any desktop
        bounds.fill()
        for c in cells {
            let r = NSRect(x: c.rect.x, y: c.rect.y, width: c.rect.w, height: c.rect.h).insetBy(dx: 6, dy: 6)
            guard r.width > 12, r.height > 12 else { continue }
            let path = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
            NSColor(red: 0.98, green: 0.70, blue: 0.20, alpha: 0.14).setFill(); path.fill()
            NSColor.white.withAlphaComponent(0.32).setStroke(); path.lineWidth = 1; path.stroke()
            let label = c.key.uppercased() as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: min(40, r.height * 0.4), weight: .bold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            ]
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
        }
    }
}
