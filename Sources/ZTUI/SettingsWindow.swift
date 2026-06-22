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
        // SwiftUI's `.searchable(placement: .toolbar)` attaches a toolbar to host the search field in the
        // (otherwise empty) titlebar; unified style keeps it flush with the appbar look.
        w.toolbarStyle = .unified
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true
        w.standardWindowButton(.zoomButton)?.isHidden = true
        let maxH = (NSScreen.main?.visibleFrame.height ?? 1000) - 40
        // Tall default — this is a complex program, so give the dense panes vertical room (up to
        // 1400) to cut scrolling. Width stays modest.
        w.setContentSize(NSSize(width: 1000, height: min(1400, maxH)))
        w.contentMinSize = NSSize(width: 980, height: 360)
        w.contentMaxSize = NSSize(width: 1280, height: maxH)
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
