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
    private var searchBar: NSWindow?
    public init() {}

    /// A centered pill showing the live "/" filter query (pass nil to hide it).
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
            // Bottom-centred (above the Dock) so it never covers the Spaces strip at the top.
            win.setFrame(NSRect(x: scr.visibleFrame.midX - w / 2, y: scr.visibleFrame.minY + 30, width: w, height: h), display: true)
            win.contentView = card
            win.orderFront(nil)
            self.searchBar = win
        }
    }

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
                g.tintColor = NSColor.black.withAlphaComponent(0.16)   // a touch of depth (not milky) but lighter than 0.28, which read too dark
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

    /// During "/" search: border the matching windows + dim the rest (pass nil to clear the effect).
    public func updateMatches(_ ids: Set<Int>?) {
        DispatchQueue.main.async { [weak self] in self?.views.forEach { $0.matchedWindowIds = ids } }
    }

    public func hide() {
        DispatchQueue.main.async { [weak self] in self?.hideNow() }
    }
    private func hideNow() { windows.forEach { $0.orderOut(nil) }; windows = []; views = []; searchBar?.orderOut(nil); searchBar = nil }

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
