// MissionControlOverlay.swift — draws the Mission Control window hints (a label badge + a close (×)
// button per exposed window) from the pure ZTCore.MissionControl.Hint geometry. This is the DRAW +
// (deterministic) render half; the live half — detecting Exposé and reading tile rects via private
// CGS/SkyLight, then floating this above the exposé layer + capturing keys/clicks — is specced in
// ARCHITECTURE.md (Spaces & Exposé). Mirrors ZoneHUDOverlay: a click-through borderless window, plus a static
// renderPNG for QA / Gemini grading. Coordinates: ZTRect top-left CG (CoordConvert to NS frames).

import AppKit
import ZTCore

public final class MissionControlOverlay {
    public struct SpaceMiniWindow {
        public let key: String
        public let badgeColor: NSColor
        public let windowId: Int
        public let normRect: CGRect   // the window's position within its screen, normalised 0…1 (top-left)
        public init(key: String, badgeColor: NSColor, windowId: Int = 0,
                    normRect: CGRect = CGRect(x: 0.1, y: 0.1, width: 0.35, height: 0.35)) {
            self.key = key
            self.badgeColor = badgeColor
            self.windowId = windowId
            self.normRect = normRect
        }
    }
    public struct SpaceInfo {
        public let name: String
        public var windows: [SpaceMiniWindow]
        public let wallpaper: NSImage?
        public let isCurrent: Bool   // highlight this thumbnail as the active space
        public init(name: String, windows: [SpaceMiniWindow], wallpaper: NSImage? = nil, isCurrent: Bool = false) {
            self.name = name
            self.windows = windows
            self.wallpaper = wallpaper
            self.isCurrent = isCurrent
        }
    }

    /// A contiguous run of thumbnails that belong to one monitor (the "all monitors" combined strip
    /// draws a labelled border around each group so it's clear which spaces are on which monitor).
    public struct SpaceGroup {
        public let name: String
        public let count: Int
        public init(name: String, count: Int) { self.name = name; self.count = count }
    }

    /// One display's worth of overlay content. "All-monitors" mode builds one Panel per display
    /// (macOS "separate Spaces" forbids a single window spanning displays), so the overlay shows a
    /// window per panel.
    public struct Panel {
        public let screenCGFrame: ZTRect
        public let hints: [MissionControl.Hint]
        public let spaces: [SpaceInfo]
        public let selectedSpaceIndex: Int
        public let groups: [SpaceGroup]   // monitor groupings for the combined "all" strip ([] = flat)
        public init(screenCGFrame: ZTRect, hints: [MissionControl.Hint], spaces: [SpaceInfo] = [],
                    selectedSpaceIndex: Int = 0, groups: [SpaceGroup] = []) {
            self.screenCGFrame = screenCGFrame; self.hints = hints; self.spaces = spaces
            self.selectedSpaceIndex = selectedSpaceIndex; self.groups = groups
        }
    }

    private var windows: [NSWindow] = []
    private var views: [MissionControlView] = []
    public init() {}

    /// Callbacks shared by every panel; they operate on global window ids, so one set drives all
    /// displays. `editableSpaces=false` (all-monitors strip = monitor targets) hides the + / × chrome.
    public func show(
        panels: [Panel],
        selectedWindowId: Int? = nil,
        spacesBarPosition: String = "top",
        editableSpaces: Bool = true,
        onJump: ((Int) -> Void)? = nil,
        onClose: ((Int) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        onSelectSpace: ((Int) -> Void)? = nil,
        onAddSpace: (() -> Void)? = nil,
        onDeleteSpace: ((Int) -> Void)? = nil,
        onMoveWindowToSpace: ((Int, Int) -> Void)? = nil,
        onRenameSpace: ((Int) -> Void)? = nil
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hideNow()
            for panel in panels {
                let (w, v) = self.buildPanel(panel, selectedWindowId: selectedWindowId,
                                             spacesBarPosition: spacesBarPosition, editableSpaces: editableSpaces,
                                             onJump: onJump, onClose: onClose, onDismiss: onDismiss,
                                             onSelectSpace: onSelectSpace, onAddSpace: onAddSpace,
                                             onDeleteSpace: onDeleteSpace, onMoveWindowToSpace: onMoveWindowToSpace,
                                             onRenameSpace: onRenameSpace)
                w.orderFrontRegardless()   // the agent isn't the active app
                self.windows.append(w)
                self.views.append(v)
            }
        }
    }

    private func buildPanel(_ panel: Panel, selectedWindowId: Int?, spacesBarPosition: String, editableSpaces: Bool,
                            onJump: ((Int) -> Void)?, onClose: ((Int) -> Void)?, onDismiss: (() -> Void)?,
                            onSelectSpace: ((Int) -> Void)?, onAddSpace: (() -> Void)?, onDeleteSpace: ((Int) -> Void)?,
                            onMoveWindowToSpace: ((Int, Int) -> Void)?, onRenameSpace: ((Int) -> Void)?) -> (NSWindow, MissionControlView) {
        let nsFrame = CoordConvert.nsFrame(fromCG: panel.screenCGFrame)
        let w = NSWindow(contentRect: nsFrame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear
        w.ignoresMouseEvents = (onJump == nil && onClose == nil && onDismiss == nil)
        w.level = .statusBar; w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // Desktop wallpaper for the display this panel covers.
        let matchingScreen = NSScreen.screens.first { $0.frame.intersects(nsFrame) } ?? NSScreen.main
        let wallpaper: NSImage? = matchingScreen.flatMap { screen in
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
            return NSImage(contentsOf: url)
        }

        // Layered container (flipped to match the drawing view): wallpaper → Liquid Glass strip →
        // transparent MissionControlView on top (draws previews + strip above the glass, owns mouse).
        let container = FlippedContainerView(frame: NSRect(origin: .zero, size: nsFrame.size))

        if let wallpaper {
            let bg = NSImageView(frame: container.bounds)
            bg.image = wallpaper
            bg.imageScaling = .scaleAxesIndependently
            bg.autoresizingMask = [.width, .height]
            container.addSubview(bg)
        }

        if !panel.spaces.isEmpty {
            // A floating, rounded Liquid-Glass strip (inset from the bar edges) rather than a flat
            // full-bleed frosted panel — the latter reads as a grey blob.
            let bar = MissionControlView.barRect(position: spacesBarPosition, size: nsFrame.size).insetBy(dx: 12, dy: 12)
            let glass: NSView
            if #available(macOS 26.0, *) {
                let g = NSGlassEffectView(frame: bar)   // real macOS 26 Liquid Glass
                g.cornerRadius = 28
                g.tintColor = NSColor.black.withAlphaComponent(0.28)   // deepen it — default reads too milky-gray
                glass = g
            } else {
                let g = NSVisualEffectView(frame: bar)
                g.material = .underWindowBackground; g.blendingMode = .behindWindow; g.state = .active
                g.wantsLayer = true; g.layer?.cornerRadius = 28; g.layer?.masksToBounds = true
                glass = g
            }
            glass.autoresizingMask = [.width, .height]
            container.addSubview(glass)
        }

        let view = MissionControlView(frame: NSRect(origin: .zero, size: nsFrame.size))
        view.autoresizingMask = [.width, .height]
        view.drawsOwnBackground = false   // wallpaper image + glass material are layered behind it
        view.editableSpaces = editableSpaces
        view.groups = panel.groups
        view.set(panel.hints, screenOrigin: (panel.screenCGFrame.x, panel.screenCGFrame.y), wallpaper: wallpaper,
                 spaces: panel.spaces, selectedSpaceIndex: panel.selectedSpaceIndex, spacesBarPosition: spacesBarPosition)
        view.selectedWindowId = selectedWindowId
        view.onJump = onJump
        view.onClose = onClose
        view.onDismiss = onDismiss
        view.onSelectSpace = onSelectSpace
        view.onAddSpace = onAddSpace
        view.onDeleteSpace = onDeleteSpace
        view.onMoveWindowToSpace = onMoveWindowToSpace
        view.onRenameSpace = onRenameSpace
        container.addSubview(view)
        w.contentView = container
        return (w, view)
    }

    /// Move the keyboard selection highlight without rebuilding (arrow / vim nav). Each display's view
    /// draws the ring only for a window it actually hosts, so the highlight follows across monitors.
    public func updateSelection(_ windowId: Int?) {
        DispatchQueue.main.async { [weak self] in self?.views.forEach { $0.selectedWindowId = windowId } }
    }

    public func hide() {
        DispatchQueue.main.async { [weak self] in self?.hideNow() }
    }
    private func hideNow() { windows.forEach { $0.orderOut(nil) }; windows = []; views = [] }

    /// Deterministic windowless render (badges + × buttons) over a neutral backdrop → PNG, for QA.
    public static func renderPNG(hints: [MissionControl.Hint], screenCGFrame: ZTRect,
                                 spaces: [SpaceInfo] = [], selectedSpaceIndex: Int = 0,
                                 selectedWindowId: Int? = nil,
                                 backdrop: NSColor = NSColor(white: 0.30, alpha: 1),
                                 backdropImage: NSImage? = nil) -> Data? {
        let size = NSSize(width: screenCGFrame.w, height: screenCGFrame.h)
        let view = MissionControlView(frame: NSRect(origin: .zero, size: size))
        view.set(hints, screenOrigin: (screenCGFrame.x, screenCGFrame.y), wallpaper: backdropImage, spaces: spaces, selectedSpaceIndex: selectedSpaceIndex)
        view.selectedWindowId = selectedWindowId
        return OverlayRender.png(of: view, size: size, backdrop: backdrop, backdropImage: backdropImage)
    }
}

/// Top-left/flipped container so child frames (wallpaper, glass bar, drawing view) share the same
/// coordinate space as the flipped MissionControlView.
private final class FlippedContainerView: NSView {
    override var isFlipped: Bool { true }
}

private final class MissionControlView: NSView {
    /// The spaces-bar rect (flipped/top-left coords) for a given position + overlay size. Single
    /// source of truth for the bar geometry — used by both the live glass material and the draw pass.
    static let barThickness: CGFloat = 240
    static func barRect(position: String, size: NSSize) -> NSRect {
        switch position.lowercased() {
        case "left":   return NSRect(x: 0, y: 0, width: barThickness, height: size.height)
        case "right":  return NSRect(x: size.width - barThickness, y: 0, width: barThickness, height: size.height)
        case "bottom": return NSRect(x: 0, y: size.height - barThickness, width: size.width, height: barThickness)
        default:       return NSRect(x: 0, y: 0, width: size.width, height: barThickness)   // "top"
        }
    }

    private var hints: [MissionControl.Hint] = []
    private var origin: (x: Double, y: Double) = (0, 0)
    private var windowImages: [Int: CGImage] = [:]
    private var wallpaper: NSImage?
    
    // Spaces state
    private var spaces: [MissionControlOverlay.SpaceInfo] = []
    private var selectedSpaceIndex: Int = 0
    private var spacesBarPosition: String = "top"
    var groups: [MissionControlOverlay.SpaceGroup] = []   // monitor groupings for the combined strip

    /// Live overlay layers a wallpaper image + a Liquid Glass material behind this view, so it draws
    /// transparently. The QA renderPNG path has neither, so it keeps painting its own backdrop + bar.
    var drawsOwnBackground = true

    /// Keyboard-selected window (arrow / vim nav) — drawn with a highlight ring. nil = none.
    var selectedWindowId: Int? { didSet { if oldValue != selectedWindowId { needsDisplay = true } } }

    var onJump: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onDismiss: (() -> Void)?
    var onSelectSpace: ((Int) -> Void)?
    var onAddSpace: (() -> Void)?
    var onDeleteSpace: ((Int) -> Void)?
    var onMoveWindowToSpace: ((Int, Int) -> Void)?
    var onRenameSpace: ((Int) -> Void)?

    /// When false (all-monitors strip = monitor targets), the + / × chrome for editing virtual
    /// spaces is hidden — you can only select / drop onto the monitor thumbnails.
    var editableSpaces = true

    // Dragging state
    private var draggedWindowId: Int? = nil
    private var dragStartPoint: NSPoint = .zero
    private var dragCurrentPoint: NSPoint = .zero

    override var isFlipped: Bool { true }   // top-left origin to match CG
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var iconCache: [String: NSImage?] = [:]

    private func appIcon(for name: String) -> NSImage? {
        if name.isEmpty { return nil }
        if let cached = iconCache[name] { return cached }
        let icon = NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.icon
        iconCache[name] = icon
        return icon
    }

    private func badgeColor(for zone: String?) -> NSColor {
        guard let zone = zone?.lowercased() else {
            return NSColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 0.97) // Pastel Gray
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
                NSColor(red: 0.85, green: 0.92, blue: 0.97, alpha: 0.97),
                NSColor(red: 0.85, green: 0.95, blue: 0.88, alpha: 0.97),
                NSColor(red: 0.92, green: 0.88, blue: 0.96, alpha: 0.97),
                NSColor(red: 0.98, green: 0.92, blue: 0.85, alpha: 0.97),
                NSColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 0.97)
            ]
            let hash = abs(zone.hashValue)
            return colors[hash % colors.count]
        }
    }

    func set(_ hints: [MissionControl.Hint], screenOrigin: (x: Double, y: Double), wallpaper: NSImage? = nil, spaces: [MissionControlOverlay.SpaceInfo] = [], selectedSpaceIndex: Int = 0, spacesBarPosition: String = "top") {
        self.origin = screenOrigin
        self.wallpaper = wallpaper
        self.windowImages = [:]
        self.spaces = spaces
        self.selectedSpaceIndex = selectedSpaceIndex
        self.spacesBarPosition = spacesBarPosition
        
        var adjustedHints: [MissionControl.Hint] = []
        for h in hints {
            if let image = CGWindowListCreateImage(CGRect.null, .optionIncludingWindow, CGWindowID(h.windowId), []) {
                self.windowImages[h.windowId] = image
                
                let imgW = Double(image.width)
                let imgH = Double(image.height)
                if imgW > 0 && imgH > 0 {
                    // Calculate aspect-fitted bounds in global coordinates
                    let scale = min(h.frame.w / imgW, h.frame.h / imgH)
                    let dw = imgW * scale
                    let dh = imgH * scale
                    let dx = h.frame.x + (h.frame.w - dw) / 2
                    let dy = h.frame.y + (h.frame.h - dh) / 2
                    
                    // Center the badge inside the actual preview rect
                    let hasIcon = self.appIcon(for: h.appName) != nil
                    let bw = min(hasIcon ? 62.0 : 34.0, dw)
                    let bh = min(28.0, dh)
                    let badgeRect = ZTRect(x: dx + (dw - bw) / 2, y: dy + (dh - bh) / 2, w: bw, h: bh)
                    
                    // Position close button at the top-LEFT corner of the preview rect (macOS-native
                    // side), slightly larger than before.
                    let cs = 26.0
                    let inset = 4.0
                    let closeRect = ZTRect(x: dx + inset, y: dy + inset, w: cs, h: cs)
                    
                    adjustedHints.append(MissionControl.Hint(
                        windowId: h.windowId,
                        label: h.label,
                        frame: h.frame,
                        badge: badgeRect,
                        close: closeRect,
                        appName: h.appName,
                        zoneKey: h.zoneKey
                    ))
                } else {
                    adjustedHints.append(h)
                }
            } else {
                adjustedHints.append(h)
            }
        }
        self.hints = adjustedHints

        // Also capture screenshots for any window shown in a strip thumbnail (so every monitor's
        // thumbnail renders real mini-previews, not just the windows in this panel's grid). All are
        // on-screen → capture succeeds. 0 AX (CGWindowList).
        for sp in spaces {
            for win in sp.windows where win.windowId != 0 && windowImages[win.windowId] == nil {
                if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(win.windowId), []) {
                    windowImages[win.windowId] = image
                }
            }
        }
    }

    /// Draw a CGImage upright inside `rect` in this flipped view (file-loaded wallpapers otherwise
    /// render upside-down here).
    private func drawUpright(_ cg: CGImage, in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    private func spacesBarGeometry(bounds: NSRect) -> (bar: NSRect, thumbs: [NSRect], closeButtons: [NSRect], plus: NSRect) {
        let pos = spacesBarPosition.lowercased()
        let barRect = Self.barRect(position: pos, size: bounds.size)

        let thumbW: CGFloat = 210, thumbH: CGFloat = 135, plusSize: CGFloat = 135, gap: CGFloat = 20
        let n = spaces.count
        var thumbs: [NSRect] = []
        var closeButtons: [NSRect] = []
        let horizontal = (pos != "left" && pos != "right")

        func appendThumb(_ t: NSRect) {
            thumbs.append(t)
            // Close (×) at the thumbnail's top-left corner.
            closeButtons.append(NSRect(x: t.minX - 6, y: t.minY - 6, width: 24, height: 24))
        }

        // The + button only exists when spaces are editable; otherwise the group is just the thumbs.
        let plusExtent = editableSpaces ? (gap + plusSize) : 0

        // Extra spacing inserted before each monitor group's first thumbnail (combined strip).
        let groupGap: CGFloat = 56
        var groupStart = Set<Int>()
        if !groups.isEmpty { var acc = 0; for g in groups { if acc > 0 { groupStart.insert(acc) }; acc += g.count } }
        let groupExtent = CGFloat(max(0, groups.count - 1)) * groupGap

        let plusRect: NSRect
        if horizontal {
            // Centre the whole [thumb … thumb (+)] group across the bar width (with monitor-group gaps).
            let totalW = CGFloat(n) * thumbW + CGFloat(max(0, n - 1)) * gap + groupExtent + plusExtent
            let y: CGFloat = (pos == "bottom") ? bounds.height - 240 + 40 : 40
            var x = (bounds.width - totalW) / 2
            for i in 0..<n {
                if groupStart.contains(i) { x += groupGap }
                appendThumb(NSRect(x: x, y: y, width: thumbW, height: thumbH))
                x += thumbW + (i < n - 1 || editableSpaces ? gap : 0)
            }
            plusRect = NSRect(x: x, y: y + (thumbH - plusSize) / 2, width: plusSize, height: plusSize)
        } else {
            // Vertical bar: centre the group across the bar height.
            let totalH = CGFloat(n) * thumbH + CGFloat(max(0, n - 1)) * gap + plusExtent
            let x: CGFloat = (pos == "right") ? bounds.width - 240 + 15 : 15
            var y = (bounds.height - totalH) / 2
            for i in 0..<n { appendThumb(NSRect(x: x, y: y, width: thumbW, height: thumbH)); y += thumbH + (i < n - 1 || editableSpaces ? gap : 0) }
            plusRect = NSRect(x: x + (thumbW - plusSize) / 2, y: y, width: plusSize, height: plusSize)
        }

        return (barRect, thumbs, closeButtons, plusRect)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)   // local flipped (top-left)
        
        // 1. Check if spaces bar hit
        if !spaces.isEmpty {
            let geom = spacesBarGeometry(bounds: bounds)
            if geom.bar.contains(p) {
                // Check space close buttons (x) if count > 1 (only when spaces are editable)
                if editableSpaces && spaces.count > 1 {
                    for i in 0..<spaces.count {
                        if geom.closeButtons[i].contains(p) {
                            onDeleteSpace?(i)
                            return
                        }
                    }
                }

                // Check space thumbnails — single-click switches, double-click renames.
                for i in 0..<spaces.count {
                    if geom.thumbs[i].contains(p) {
                        if event.clickCount >= 2 { onRenameSpace?(i) } else { onSelectSpace?(i) }
                        return
                    }
                }

                // Check plus button (only when spaces are editable)
                if editableSpaces && geom.plus.contains(p) {
                    onAddSpace?()
                    return
                }
                
                // clicked spaces bar empty space, do nothing
                return
            }
        }
        
        // 2. Check window close button (×)
        let cx = Double(p.x) + origin.x
        let cy = Double(p.y) + origin.y
        if let id = MissionControl.closeHit(at: cx, cy, in: hints) {
            onClose?(id)
            return
        }
        
        // 3. Check window grid preview click to start dragging
        for h in hints {
            let tf = local(h.frame)
            if tf.contains(p) {
                draggedWindowId = h.windowId
                dragStartPoint = p
                dragCurrentPoint = p
                needsDisplay = true
                return
            }
        }
        
        // Clicked empty grid space, dismiss
        onDismiss?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard draggedWindowId != nil else { return }
        let p = convert(event.locationInWindow, from: nil)
        dragCurrentPoint = p
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let wid = draggedWindowId else { return }
        let p = convert(event.locationInWindow, from: nil)
        
        let dx = p.x - dragStartPoint.x
        let dy = p.y - dragStartPoint.y
        let distance = sqrt(dx*dx + dy*dy)
        
        if distance > 5.0 {
            // Drop over the strip → move to the closest thumbnail (a virtual space in "active" mode,
            // or a monitor target in "all" mode — the controller's callback interprets the index).
            if !spaces.isEmpty {
                let geom = spacesBarGeometry(bounds: bounds)
                if geom.bar.contains(p) {
                    var closestIdx = 0
                    var minDist = CGFloat.infinity
                    for i in 0..<spaces.count {
                        let center = NSPoint(x: geom.thumbs[i].midX, y: geom.thumbs[i].midY)
                        let dist = sqrt(pow(center.x - p.x, 2) + pow(center.y - p.y, 2))
                        if dist < minDist { minDist = dist; closestIdx = i }
                    }
                    onMoveWindowToSpace?(wid, closestIdx)
                }
            }
        } else {
            // Regular click/tap on the preview window to jump
            onJump?(wid)
        }
        
        draggedWindowId = nil
        needsDisplay = true
    }

    private func local(_ r: ZTRect) -> NSRect {
        NSRect(x: r.x - origin.x, y: r.y - origin.y, width: r.w, height: r.h)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Backdrop is drawn here ONLY for the windowless QA render; the live overlay layers a
        // wallpaper NSImageView + a Liquid Glass NSVisualEffectView behind this (transparent) view.
        if drawsOwnBackground {
            if let wallpaper = self.wallpaper {
                wallpaper.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
            } else {
                NSColor(white: 0.15, alpha: 1.0).setFill()
                bounds.fill()
            }
        }

        // Draw Spaces Bar
        if !spaces.isEmpty {
            let geom = spacesBarGeometry(bounds: bounds)

            // Flat bar background only in the QA render; live uses the glass material behind the view.
            if drawsOwnBackground {
                NSColor.black.withAlphaComponent(0.45).setFill()
                geom.bar.fill()
            }

            // Hard divider line only in the QA render; the live floating glass panel needs none.
            if drawsOwnBackground {
                let dividerRect: NSRect
                let pos = spacesBarPosition.lowercased()
                if pos == "left" {
                    dividerRect = NSRect(x: geom.bar.width - 1, y: 0, width: 1, height: bounds.height)
                } else if pos == "right" {
                    dividerRect = NSRect(x: geom.bar.minX, y: 0, width: 1, height: bounds.height)
                } else if pos == "bottom" {
                    dividerRect = NSRect(x: 0, y: geom.bar.minY, width: bounds.width, height: 1)
                } else {
                    dividerRect = NSRect(x: 0, y: geom.bar.height - 1, width: bounds.width, height: 1)
                }
                NSColor.white.withAlphaComponent(0.12).setFill()
                dividerRect.fill()
            }

            // Draw a labelled rounded border around each monitor group (combined "all" strip) so it's
            // clear which spaces belong to which monitor.
            if !groups.isEmpty {
                var idx = 0
                for g in groups where g.count > 0 && idx < geom.thumbs.count {
                    let slice = geom.thumbs[idx..<min(idx + g.count, geom.thumbs.count)]
                    var u = slice.first!
                    for r in slice { u = u.union(r) }
                    let box = u.insetBy(dx: -12, dy: -12)
                    let path = NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10)
                    NSColor.white.withAlphaComponent(0.06).setFill(); path.fill()
                    NSColor.white.withAlphaComponent(0.35).setStroke(); path.lineWidth = 1.5; path.stroke()
                    let label = g.name as NSString
                    let la: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                        .foregroundColor: NSColor.white.withAlphaComponent(0.85)
                    ]
                    label.draw(at: NSPoint(x: box.minX + 6, y: box.minY - 16), withAttributes: la)
                    idx += g.count
                }
            }

            // Draw spaces thumbnails
            for i in 0..<spaces.count {
                let thumbRect = geom.thumbs[i]
                
                // Draw thumbnail background — the actual desktop wallpaper, UPRIGHT (#1), clipped to the
                // rounded thumb. space.wallpaper is the real per-monitor wallpaper in all-mode; else the
                // panel's own (so virtual-space thumbs all show the correct current wallpaper, #2).
                let space = spaces[i]
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: thumbRect, xRadius: 4, yRadius: 4).addClip()
                if let wp = space.wallpaper ?? self.wallpaper,
                   let cg = wp.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    drawUpright(cg, in: thumbRect)
                } else {
                    NSColor(white: 0.1, alpha: 0.8).setFill(); thumbRect.fill()
                }
                NSGraphicsContext.restoreGraphicsState()
                
                // Draw selection highlight or border (the current space gets the accent ring)
                if space.isCurrent {
                    NSColor.keyboardFocusIndicatorColor.setStroke()
                    let path = NSBezierPath(roundedRect: thumbRect, xRadius: 4, yRadius: 4)
                    path.lineWidth = 2.0
                    path.stroke()
                } else {
                    NSColor.white.withAlphaComponent(0.2).setStroke()
                    let path = NSBezierPath(roundedRect: thumbRect, xRadius: 4, yRadius: 4)
                    path.lineWidth = 1.0
                    path.stroke()
                }

                // Draw space name centered below the thumbnail
                let name = space.name as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: space.isCurrent ? NSColor.keyboardFocusIndicatorColor : NSColor.secondaryLabelColor
                ]
                let nameSize = name.size(withAttributes: attrs)
                name.draw(at: NSPoint(x: thumbRect.midX - nameSize.width / 2, y: thumbRect.maxY + 4), withAttributes: attrs)
                
                // Draw each window as a real mini-screenshot at its true on-screen position (#3) — a
                // faithful miniature of the desktop, clipped to the thumbnail (replaces the random
                // colored chips). Falls back to a colored box only if a screenshot is unavailable.
                if !space.windows.isEmpty {
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(roundedRect: thumbRect, xRadius: 4, yRadius: 4).addClip()
                    for win in space.windows {
                        let nr = win.normRect
                        let r = NSRect(x: thumbRect.minX + nr.minX * thumbRect.width,
                                       y: thumbRect.minY + nr.minY * thumbRect.height,
                                       width: max(6, nr.width * thumbRect.width),
                                       height: max(6, nr.height * thumbRect.height))
                        let rp = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)
                        if let img = windowImages[win.windowId] {
                            NSGraphicsContext.saveGraphicsState()
                            rp.addClip()
                            drawUpright(img, in: r)
                            NSGraphicsContext.restoreGraphicsState()
                        } else {
                            win.badgeColor.withAlphaComponent(0.85).setFill(); rp.fill()
                        }
                        NSColor.black.withAlphaComponent(0.55).setStroke(); rp.lineWidth = 0.75; rp.stroke()
                    }
                    NSGraphicsContext.restoreGraphicsState()
                }
                
                // Draw space delete button (x) (larger) — only when spaces are editable.
                if editableSpaces && spaces.count > 1 {
                    let closeRect = geom.closeButtons[i]
                    let closePath = NSBezierPath(ovalIn: closeRect)
                    NSColor.gray.withAlphaComponent(0.85).setFill()
                    closePath.fill()
                    let xStr = "×" as NSString
                    let xattrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 16, weight: .bold),
                        .foregroundColor: NSColor.white
                    ]
                    let xsz = xStr.size(withAttributes: xattrs)
                    xStr.draw(at: NSPoint(x: closeRect.midX - xsz.width / 2, y: closeRect.midY - xsz.height / 2 - 1), withAttributes: xattrs)
                }
            }
            
            // Draw plus button (larger) — only when spaces are editable (hidden for monitor targets).
            if editableSpaces {
                let plusRect = geom.plus
                let plusPath = NSBezierPath(roundedRect: plusRect, xRadius: 4, yRadius: 4)
                NSColor.white.withAlphaComponent(0.1).setFill()
                plusPath.fill()

                NSColor.white.withAlphaComponent(0.3).setStroke()
                plusPath.lineWidth = 1.0
                plusPath.stroke()

                let plusStr = "+" as NSString
                let pattrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 40, weight: .medium),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.6)
                ]
                let psz = plusStr.size(withAttributes: pattrs)
                plusStr.draw(at: NSPoint(x: plusRect.midX - psz.width / 2, y: plusRect.midY - psz.height / 2), withAttributes: pattrs)
            }
        }

        // Draw grid preview windows
        for h in hints {
            var tf = local(h.frame)
            var b = local(h.badge)
            var c = local(h.close)

            // The PREVIEW rect = the screenshot aspect-fitted inside the tile. The badge, close (×) and
            // selection ring all conform to THIS rect so they hug the screenshot, not the letterboxed
            // tile (prettier + the × stays pinned to the screenshot's top-left corner).
            var pf = tf
            if let image = windowImages[h.windowId], image.width > 0, image.height > 0 {
                let scale = min(tf.width / CGFloat(image.width), tf.height / CGFloat(image.height))
                let dw = CGFloat(image.width) * scale, dh = CGFloat(image.height) * scale
                pf = NSRect(x: tf.minX + (tf.width - dw) / 2, y: tf.minY + (tf.height - dh) / 2, width: dw, height: dh)
            }

            // Apply drag translations
            if draggedWindowId == h.windowId {
                let dx = dragCurrentPoint.x - dragStartPoint.x
                let dy = dragCurrentPoint.y - dragStartPoint.y
                tf = tf.offsetBy(dx: dx, dy: dy); pf = pf.offsetBy(dx: dx, dy: dy)
                b = b.offsetBy(dx: dx, dy: dy); c = c.offsetBy(dx: dx, dy: dy)
            }

            if pf.width > 10 && pf.height > 10 {
                let path = NSBezierPath(roundedRect: pf, xRadius: 8, yRadius: 8)
                // Draw the actual window screenshot, rounded to the preview rect.
                if let image = windowImages[h.windowId] {
                    NSGraphicsContext.saveGraphicsState()
                    path.addClip()
                    NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                        .draw(in: pf, from: .zero, operation: .sourceOver, fraction: 1.0)
                    NSGraphicsContext.restoreGraphicsState()
                } else {
                    NSColor.white.withAlphaComponent(0.08).setFill()
                    path.fill()
                }

                // Keyboard-selection ring hugging the screenshot (#6).
                if h.windowId == selectedWindowId {
                    let ring = NSBezierPath(roundedRect: pf.insetBy(dx: -2, dy: -2), xRadius: 10, yRadius: 10)
                    NSColor.controlAccentColor.setStroke(); ring.lineWidth = 3.5; ring.stroke()
                }
            }

            // Label badge — pastel color chip + dark border + icon + key.
            let chip = NSBezierPath(roundedRect: b, xRadius: 6, yRadius: 6)
            badgeColor(for: h.zoneKey).setFill(); chip.fill()
            NSColor.black.withAlphaComponent(0.85).setStroke(); chip.lineWidth = 1.5; chip.stroke()

            let label = h.label.uppercased() as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold),
                .foregroundColor: NSColor.black,
            ]
            let sz = label.size(withAttributes: attrs)

            if let icon = appIcon(for: h.appName) {
                // Draw icon on the left
                let iconSize: CGFloat = 18.0
                let iconRect = NSRect(
                    x: b.minX + 6,
                    y: b.minY + (b.height - iconSize) / 2,
                    width: iconSize,
                    height: iconSize
                )
                icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)

                // Center the key letter in the remaining space
                let remainingCenterX = (b.minX + 6 + iconSize + 6 + b.maxX) / 2.0
                label.draw(
                    at: NSPoint(x: remainingCenterX - sz.width / 2, y: b.midY - sz.height / 2),
                    withAttributes: attrs
                )
            } else {
                // Center key letter fully
                label.draw(
                    at: NSPoint(x: b.midX - sz.width / 2, y: b.midY - sz.height / 2),
                    withAttributes: attrs
                )
            }

            // Close (×) button — red disc + white cross at the tile's top-right.
            let disc = NSBezierPath(ovalIn: c)
            NSColor.systemRed.withAlphaComponent(0.92).setFill(); disc.fill()
            let x = NSBezierPath(); let pad = c.width * 0.3
            x.move(to: NSPoint(x: c.minX + pad, y: c.minY + pad)); x.line(to: NSPoint(x: c.maxX - pad, y: c.maxY - pad))
            x.move(to: NSPoint(x: c.maxX - pad, y: c.minY + pad)); x.line(to: NSPoint(x: c.minX + pad, y: c.maxY - pad))
            NSColor.white.setStroke(); x.lineWidth = 1.6; x.lineCapStyle = .round; x.stroke()
        }
    }
}
