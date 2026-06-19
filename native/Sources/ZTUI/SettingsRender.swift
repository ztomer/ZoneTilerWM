// SettingsRender.swift — deterministic, windowless render of a settings tab to PNG (QA + Gemini
// grading). Uses SwiftUI's ImageRenderer so a tab can be rendered off-screen without bringing a
// real window forward (the transient-agent window-capture path is unreliable). Mirrors the overlay
// render harness.

import SwiftUI
import AppKit

@MainActor
public enum SettingsRender {
    /// Render a named settings tab to PNG at `width`. SwiftUI Form/List only lay out inside a real
    /// hosting window, so we host the tab in an OFF-SCREEN window, spin the runloop to let SwiftUI
    /// render, size to fit, then cacheDisplay to a bitmap (ImageRenderer renders Forms blank).
    public static func png(model: SettingsModel, tab: String, width: CGFloat = 720) -> Data? {
        let host = NSHostingView(rootView: AnyView(tabView(tab, model).frame(width: width)))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 2200)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        win.setFrameOrigin(NSPoint(x: -30000, y: 0))   // off any visible display
        win.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))   // let SwiftUI render
        let h = max(min(host.fittingSize.height, 5000), 300)
        host.setFrameSize(NSSize(width: width, height: h))
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        defer { win.orderOut(nil) }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    @ViewBuilder
    private static func tabView(_ tab: String, _ model: SettingsModel) -> some View {
        switch tab {
        case "features":   FeaturesTab(model: model)
        case "automation": AutomationTab(model: model)
        case "pomodoro":   PomodoroTab(model: model)
        default:           FeaturesTab(model: model)
        }
    }
}
