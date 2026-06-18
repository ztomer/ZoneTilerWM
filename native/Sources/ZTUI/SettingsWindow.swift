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
        // Fixed, resizable window. (We do NOT auto-size to each tab via preferredContentSize:
        // that fought the SwiftUI layout pass — resizing the window inside layout — and crashed
        // with a reentrant constraint update; it also made padding jump on tab switches.)
        let w = NSWindow(contentViewController: hosting)
        w.title = "ZoneTilerWM Settings"
        // Unified "appbar": the tab bar (in the SwiftUI content) sits in a transparent,
        // full-size titlebar with no title text and only the close button.
        w.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true
        w.standardWindowButton(.zoomButton)?.isHidden = true
        let maxH = (NSScreen.main?.visibleFrame.height ?? 1000) - 40
        w.setContentSize(NSSize(width: 760, height: min(960, maxH)))   // fits the tallest tab
        w.contentMinSize = NSSize(width: 760, height: 360)
        w.contentMaxSize = NSSize(width: 760, height: maxH)
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
