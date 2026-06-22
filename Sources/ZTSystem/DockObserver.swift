// DockObserver.swift — the system-layer read of the macOS Dock for the hover-preview feature.
//
// Two reads, both cheap and cacheable:
//  • Dock edge + auto-hide come from the `com.apple.dock` preferences (no AX).
//  • The app-tile frames + titles come from the Dock's AX tree in ONE bounded query
//    (com.apple.dock process → AXList → AXApplicationDockItem children). The controller caches the
//    result and re-reads only on a Dock change, so the steady-state hover path stays 0-AX.
//
// Frames are returned in top-left screen coordinates (AXPosition is already top-left), matching
// ZTRect / DockItem / CGWindowList — no conversion needed.

import AppKit
import ApplicationServices
import ZTCore

public struct DockObserver {
    public init() {}

    /// Which edge the Dock is on (from `com.apple.dock orientation`; default bottom).
    public func dockEdge() -> DockEdge {
        DockPreview.edge(fromOrientation: UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation"))
    }

    /// Whether the Dock auto-hides (from `com.apple.dock autohide`). The preview controller uses this
    /// only for timing (a hidden Dock reveals on edge-hover, then the tile frames become valid).
    public func isAutohidden() -> Bool {
        UserDefaults(suiteName: "com.apple.dock")?.bool(forKey: "autohide") ?? false
    }

    /// The Dock's app tiles (title + on-screen frame), read from its AX tree. Returns [] if the Dock
    /// process is gone or AX is denied. One bounded query — cache it; re-read on Dock change.
    public func dockItems() -> [DockItem] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return [] }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        guard let children = Self.attr(app, kAXChildrenAttribute as String) as? [AXUIElement] else { return [] }
        for child in children where (Self.attr(child, kAXRoleAttribute as String) as? String) == (kAXListRole as String) {
            let items = Self.attr(child, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
            return items.compactMap(Self.dockItem)
        }
        return []
    }

    /// One AXApplicationDockItem → DockItem (nil for separators, the Trash, minimized-window tiles
    /// without an app title, etc.).
    private static func dockItem(_ el: AXUIElement) -> DockItem? {
        guard (attr(el, kAXSubroleAttribute as String) as? String) == "AXApplicationDockItem",
              let title = attr(el, kAXTitleAttribute as String) as? String, !title.isEmpty,
              let posV = attr(el, kAXPositionAttribute as String), let sizeV = attr(el, kAXSizeAttribute as String)
        else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(posV as! AXValue, .cgPoint, &pt)   // CF unchecked bridge — safe, AX contract
        AXValueGetValue(sizeV as! AXValue, .cgSize, &sz)
        guard sz.width > 0, sz.height > 0 else { return nil }
        return DockItem(appName: title, frame: ZTRect(x: pt.x, y: pt.y, w: sz.width, h: sz.height))
    }

    private static func attr(_ el: AXUIElement, _ attribute: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, attribute as CFString, &v) == .success ? v : nil
    }
}
