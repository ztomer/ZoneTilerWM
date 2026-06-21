// AgentController+Runtime.swift — layout snapshots, display/screen handling, live reload, the
// menubar/status item, window openers, QA render hooks, onboarding. Split out of main.swift.

import Foundation
import AppKit
import ZTCore
import ZTSystem
import ZTUI

extension AgentController {

    /// Live windows for the command palette's "find a window by typing": app name + a best-zone
    /// locator. Enumeration is CGWindowList (0 AX); only the focus-on-select touches AX (like hints).
    func paletteWindows() -> [(id: Int, app: String, detail: String)] {
        let mine = NSRunningApplication.current.localizedName
        let all = screens.allScreens()
        return windowSystem.allWindows().compactMap { w -> (id: Int, app: String, detail: String)? in
            guard !w.appName.isEmpty, w.appName != mine else { return nil }
            var detail = ""
            let cx = w.frame.x + w.frame.w / 2, cy = w.frame.y + w.frame.h / 2
            if let s = all.first(where: { cx >= $0.frame.x && cx < $0.frame.x + $0.frame.w
                                       && cy >= $0.frame.y && cy < $0.frame.y + $0.frame.h }) {
                let info = ZoneCalculator.ScreenInfo(name: s.name, frame: s.frame)
                let zones = ZoneCalculator.computeZones(screen: info, config: config.zoneConfig, offsets: { _, _ in 0 }).zones
                if let z = ZoneOccupancy.bestZone(window: w.frame, zones: zones) { detail = "zone \(z)" }
            }
            return (id: w.id, app: w.appName, detail: detail)
        }
    }

    // MARK: - Layout snapshots

    /// Current arrangement as value snapshots via the read-only query provider (0 AX).
    func currentArrangement() -> [WindowInfo] {
        if case .arrangement(let windows) = arrangementQuery.answer(.arrangement) { return windows }
        return []
    }

    /// Capture the current arrangement into a named snapshot and persist it.
    /// A SyncEngine bound to the live config dir (where config.toml actually lives) + the state dir
    /// (cache_dir) + the [sync] folder, rebuilt per call so a config reload is reflected. File-based
    /// settings sync — 0 AX, no network, no entitlements.
    func syncEngine() -> SyncEngine {
        SyncEngine(configDir: configURL.deletingLastPathComponent().path,
                   stateDir: config.windowMemory.cacheDir,
                   syncFolder: { [unowned self] in self.config.syncFolder })
    }

    /// After a successful sync-import: re-read config.toml AND the imported state JSON so the new
    /// settings are live immediately (and the in-memory state can't overwrite the import on the
    /// next save). Layouts replace wholesale; learned positions merge (imported wins per app/monitor).
    func adoptImportedSettings() {
        _ = reloadFromDisk()   // config.toml (validated; kept if invalid)
        if let saved = resizeStorage.load("window_positions", as: WindowMemory.SaveData.self) {
            learnedMemory?.load(saved)
        }
        layouts = resizeStorage.load("layouts", as: LayoutLibrary.self) ?? layouts
        log("zt-agent: sync-import adopted config + learned state")
    }

    /// Apply the context-aware placement suggestions: move each window the `suggestions` resource
    /// flags into its learned-preferred zone (the same per-window tile path the rules engine uses).
    /// Bounded AX (one move per out-of-place window); user/LLM-invoked, never automatic.
    func applyPlacementSuggestions() -> ActionResult {
        guard case .suggestions(let suggestions) = arrangementQuery.answer(.suggestions) else {
            return .failed(reason: .unsupportedAction)   // window memory disabled → no suggestions
        }
        var moves: [TiledMove] = []
        for s in suggestions {
            if let o = coordinator.moveWindow(windowId: s.windowId, toZone: s.suggestedZone) {
                moves.append(TiledMove(windowId: o.windowId, zone: o.zoneKey, tileIndex: .int(o.tileIndex), rect: o.target))
            }
        }
        log("zt-agent: applied \(moves.count)/\(suggestions.count) placement suggestion(s)")
        return .suggestionsApplied(moves: moves)
    }

    /// Arrange a named app-cluster profile: launch any of its apps not running (0 AX), then tile
    /// each running matching window to its zone (CGWindowList enumerate = 0 AX; one move per window).
    func applyCluster(_ name: String) -> ActionResult {
        guard let profile = config.clusters.first(where: { $0.name.lowercased() == name.lowercased() }) else {
            return .failed(reason: .invalidParameter("unknown cluster '\(name)'"))
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.localizedName?.lowercased() })
        let missing = ClusterPlan.apps(profile).filter { !running.contains($0.lowercased()) }
        if !missing.isEmpty { AppController.summon(missing) }   // best-effort launch; placed on a later apply
        guard case .arrangement(let windows) = arrangementQuery.answer(.arrangement) else {
            return .failed(reason: .unsupportedAction)
        }
        var moves: [TiledMove] = []
        for m in ClusterPlan.match(profile: profile, windows: windows.map { ($0.windowId, $0.app) }) {
            if let o = coordinator.moveWindow(windowId: m.windowId, toZone: m.zone) {
                moves.append(TiledMove(windowId: o.windowId, zone: o.zoneKey, tileIndex: .int(o.tileIndex), rect: o.target))
            }
        }
        log("zt-agent: cluster '\(profile.name)' arranged \(moves.count) window(s), launched \(missing.count)")
        return .clusterApplied(name: profile.name, moves: moves)
    }

    func saveLayout(_ name: String) -> ActionResult {
        let snapshot = LayoutSnapshots.capture(name: name, from: currentArrangement())
        layouts = layouts.upserting(snapshot)
        resizeStorage.save("layouts", layouts)
        log("zt-agent: saved layout '\(name)' (\(snapshot.assignments.count) windows)")
        return .layoutSaved(name: name, windowCount: snapshot.assignments.count)
    }

    /// Restore a named snapshot: tile each matched window to its saved zone (window-targeted).
    func applyLayout(_ name: String) -> ActionResult {
        guard let snapshot = layouts.snapshot(named: name) else {
            log("zt-agent: apply-layout '\(name)' — no such layout")
            return .failed(reason: .invalidParameter("name"))
        }
        let plan = LayoutSnapshots.restorePlan(snapshot, current: currentArrangement())
        var moved = 0
        for move in plan where coordinator.moveWindow(windowId: move.windowId, toZone: move.zone)?.applied == true {
            moved += 1
        }
        log("zt-agent: applied layout '\(name)' (\(moved)/\(plan.count) moved)")
        return .layoutApplied(name: name, moved: moved)
    }

    // MARK: - Display arrangement

    /// Register every connected screen in enumeration order so logical monitor ids match the
    /// on-disk window_positions.json numbering (main display == 1), like Lua's
    /// monitor_manager.init(). Must run before any tile/move op: lazy registration would let
    /// whichever monitor the first op touches steal id 1 and read the wrong monitor's learned
    /// preferences. Idempotent (reregister preserves existing ids), so it doubles as the
    /// screen-change handler.
    func seedMonitors() {
        let uuids = screens.allScreens().map { $0.uuid }
        monitorManager.reregister(uuids: uuids)
        let arrangement = screens.allScreens()
            .map { "\(monitorManager.id(forUUID: $0.uuid))=\($0.name) \(Int($0.fullFrame.w))x\(Int($0.fullFrame.h))" }
            .joined(separator: ", ")
        log("zt-agent: \(uuids.count) display(s): \(arrangement)")
    }

    /// React to connect / disconnect / rearrange / resolution change. Re-register the current
    /// screens (new displays get a stable id immediately, in enumeration order; existing ids are
    /// preserved across a reconnect). Zones are recomputed live on every op, so nothing else is
    /// cached to invalidate — this just keeps the id↔display mapping correct, which is what makes
    /// zone memory and resize offsets resolve to the right monitor after a hot-plug.
    func setupScreenWatch() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            log("zt-agent: display arrangement changed — re-registering monitors")
            self?.seedMonitors()
            self?.evaluateDisplayChangeRules()
            self?.applyDisplayPreset()
        }
    }

    /// Environment/topology presets: when the connected display set changes, run the first matching
    /// [[display_presets]] action (e.g. apply a docked layout when an external monitor appears).
    /// Gated — no-op unless presets are configured. 0 AX (display names from NSScreen; the action
    /// itself uses the standard dispatch path).
    func applyDisplayPreset() {
        guard !config.displayPresets.isEmpty else { return }
        let names = screens.allScreens().map { $0.name }
        guard let action = DisplayPresetEngine.match(current: names, presets: config.displayPresets) else { return }
        log("zt-agent: display preset matched (\(names.joined(separator: ", "))) → \(dispatcher.perform(action))")
    }

    @discardableResult
    func reloadFromDisk() -> Bool {
        guard let newConfig = try? ConfigLoader.load(contentsOf: configURL) else {
            log("zt-agent: config reload skipped — could not parse \(configURL.lastPathComponent)")
            return false
        }
        let problems = ConfigValidator.validate(newConfig)
        guard problems.isEmpty else {
            log("zt-agent: config reload skipped — invalid: \(problems.joined(separator: "; "))")
            return false   // keep the running config
        }
        applyConfig(newConfig)
        log("zt-agent: config reloaded from \(configURL.lastPathComponent)")
        return true
    }

    /// Apply a validated config in place: rebuild config-derived state, then rebind hotkeys.
    /// Stable subsystems (window memory/storage, the running Pomodoro session, the menubar
    /// item + timer) are preserved.
    func applyConfig(_ newConfig: ConfigLoader.LoadedConfig) {
        config = newConfig
        spacesMenubar?.refresh()   // re-evaluate the menu-bar Spaces widget gate on reload
        coordinator = AgentController.makeCoordinator(config: newConfig, windowSystem: windowSystem,
                                                      screens: screens, memory: learnedMemory,
                                                      monitorManager: monitorManager, storage: storage,
                                                      resizeManager: resizeManager, floats: floats)
        autoTilerConfig = newConfig.autoTilerConfig()
        appSwitcher = newConfig.appSwitcher
        rulesEngine = RulesEngine(rules: newConfig.rules)
        pomodoro.updateConfig(.init(workPeriodSec: newConfig.pomodoroWorkSec,
                                    restPeriodSec: newConfig.pomodoroRestSec,
                                    enableColorBar: newConfig.pomodoroEnableColorBar))
        enableColorBar = newConfig.pomodoroEnableColorBar
        pomodoroIndicatorHeight = newConfig.pomodoroIndicatorHeight
        pomodoroIndicatorAlpha = newConfig.pomodoroIndicatorAlpha
        pomodoroColorRemaining = PomodoroBar.color(named: newConfig.pomodoroColorRemaining)
        pomodoroColorUsed = PomodoroBar.color(named: newConfig.pomodoroColorUsed)
        applyBorders(newConfig)
        bindAllHotkeys()
        reconcileIPCServer()        // start/stop the MCP/CLI socket if [automation] enabled changed
        reconcileZoneHUD()          // start/stop the zone HUD if [zone_hud] enabled changed
        reconcileDragSnap()         // start/stop drag-to-snap if [drag_snap] enabled changed
        reconcileFocusFollowsMouse()  // start/stop focus-follows-mouse if [focus_follows_mouse] changed
        reconcileEventStream()        // start/stop the arrangement event stream if [events] changed
        coordinator.seedFocusTimes(now: Int(Date().timeIntervalSince1970))
        refreshPomodoro()
    }

    func refreshPomodoro() {
        if pomodoro.isActive {
            let m = pomodoro.timeLeft / 60, s = pomodoro.timeLeft % 60
            let phase = pomodoro.phase == .work ? "Work" : "Rest"
            let count = pomodoro.workCount > 0 ? "  ·\(pomodoro.workCount)" : ""
            let text = String(format: "%@  %02d:%02d%@", phase, m, s, count)
            let w = pomodoroPill?.update(text) ?? 0
            pomodoroPill?.isHidden = false
            pomodoroItem?.length = w
        } else {
            pomodoroPill?.isHidden = true
            pomodoroItem?.length = 0
        }
        if pomodoro.isActive && enableColorBar {
            pomodoroBar.update(timeLeft: pomodoro.timeLeft, maxTime: pomodoro.maxTimeSec,
                               heightRatio: pomodoroIndicatorHeight, alpha: pomodoroIndicatorAlpha,
                               remaining: pomodoroColorRemaining, used: pomodoroColorUsed)
        } else {
            pomodoroBar.hide()
        }
    }

    func bindMiscHotkeys(_ config: ConfigLoader.LoadedConfig) {
        // Zen mode (minimize other windows on the focused screen).
        bindAction(config.resolvedHotkey("zen_mode", in: config.tilerHotkeys), label: "zen_mode") { [weak self] in
            self?.dispatcher.perform(.toggleZen)
        }
        // Float toggle (exclude focused window from auto-tile) — optional hotkey; also via palette/CLI/MCP.
        bindAction(config.resolvedHotkey("float", in: config.tilerHotkeys), label: "float") { [weak self] in
            self?.dispatcher.perform(.toggleFloat)
        }
        // System: toggle Activity Monitor.
        bindAction(config.resolvedHotkey("activity_monitor", in: config.systemHotkeys), label: "activity_monitor") { [weak self] in
            self?.dispatcher.perform(.appToggle(app: "Activity Monitor"))
        }
        // Scratchpad drawer: summon/dismiss the configured app set (opt-in — only bound when the
        // scratchpad hotkey is set AND [scratchpad] apps is non-empty; also via palette/CLI/MCP).
        bindAction(config.resolvedHotkey("scratchpad", in: config.systemHotkeys), label: "scratchpad") { [weak self] in
            self?.dispatcher.perform(.scratchpad)
        }
        // Resize mode: toggle the grid-line adjustment modal.
        bindAction(config.resolvedHotkey("resize_mode", in: config.tilerHotkeys), label: "resize_mode") { [weak self] in
            self?.dispatcher.perform(.toggleResizeMode)
        }
        // Multi-monitor: move focused window to next/previous monitor (placement_mode/zone_info),
        // and focus next/previous screen. No-ops on a single display.
        bindAction(config.resolvedHotkey("placement_mode", in: config.tilerHotkeys), label: "move_to_next_monitor") { [weak self] in
            self?.dispatcher.perform(.moveFocusedToMonitor(direction: .next))
        }
        bindAction(config.resolvedHotkey("zone_info", in: config.tilerHotkeys), label: "move_to_prev_monitor") { [weak self] in
            self?.dispatcher.perform(.moveFocusedToMonitor(direction: .previous))
        }
        bindAction(config.resolvedHotkey("focus_next_screen", in: config.tilerHotkeys), label: "focus_next_screen") { [weak self] in
            self?.dispatcher.perform(.focusScreen(direction: .next))
        }
        bindAction(config.resolvedHotkey("focus_prev_screen", in: config.tilerHotkeys), label: "focus_prev_screen") { [weak self] in
            self?.dispatcher.perform(.focusScreen(direction: .previous))
        }
        // Window stacks: cycle focus through the windows stacked in the focused zone (opt-in —
        // only bound when stack_next/stack_prev are set; also via palette/CLI/MCP).
        bindAction(config.resolvedHotkey("stack_next", in: config.tilerHotkeys), label: "stack_next") { [weak self] in
            self?.dispatcher.perform(.cycleZoneStack(direction: .next))
        }
        bindAction(config.resolvedHotkey("stack_prev", in: config.tilerHotkeys), label: "stack_prev") { [weak self] in
            self?.dispatcher.perform(.cycleZoneStack(direction: .previous))
        }
        // System: window hints (label each window, type to focus) + config reload hotkey.
        bindAction(config.resolvedHotkey("window_hints", in: config.systemHotkeys), label: "window_hints") { [weak self] in
            self?.dispatcher.perform(.toggleWindowHints)
        }
        // Window peek: hints scoped to the focused window's zone (opt-in — only bound when a `peek`
        // hotkey is set; also via palette/CLI/MCP).
        bindAction(config.resolvedHotkey("peek", in: config.systemHotkeys), label: "peek") { [weak self] in
            self?.dispatcher.perform(.peekZone)
        }
        // Session sandbox: hide-all-but-focused / restore (opt-in `sandbox` hotkey; also palette/CLI/MCP).
        bindAction(config.resolvedHotkey("sandbox", in: config.systemHotkeys), label: "sandbox") { [weak self] in
            self?.dispatcher.perform(.sandboxToggle)
        }
        // Exposé replacement: lay all windows out in a grid with jump labels (opt-in `expose` hotkey).
        // Routed through the dispatcher so the hotkey, MCP, IPC, CLI and URL all share one path.
        bindAction(config.resolvedHotkey("expose", in: config.systemHotkeys), label: "expose") { [weak self] in
            self?.dispatcher.perform(.toggleExpose)
        }
        // Chrome tab-strip toggle (opt-in `chrome_tabs` hotkey; only acts when Chrome is frontmost).
        bindAction(config.resolvedHotkey("chrome_tabs", in: config.systemHotkeys), label: "chrome_tabs") { [weak self] in
            self?.chromeTabs.toggle()
        }
        bindAction(config.resolvedHotkey("reload", in: config.systemHotkeys), label: "reload") { [weak self] in
            self?.dispatcher.perform(.reloadConfig)
        }
        // Command palette — opt-in: only bound when [command_palette] enabled. When [nl] is also on,
        // the palette doubles as the natural-language box (type a request, ⏎ asks the on-device model).
        if config.commandPaletteEnabled {
            bindAction(config.resolvedHotkey("command_palette", in: config.systemHotkeys), label: "command_palette") { [weak self] in
                self?.commandPalette.toggle()
            }
        }
    }

    /// The menubar mark: a 2x2 zone grid with the top-left zone filled (echoes the app icon).
    /// A **template** image — macOS renders it in the correct ink for the *actual* menu-bar
    /// appearance (white on a dark menu bar, black on a light one), including the tricky case of
    /// a translucent menu bar darkened by the wallpaper while the system is in Light mode. That
    /// case is exactly what broke the old colored/manually-flipped glyph (the appearance signal
    /// didn't fire, so the black lines vanished on dark). Monochrome, so the amber accent lives
    /// in the app icon + hint badges rather than the menu bar.
    static func menubarGlyph() -> NSImage {
        let s: CGFloat = 18
        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
            let inset: CGFloat = 2.5
            let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
            let cx = rect.midX, cy = rect.midY
            let lw: CGFloat = 1.4
            let ink = NSColor.black   // template: used as the alpha mask; macOS recolors it
            let outline = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            // Filled top-left quadrant (the accent zone), clipped to the rounded outline.
            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            ink.set()
            NSBezierPath(rect: NSRect(x: rect.minX, y: cy, width: cx - rect.minX, height: rect.maxY - cy)).fill()
            NSGraphicsContext.restoreGraphicsState()
            outline.lineWidth = lw; outline.stroke()
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: cx, y: rect.minY)); cross.line(to: NSPoint(x: cx, y: rect.maxY))
            cross.move(to: NSPoint(x: rect.minX, y: cy)); cross.line(to: NSPoint(x: rect.maxX, y: cy))
            cross.lineWidth = lw; cross.stroke()
            return true
        }
        img.isTemplate = true   // let AppKit adapt it to the menu-bar appearance
        return img
    }

    /// The menu-bar Spaces widget (Phase 3) — gated by [ui] spaces_menubar + the experimental
    /// real-Spaces toggle. Reads live config via closures so a reload re-evaluates the gate.
    func setupSpacesMenubar() {
        let c = SpacesMenubarController(
            enabled: { [weak self] in self?.config.spacesMenubar ?? false },
            realSpaces: { [weak self] in self?.config.experimentalRealSpaces ?? false },
            switchMethod: { [weak self] in self?.config.spaceSwitchMethod ?? "auto" },
            bracketStyle: { [weak self] in self?.config.spacesMenubarBracket ?? "bold" })
        spacesMenubar = c
        c.refresh()
    }

    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.image = AgentController.menubarGlyph()   // template adapts automatically
        item.button?.title = ""
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "ZoneTilerWM", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "About ZoneTilerWM", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        let tutorialItem = NSMenuItem(title: "Tutorial / Getting Started", action: #selector(openTutorial), keyEquivalent: "")
        tutorialItem.target = self
        menu.addItem(tutorialItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let analyticsItem = NSMenuItem(title: "Window Analytics…", action: #selector(openAnalytics), keyEquivalent: "")
        analyticsItem.target = self
        menu.addItem(analyticsItem)
        // No manual "Reload Config" item — the config file-watcher live-reloads on every save, so a
        // manual reload is redundant. (The action is still reachable programmatically via the dispatcher.)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    @objc func openAnalytics() {
        if analytics == nil {
            analytics = AnalyticsWindowController(model: SettingsModel(configURL: configURL, config: config, memory: learnedMemory))
        }
        analytics?.show()
    }

    @objc func openSettings() {
        if settings == nil {
            settings = SettingsWindowController(model: SettingsModel(configURL: configURL, config: config, memory: learnedMemory))
        }
        settings?.show()
    }

    @objc func openAbout() {
        if about == nil { about = AboutWindowController() }
        about?.show()
    }

    @objc func openTutorial() {
        if tutorial == nil { tutorial = TutorialWindowController() }
        tutorial?.show()
    }

    /// QA / debug entry point to show the command palette (the normal trigger is the gated hotkey).
    func showCommandPalette() { commandPalette.show() }

    /// QA / debug entry point to force the zone HUD on (the normal trigger is the modifier hold).
    /// ZT_HUD_HIGHLIGHT=<key> also previews that zone (screenshot the tile-on-release highlight).
    func showZoneHUDForQA() {
        let env = ProcessInfo.processInfo.environment
        if let z = env["ZT_HUD_HIGHLIGHT"], !z.isEmpty {
            zoneHUD.forceShow(highlight: z, tile: Int(env["ZT_HUD_TILE"] ?? "") ?? 0)
        } else {
            zoneHUD.forceShow()
        }
    }
    func dragSnapForQA() { dragSnap.forceSnap() }
    func breakScreenForQA() { breakScreen.forceShow() }
    func showExposeForQA() { expose.enter() }   // live exposé overlay (glass material) for screenshot QA

    /// Deterministic, windowless render of a visual overlay to a PNG (QA / Gemini visual grading).
    /// No app loop, no display capture — draws the overlay view into a bitmap over a neutral backdrop.
    /// Deterministic render of a settings tab to PNG (QA / Gemini grading) via SwiftUI ImageRenderer.
    func renderSettingsPNG(_ tab: String, to path: String) {
        let model = SettingsModel(configURL: configURL, config: config, memory: learnedMemory)
        let data = MainActor.assumeIsolated { SettingsRender.png(model: model, tab: tab) }
        if let data, (try? data.write(to: URL(fileURLWithPath: path))) != nil { log("zt-agent: rendered settings '\(tab)' → \(path)") }
        else { log("zt-agent: render settings '\(tab)' failed") }
    }

    func renderOverlayPNG(_ which: String, to path: String) {
        guard let screen = screens.screenUnderMouse() ?? screens.mainScreen() else { log("render: no screen"); return }
        // Optional real-desktop backdrop (ZT_RENDER_BG=/path.png) so the dim is judged over content.
        let bg = ProcessInfo.processInfo.environment["ZT_RENDER_BG"].flatMap { NSImage(contentsOfFile: $0) }
        var data: Data?
        switch which {
        case "hud":
            let info = ZoneCalculator.ScreenInfo(name: screen.name, frame: screen.frame)
            let cfg = config.zoneConfig
            let resolved = ZoneCalculator.computeZones(screen: info, config: cfg)
            let zones = resolved.zones
            let grid = cfg.grids[resolved.layoutKey]
            let (gv, gh) = GridLines.positions(frame: screen.frame, cols: grid?.cols ?? 0, rows: grid?.rows ?? 0) { _, _ in 0 }
            // ZT_HUD_HIGHLIGHT=<key> previews a zone; ZT_HUD_TILE=<index> picks the cycle placement.
            let env = ProcessInfo.processInfo.environment
            let hl: (key: String, tile: Int)? = env["ZT_HUD_HIGHLIGHT"].flatMap { $0.isEmpty ? nil : $0 }
                .map { (key: $0, tile: Int(env["ZT_HUD_TILE"] ?? "") ?? 0) }
            data = ZoneHUDOverlay.renderPNG(tilesByKey: zones, caps: ZoneHUD.caps(zones: zones),
                                            gridV: gv, gridH: gh, screenCGFrame: screen.frame,
                                            highlight: hl, backdropImage: bg)
        case "break":
            let m = BreakScreen.message(restSec: 300, workCount: 3)
            data = BreakScreenOverlay.renderPNG(title: m.title, subtitle: m.subtitle,
                                                size: NSSize(width: screen.fullFrame.w, height: screen.fullFrame.h), backdropImage: bg)
        case "mc":
            // Fake a 2×2 exposé layout so the overlay's badges + × buttons can be graded headlessly.
            let f = screen.frame, barH = 240.0, mx = f.w * 0.06
            let my = (f.h - barH) * 0.08
            let cw = (f.w - 3 * mx) / 2, ch = ((f.h - barH) - 3 * my) / 2
            let tiles = [(0, 0), (1, 0), (0, 1), (1, 1)].enumerated().map { i, p in
                MissionControl.Tile(windowId: i + 1, frame: ZTRect(
                    x: f.x + mx + Double(p.0) * (cw + mx),
                    y: f.y + barH + my + Double(p.1) * (ch + my),
                    w: cw, h: ch))
            }
            let mockSpaces = [
                MissionControlOverlay.SpaceInfo(name: "Desktop 1", windows: [
                    MissionControlOverlay.SpaceMiniWindow(key: "A", badgeColor: NSColor(red: 0.85, green: 0.92, blue: 0.97, alpha: 0.97)),
                    MissionControlOverlay.SpaceMiniWindow(key: "S", badgeColor: NSColor(red: 0.85, green: 0.95, blue: 0.88, alpha: 0.97))
                ]),
                MissionControlOverlay.SpaceInfo(name: "Desktop 2", windows: [
                    MissionControlOverlay.SpaceMiniWindow(key: "D", badgeColor: NSColor(red: 0.98, green: 0.92, blue: 0.85, alpha: 0.97))
                ])
            ]
            data = MissionControlOverlay.renderPNG(hints: MissionControl.hints(for: tiles), screenCGFrame: f, spaces: mockSpaces, selectedSpaceIndex: 0, selectedWindowId: tiles.first?.windowId, backdropImage: bg)
        default: break
        }
        if let data, (try? data.write(to: URL(fileURLWithPath: path))) != nil { log("zt-agent: rendered \(which) → \(path)") }
        else { log("zt-agent: render \(which) failed") }
    }

    /// First launch: present the getting-started tutorial once (in EVERY build — dev included), and,
    /// whenever Accessibility isn't granted yet, the permission guide. Deferred onto the main run loop
    /// because doing it synchronously during bootstrap (before `NSApp.run()`) left a fresh launch of
    /// this `.accessory` menubar app with no visible window — the bug a first-time user hit: "nothing
    /// at all" (the dev never sees it; the dev machine is already trusted). `force` (QA / the
    /// `ZT_FORCE_ONBOARDING` env) shows both regardless of trust + the first-run sentinel.
    func showFirstRunIfNeeded(force: Bool = false) {
        let force = force || ProcessInfo.processInfo.environment["ZT_FORCE_ONBOARDING"] != nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Tutorial first so the (more urgent) permission guide lands on top.
            if force || !self.firstRunDone {
                if self.tutorial == nil { self.tutorial = TutorialWindowController() }
                self.tutorial?.show()
                self.markFirstRunDone()
            }
            self.onboarding.showIfNeeded(force: force) {
                log("zt-agent: Accessibility granted — window moves enabled")
            }
        }
    }

    /// One-time first-run marker, a file beside the live config so it survives rebuilds and is
    /// consistent whether launched as the `.app` or from the command line (UserDefaults' domain is
    /// not, for a bundle-less CLI launch).
    private var firstRunSentinelURL: URL {
        configURL.deletingLastPathComponent().appendingPathComponent(".first_run_done")
    }
    private var firstRunDone: Bool { FileManager.default.fileExists(atPath: firstRunSentinelURL.path) }
    private func markFirstRunDone() { try? Data().write(to: firstRunSentinelURL) }
}