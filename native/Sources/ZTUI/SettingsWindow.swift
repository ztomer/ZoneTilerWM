// SettingsWindow.swift — hosts SettingsView in an NSWindow, opened from the agent's menubar.

import AppKit
import SwiftUI

public final class SettingsWindowController {
    private var window: NSWindow?
    private let model: SettingsModel

    public init(model: SettingsModel) { self.model = model }

    public func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        // Size the window to the SELECTED tab's content (like System Settings) — no scroll on
        // tall tabs, no empty void on short ones. Width is fixed (760 in the view); height
        // follows content, capped to the screen so a tall tab still fits a laptop (Form scrolls
        // beyond the cap).
        hosting.sizingOptions = [.preferredContentSize]
        let w = NSWindow(contentViewController: hosting)
        w.title = "ZoneTilerWM Settings"
        // Unified "appbar": the tab bar (in the SwiftUI content) sits in a transparent,
        // full-size titlebar with no title text and only the close button.
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true
        w.standardWindowButton(.zoomButton)?.isHidden = true
        let maxH = (NSScreen.main?.visibleFrame.height ?? 1000) - 40
        w.contentMinSize = NSSize(width: 760, height: 320)
        w.contentMaxSize = NSSize(width: 760, height: maxH)
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
