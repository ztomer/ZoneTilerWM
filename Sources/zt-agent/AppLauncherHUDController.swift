// AppLauncherHUDController.swift — hold an app-launcher modifier (appCuts's `mash_app` or
// hyperAppCuts's `HYPER`) past a short delay and a keyboard palette of THAT group's shortcuts appears
// (which key → which app), dismissed on release. A passive cheat-sheet — the actual launch is the
// existing modifier+key Carbon hotkey. Picks the screen under the mouse (0 AX). Mirrors the zone HUD's
// hold-to-reveal: arm only when the modifier is held ALONE (a key during the delay means you're
// launching, not summoning), and a modifier-state poll is the safety net for a missed release.

import AppKit
import ZTCore
import ZTSystem

final class AppLauncherHUDController {
    struct Group { let modifier: [String]; let apps: [String: String] }

    private let screens: NSScreenProvider
    private let groups: () -> [Group]
    private let holdDelayMs: () -> Int

    private let overlay = AppLauncherOverlay()
    private var monitor: Any?
    private var keyMonitor: Any?
    private var heldKeys: Set<UInt16> = []
    private var observers: [NSObjectProtocol] = []
    private var armTimer: Timer?
    private var pollTimer: Timer?
    private var shown = false
    private var armedApps: [String: String]?

    init(screens: NSScreenProvider, groups: @escaping () -> [Group], holdDelayMs: @escaping () -> Int) {
        self.screens = screens; self.groups = groups; self.holdDelayMs = holdDelayMs
    }

    var isRunning: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in self?.handle(e.modifierFlags) }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in self?.handleKey(e) }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                        object: nil, queue: .main) { [weak self] _ in self?.dismiss() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.dismiss() })
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil
        if let k = keyMonitor { NSEvent.removeMonitor(k) }; keyMonitor = nil
        heldKeys.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        dismiss()
    }

    /// The app group whose modifier is held EXACTLY (and which has apps), or nil.
    private func matchedApps(_ flags: NSEvent.ModifierFlags) -> [String: String]? {
        let current = flags.intersection(.tilingRelevant)
        for g in groups() where !g.apps.isEmpty {
            let target = NSEvent.ModifierFlags(aliases: g.modifier)
            if !target.isEmpty, current == target { return g.apps }
        }
        return nil
    }

    private func handle(_ flags: NSEvent.ModifierFlags) {
        guard let apps = matchedApps(flags), heldKeys.isEmpty else { dismiss(); return }
        guard armTimer == nil, !shown else { return }
        armedApps = apps
        let ms = max(80, min(2000, holdDelayMs()))
        armTimer = Timer.scheduledTimer(withTimeInterval: Double(ms) / 1000.0, repeats: false) { [weak self] _ in self?.present() }
    }

    private func handleKey(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            heldKeys.insert(event.keyCode)
            if armTimer != nil { armTimer?.invalidate(); armTimer = nil }   // a key during the delay → launching, not summoning
        case .keyUp:
            heldKeys.remove(event.keyCode)
        default:
            break
        }
    }

    private func present() {
        armTimer = nil
        guard !shown, let apps = armedApps, let screen = screens.screenUnderMouse() else { return }
        overlay.show(caps: AppLauncherHUD.caps(apps: apps), screenCGFrame: screen.frame)
        shown = true
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.matchedApps(NSEvent.modifierFlags) == nil { self.dismiss() }   // missed-release safety net
        }
    }

    private func dismiss() {
        armTimer?.invalidate(); armTimer = nil
        pollTimer?.invalidate(); pollTimer = nil
        armedApps = nil
        if shown { overlay.hide(); shown = false }
    }

    /// QA/debug: force the palette on for the first non-empty group (screenshot the live overlay).
    func forceShowForQA() {
        guard let apps = groups().first(where: { !$0.apps.isEmpty })?.apps,
              let screen = screens.screenUnderMouse() ?? screens.mainScreen() else { return }
        overlay.show(caps: AppLauncherHUD.caps(apps: apps), screenCGFrame: screen.frame)
        shown = true
    }
}
