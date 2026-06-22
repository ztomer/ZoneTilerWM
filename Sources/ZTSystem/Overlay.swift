// Overlay.swift — lightweight on-screen overlays (borderless click-through windows):
// a focus flash and the Pomodoro color bar. Purely visual; validate in a UI round.
//
// Coordinates: ZTRect is top-left CG; NSWindow frames are bottom-left global. CoordConvert
// flips using the primary display height (CGDisplayBounds(main)). A flip bug here is the
// most likely visual regression.

import AppKit
import ZTCore

enum CoordConvert {
    /// Convert a top-left CG rect to a bottom-left global NSRect for NSWindow placement.
    static func nsFrame(fromCG r: ZTRect) -> NSRect {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        return NSRect(x: r.x, y: primaryHeight - r.y - r.h, width: r.w, height: r.h)
    }
}

private func makeOverlayWindow(_ frame: NSRect, color: NSColor) -> NSWindow {
    let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    w.isOpaque = false
    w.backgroundColor = color
    w.ignoresMouseEvents = true
    w.level = .statusBar
    w.hasShadow = false
    w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    return w
}

/// Resize-mode grid overlay: cyan "Tron" grid lines (port of grid_overlay.lua) covering a
/// screen, drawn from ZTCore's GridLines geometry so offsets shift the lines live.
final class GridOverlayView: NSView {
    var vertical: [CGFloat] = []     // x positions, relative to view left (top-left origin)
    var horizontal: [CGFloat] = []   // y positions, relative to view top
    override var isFlipped: Bool { true }   // top-left origin to match CG coords

    override func draw(_ dirtyRect: NSRect) {
        let line = NSColor(red: 0, green: 0.8, blue: 1, alpha: 0.8)
        NSColor(red: 0, green: 0.2, blue: 0.3, alpha: 0.1).setFill()
        bounds.fill()
        line.setStroke()
        let path = NSBezierPath(); path.lineWidth = 4
        for x in vertical { path.move(to: NSPoint(x: x, y: 0)); path.line(to: NSPoint(x: x, y: bounds.height)) }
        for y in horizontal { path.move(to: NSPoint(x: 0, y: y)); path.line(to: NSPoint(x: bounds.width, y: y)) }
        path.stroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 5, dy: 5)); border.lineWidth = 10
        NSColor(red: 0, green: 0.8, blue: 1, alpha: 0.3).setStroke(); border.stroke()
    }
}

public final class GridOverlay {
    private var window: NSWindow?
    private var view: GridOverlayView?
    public init() {}

    /// Show/update lines on the screen whose top-left CG full-frame is `screenCGFrame`.
    /// `verticalX`/`horizontalY` are absolute top-left CG coordinates (from GridLines.positions).
    public func show(screenCGFrame: ZTRect, verticalX: [Double], horizontalY: [Double]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let nsFrame = CoordConvert.nsFrame(fromCG: screenCGFrame)
            let v = self.window ?? makeOverlayWindow(nsFrame, color: .clear)
            v.setFrame(nsFrame, display: false)
            let view = self.view ?? GridOverlayView(frame: NSRect(origin: .zero, size: nsFrame.size))
            view.frame = NSRect(origin: .zero, size: nsFrame.size)
            view.vertical = verticalX.map { CGFloat($0 - screenCGFrame.x) }       // → view-relative
            view.horizontal = horizontalY.map { CGFloat($0 - screenCGFrame.y) }
            view.needsDisplay = true
            v.contentView = view
            v.orderFront(nil)
            self.window = v; self.view = view
        }
    }

    public func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.window?.orderOut(nil); self?.window = nil; self?.view = nil
        }
    }
}

/// Window-hints overlay: a small label badge centered on each window (port of the visual
/// half of hs.hints.windowHints). The key capture lives in the agent's hints modal.
public final class HintOverlay {
    private var windows: [NSWindow] = []
    private var searchBar: NSWindow?
    private var highlightWindows: [NSWindow] = []
    public init() {}

    /// During "/" search: draw an accent border around each matching window's real frame (clears any
    /// previous highlights; pass [] to clear). Click-through outline windows over the live desktop.
    public func showHighlights(_ frames: [ZTRect]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.highlightWindows.forEach { $0.orderOut(nil) }
            self.highlightWindows = []
            for f in frames {
                let w = NSWindow(contentRect: CoordConvert.nsFrame(fromCG: f), styleMask: .borderless, backing: .buffered, defer: false)
                w.isOpaque = false; w.backgroundColor = .clear; w.ignoresMouseEvents = true
                w.level = .statusBar; w.hasShadow = false
                w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                let v = NSView(frame: NSRect(origin: .zero, size: w.frame.size))
                v.wantsLayer = true
                v.layer?.borderColor = NSColor.controlAccentColor.cgColor
                v.layer?.borderWidth = 3
                v.layer?.cornerRadius = 8
                w.contentView = v
                w.orderFront(nil)
                self.highlightWindows.append(w)
            }
        }
    }

    /// A small centered pill showing the live "/" filter query (pass nil to hide it).
    public func setSearchBar(_ text: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let text, let scr = NSScreen.main else { self.searchBar?.orderOut(nil); self.searchBar = nil; return }
            let label = NSTextField(labelWithString: text)
            label.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
            label.textColor = .white
            label.sizeToFit()
            let w = max(240, label.frame.width + 36), h: CGFloat = 38
            let card = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
            card.wantsLayer = true
            card.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
            card.layer?.cornerRadius = 10
            label.frame = NSRect(x: (w - label.frame.width) / 2, y: (h - label.frame.height) / 2,
                                 width: label.frame.width, height: label.frame.height)
            card.addSubview(label)
            let win = self.searchBar ?? NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            win.isOpaque = false; win.backgroundColor = .clear; win.ignoresMouseEvents = true
            win.level = .statusBar; win.hasShadow = true
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            // Bottom-centred (above the Dock) — same position as the Exposé search, clear of the
            // Spaces strip / top-of-screen content.
            win.setFrame(NSRect(x: scr.visibleFrame.midX - w / 2, y: scr.visibleFrame.minY + 30, width: w, height: h), display: true)
            win.contentView = card
            win.orderFront(nil)
            self.searchBar = win
        }
    }

    /// Show a hint badge centered on each window: app icon (recognition) + the key (the action)
    /// + the app name (a small confirm). `center` is the window's top-left CG center point.
    public func show(_ hints: [(label: String, app: String, icon: NSImage?, center: ZTRect, zone: String?)]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.clear()
            // Build each badge + its desired center-anchored rect first, then de-overlap so badges
            // for stacked/overlapping windows don't hide one another (they dodge downward).
            let built = hints.map { h -> (badge: NSView, rect: ZTRect) in
                let (badge, size) = HintOverlay.makeBadge(label: h.label, app: h.app, icon: h.icon, zone: h.zone)
                return (badge, ZTRect(x: h.center.x - size.width / 2, y: h.center.y - size.height / 2,
                                      w: size.width, h: size.height))
            }
            let placed = WindowHints.deoverlap(built.map { $0.rect })
            for (item, rect) in zip(built, placed) {
                let w = NSWindow(contentRect: CoordConvert.nsFrame(fromCG: rect),
                                 styleMask: .borderless, backing: .buffered, defer: false)
                w.isOpaque = false
                w.backgroundColor = .clear
                w.ignoresMouseEvents = true
                w.level = .statusBar
                w.hasShadow = true
                w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                w.contentView = item.badge
                w.orderFront(nil)
                self.windows.append(w)
            }
        }
    }

    /// A badge: [icon] [KEY] [name], black on the zone's pastel color, sized to its content.
    private static func makeBadge(label: String, app: String, icon: NSImage?, zone: String?) -> (NSView, NSSize) {
        let h: CGFloat = 38, pad: CGFloat = 9, gap: CGFloat = 7, iconSize: CGFloat = 22
        let key = NSTextField(labelWithString: label.uppercased())
        key.font = .monospacedSystemFont(ofSize: 18, weight: .bold)
        key.textColor = .black
        key.sizeToFit()
        let name = NSTextField(labelWithString: app)
        name.font = .systemFont(ofSize: 12, weight: .medium)
        name.textColor = NSColor.black.withAlphaComponent(0.75)
        name.lineBreakMode = .byTruncatingTail
        name.sizeToFit()
        let nameW = min(name.frame.width, 170)

        var x = pad
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = HintOverlay.color(for: zone).cgColor
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1.5
        container.layer?.borderColor = NSColor.black.withAlphaComponent(0.85).cgColor

        if let icon {
            let iv = NSImageView(frame: NSRect(x: x, y: (h - iconSize) / 2, width: iconSize, height: iconSize))
            iv.image = icon
            iv.imageScaling = .scaleProportionallyUpOrDown
            container.addSubview(iv)
            x += iconSize + gap
        }
        key.frame = NSRect(x: x, y: (h - key.frame.height) / 2, width: key.frame.width, height: key.frame.height)
        container.addSubview(key)
        x += key.frame.width + gap
        if !app.isEmpty {
            name.frame = NSRect(x: x, y: (h - name.frame.height) / 2, width: nameW, height: name.frame.height)
            container.addSubview(name)
            x += nameW
        }
        let total = NSSize(width: x + pad, height: h)
        container.frame = NSRect(origin: .zero, size: total)
        return (container, total)
    }

    private static func color(for zone: String?) -> NSColor {
        guard let zone = zone?.lowercased() else {
            return NSColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 0.97) // Pastel Gray (Floating/None)
        }
        switch zone {
        case "h", "left":
            return NSColor(red: 0.85, green: 0.92, blue: 0.97, alpha: 0.97) // Pastel Blue
        case "l", "right":
            return NSColor(red: 0.85, green: 0.95, blue: 0.88, alpha: 0.97) // Pastel Green
        case "k", "top":
            return NSColor(red: 0.92, green: 0.88, blue: 0.96, alpha: 0.97) // Pastel Purple
        case "j", "bottom":
            return NSColor(red: 0.98, green: 0.92, blue: 0.85, alpha: 0.97) // Pastel Orange
        case "c", "center":
            return NSColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 0.97)  // Pastel Yellow/Amber
        default:
            let colors = [
                NSColor(red: 0.85, green: 0.92, blue: 0.97, alpha: 0.97), // Blue
                NSColor(red: 0.85, green: 0.95, blue: 0.88, alpha: 0.97), // Green
                NSColor(red: 0.92, green: 0.88, blue: 0.96, alpha: 0.97), // Purple
                NSColor(red: 0.98, green: 0.92, blue: 0.85, alpha: 0.97), // Orange
                NSColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 0.97)  // Yellow/Amber
            ]
            let hash = abs(zone.hashValue)
            return colors[hash % colors.count]
        }
    }

    public func hide() { DispatchQueue.main.async { [weak self] in self?.clear() } }

    private func clear() {
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        highlightWindows.forEach { $0.orderOut(nil) }; highlightWindows = []
        searchBar?.orderOut(nil); searchBar = nil
    }
}

/// A brief translucent highlight over a window's frame (focus/tile feedback).
public final class FlashOverlay {
    private var window: NSWindow?
    private var hideWork: DispatchWorkItem?
    public init() {}

    /// Flash uses the user's system accent color by default (NSColor.controlAccentColor), which
    /// adapts to light/dark appearance and the user's chosen accent. A crisp accent border keeps
    /// it legible over windows of any color. Pass `color` to override.
    public func flash(_ rect: ZTRect, duration: Double = 0.2, color: NSColor? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let accent = color ?? .controlAccentColor
            self.hideWork?.cancel()
            self.window?.orderOut(nil)
            let w = makeOverlayWindow(CoordConvert.nsFrame(fromCG: rect), color: .clear)
            let v = NSView(frame: NSRect(origin: .zero, size: CoordConvert.nsFrame(fromCG: rect).size))
            v.wantsLayer = true
            v.layer?.backgroundColor = accent.withAlphaComponent(0.22).cgColor
            v.layer?.borderColor = accent.withAlphaComponent(0.9).cgColor
            v.layer?.borderWidth = 2
            v.layer?.cornerRadius = 6
            w.contentView = v
            w.orderFront(nil)
            self.window = w
            let work = DispatchWorkItem { [weak self] in self?.window?.orderOut(nil); self?.window = nil }
            self.hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }
    }
}

/// Two thin strips at the top of the main screen: used (left) + remaining (right).
public final class PomodoroBar {
    private var usedWindow: NSWindow?
    private var remainingWindow: NSWindow?
    public init() {}

    /// Pure geometry: the two top-edge strips (used on the left, remaining on the right) in
    /// top-left CG coords, mirroring pomodoor.lua's `pom_draw_on_menu`. `menubarHeight` is the
    /// screen's menubar thickness; bar height = indicator_height ratio of it (min 2px).
    public static func layout(timeLeft: Int, maxTime: Int, heightRatio: Double,
                              fullFrame: CGRect, menubarHeight: Double) -> (used: ZTRect, remaining: ZTRect) {
        let barHeight = max(2.0, menubarHeight * heightRatio)
        let ratio = maxTime > 0 ? max(0, min(1, Double(timeLeft) / Double(maxTime))) : 0
        let remainingW = fullFrame.width * ratio
        let usedW = fullFrame.width - remainingW
        let used = ZTRect(x: fullFrame.minX, y: fullFrame.minY, w: usedW, h: barHeight)
        let remaining = ZTRect(x: fullFrame.minX + usedW, y: fullFrame.minY, w: remainingW, h: barHeight)
        return (used, remaining)
    }

    public func update(timeLeft: Int, maxTime: Int, heightRatio: Double, alpha: Double,
                       remaining: NSColor, used: NSColor) {
        DispatchQueue.main.async { [weak self] in
            guard let self, maxTime > 0 else { return }
            let rects = PomodoroBar.layout(timeLeft: timeLeft, maxTime: maxTime, heightRatio: heightRatio,
                                           fullFrame: CGDisplayBounds(CGMainDisplayID()),
                                           menubarHeight: PomodoroBar.mainMenubarHeight())
            self.usedWindow = self.place(self.usedWindow, rects.used, used.withAlphaComponent(alpha))
            self.remainingWindow = self.place(self.remainingWindow, rects.remaining, remaining.withAlphaComponent(alpha))
        }
    }

    public func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.usedWindow?.orderOut(nil); self?.usedWindow = nil
            self?.remainingWindow?.orderOut(nil); self?.remainingWindow = nil
        }
    }

    /// Menubar thickness for the main screen, in CG points: NSScreen.frame.height minus
    /// visibleFrame.height isn't right (that also nets the Dock); use the explicit menubar
    /// inset = frame.maxY - visibleFrame.maxY (top gap), matching Lua's frame.y delta.
    static func mainMenubarHeight() -> Double {
        guard let s = NSScreen.main else { return 24 }
        let delta = s.frame.maxY - s.visibleFrame.maxY
        return delta > 0 ? Double(delta) : 24
    }

    /// Resolve the small set of color names the Lua config uses to NSColor (falls back to a
    /// hashed-name gray for anything unrecognized, never crashes).
    public static func color(named name: String) -> NSColor {
        switch name.lowercased() {
        case "green": return .systemGreen
        case "red": return .systemRed
        case "blue": return .systemBlue
        case "yellow": return .systemYellow
        case "orange": return .systemOrange
        case "purple": return .systemPurple
        case "white": return .white
        case "black": return .black
        case "accent": return ZTPalette.accent   // the app's functional accent (#FF6B00)
        default: return .gray
        }
    }

    private func place(_ existing: NSWindow?, _ rect: ZTRect, _ color: NSColor) -> NSWindow {
        let frame = CoordConvert.nsFrame(fromCG: rect)
        if let w = existing {
            w.setFrame(frame, display: true)
            w.backgroundColor = color
            w.orderFront(nil)
            return w
        }
        let w = makeOverlayWindow(frame, color: color)
        w.orderFront(nil)
        return w
    }
}
