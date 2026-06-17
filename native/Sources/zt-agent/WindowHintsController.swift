// WindowHintsController.swift — the window-hints modal, extracted from AgentController.
// Shows a label badge over every visible window (the hint key mapped to where the window sits
// on screen), then binds a transient key-capture modal: type a label to focus that window, ESC
// cancels. Owns its overlay, its transient Carbon binds, and an app-icon cache. Port of
// hs.hints.windowHints.

import Foundation
import AppKit
import ZTCore
import ZTSystem

final class WindowHintsController {
    private let binder: CarbonHotkeyBinder
    private let screens: NSScreenProvider
    private let windowSystem: AXWindowSystem
    private let keyboardLayout: () -> String   // live (config can reload)

    private let overlay = HintOverlay()
    private var active = false
    private var modalIDs: [UInt32] = []
    private var targets: [String: Int] = [:]
    private var iconCache: [String: NSImage?] = [:]

    init(binder: CarbonHotkeyBinder, screens: NSScreenProvider, windowSystem: AXWindowSystem,
         keyboardLayout: @escaping () -> String) {
        self.binder = binder
        self.screens = screens
        self.windowSystem = windowSystem
        self.keyboardLayout = keyboardLayout
    }

    func toggle() { active ? exit() : enter() }

    func enter() {
        // All visible standard windows across screens, front-to-back, deduped by id.
        var seen = Set<Int>()
        var wins: [LiveWindow] = []
        for s in screens.allScreens() {
            for w in windowSystem.windows(onScreen: s.uuid) where !seen.contains(w.id) {
                seen.insert(w.id); wins.append(w)
            }
        }
        guard !wins.isEmpty else { return }

        // Desktop bounds (union of screens) → normalize each window center to [0,1] so the hint
        // key's physical keyboard position maps to where the window sits on screen.
        let frames = screens.allScreens().map { $0.frame }
        let minX = frames.map { $0.x }.min() ?? 0, maxX = frames.map { $0.x + $0.w }.max() ?? 1
        let minY = frames.map { $0.y }.min() ?? 0, maxY = frames.map { $0.y + $0.h }.max() ?? 1
        func norm(_ v: Double, _ lo: Double, _ hi: Double) -> Double { hi > lo ? (v - lo) / (hi - lo) : 0.5 }
        let centers = wins.map { w in
            (x: norm(w.frame.x + w.frame.w / 2, minX, maxX), y: norm(w.frame.y + w.frame.h / 2, minY, maxY))
        }
        let labels = WindowHints.spatialLabels(centers: centers, keys: keyRows())
        let labeled = zip(labels, wins).filter { !$0.0.isEmpty }
        if labeled.count < wins.count {
            log("zt-agent: window hints — \(wins.count) windows, \(labeled.count) labeled")
        }
        targets = [:]
        var badges: [(label: String, app: String, icon: NSImage?, center: ZTRect)] = []
        for (label, w) in labeled {
            targets[label] = w.id
            let center = ZTRect(x: w.frame.x + w.frame.w / 2, y: w.frame.y + w.frame.h / 2, w: 0, h: 0)
            badges.append((label, w.appName, appIcon(for: w.appName), center))
        }
        active = true
        overlay.show(badges)
        bindModal(labels: labeled.map { $0.0 })
        log("zt-agent: window hints ON (\(targets.count) windows) — type a label, ESC cancels")
    }

    func exit() {
        guard active else { return }
        active = false
        for id in modalIDs { binder.unbind(id) }
        modalIDs = []
        targets = [:]
        overlay.hide()
    }

    /// The 3 letter rows of the active keyboard layout, used as spatially-assignable hint keys.
    private func keyRows() -> [[String]] {
        let layout = keyboardLayout()
        let name = layout == "auto" ? KeyboardLayoutDetector.current() : layout
        return Array(KeyboardLayout.rows(for: name).suffix(3))
    }

    /// The running app's icon by display name (cached to avoid re-querying every hint pass).
    private func appIcon(for name: String) -> NSImage? {
        if let cached = iconCache[name] { return cached }
        let icon = NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.icon
        iconCache[name] = icon
        return icon
    }

    private func bindModal(labels: [String]) {
        for label in labels {
            guard let code = KeyMap.keyCode(for: label) else { continue }
            if let id = binder.register(keyCode: code, modifiers: 0, action: { [weak self] in
                guard let self, let wid = self.targets[label] else { return }
                self.windowSystem.focus(windowId: wid)
                self.exit()
            }) { modalIDs.append(id) }
        }
        if let esc = KeyMap.keyCode(for: "escape"),
           let id = binder.register(keyCode: esc, modifiers: 0, action: { [weak self] in self?.exit() }) {
            modalIDs.append(id)
        }
    }
}
