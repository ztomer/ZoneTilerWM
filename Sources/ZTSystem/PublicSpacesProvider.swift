// PublicSpacesProvider.swift — the App-Store-safe Spaces provider (no private CGS/SkyLight).
//
// Technique (WhichSpace / AirSpace): you can't enumerate Spaces with public API, but you CAN pin a
// tiny invisible window to ONE Space (a window without `.canJoinAllSpaces` stays on the Space it was
// ordered onto), and `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` lists only the windows on the
// *active* Space. So we drop one marker window per Space as the user visits it, and "which marker is
// on-screen right now" identifies the current Space. The set of Spaces is LEARNED as the user moves
// between desktops — hence a one-time "cycle your Spaces" onboarding.
//
// Honest limits (documented for callers): discovers only VISITED Spaces; ordering is visit-order, not
// desktop left-to-right; no wallpapers; no native-full-screen tracking; synthetic ids aren't stable
// across relaunches. When the private CGS reader is available + enabled it's strictly better — this is
// the fallback so a build without private APIs still shows real Spaces instead of "current only".

import AppKit

public final class PublicSpacesProvider: SpacesProvider {
    public static let shared = PublicSpacesProvider()
    private init() {}

    private struct Marker { let window: NSWindow; let id: Int; let displayUUID: String }
    private var markers: [Marker] = []
    private var nextID = 1
    private var started = false
    // Which marker is on the current Space. Recomputed (one CGWindowList scan) only when the Space
    // actually changes — not on every spacesByDisplay()/click read.
    private var cachedCurrentID: Int? = nil
    private var needsRescan = true

    public func start() {
        guard !started else { return }
        started = true
        // queue: .main — these notifications already arrive on main, but NSWindow creation in the
        // handler MUST be on main, so pin it explicitly (defense-in-depth).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.spaceChanged() }
        ensureMarkerOnCurrentSpace()
    }

    private func spaceChanged() { needsRescan = true; ensureMarkerOnCurrentSpace() }

    /// True until the provider has learned more than the Space it started on (drives the onboarding
    /// nudge). Once the user has visited ≥2 Spaces we assume they understand the cycle.
    public var needsOnboarding: Bool { markers.count <= 1 }

    public static let onboardingMessage =
        "To show all your Spaces without private APIs, visit each desktop once — swipe between them " +
        "(Ctrl+← / Ctrl+→) or use Mission Control. ZoneTilerWM learns them as you go."

    // MARK: - SpacesProvider

    public func spacesByDisplay() -> [String: [RealSpace]] {
        let currentID = onScreenMarkerID()
        var out: [String: [RealSpace]] = [:]
        for m in markers {
            out[m.displayUUID, default: []].append(
                RealSpace(id: m.id, uuid: "pub:\(m.id)", displayUUID: m.displayUUID,
                          isCurrent: m.id == currentID, isFullscreen: false))
        }
        return out
    }

    public func wallpapersBySpaceUUID() -> [String: NSImage] { [:] }   // not available via public API
    public var isAvailable: Bool { !markers.isEmpty }

    // MARK: - markers

    /// If none of our markers is on the (now-)current Space, create one. This is how the set of Spaces
    /// is discovered: each newly-visited desktop gets a marker the first time it's seen.
    private func ensureMarkerOnCurrentSpace() {
        guard onScreenMarkerID() == nil else { return }
        // KNOWN LIMIT (multi-display): we assign the new Space to the display under the cursor. During a
        // swipe the cursor may be on a different display than the one whose Space changed, so on a
        // multi-display "separate Spaces" setup a Space can be attributed to the wrong display. Single
        // display is correct. A robust fix needs the display that actually changed Spaces (no public API).
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        let displayUUID = Self.displayUUID(of: screen) ?? ""
        // 1×1, ~transparent, on-screen (so optionOnScreenOnly lists it on its Space), click-through,
        // pinned to THIS Space (default collectionBehavior — explicitly NOT canJoinAllSpaces).
        let frame = NSRect(x: screen.frame.minX + 1, y: screen.frame.minY + 1, width: 1, height: 1)
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.alphaValue = 0.02            // > 0 so the window server keeps it in the on-screen list
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.level = .normal
        // .stationary PINS the window to its creation Space (it's what actually keeps the marker put —
        // `.ignoresCycle` only affects Cmd-` and does NOT control Space membership). No .canJoinAllSpaces.
        w.collectionBehavior = [.stationary, .ignoresCycle]
        w.orderFrontRegardless()
        let id = nextID
        markers.append(Marker(window: w, id: id, displayUUID: displayUUID))
        nextID += 1
        cachedCurrentID = id   // the just-created marker IS on the current Space
        needsRescan = false
    }

    /// The id of the marker currently on-screen (= on the active Space), if any. Cached; only a Space
    /// change (or a fresh marker) recomputes it, so repeated reads don't each scan the window list.
    private func onScreenMarkerID() -> Int? {
        if needsRescan {
            let onScreen = Self.onScreenWindowNumbers()
            cachedCurrentID = markers.first { onScreen.contains($0.window.windowNumber) }?.id
            needsRescan = false
        }
        return cachedCurrentID
    }

    private static func onScreenWindowNumbers() -> Set<Int> {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        return Set(list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue })
    }

    private static func displayUUID(of screen: NSScreen) -> String? {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let cf = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(num.uint32Value))?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, cf) as String?
    }
}
