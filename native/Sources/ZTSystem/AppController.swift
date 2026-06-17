// AppController.swift — executes AppSwitcher decisions against the live system (NSWorkspace /
// NSRunningApplication). The decision (hide / hide-via-menu / launch-or-focus, incl. the
// ambiguous-pair + special-mapping logic) is the ported, unit-tested AppSwitcher; this is the
// thin execution layer.

import Foundation
import AppKit
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
            NSWorkspace.shared.frontmostApplication?.hide()
        case .hideViaMenu:
            // v1: AX "Hide <app>" menu traversal is deferred; hide() is a reasonable fallback
            // for the workaround apps. The decision still distinguishes the cases.
            NSWorkspace.shared.frontmostApplication?.hide()
        }
    }

    /// Launch the app if not running, else activate it (à la hs.application.launchOrFocus).
    private static func launchOrFocus(_ name: String) {
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            ($0.localizedName ?? "").caseInsensitiveCompare(name) == .orderedSame
        }) {
            running.activate()
            return
        }
        // `open -a <name>` launches or activates by display name — robust, not deprecated.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", name]
        try? process.run()
    }
}
