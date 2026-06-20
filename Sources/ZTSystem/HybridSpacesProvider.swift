// HybridSpacesProvider.swift — the best public-API Spaces provider: the plist's exact LAYOUT joined to
// the 1×1-marker trick's LIVE current Space, with NO private API.
//
//   • LAYOUT (count / order / per-display / UUIDs / full-screen) ← PlistSpacesReader.
//   • LIVE current Space ← a 1×1, ~invisible window pinned to each display's current Space (the
//     WhichSpace trick). `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` lists only windows on the
//     current Space of each display, so "which of a display's markers is on-screen" = its live current.
//   • JOIN (opaque marker id ⇄ plist ManagedSpaceID) ← MarkerSpaceResolver (launch-seed + elimination).
//
// We create at most one marker per Space, lazily, the first time a display's current Space lacks one —
// positioning the window inside that display's frame so it pins to THAT display's current Space (fixing
// the cursor-attribution ambiguity of the pure-marker provider). Markers persist for the session and
// are pruned when their display is unplugged. This is selected only when the plist is readable; if it
// isn't (a sandboxed App-Store build), provider selection falls through to PublicSpacesProvider.

import AppKit

public final class HybridSpacesProvider: SpacesProvider {
    public static let shared = HybridSpacesProvider()
    private init() {}

    private struct Marker { let window: NSWindow; let id: Int; let displayUUID: String }
    private var markers: [Marker] = []
    private var nextID = 1
    private var started = false
    private var map: [Int: Int] = [:]                       // markerID → ManagedSpaceID (resolver-accumulated)
    private var currentMarkerByDisplay: [String: Int] = [:] // cached live current marker per display
    private var lastOnScreenMarkers: Set<Int> = []          // our markers seen on-screen at the last rescan
    private var firstRescan = true
    private var lastPlistMTime: Date? = nil
    private var sawFirstRead = false

    public func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.prune() }
    }

    public var isAvailable: Bool { PlistSpacesReader.isAvailable }
    // Per-Space wallpapers come from the wallpaper Store plist keyed by Space UUID — a plain file read,
    // NOT a private API — so each Space's strip thumbnail shows its own wallpaper even with the toggle off.
    public func wallpapersBySpaceUUID() -> [String: NSImage] { SpacesReader.wallpapersBySpaceUUID() }

    public func spacesByDisplay() -> [String: [RealSpace]] {
        let layout = PlistSpacesReader.spacesByDisplay()
        guard !layout.isEmpty else { return [:] }

        // Self-detect a Space change at READ time (no dependence on observer ordering vs. the menubar):
        // the set of OUR markers that are on-screen changes exactly when a display switches Space. Only
        // then do we rescan/create — so a freshly-created window (not yet on-screen) can't trigger a leak.
        let onScreen = Self.onScreenWindowNumbers()
        let ourOnScreen = Set(markers.filter { onScreen.contains($0.window.windowNumber) }.map(\.id))
        if firstRescan || ourOnScreen != lastOnScreenMarkers {
            rescanMarkers(displays: Array(layout.keys), onScreen: onScreen)
            lastOnScreenMarkers = Set(markers.filter { onScreen.contains($0.window.windowNumber) }.map(\.id))
            firstRescan = false
        }

        var orderedIDs: [String: [Int]] = [:]
        var plistCurrent: [String: Int] = [:]
        for (disp, spaces) in layout {
            orderedIDs[disp] = spaces.map(\.id)
            if let cur = spaces.first(where: { $0.isCurrent })?.id { plistCurrent[disp] = cur }
        }
        let markerDisplay = Dictionary(markers.map { ($0.id, $0.displayUUID) }, uniquingKeysWith: { a, _ in a })
        let res = MarkerSpaceResolver.resolve(
            layout: orderedIDs, currentMarkerByDisplay: currentMarkerByDisplay, markerDisplay: markerDisplay,
            plistCurrent: plistCurrent, plistFresh: plistIsFresh(), prior: map)
        map = res.map

        var out: [String: [RealSpace]] = [:]
        for (disp, spaces) in layout {
            let cur = res.currentByDisplay[disp]
            out[disp] = spaces.map {
                RealSpace(id: $0.id, uuid: $0.uuid, displayUUID: $0.displayUUID,
                          isCurrent: $0.id == cur, isFullscreen: $0.isFullscreen)
            }
        }
        return out
    }

    // MARK: - freshness

    /// True on the first read and whenever the plist file has been rewritten since the last read (a Space
    /// create/delete) — the only times the plist's "Current Space" is trustworthy enough to seed from.
    private func plistIsFresh() -> Bool {
        let mt = PlistSpacesReader.sourceModified()
        let fresh = !sawFirstRead || mt != lastPlistMTime
        lastPlistMTime = mt; sawFirstRead = true
        return fresh
    }

    // MARK: - markers

    /// Re-detect each display's current marker: if one of its markers is on-screen, that's it; otherwise
    /// the current Space has no marker yet, so create one (positioned on that display, so it pins to that
    /// display's current Space) and treat it as current optimistically — a brand-new window isn't listed
    /// on-screen synchronously, so we can't wait for confirmation. Runs only on a Space/display change,
    /// which bounds markers to one per visited Space (returning to a known Space reuses its marker).
    private func rescanMarkers(displays: [String], onScreen: Set<Int>) {
        var cur = currentMarkerByDisplay
        for disp in displays {
            if let m = markers.first(where: { $0.displayUUID == disp && onScreen.contains($0.window.windowNumber) }) {
                cur[disp] = m.id
            } else if let screen = Self.screen(forUUID: disp) {
                cur[disp] = createMarker(on: screen, displayUUID: disp)
            }
        }
        currentMarkerByDisplay = cur.filter { displays.contains($0.key) }
    }

    private func createMarker(on screen: NSScreen, displayUUID: String) -> Int {
        // 1×1, ~transparent (alpha > 0 so the window server keeps it on-screen), click-through, pinned to
        // THIS Space (.stationary; explicitly NOT .canJoinAllSpaces), inside this display's frame.
        let frame = NSRect(x: screen.frame.minX + 1, y: screen.frame.minY + 1, width: 1, height: 1)
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.alphaValue = 0.02
        w.ignoresMouseEvents = true; w.hasShadow = false; w.level = .normal
        w.collectionBehavior = [.stationary, .ignoresCycle]
        w.orderFrontRegardless()
        let id = nextID; nextID += 1
        markers.append(Marker(window: w, id: id, displayUUID: displayUUID))
        return id
    }

    private func prune() {
        let connected = Set(NSScreen.screens.compactMap { Self.uuid(of: $0) })
        for g in markers where !connected.contains(g.displayUUID) { map[g.id] = nil }
        markers.removeAll { !connected.contains($0.displayUUID) }
        currentMarkerByDisplay = currentMarkerByDisplay.filter { connected.contains($0.key) }
    }

    // MARK: - leaf helpers

    private static func onScreenWindowNumbers() -> Set<Int> {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        return Set(list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue })
    }

    private static func uuid(of screen: NSScreen) -> String? {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let cf = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(num.uint32Value))?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, cf) as String?
    }

    private static func screen(forUUID uuid: String) -> NSScreen? {
        NSScreen.screens.first { Self.uuid(of: $0) == uuid }
    }
}
