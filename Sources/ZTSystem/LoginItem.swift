// LoginItem.swift — launch-at-login via SMAppService (macOS 13+). Registers the bundled .app
// as a login item so the agent starts automatically. Only meaningful for the packaged .app;
// when run as the bare SwiftPM binary there's no bundle to register and status stays disabled.

import Foundation
import ServiceManagement

public enum LoginItem {
    /// Whether the app is currently registered to launch at login.
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// True only when we're running from a real .app bundle (SMAppService can't register a
    /// loose executable) — the UI uses this to disable the toggle in dev/CLI runs.
    public static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Register / unregister the main app as a login item. Best-effort; throws on failure.
    public static func setEnabled(_ on: Bool) throws {
        if on {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
        }
    }
}
