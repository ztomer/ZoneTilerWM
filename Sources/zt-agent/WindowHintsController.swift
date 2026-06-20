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
    private let zoneConfig: () -> ZoneConfig    // for the zone-scoped "peek" variant

    private let overlay = HintOverlay()
    private var active = false
    private var modalIDs: [UInt32] = []
    private var targets: [String: Int] = [:]
    private var iconCache: [String: NSImage?] = [:]
    // "/" search: filter the shown windows by app name (letters build a query instead of jumping).
    private var searchMode = false
    private var query = ""
    private var presented: [(app: String, icon: NSImage?, center: ZTRect, zone: String?, id: Int, frame: ZTRect)] = []

    init(binder: CarbonHotkeyBinder, screens: NSScreenProvider, windowSystem: AXWindowSystem,
         keyboardLayout: @escaping () -> String,
         zoneConfig: @escaping () -> ZoneConfig = { ZoneConfig(grids: [:], layouts: [:], margins: nil) }) {
        self.binder = binder
        self.screens = screens
        self.windowSystem = windowSystem
        self.keyboardLayout = keyboardLayout
        self.zoneConfig = zoneConfig
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
        present(wins)
    }

    /// Visual Window Peek: hints scoped to the windows occupying the FOCUSED window's zone — a quick
    /// way to jump to a specific window stacked in the current zone. 0 AX enumeration (CGWindowList);
    /// the focusedWindow() read + the focus-on-select are the only AX, same as window hints.
    func enterZone() {
        guard let focused = windowSystem.focusedWindow(), let uuid = focused.screenUUID,
              let screen = screens.screen(uuid: uuid) else { return }
        let info = ZoneCalculator.ScreenInfo(name: screen.name, frame: screen.frame)
        let zones = ZoneCalculator.computeZones(screen: info, config: zoneConfig()).zones
        guard let zoneKey = ZoneOccupancy.bestZone(window: focused.frame, zones: zones) else { return }
        let wins = windowSystem.windows(onScreen: uuid).filter {
            ZoneOccupancy.bestZone(window: $0.frame, zones: zones) == zoneKey
        }
        present(wins)
    }

    private func present(_ wins: [LiveWindow]) {
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
        presented = []
        searchMode = false; query = ""
        var badges: [(label: String, app: String, icon: NSImage?, center: ZTRect, zone: String?)] = []
        let zConfig = zoneConfig()
        var screenZones: [String: [String: [ZTRect]]] = [:]
        for s in screens.allScreens() {
            let info = ZoneCalculator.ScreenInfo(name: s.name, frame: s.frame)
            screenZones[s.uuid] = ZoneCalculator.computeZones(screen: info, config: zConfig).zones
        }
        for (label, w) in labeled {
            targets[label] = w.id
            let center = ZTRect(x: w.frame.x + w.frame.w / 2, y: w.frame.y + w.frame.h / 2, w: 0, h: 0)
            var zoneKey: String? = nil
            if let uuid = w.screenUUID, let zones = screenZones[uuid] {
                zoneKey = ZoneOccupancy.bestZone(window: w.frame, zones: zones)
            }
            let icon = appIcon(for: w.appName)
            badges.append((label, w.appName, icon, center, zoneKey))
            presented.append((app: w.appName, icon: icon, center: center, zone: zoneKey, id: w.id, frame: w.frame))
        }
        active = true
        overlay.show(badges)
        overlay.setSearchBar("press / to search")
        bindModal(labels: labeled.map { $0.0 })
        log("zt-agent: window hints ON (\(targets.count) windows) — type a label, / to search, ESC cancels")
    }

    func exit() {
        guard active else { return }
        active = false
        searchMode = false; query = ""; presented = []
        log("zt-agent: window hints OFF (dismissed)")
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
        if let slash = KeyMap.keyCode(for: "/"),
           let id = binder.register(keyCode: slash, modifiers: 0, action: { [weak self] in self?.startSearch() }) {
            modalIDs.append(id)
        }
    }

    // MARK: - "/" search (filter the shown windows by app name)

    /// Switch from label-jump mode to search mode: rebind so letters/digits build a query.
    private func startSearch() {
        guard active, !searchMode else { return }
        searchMode = true
        query = ""
        for id in modalIDs { binder.unbind(id) }
        modalIDs = []
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789".map(String.init) + ["space"]
        for ch in chars {
            guard let code = KeyMap.keyCode(for: ch) else { continue }
            let c = ch == "space" ? " " : ch
            if let id = binder.register(keyCode: code, modifiers: 0, action: { [weak self] in self?.appendQuery(c) }) { modalIDs.append(id) }
        }
        if let del = KeyMap.keyCode(for: "delete"), let id = binder.register(keyCode: del, modifiers: 0, action: { [weak self] in self?.backspaceQuery() }) { modalIDs.append(id) }
        if let ret = KeyMap.keyCode(for: "return"), let id = binder.register(keyCode: ret, modifiers: 0, action: { [weak self] in self?.focusTopMatch() }) { modalIDs.append(id) }
        if let esc = KeyMap.keyCode(for: "escape"), let id = binder.register(keyCode: esc, modifiers: 0, action: { [weak self] in self?.searchEscape() }) { modalIDs.append(id) }
        renderSearch()
    }

    private func appendQuery(_ c: String) { query += c; renderSearch() }
    private func backspaceQuery() { if !query.isEmpty { query.removeLast(); renderSearch() } }
    private func searchEscape() { if query.isEmpty { exit() } else { query = ""; renderSearch() } }

    private func filteredPresented() -> [(app: String, icon: NSImage?, center: ZTRect, zone: String?, id: Int, frame: ZTRect)] {
        let q = query.lowercased()
        return q.isEmpty ? presented : presented.filter { Self.fuzzyMatch(q, $0.app.lowercased()) }
    }

    private func renderSearch() {
        let f = filteredPresented()
        // Badges show no jump key while searching (letters drive the filter) — icon + app only.
        overlay.show(f.map { (label: "", app: $0.app, icon: $0.icon, center: $0.center, zone: $0.zone) })
        // Border each matching window's real frame (only once something is typed).
        overlay.showHighlights(query.isEmpty ? [] : f.map { $0.frame })
        overlay.setSearchBar(query.isEmpty ? "type to find a window · ⏎ focus · ⎋ back" : "/ \(query)    \(f.count) match\(f.count == 1 ? "" : "es")")
    }

    private func focusTopMatch() {
        guard let w = filteredPresented().first else { return }
        windowSystem.focus(windowId: w.id)
        exit()
    }

    /// Loose subsequence match (so "sf" finds "Safari"), substring fast-path.
    private static func fuzzyMatch(_ needle: String, _ hay: String) -> Bool {
        if needle.isEmpty || hay.contains(needle) { return true }
        var idx = hay.startIndex
        for ch in needle { guard let f = hay[idx...].firstIndex(of: ch) else { return false }; idx = hay.index(after: f) }
        return true
    }
}
