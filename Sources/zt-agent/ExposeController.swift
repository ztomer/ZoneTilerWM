// ExposeController.swift — the custom Exposé *replacement* (#26): a hotkey lays every visible
// window out in a grid with a home-row jump label on each (type it to raise that window, ESC
// cancels), drawn by MissionControlOverlay. The user's review allowed "an overlay OR replacement";
// this is the replacement, which sidesteps the private-API problem of overlaying macOS's real
// Mission Control. Enumeration is CGWindowList (0 AX) via allWindows(); only the focus-on-select
// touches AX — same budget as window hints. Modeled on WindowHintsController.
//
// v1 = jump + cancel. The overlay also DRAWS a per-window (×); wiring its click to close the window
// (overlay mouse hit-test → AX close) is the next step — see docs/V6_FEATURE_PLAN.md.

import Foundation
import AppKit
import ZTCore
import ZTSystem

final class ExposeController {
    private let binder: CarbonHotkeyBinder
    private let screens: NSScreenProvider
    private let windowSystem: AXWindowSystem

    private let overlay = MissionControlOverlay()
    private var active = false
    private var modalIDs: [UInt32] = []
    private var targets: [String: Int] = [:]

    init(binder: CarbonHotkeyBinder, screens: NSScreenProvider, windowSystem: AXWindowSystem) {
        self.binder = binder; self.screens = screens; self.windowSystem = windowSystem
    }

    func toggle() { active ? exit() : enter() }

    func enter() {
        guard !active, let screen = screens.screenUnderMouse() ?? screens.mainScreen() else { return }
        let mine = NSRunningApplication.current.localizedName
        let wins = windowSystem.allWindows().filter { $0.appName != mine }   // all standard windows, 0 AX
        guard !wins.isEmpty else { return }
        let tiles = MissionControl.gridTiles(windowIds: wins.map { $0.id }, in: screen.frame)
        let hints = MissionControl.hints(for: tiles)
        targets = Dictionary(hints.map { ($0.label, $0.windowId) }, uniquingKeysWith: { a, _ in a })
        active = true
        overlay.show(hints, screenCGFrame: screen.frame)
        bindModal(labels: hints.map { $0.label })
        log("zt-agent: exposé ON (\(hints.count) windows) — type a label, ESC cancels")
    }

    func exit() {
        guard active else { return }
        active = false
        for id in modalIDs { binder.unbind(id) }
        modalIDs = []
        targets = [:]
        overlay.hide()
    }

    /// Transient single-key binds (one per label) → raise that window + dismiss; ESC cancels.
    private func bindModal(labels: [String]) {
        for label in labels {
            guard let code = KeyMap.keyCode(for: label) else { continue }   // single-key labels only
            if let id = binder.register(keyCode: code, modifiers: 0, action: { [weak self] in
                guard let self, let wid = self.targets[label] else { return }
                self.windowSystem.focus(windowId: wid)   // AX raise + focus
                self.exit()
            }) { modalIDs.append(id) }
        }
        if let esc = KeyMap.keyCode(for: "escape"),
           let id = binder.register(keyCode: esc, modifiers: 0, action: { [weak self] in self?.exit() }) {
            modalIDs.append(id)
        }
    }
}
