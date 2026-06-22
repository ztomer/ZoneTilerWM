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
    public static func png(model: SettingsModel, tab: String, width: CGFloat = 1000) -> Data? {
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

    /// Render a single first-run wizard step (the view is fixed-size, so capture its exact bounds
    /// rather than the Form-growth path png() uses). `step` is 0…5 (welcome…done).
    public static func wizardPNG(model: SettingsModel, step: Int) -> Data? {
        let s = WizardStep(rawValue: step) ?? .welcome
        let view = FirstRunWizardView(model: model, initialStep: s)
        let host = NSHostingView(rootView: AnyView(view))
        host.frame = NSRect(x: 0, y: 0, width: WizardStyle.width, height: WizardStyle.height)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        win.setFrameOrigin(NSPoint(x: -30000, y: 0))
        win.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        defer { win.orderOut(nil) }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    @ViewBuilder
    private static func tabView(_ tab: String, _ model: SettingsModel) -> some View {
        // "icons" → the custom sidebar-glyph montage (for the Gemini asset-grade loop).
        if tab == "icons" {
            IconMontage()
        } else {
            // Render one sidebar group's detail pane in isolation (same view the live window shows).
            SettingsGroupDetail(model: model, id: tab)
        }
    }
}
