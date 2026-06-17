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
        let w = NSWindow(contentViewController: hosting)
        w.title = "ZoneTilerWM Settings"
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.setContentSize(NSSize(width: 560, height: 460))
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
