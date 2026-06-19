// AppController.swift — executes AppSwitcher decisions against the live system (NSWorkspace /
// NSRunningApplication). The decision (hide / hide-via-menu / launch-or-focus, incl. the
// ambiguous-pair + special-mapping logic) is the ported, unit-tested AppSwitcher; this is the
// thin execution layer.

import Foundation
import AppKit
import ApplicationServices
import ZTCore

public enum AppController {

    public static func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    /// Toggle an app: hide it if it's frontmost, else launch/focus it.
    public static func toggle(app: String, config: AppSwitcher.Config) {
        let front = frontmostAppName() ?? ""
        perform(AppSwitcher.decide(frontApp: front, target: app, config: config))
    }

    public static func perform(_ action: AppSwitcher.Action) {
        switch action {
        case .launchOrFocus(let app):
            launchOrFocus(app)
        case .hide:
            hideFrontmost()
        case .hideViaMenu(let menuItem):
            hideFrontmost(preferredTitle: menuItem)
        }
    }

    /// Hide the frontmost app. Presses its app-menu "Hide <app>" item via Accessibility — the same
    /// approach the original Lua used (`app:selectMenuItem('Hide <app>')`) — and only falls back to
    /// NSRunningApplication.hide() if that fails. The menu route goes through the app's own Hide
    /// command, so it's reliable for Electron apps (Discord/Slack/…) where the WindowServer hide()
    /// is intermittently ignored. A handful of AX calls, only on an explicit toggle (not the
    /// enumeration hot path), so it's within the AX budget.
    @discardableResult
    static func hideFrontmost(preferredTitle: String? = nil) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        if pressHideMenuItem(pid: app.processIdentifier, preferredTitle: preferredTitle) { return true }
        app.hide()
        return false
    }

    /// Find and press the "Hide <app>" item in the frontmost app's application menu (the 2nd
    /// menu-bar menu, after the Apple menu). Matches `preferredTitle` exactly when given, else any
    /// "Hide …" item that isn't "Hide Others". Returns false if the menu can't be walked.
    private static func pressHideMenuItem(pid: pid_t, preferredTitle: String?) -> Bool {
        func children(_ el: AXUIElement) -> [AXUIElement]? {
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref) == .success
            else { return nil }
            return ref as? [AXUIElement]
        }
        let appEl = AXUIElementCreateApplication(pid)
        var mbRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXMenuBarAttribute as CFString, &mbRef) == .success,
              let menuBar = mbRef, CFGetTypeID(menuBar) == AXUIElementGetTypeID() else { return false }
        // menu-bar items: [Apple, <app>, File, …] → the application menu is index 1.
        guard let topItems = children(menuBar as! AXUIElement), topItems.count > 1,
              let appMenu = children(topItems[1])?.first,        // the AXMenu under the app menu item
              let entries = children(appMenu) else { return false }
        for item in entries {
            var tRef: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &tRef)
            guard let title = tRef as? String else { continue }
            let matches = preferredTitle.map { title == $0 } ?? false
                || (title.hasPrefix("Hide ") && title != "Hide Others")
            if matches { return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success }
        }
        return false
    }

    /// Summon a scratchpad set: launch/activate each app, ending with the first so it lands
    /// frontmost. 0 AX (NSWorkspace activation).
    public static func summon(_ apps: [String]) {
        for name in apps.reversed() { launchOrFocus(name) }
    }

    /// Hide every running app in the set (the scratchpad dismiss). 0 AX.
    public static func hideApps(_ apps: [String]) {
        let lower = Set(apps.map { $0.lowercased() })
        for r in NSWorkspace.shared.runningApplications
        where lower.contains((r.localizedName ?? "").lowercased()) {
            r.hide()
        }
    }

    /// Launch the app if not running, else activate it (à la hs.application.launchOrFocus).
    private static func launchOrFocus(_ name: String) {
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            ($0.localizedName ?? "").caseInsensitiveCompare(name) == .orderedSame
        }) {
            // unhide() FIRST: activate() alone does NOT reliably bring back a *hidden* app, so a
            // toggle that just hid an app (esp. Electron) would fail to restore it. hs's
            // launchOrFocus unhides as part of activate — we replicate that here.
            running.unhide()
            running.activate(options: [.activateAllWindows])
            return
        }
        // `open -a <name>` launches or activates by display name — robust, not deprecated.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", name]
        try? process.run()
    }
}
