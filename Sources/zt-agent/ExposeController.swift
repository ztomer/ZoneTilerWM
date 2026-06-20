// ExposeController.swift — the custom Exposé *replacement* (#26): a hotkey lays every visible
// window out in a grid with a home-row jump label on each (type it to raise that window, ESC
// cancels), drawn by MissionControlOverlay. The user's review allowed "an overlay OR replacement";
// this is the replacement, which sidesteps the private-API problem of overlaying macOS's real
// Mission Control. Enumeration is CGWindowList (0 AX) via allWindows(); only the focus-on-select
// touches AX — same budget as window hints. Modeled on WindowHintsController.
//
// The overlay also draws a per-window (×) whose click closes the window (overlay mouse hit-test →
// AX close), plus ↵/⌘W/⌘M/⌘Q actions and arrow/vim/wasd nav. See docs/ROADMAP.md (Exposé).

import Foundation
import AppKit
import ZTCore
import ZTSystem

final class ExposeController {
    private let binder: CarbonHotkeyBinder
    private let screens: NSScreenProvider
    private let windowSystem: AXWindowSystem
    private let layoutGrid: (ScreenSnapshot) -> (cols: Int, rows: Int)
    private let screenZones: (ScreenSnapshot) -> [String: [ZTRect]]
    private let spacesBarPosition: () -> String
    private let exposeNav: () -> String   // "arrows" (default) or "vim" (hjkl move the selection)
    private let exposeScope: () -> String // "active" monitor (default) or "all" monitors
    private let realSpacesEnabled: () -> Bool   // runtime opt-in to the experimental private-API real Spaces

    private let overlay = MissionControlOverlay()
    private let nameStore = SpaceNameStore()
    private var active = false
    private var modalIDs: [UInt32] = []
    private var targets: [String: Int] = [:]
    private var safety: Timer?   // force-exit if a key/Esc is ever missed, so single-letter binds can't get stuck
    private var displayObserver: NSObjectProtocol?   // dismiss the overlay if a display is hot-plugged while it's up

    // Keyboard-driven selection (arrow / vim nav + ⌘W/⌘M/⌘Q/↵ actions).
    private var hints: [MissionControl.Hint] = []
    private var selectedId: Int?
    private var windowPids: [Int: pid_t] = [:]
    // "/" search: type an app name to move the selection ring to the matching window (↵ focuses it).
    private var searchMode = false
    private var query = ""
    private var winApps: [Int: String] = [:]

    init(
        binder: CarbonHotkeyBinder,
        screens: NSScreenProvider,
        windowSystem: AXWindowSystem,
        layoutGrid: @escaping (ScreenSnapshot) -> (cols: Int, rows: Int),
        screenZones: @escaping (ScreenSnapshot) -> [String: [ZTRect]],
        spacesBarPosition: @escaping () -> String,
        exposeNav: @escaping () -> String = { "arrows" },
        exposeScope: @escaping () -> String = { "active" },
        realSpacesEnabled: @escaping () -> Bool = { false }
    ) {
        self.binder = binder
        self.screens = screens
        self.windowSystem = windowSystem
        self.layoutGrid = layoutGrid
        self.screenZones = screenZones
        self.spacesBarPosition = spacesBarPosition
        self.exposeNav = exposeNav
        self.exposeScope = exposeScope
        self.realSpacesEnabled = realSpacesEnabled
    }

    func toggle() { active ? exit() : enter() }

    /// A display's usable grid frame = its frame minus the part overlapping the spaces-bar band
    /// (the band sits along one edge of the union of all shown displays).
    private static func layoutFrame(for s: ZTRect, union: ZTRect, pos: String, thickness t: Double) -> ZTRect {
        var f = s
        switch pos {
        case "left":
            let band = union.x + t
            if f.x < band { let nx = band; f.w -= (nx - f.x); f.x = nx }
        case "right":
            let band = union.x + union.w - t
            if f.x + f.w > band { f.w = max(0, band - f.x) }
        case "bottom":
            let band = union.y + union.h - t
            if f.y + f.h > band { f.h = max(0, band - f.y) }
        default: // "top"
            let band = union.y + t
            if f.y < band { let ny = band; f.h -= (ny - f.y); f.y = ny }
        }
        return f
    }

    /// The desktop wallpaper for a logical screen (matched to its NSScreen by CG display bounds),
    /// used for the per-monitor thumbnails in the "all monitors" strip.
    private func wallpaper(for screen: ScreenSnapshot) -> NSImage? {
        let target = screen.frame
        let ns = NSScreen.screens.first { s in
            guard let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            let b = CGDisplayBounds(CGDirectDisplayID(num.uint32Value))   // CG top-left
            return abs(b.origin.x - target.x) < 2 && abs(b.origin.y - target.y) < 2
        }
        guard let ns, let url = NSWorkspace.shared.desktopImageURL(for: ns) else { return nil }
        return NSImage(contentsOf: url)
    }

    func enter() {
        guard !active, let activeScreen = screens.screenUnderMouse() ?? screens.mainScreen() else { return }
        let mine = NSRunningApplication.current.localizedName
        let pos = spacesBarPosition().lowercased()
        let scopeAll = exposeScope().lowercased() == "all"

        // Target displays: just the active one, or all of them ("all" → one overlay window per
        // display, since macOS "separate Spaces" forbids a single window spanning displays). Ordered
        // left→right then top→bottom by frame origin so the strip matches the physical arrangement
        // (the display layout is encoded in the CG frame positions — no extra API needed).
        let targetScreens: [ScreenSnapshot] = (scopeAll ? screens.allScreens() : [activeScreen])
            .sorted { ($0.frame.x, $0.frame.y) < ($1.frame.x, $1.frame.y) }
        guard !targetScreens.isEmpty else { return }

        // On-screen-only (= each display's current Space — real, capturable windows; see git blame
        // for why allWindowsAcrossSpaces was 72 windows of junk).
        let ignoredApps = ["loginwindow", "SystemUIServer", "ControlCenter", "NotificationCenter", "Dock", "Window Server"]
        let allWins = windowSystem.allWindows().filter { w in
            w.appName != mine && !ignoredApps.contains(w.appName) && w.frame.w > 100 && w.frame.h > 100
        }
        func windowsOn(_ f: ZTRect) -> [LiveWindow] {
            allWins.filter { w in
                let cx = w.frame.x + w.frame.w / 2, cy = w.frame.y + w.frame.h / 2
                return cx >= f.x && cx < f.x + f.w && cy >= f.y && cy < f.y + f.h
            }
        }
        let wins = targetScreens.flatMap { windowsOn($0.frame) }
        guard !wins.isEmpty else { return }

        // App name + best-match zone per window (zones computed on the window's own display).
        var appNames: [Int: String] = [:]
        var zoneKeys: [Int: String?] = [:]
        for s in targetScreens {
            let zones = screenZones(s)
            for w in windowsOn(s.frame) {
                appNames[w.id] = w.appName
                zoneKeys[w.id] = ZoneOccupancy.bestZone(window: w.frame, zones: zones)
            }
        }
        winApps = appNames   // for "/" search
        searchMode = false; query = ""

        // One grid PER display, packed within that display's own frame (minus the strip band), so a
        // window appears in its monitor's region. Combined `hints` drives keyboard nav; `perDisplay`
        // feeds each Panel (one overlay window per display in "all" mode).
        var perDisplay: [[MissionControl.Hint]] = []
        var hints: [MissionControl.Hint] = []
        for s in targetScreens {
            let winsS = windowsOn(s.frame)   // the current real Space's windows on this display
            guard !winsS.isEmpty else { perDisplay.append([]); continue }
            var (cols, rows) = layoutGrid(s)
            while cols * rows < winsS.count { if cols <= rows { cols += 1 } else { rows += 1 } }
            let lf = Self.layoutFrame(for: s.frame, union: s.frame, pos: pos, thickness: 240.0)
            let tiles = MissionControl.spatialGridTiles(windows: winsS.map { ($0.id, $0.frame) }, in: lf, cols: cols, rows: rows)
            let hs = MissionControl.hints(for: tiles, appNames: appNames, zoneKeys: zoneKeys)
            perDisplay.append(hs); hints += hs
        }
        guard !hints.isEmpty else { return }
        targets = Dictionary(hints.map { ($0.label, $0.windowId) }, uniquingKeysWith: { a, _ in a })

        // Keyboard selection: keep the prior selection if it survived (close/minimize refresh), else
        // start at the first tile. Map window → pid so ⌘Q can quit the owning app.
        self.hints = hints
        self.windowPids = Dictionary(wins.compactMap { w in w.pid.map { (w.id, pid_t($0)) } },
                                     uniquingKeysWith: { a, _ in a })
        if selectedId == nil || !hints.contains(where: { $0.windowId == selectedId }) {
            selectedId = hints.first?.windowId
        }

        // Strip thumbnails draw each window as a real mini-screenshot at its true on-screen position.
        func miniFor(_ ws: [LiveWindow], on screen: ScreenSnapshot) -> [MissionControlOverlay.SpaceMiniWindow] {
            let sf = screen.frame
            return ws.map { w in
                let nr = CGRect(x: (w.frame.x - sf.x) / sf.w, y: (w.frame.y - sf.y) / sf.h, width: w.frame.w / sf.w, height: w.frame.h / sf.h)
                return .init(key: "", badgeColor: badgeColor(for: zoneKeys[w.id] ?? nil), windowId: w.id, normRect: nr)
            }
        }

        // REAL macOS Spaces per display (read-only via CGS) + correct per-space wallpapers. The strip
        // shows each monitor's real Spaces as a bordered group; only the current Space's windows can be
        // screenshotted (the rest show their wallpaper). Click a Space → switch to it. Drop a window on
        // ANOTHER monitor's Space → move it to that monitor (autotiled).
        // Real macOS Spaces only when BOTH the runtime toggle is on AND the private-API path is
        // compiled in (ZT_PRIVATE_APIS). Otherwise → public fallback (one synthetic current Space).
        let useReal = realSpacesEnabled() && SpacesReader.experimentalEnabled
        let spacesByDisplay = useReal ? SpacesReader.spacesByDisplay() : [:]
        let spaceWP = useReal ? SpacesReader.wallpapersBySpaceUUID() : [:]

        var panels: [MissionControlOverlay.Panel] = []
        var strip: [MissionControlOverlay.SpaceInfo] = []
        var groups: [MissionControlOverlay.SpaceGroup] = []
        var flatMap: [(monitor: Int, space: RealSpace)] = []
        for (i, s) in targetScreens.enumerated() {
            // Public-API fallback: when the experimental SkyLight reader is off (App-Store-safe build)
            // we can only see the CURRENT Space → one synthetic space per display, no switching.
            let real = spacesByDisplay[s.uuid] ?? []
            let effective = real.isEmpty
                ? [RealSpace(id: -1, uuid: "", displayUUID: s.uuid, isCurrent: true, isFullscreen: false)]
                : real
            let monWins = windowsOn(s.frame)
            for (j, sp) in effective.enumerated() {
                let wp = spaceWP[sp.uuid] ?? wallpaper(for: s)
                let mini = sp.isCurrent ? miniFor(monWins, on: s) : []   // off-Space windows aren't capturable
                let name = nameStore.name(for: sp) ?? (sp.isFullscreen ? "Full Screen" : "Desktop \(j + 1)")
                strip.append(.init(name: name, windows: mini, wallpaper: wp, isCurrent: sp.isCurrent))
                flatMap.append((i, sp))
            }
            groups.append(.init(name: s.name.isEmpty ? "Monitor \(i + 1)" : s.name, count: effective.count))
        }
        // In active mode the grouping border is unnecessary (single monitor).
        let panelGroups = scopeAll ? groups : []
        for (i, s) in targetScreens.enumerated() {
            panels.append(.init(screenCGFrame: s.frame, hints: perDisplay[i], spaces: strip,
                                selectedSpaceIndex: 0, groups: panelGroups))
        }

        let onStripDrop: (Int, Int) -> Void = { [weak self] wid, flatIdx in
            guard let self, flatIdx < flatMap.count else { return }
            let (mon, _) = flatMap[flatIdx]
            // We can't move a window into another *Space* (read-only), but we CAN move it to another
            // *monitor* (autotiled into its largest zone).
            let s = targetScreens[mon]
            let zones = self.screenZones(s).values.flatMap { $0 }
            let dest = zones.max(by: { $0.w * $0.h < $1.w * $1.h }) ?? s.frame
            self.windowSystem.move(windowId: wid, to: dest)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.refresh() }
        }
        let onStripSelect: (Int) -> Void = { [weak self] flatIdx in
            guard let self, flatIdx < flatMap.count else { return }
            let sp = flatMap[flatIdx].space
            guard !sp.isCurrent else { return }
            self.exit()
            SpaceSwitcher.switchTo(space: sp, allSpaces: spacesByDisplay[sp.displayUUID] ?? [])
        }
        let onRenameSpace: (Int) -> Void = { [weak self] flatIdx in
            guard let self, flatIdx < flatMap.count else { return }
            self.promptRename(flatMap[flatIdx].space)
        }

        active = true
        overlay.show(
            panels: panels,
            selectedWindowId: selectedId,
            spacesBarPosition: pos,
            editableSpaces: false,   // real macOS Spaces can't be created/destroyed via +/× (would need GUI automation)
            onJump: { [weak self] id in self?.windowSystem.focus(windowId: id); self?.exit() },
            onClose: { [weak self] id in
                self?.windowSystem.closeWindow(windowId: id)               // press the window's × via AX
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.refresh() }  // rebuild grid sans it
            },
            onDismiss: { [weak self] in self?.exit() },
            onSelectSpace: onStripSelect,   // click a Space thumbnail → switch to it
            onMoveWindowToSpace: onStripDrop,
            onRenameSpace: onRenameSpace    // double-click a Space thumbnail → rename
        )

        bindModal(labels: hints.map { $0.label })
        overlay.setSearchBar("press / to search")
        safety = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in self?.exit() }
        // Hot-plug safety: the panels were built from a snapshot of the displays (captured `targetScreens`
        // + their frames). If a monitor is connected/disconnected/rearranged while the overlay is up, that
        // snapshot is stale — dismiss rather than draw an overlay on a display that no longer exists.
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.exit() }
        log("zt-agent: exposé ON (\(hints.count) windows) — type a label / click to jump, click × to close, ESC cancels")
    }

    /// Rename a Space: close the overlay first (so the alert can take keyboard focus — the agent is an
    /// accessory app), then prompt with an NSAlert text field and persist via SpaceNameStore.
    private func promptRename(_ space: RealSpace) {
        exit()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Rename Space"
            alert.informativeText = "Name this desktop Space (leave blank to reset)."
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
            field.stringValue = self.nameStore.name(for: space) ?? ""
            alert.accessoryView = field
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = field
            if alert.runModal() == .alertFirstButtonReturn {
                self.nameStore.setName(field.stringValue, for: space)
            }
        }
    }

    /// Rebuild the grid after a window closed or spaces state changes
    private func refresh() { guard active else { return }; exit(); enter() }

    func exit() {
        guard active else { return }
        active = false
        searchMode = false; query = ""; winApps = [:]
        log("zt-agent: exposé OFF (dismissed)")
        safety?.invalidate(); safety = nil
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver); self.displayObserver = nil }
        for id in modalIDs { binder.unbind(id) }
        modalIDs = []
        targets = [:]
        overlay.hide()
    }

    /// Transient modal binds while the overlay is up. Type a label → jump; arrow/vim keys move the
    /// selection ring; ↵ opens, ⌘W closes, ⌘M minimizes, ⌘Q quits the selected window's app; ESC
    /// cancels. All are unbound in exit().
    private func bindModal(labels: [String]) {
        // Navigation scheme: arrows always work; "vim" adds hjkl, "wasd" adds FPS-style wasd. Those
        // letters double as type-to-jump labels, so in the chosen scheme they drive navigation and
        // are NOT also bound as jump labels (the documented trade-off).
        let mode = exposeNav().lowercased()
        let letterNav: [(String, MissionControl.NavMove)]
        switch mode {
        case "vim":  letterNav = [("h", .left), ("j", .down), ("k", .up), ("l", .right)]
        case "wasd": letterNav = [("a", .left), ("s", .down), ("w", .up), ("d", .right)]
        default:     letterNav = []
        }
        let navLetters = Set(letterNav.map { $0.0 })

        for label in labels where !navLetters.contains(label) {
            guard let code = KeyMap.keyCode(for: label) else { continue }
            bindKey(code, mods: 0) { [weak self] in
                guard let self, let wid = self.targets[label] else { return }
                self.windowSystem.focus(windowId: wid)   // AX raise + focus
                self.exit()
            }
        }

        // Arrow keys always navigate the selection; the chosen letter scheme too.
        var navBinds: [(String, MissionControl.NavMove)] =
            [("left", .left), ("right", .right), ("up", .up), ("down", .down)]
        navBinds += letterNav
        for (key, move) in navBinds {
            guard let code = KeyMap.keyCode(for: key) else { continue }
            bindKey(code, mods: 0) { [weak self] in self?.navSelect(move) }
        }

        // ↵ open · ⌘W close · ⌘M minimize · ⌘Q quit-app — all act on the current selection.
        let cmd = KeyMap.modifierMask(for: ["cmd"])
        if let ret = KeyMap.keyCode(for: "return") { bindKey(ret, mods: 0) { [weak self] in self?.openSelected() } }
        if let w = KeyMap.keyCode(for: "w") { bindKey(w, mods: cmd) { [weak self] in self?.closeSelected() } }
        if let m = KeyMap.keyCode(for: "m") { bindKey(m, mods: cmd) { [weak self] in self?.minimizeSelected() } }
        if let q = KeyMap.keyCode(for: "q") { bindKey(q, mods: cmd) { [weak self] in self?.quitSelectedApp() } }
        if let esc = KeyMap.keyCode(for: "escape") { bindKey(esc, mods: 0) { [weak self] in self?.exit() } }
        if let slash = KeyMap.keyCode(for: "/") { bindKey(slash, mods: 0) { [weak self] in self?.startSearch() } }
    }

    // MARK: - "/" search (type an app name → the selection ring jumps to the matching window)

    private func startSearch() {
        guard active, !searchMode else { return }
        searchMode = true; query = ""
        for id in modalIDs { binder.unbind(id) }
        modalIDs = []
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789".map(String.init) + ["space"]
        for ch in chars {
            guard let code = KeyMap.keyCode(for: ch) else { continue }
            let c = ch == "space" ? " " : ch
            bindKey(code, mods: 0) { [weak self] in self?.appendQuery(c) }
        }
        if let del = KeyMap.keyCode(for: "delete") { bindKey(del, mods: 0) { [weak self] in self?.backspaceQuery() } }
        if let ret = KeyMap.keyCode(for: "return") { bindKey(ret, mods: 0) { [weak self] in self?.openSelected() } }
        if let esc = KeyMap.keyCode(for: "escape") { bindKey(esc, mods: 0) { [weak self] in self?.searchEscape() } }
        updateMatch()
    }

    private func appendQuery(_ c: String) { query += c; updateMatch() }
    private func backspaceQuery() { if !query.isEmpty { query.removeLast(); updateMatch() } }
    private func searchEscape() { if query.isEmpty { exit() } else { query = ""; updateMatch() } }

    private func matchingIds() -> [Int] {
        let q = query.lowercased()
        let ids = hints.map { $0.windowId }
        return q.isEmpty ? ids : ids.filter { Self.fuzzyMatch(q, (winApps[$0] ?? "").lowercased()) }
    }

    private func updateMatch() {
        let ids = matchingIds()
        if selectedId == nil || !ids.contains(selectedId!) { selectedId = ids.first }
        overlay.updateSelection(selectedId)
        overlay.updateMatches(query.isEmpty ? nil : Set(ids))   // border matches, dim the rest
        overlay.setSearchBar(query.isEmpty ? "type to find a window · ↵ focus · ⎋ back"
                                           : "/ \(query)    \(ids.count) match\(ids.count == 1 ? "" : "es")")
    }

    private static func fuzzyMatch(_ needle: String, _ hay: String) -> Bool {
        if needle.isEmpty || hay.contains(needle) { return true }
        var idx = hay.startIndex
        for ch in needle { guard let f = hay[idx...].firstIndex(of: ch) else { return false }; idx = hay.index(after: f) }
        return true
    }

    private func bindKey(_ code: UInt32, mods: UInt32, _ action: @escaping () -> Void) {
        if let id = binder.register(keyCode: code, modifiers: mods, action: action) { modalIDs.append(id) }
    }

    private func navSelect(_ move: MissionControl.NavMove) {
        guard let id = selectedId else { return }
        selectedId = MissionControl.navigate(from: id, move, in: hints)
        overlay.updateSelection(selectedId)   // lightweight redraw, no rebuild
    }

    private func openSelected() {
        guard let id = selectedId else { return }
        windowSystem.focus(windowId: id)
        exit()
    }

    /// Mutate the selected window (close/minimize/quit), advance the selection to a neighbour so it
    /// lands sensibly, then rebuild the grid (without the gone window). `enter()` keeps the new
    /// selection if it survived.
    private func mutateSelected(_ body: (Int) -> Void) {
        guard let id = selectedId else { return }
        let right = MissionControl.navigate(from: id, .right, in: hints)
        selectedId = (right != id) ? right : MissionControl.navigate(from: id, .left, in: hints)
        if selectedId == id { selectedId = nil }   // last window — let enter() reset
        body(id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refresh() }
    }

    private func closeSelected()    { mutateSelected { windowSystem.closeWindow(windowId: $0) } }
    private func minimizeSelected() { mutateSelected { _ = windowSystem.setMinimized(true, windowId: $0) } }
    private func quitSelectedApp()  {
        mutateSelected { id in
            if let pid = windowPids[id] { NSRunningApplication(processIdentifier: pid)?.terminate() }
        }
    }

    private func badgeColor(for zone: String?) -> NSColor {
        guard let zone = zone?.lowercased() else {
            return NSColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 0.97) // Pastel Gray
        }
        switch zone {
        case "h", "left":
            return NSColor(red: 0.85, green: 0.92, blue: 0.97, alpha: 0.97) // Pastel Blue
        case "l", "right":
            return NSColor(red: 0.85, green: 0.95, blue: 0.88, alpha: 0.97) // Pastel Green
        case "k", "top":
            return NSColor(red: 0.92, green: 0.88, blue: 0.96, alpha: 0.97) // Pastel Purple
        case "j", "bottom":
            return NSColor(red: 0.98, green: 0.92, blue: 0.85, alpha: 0.97) // Pastel Orange
        case "c", "center":
            return NSColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 0.97)  // Pastel Yellow/Amber
        default:
            let colors = [
                NSColor(red: 0.85, green: 0.92, blue: 0.97, alpha: 0.97),
                NSColor(red: 0.85, green: 0.95, blue: 0.88, alpha: 0.97),
                NSColor(red: 0.92, green: 0.88, blue: 0.96, alpha: 0.97),
                NSColor(red: 0.98, green: 0.92, blue: 0.85, alpha: 0.97),
                NSColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 0.97)
            ]
            let hash = abs(zone.hashValue)
            return colors[hash % colors.count]
        }
    }
}
