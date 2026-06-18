// AboutWindow.swift — a small About window opened from the menubar: app icon, name, version,
// and the proprietary / all-rights-reserved declaration. Matches the unified "appbar" chrome
// (transparent titlebar, close button only) used by Settings and Analytics.

import AppKit
import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    // Load the real app icon from the bundled resource (works in the dev binary too, where
    // NSApplication.applicationIconImage is just the generic executable icon).
    private var appIcon: NSImage {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) { return img }
        return NSApplication.shared.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 10) {
            // The PNG is a full-bleed square; clip to the macOS "squircle" (≈22.4% radius) so the
            // corners are rounded like the real app icon.
            Image(nsImage: appIcon)
                .resizable().interpolation(.high)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                .accessibilityHidden(true)

            Text("ZoneTilerWM")
                .font(.system(.title, design: .rounded)).bold()
            Text("Version \(version)")
                .font(.callout).foregroundColor(.secondary)

            Text("A kinesthetic tiling window manager for macOS.")
                .font(.callout).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            Divider().frame(width: 200).padding(.vertical, 6)

            VStack(spacing: 3) {
                Text("© 2026 Tomer Zaidenstein").font(.callout)
                Text("All rights reserved.").font(.callout)
                Text("Proprietary software — not open source.")
                    .font(.caption).foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)        // clears the transparent titlebar / close button
        .padding(.bottom, 26)
        .frame(width: 320)
    }
}

public final class AboutWindowController {
    private var window: NSWindow?
    public init() {}

    public func show() {
        if let window {
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let hosting = NSHostingController(rootView: AboutView())
        hosting.sizingOptions = [.preferredContentSize]
        let w = NSWindow(contentViewController: hosting)
        w.title = "About ZoneTilerWM"
        // Unified appbar chrome: transparent full-size titlebar, no title text, close only.
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true
        w.standardWindowButton(.zoomButton)?.isHidden = true
        w.isReleasedWhenClosed = false
        w.isMovableByWindowBackground = true
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
