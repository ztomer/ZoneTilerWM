// ZoneHUDOverlay.swift — the modifier-held interactive zone picker. One click-through window over the
// target screen, lightly dimmed, that draws three honest layers (the design-consult outcome — Rams +
// Kare + Magnet/Moom/Loop): the TRUE cols×rows base grid (faint, non-overlapping — the real structure,
// not a pile of overlapping zone rects); a KEYCAP per key centred in its SMALLEST tile (its atomic
// cell, collision-split so none floats on a boundary); and a single PREVIEW FILL of the highlighted
// key's CURRENT cycle tile, so re-pressing visibly resizes the target. The actual tiling is the
// existing modifier+zone hotkey (routed through the HUD in tile-on-release mode).

import AppKit
import ZTCore

public final class ZoneHUDOverlay {
    private var window: NSWindow?
    private weak var bgView: ZoneHUDView?   // draws the grid + preview fill behind the glass caps
    public init() {}

    /// Present the picker. `tilesByKey` = each key's placement cycle (for the preview fill); `caps` =
    /// keycap centres (smallest-tile, collision-split); `gridV`/`gridH` = the true interior grid lines.
    /// All in CG screen-absolute coords.
    public func show(tilesByKey: [String: [ZTRect]], caps: [ZoneHUD.CapLabel],
                     gridV: [Double], gridH: [Double], screenCGFrame: ZTRect) {
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
            let full = NSRect(origin: .zero, size: nsFrame.size)
            let container = NSView(frame: full)
            let bg = ZoneHUDView(frame: full)
            bg.drawsCaps = false   // the glass chips draw the caps; this draws the grid + preview fill
            bg.setData(tilesByKey: tilesByKey, caps: caps, gridV: gridV, gridH: gridH,
                       screenOrigin: (screenCGFrame.x, screenCGFrame.y))
            container.addSubview(bg)
            container.addSubview(ZoneHUDOverlay.glassCaps(caps: caps,
                                 screenOrigin: (screenCGFrame.x, screenCGFrame.y), bounds: full))
            w.contentView = container
            self.bgView = bg
            w.alphaValue = 0
            w.orderFrontRegardless()   // the menubar agent isn't the active app — orderFront(nil) would no-op
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.12; w.animator().alphaValue = 1 }
            self.window = w
        }
    }

    /// Preview a zone at a specific placement in its cycle (tile-on-release): fill that tile so it reads
    /// as "release to land here". `key == nil` clears the highlight. No-op if the overlay isn't up.
    public func highlight(_ key: String?, tile: Int = 0) {
        DispatchQueue.main.async { [weak self] in
            self?.bgView?.setHighlight(key: key, tile: tile)
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

    /// One Liquid-Glass chip per zone keycap, at its smallest-tile centre — the shared template, so the
    /// zone HUD reads native like the app-launcher. Scattered (zones are far apart) so spacing is small.
    private static func glassCaps(caps: [ZoneHUD.CapLabel], screenOrigin: (x: Double, y: Double), bounds: NSRect) -> NSView {
        let chipW = 54.0, chipH = 44.0
        let (container, content) = LiquidGlass.container(frame: bounds, spacing: 6)
        for cap in caps {
            let lx = cap.x - screenOrigin.x, ly = cap.y - screenOrigin.y
            let label = ZoneKeyLabel(); label.key = cap.key
            // Dark frosted glass (NOT clear/lensing): a HUD must stay legible over ANY wallpaper, and
            // a clear chip lets a white desktop bleed through until the amber glyph washes out (field
            // bug). `.regular` frost + a strong dark tint keeps caps a consistent dark glass everywhere.
            let chip = LiquidGlass.chip(frame: NSRect(x: lx - chipW / 2, y: ly - chipH / 2, width: chipW, height: chipH),
                                        cornerRadius: 13, tint: NSColor.black.withAlphaComponent(0.55),
                                        clear: false, content: label)
            content.addSubview(chip)
        }
        return container
    }

    /// Deterministic windowless render of the picker → PNG (QA / render harness / tests). `highlight`
    /// previews `(key, tile)`, matching the live overlay.
    public static func renderPNG(tilesByKey: [String: [ZTRect]], caps: [ZoneHUD.CapLabel],
                                 gridV: [Double], gridH: [Double], screenCGFrame: ZTRect,
                                 highlight: (key: String, tile: Int)? = nil,
                                 backdrop: NSColor = NSColor(white: 0.42, alpha: 1),
                                 backdropImage: NSImage? = nil) -> Data? {
        let size = NSSize(width: screenCGFrame.w, height: screenCGFrame.h)
        let view = ZoneHUDView(frame: NSRect(origin: .zero, size: size))
        view.setData(tilesByKey: tilesByKey, caps: caps, gridV: gridV, gridH: gridH,
                     screenOrigin: (screenCGFrame.x, screenCGFrame.y))
        if let h = highlight { view.setHighlight(key: h.key, tile: h.tile) }
        return OverlayRender.png(of: view, size: size, backdrop: backdrop, backdropImage: backdropImage)
    }
}

private final class ZoneHUDView: NSView {
    private var tilesByKey: [String: [ZTRect]] = [:]   // each key's placement cycle, screen-local
    private var caps: [ZoneHUD.CapLabel] = []          // keycap centres, screen-local
    private var gridV: [Double] = []                   // interior vertical-line x's, screen-local
    private var gridH: [Double] = []                   // interior horizontal-line y's, screen-local
    private var highlightedKey: String?
    private var highlightedTile = 0
    var drawsCaps = true                                // false when glass chips draw the caps (live overlay)
    override var isFlipped: Bool { true }              // top-left origin to match CG coords

    func setData(tilesByKey: [String: [ZTRect]], caps: [ZoneHUD.CapLabel], gridV: [Double], gridH: [Double],
                 screenOrigin: (x: Double, y: Double)) {
        self.tilesByKey = tilesByKey.mapValues { tiles in
            tiles.map { ZTRect(x: $0.x - screenOrigin.x, y: $0.y - screenOrigin.y, w: $0.w, h: $0.h) }
        }
        self.caps = caps.map { ZoneHUD.CapLabel(key: $0.key, x: $0.x - screenOrigin.x, y: $0.y - screenOrigin.y) }
        self.gridV = gridV.map { $0 - screenOrigin.x }
        self.gridH = gridH.map { $0 - screenOrigin.y }
    }

    func setHighlight(key: String?, tile: Int) { highlightedKey = key; highlightedTile = tile; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        // No desktop dim — the picker floats over the LIVE desktop (the grid + caps + fill carry it).
        let amber = NSColor(red: 0.92, green: 0.68, blue: 0.20, alpha: 1.0)

        // 1) the TRUE base grid — faint interior lines (honest, non-overlapping separation).
        amber.withAlphaComponent(0.28).setStroke()
        let lines = NSBezierPath(); lines.lineWidth = 1.0
        for x in gridV where x > bounds.minX + 0.5 && x < bounds.maxX - 0.5 {
            lines.move(to: NSPoint(x: x, y: bounds.minY)); lines.line(to: NSPoint(x: x, y: bounds.maxY))
        }
        for y in gridH where y > bounds.minY + 0.5 && y < bounds.maxY - 0.5 {
            lines.move(to: NSPoint(x: bounds.minX, y: y)); lines.line(to: NSPoint(x: bounds.maxX, y: y))
        }
        lines.stroke()

        // 2) the single preview fill — the highlighted key's CURRENT cycle tile (resizes on re-press).
        if let key = highlightedKey, let tiles = tilesByKey[key], !tiles.isEmpty {
            let t = tiles[((highlightedTile % tiles.count) + tiles.count) % tiles.count]
            let r = NSRect(x: t.x, y: t.y, width: t.w, height: t.h).insetBy(dx: 2, dy: 2)
            if r.width > 4, r.height > 4 {
                let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
                amber.withAlphaComponent(0.22).setFill(); path.fill()
                amber.withAlphaComponent(0.95).setStroke(); path.lineWidth = 2.0; path.stroke()
            }
        }

        // 3) the keycaps — at smallest-tile centres (collision-split). Live, these are Liquid-Glass
        //    chips (drawsCaps=false); the headless render draws opaque chips here for the harness.
        guard drawsCaps else { return }
        let chipW = 46.0, chipH = 38.0
        let font = NSFont.monospacedSystemFont(ofSize: 20, weight: .bold)
        for cap in caps {
            let r = NSRect(x: cap.x - chipW / 2, y: cap.y - chipH / 2, width: chipW, height: chipH)
            let bg = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
            let active = cap.key == highlightedKey
            (active ? amber.withAlphaComponent(0.92) : NSColor.black.withAlphaComponent(0.78)).setFill(); bg.fill()
            (active ? NSColor.clear : amber.withAlphaComponent(0.7)).setStroke(); bg.lineWidth = 1.0; bg.stroke()
            let label = cap.key.uppercased() as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: active ? NSColor.black : amber]
            let sz = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2), withAttributes: attrs)
        }
    }
}

/// The amber key glyph that sits inside a zone-HUD glass chip.
private final class ZoneKeyLabel: NSView {
    var key: String = "" { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let amber = NSColor(red: 0.95, green: 0.72, blue: 0.24, alpha: 1.0)
        let s = key.uppercased() as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 20, weight: .bold), .foregroundColor: amber,
            .shadow: { let sh = NSShadow(); sh.shadowColor = .black; sh.shadowBlurRadius = 2; return sh }()]
        let sz = s.size(withAttributes: attrs)
        s.draw(at: NSPoint(x: bounds.midX - sz.width / 2, y: bounds.midY - sz.height / 2), withAttributes: attrs)
    }
}
