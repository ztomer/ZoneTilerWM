// AccessibilityOnboarding.swift — first-run guide shown when the agent lacks Accessibility
// (TCC) permission, which it needs to move other apps' windows. Explains why, opens the
// System Settings pane, and polls until the grant lands, then dismisses itself.

import AppKit
import SwiftUI
import ZTSystem

struct AccessibilityOnboardingView: View {
    let onGranted: () -> Void
    @State private var trusted = AXWindowSystem.isTrusted()
    // Poll for the grant (the user toggles it in System Settings; there's no callback).
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: trusted ? "checkmark.shield.fill" : "lock.shield")
                .font(.system(size: 46)).foregroundColor(trusted ? .green : .accentColor)
                .padding(.top, 32)

            Text(trusted ? "Accessibility granted" : "ZoneTilerWM needs Accessibility access")
                .font(.system(.title3, design: .rounded)).bold()
                .multilineTextAlignment(.center)

            Text(trusted
                 ? "You're all set — window tiling is enabled."
                 : "macOS requires Accessibility permission for an app to move other apps' "
                 + "windows. Enable ZoneTilerWM in System Settings → Privacy & Security → "
                 + "Accessibility, then come back — this window updates automatically.")
                .font(.callout).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !trusted {
                Button("Open System Settings") {
                    // Triggers the system prompt (with its "Open System Settings" button) and,
                    // as a fallback, deep-links to the Accessibility pane.
                    _ = AXWindowSystem.isTrusted(prompt: true)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.large).keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { onGranted() }
                    .controlSize(.large).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 30).padding(.bottom, 28)
        .frame(width: 380)
        .onReceive(poll) { _ in
            let now = AXWindowSystem.isTrusted()
            if now != trusted { trusted = now }
            if now { onGranted() }
        }
    }
}

public final class AccessibilityOnboardingController {
    private var window: NSWindow?
    public init() {}

    /// Show only if not already trusted. `onGranted` fires once the permission lands.
    public func showIfNeeded(onGranted: @escaping () -> Void = {}) {
        guard !AXWindowSystem.isTrusted() else { return }
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let hosting = NSHostingController(rootView: AccessibilityOnboardingView(onGranted: { [weak self] in
            onGranted()
            self?.window?.close()
        }))
        hosting.sizingOptions = [.preferredContentSize]
        let w = NSWindow(contentViewController: hosting)
        w.title = "Welcome to ZoneTilerWM"
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
