// AgentController+Setup.swift — borders/coordinator, hotkey binding, feature reconcilers, rules,
// Pomodoro, config-watch/URL handlers. Split out of main.swift (god-object → extensions). Same module.

import Foundation
import AppKit
import ZTCore
import ZTSystem
import ZTUI

extension AgentController {

    /// Apply the [borders] config to the focus-border controller (also on every live reload).
    /// ZT_BORDERS=1 force-enables it for QA regardless of the config toggle.
    func applyBorders(_ cfg: ConfigLoader.LoadedConfig) {
        let b = cfg.borders
        let env = ProcessInfo.processInfo.environment
        let forced = env["ZT_BORDERS"] == "1"
        let backendName = env["ZT_BORDERS_BACKEND"] ?? b.backend   // QA override
        focusBorder.apply(
            enabled: b.enabled || forced,
            backend: BorderBackend(rawValue: backendName) ?? .overlay,
            style: BorderStyle(color: b.color, width: b.width, cornerRadius: b.cornerRadius, inset: 0, lineStyle: BorderLineStyle(rawValue: b.style) ?? .solid),
            prediction: b.prediction)
    }

    /// Runtime focus-border toggle (the `borders` action / `zonetiler-cli borders --enabled on|off`) —
    /// no config edit. Re-applies the current config's style/backend with the given `enabled`; the next
    /// config reload resets it to the configured value.
    func setBordersEnabled(_ on: Bool) {
        let b = config.borders
        let backendName = ProcessInfo.processInfo.environment["ZT_BORDERS_BACKEND"] ?? b.backend
        focusBorder.apply(enabled: on, backend: BorderBackend(rawValue: backendName) ?? .overlay,
                          style: BorderStyle(color: b.color, width: b.width, cornerRadius: b.cornerRadius, inset: 0, lineStyle: BorderLineStyle(rawValue: b.style) ?? .solid),
                          prediction: b.prediction)
        log("zt-agent: focus border \(on ? "on" : "off") (runtime)")
    }

    static func makeCoordinator(config: ConfigLoader.LoadedConfig, windowSystem: WindowSystem,
                                        screens: ScreenProvider, memory: WindowMemory?,
                                        monitorManager: MonitorManager, storage: Storage?,
                                        resizeManager: ResizeManager, floats: FloatSet) -> TilerCoordinator {
        TilerCoordinator(windowSystem: windowSystem, screenProvider: screens,
                         zoneConfig: config.zoneConfig, placementStrategy: config.placementStrategy,
                         offsetProvider: { [weak resizeManager] m, a, i in
                             resizeManager?.getOffset(monitor: m, axis: a, index: i) ?? 0
                         },
                         isFloated: { [weak floats] in floats?.contains($0) ?? false },
                         memory: memory, monitorManager: monitorManager, storage: storage,
                         appZones: config.windowMemory.enabled ? config.windowMemory.appZones : [:])
    }

    /// Zone keys = union of keys across all layouts (excluding the "default" fallback marker).
    func zoneKeys() -> [String] {
        var keys = Set<String>()
        for (_, zones) in config.zoneConfig.layouts {
            for key in zones.keys where key != "default" { keys.insert(key) }
        }
        return keys.sorted()
    }

    func bindAppHotkeys(_ group: ConfigLoader.AppHotkeyGroup, label: String) {
        let mask = KeyMap.modifierMask(for: group.modifier)
        guard mask != 0 else { log("zt-agent: \(label) has no usable modifier \(group.modifier)"); return }
        var bound = 0
        for (key, app) in group.apps {
            guard let code = KeyMap.keyCode(for: key) else { continue }
            if binder.bind(keyCode: code, modifiers: mask, action: { [weak self] in
                self?.dispatcher.perform(.appToggle(app: app))
            }) {
                bound += 1
            }
        }
        log("zt-agent: bound \(bound)/\(group.apps.count) \(label) app hotkeys")
    }

    /// Bind each [[app_groups]] entry's hotkey to summon/dismiss that group. Reload-safe: called from
    /// bindAllHotkeys (after unbindAll); the per-group controller reads the live config by name so a
    /// renamed / re-app'd group stays correct without rebuilding it.
    func bindAppGroupHotkeys() {
        guard config.appGroupsEnabled else { return }   // gated by the App Groups header toggle ([ui] app_groups_enabled)
        var bound = 0
        for g in config.appGroups where g.hotkey.count >= 2 {
            let mods = config.aliases[g.hotkey[0]] ?? [g.hotkey[0]]
            let mask = KeyMap.modifierMask(for: mods)
            guard mask != 0, let code = KeyMap.keyCode(for: g.hotkey[1]) else { continue }
            let name = g.name
            if binder.bind(keyCode: code, modifiers: mask, action: { [weak self] in
                _ = self?.appGroupController(named: name).toggle()
            }) { bound += 1 }
        }
        if bound > 0 { log("zt-agent: bound \(bound) app-group hotkeys") }
    }

    /// The summon/dismiss controller for one app group, created on demand and reused across reloads
    /// so its summoned + auto-dismiss state survives. Reads apps/auto-dismiss live by name.
    func appGroupController(named name: String) -> ScratchpadController {
        if let c = appGroupControllers[name] { return c }
        let c = ScratchpadController(
            apps: { [unowned self] in self.config.appGroups.first { $0.name == name }?.apps ?? [] },
            autoDismiss: { [unowned self] in self.config.appGroups.first { $0.name == name }?.autoDismiss ?? true })
        appGroupControllers[name] = c
        return c
    }

    func bindAutoTile(modifier: [String], key: String) {
        guard let code = KeyMap.keyCode(for: key) else { return }
        let mask = KeyMap.modifierMask(for: modifier)
        let ok = binder.bind(keyCode: code, modifiers: mask) { [weak self] in
            guard let self else { return }
            if case .autoTiled(let moves) = self.dispatcher.perform(.autoTileScreen) {
                log("zt-agent: auto-tile -> \(moves.count) moves")
            }
        }
        if !ok { log("zt-agent: auto-tile hotkey \(modifier)+\(key) -> FAILED") }
    }

    func bindZoneHotkeys(modifier: [String], zoneKeys: [String]) {
        let mask = KeyMap.modifierMask(for: modifier)
        guard mask != 0 else { log("zt-agent: empty/unknown modifier \(modifier)"); return }
        var bound = 0
        for zoneKey in zoneKeys {
            guard let code = KeyMap.keyCode(for: zoneKey) else { continue }
            let ok = binder.bind(keyCode: code, modifiers: mask) { [weak self] in
                guard let self else { return }
                // If the zone HUD picker is up in tile-on-release mode, the keypress previews (highlights)
                // the zone and the move is committed on modifier-release; otherwise tile immediately.
                if self.zoneHUD.previewIfShowing(zoneKey) { return }
                self.tileFocusedToZone(zoneKey)
            }
            if ok { bound += 1 } else { log("zt-agent: hotkey for '\(zoneKey)' FAILED to register (taken by another app?)") }
        }
        log("zt-agent: bound \(bound)/\(zoneKeys.count) zone hotkeys with modifier \(modifier)")
    }

    /// Tile the focused window to a zone key (the shared path for the Carbon hotkey + the HUD's
    /// release-commit). `tile == nil` → the coordinator auto-picks/cycles (legacy / immediate mode);
    /// `tile != nil` → WYSIWYG placement at that exact cycle index (the on-release picker, so commit
    /// equals the preview). Flashes the target frame on success.
    func tileFocusedToZone(_ zoneKey: String, tile: Int? = nil) {
        if let tile {
            switch coordinator.moveFocusedToZone(zoneKey, tileIndex: tile) {
            case .success(let o):
                log("zt-agent: '\(zoneKey)' -> tile \(o.tileIndex) (explicit) applied=\(o.applied)")
                if o.applied { flash.flash(o.target) }
            case .failure(let e): log("zt-agent: '\(zoneKey)' -> \(e)")
            }
            return
        }
        switch dispatcher.perform(.tileFocusedToZone(zone: zoneKey)) {
        case .tiled(_, _, let tileIndex, let target, let applied):
            log("zt-agent: '\(zoneKey)' -> tile \(tileIndex) applied=\(applied)")
            flash.flash(target)
        case .failed(let reason): log("zt-agent: '\(zoneKey)' -> \(reason)")
        default: break
        }
    }

    func bindFocusHotkeys(modifier: [String], zoneKeys: [String]) {
        let mask = KeyMap.modifierMask(for: modifier)
        guard mask != 0 else { return }
        var bound = 0
        for zoneKey in zoneKeys {
            guard let code = KeyMap.keyCode(for: zoneKey) else { continue }
            if binder.bind(keyCode: code, modifiers: mask, action: { [weak self] in
                guard let self else { return }
                if case .focusCycled(let id) = self.dispatcher.perform(.cycleFocus(zone: zoneKey)),
                   id != nil, let f = self.windowSystem.focusedWindow()?.frame {
                    self.flash.flash(f)
                }
            }) { bound += 1 }
        }
        log("zt-agent: bound \(bound)/\(zoneKeys.count) focus-cycle hotkeys with modifier \(modifier)")
    }

    /// `devices` is used only to decide whether the hotkey is worth binding (need ≥2 to cycle);
    /// the actual device list + shortcut are read live by the dispatcher from config.
    func bindAudioHotkey(modifier: [String], key: String, devices: [String], shortcut: String?) {
        guard devices.count >= 2, let code = KeyMap.keyCode(for: key) else { return }
        let mask = KeyMap.modifierMask(for: modifier)
        guard mask != 0 else { return }
        let ok = binder.bind(keyCode: code, modifiers: mask) { [weak self] in
            guard let self else { return }
            if case .audioSwitched(let name) = self.dispatcher.perform(.switchAudio(device: .next)),
               let name { log("zt-agent: audio -> \(name)") }
        }
        if !ok { log("zt-agent: audio hotkey \(modifier)+\(key) -> FAILED") }
    }

    /// Generic hotkey binder for resolved (modifier, key) pairs.
    func bindAction(_ resolved: (modifier: [String], key: String)?, label: String, action: @escaping () -> Void) {
        guard let h = resolved, let code = KeyMap.keyCode(for: h.key) else { return }
        let mask = KeyMap.modifierMask(for: h.modifier)
        guard mask != 0 else { return }
        let ok = binder.bind(keyCode: code, modifiers: mask, action: action)
        // Quiet on success (the startup log was noisy); only surface binds that failed to
        // register — usually a combo already taken by another app or a config conflict.
        if !ok { log("zt-agent: \(label) hotkey \(h.modifier)+\(h.key) -> FAILED (taken by another app or a conflict?)") }
    }

    /// Passive focus-time tracking (port of window_cache.lua's windowFocused subscription):
    /// seed all visible windows once, then poll the focused window every second so the
    /// auto-tiler's working-set age cull sees real per-window focus times. Poll granularity is
    /// negligible against the 1800s default cull threshold.
    func setupFocusTracking() {
        let now = Int(Date().timeIntervalSince1970)
        coordinator.seedFocusTimes(now: now)
        manualMoveRelearn = ManualMoveRelearnController(
            coordinator: coordinator, enumerate: { [weak self] in self?.enumerateLiveWindows() ?? [] })
        manualMoveRelearn.enabled = config.relearnOnMoveEnabled
        dockPreview = DockPreviewController()
        dockPreview.thumbWidth = CGFloat(config.dockPreviewWidth)
        dockPreview.enabled = config.dockPreviewsEnabled   // gated default-off; installs a passive mouse monitor
        focusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.coordinator.noteFocusedWindow(now: Int(Date().timeIntervalSince1970))
            self.evaluateOnOpenRules()
            self.evaluateOnFocusRules()
            self.manualMoveRelearn.tick()   // feedback 7b: re-learn a window's zone after a manual drag
        }
    }

    /// All currently-live windows as id → app name (0 AX, CGWindowList via the WindowSystem).
    func enumerateWindows() -> [Int: String] {
        var map: [Int: String] = [:]
        for s in screens.allScreens() {
            for w in windowSystem.windows(onScreen: s.uuid) { map[w.id] = w.appName }
        }
        return map
    }

    /// All currently-live windows with full geometry + screen (0 AX, CGWindowList via the
    /// WindowSystem). Used by the manual-move re-learn detector, which needs each window's frame +
    /// screenUUID, not just its app name.
    func enumerateLiveWindows() -> [LiveWindow] {
        screens.allScreens().flatMap { windowSystem.windows(onScreen: $0.uuid) }
    }

    /// Fire on-open rules for windows that appeared since the last tick. Baseline-seeded on the
    /// first run so rules never retro-fire on windows that already existed (at launch or when a
    /// rule is added via live reload).
    func evaluateOnOpenRules() {
        guard rulesEngine.hasRules(for: .onOpen) else { return }   // skip the enumeration entirely
        let current = enumerateWindows()
        let currentIds = Set(current.keys)
        defer { lastWindowIds = currentIds }
        guard rulesSeeded else { rulesSeeded = true; return }      // baseline only on first run
        for id in currentIds.subtracting(lastWindowIds) {
            guard let app = current[id] else { continue }
            for rule in rulesEngine.matching(app: app, trigger: .onOpen) { apply(rule, toWindow: id) }
        }
    }

    /// Fire on-focus rules when the focused window changes (not every poll). Seed-skips the first
    /// run so a rule never fires on whatever happened to be focused at launch.
    func evaluateOnFocusRules() {
        guard rulesEngine.hasRules(for: .onFocus), let focused = windowSystem.focusedWindow() else { return }
        guard focused.id != lastFocusedRuleWindowId else { return }
        lastFocusedRuleWindowId = focused.id
        guard focusRulesSeeded else { focusRulesSeeded = true; return }
        for rule in rulesEngine.matching(app: focused.appName, trigger: .onFocus) { apply(rule, toWindow: focused.id) }
    }

    /// Fire on-display-change rules for every current window of a matching app (re-place apps on
    /// dock/undock). Called after monitors are re-registered.
    func evaluateDisplayChangeRules() {
        guard rulesEngine.hasRules(for: .onDisplayChange) else { return }
        for (id, app) in enumerateWindows() {
            for rule in rulesEngine.matching(app: app, trigger: .onDisplayChange) { apply(rule, toWindow: id) }
        }
    }

    /// Execute a rule for a specific window. Tile actions target that window directly; other
    /// actions fall back to focused-window semantics (a new window is usually focused anyway).
    func apply(_ rule: Rule, toWindow id: Int) {
        if case .tileFocusedToZone(let zone) = rule.action {
            if let o = coordinator.moveWindow(windowId: id, toZone: zone) {
                log("zt-agent: rule \(rule.app)/\(rule.trigger.rawValue) → tile \(o.zoneKey) applied=\(o.applied)")
            }
        } else {
            dispatcher.perform(rule.action)
        }
    }

    /// One-time: the menubar item + the 1s countdown timer. Pomodoro hotkeys are (re)bound in
    /// bindAllHotkeys so they pick up config-reload changes.
    func setupPomodoro() {
        let item = NSStatusBar.system.statusItem(withLength: 0)   // hidden until active
        item.button?.title = ""
        let pill = PomodoroPillView(frame: .zero)
        pill.isHidden = true
        if let b = item.button {
            b.addSubview(pill)
            NSLayoutConstraint.activate([
                pill.leadingAnchor.constraint(equalTo: b.leadingAnchor),
                pill.trailingAnchor.constraint(equalTo: b.trailingAnchor),
                pill.topAnchor.constraint(equalTo: b.topAnchor),
                pill.bottomAnchor.constraint(equalTo: b.bottomAnchor),
            ])
        }
        pomodoroPill = pill
        pomodoroItem = item
        pomodoroTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let event = self.pomodoro.tick()
            self.refreshPomodoro()
            // Retro break overlay on work→break (gated by [break_screen]). timeLeft was just set to
            // the rest period; workCount was just incremented.
            self.breakScreen.handle(event, restSec: self.pomodoro.timeLeft, workCount: self.pomodoro.workCount)
        }
    }

    func bindPomodoroHotkeys() {
        // The pomodoro dispatcher hook mutates the state machine AND refreshes the menubar UI.
        bindAction(config.resolvedHotkey("enable", in: config.pomodoroHotkeys), label: "pomodoro.enable") { [weak self] in
            self?.dispatcher.perform(.pomodoro(.enable))
        }
        bindAction(config.resolvedHotkey("disable", in: config.pomodoroHotkeys), label: "pomodoro.disable") { [weak self] in
            self?.dispatcher.perform(.pomodoro(.disable))
        }
        bindAction(config.resolvedHotkey("reset", in: config.pomodoroHotkeys), label: "pomodoro.reset") { [weak self] in
            self?.dispatcher.perform(.pomodoro(.reset))
        }
    }

    /// (Re)bind every global hotkey from the current config. Safe to call repeatedly: clears
    /// all existing Carbon registrations first. This is the rebind half of a live reload.
    func bindAllHotkeys() {
        binder.unbindAll()
        let keys = zoneKeys()
        bindZoneHotkeys(modifier: config.tilerModifier, zoneKeys: keys)
        bindFocusHotkeys(modifier: config.focusModifier, zoneKeys: keys)
        if let hyper = config.aliases["HYPER"] { bindAutoTile(modifier: hyper, key: "return") }
        bindAppHotkeys(config.appCuts, label: "appCuts")
        bindAppHotkeys(config.hyperAppCuts, label: "hyperAppCuts")
        for layer in config.appLayers { bindAppHotkeys(layer.group, label: "app_layers.\(layer.name)") }   // N1
        bindAppGroupHotkeys()
        if let audioKey = config.audioHotkeyKey {
            bindAudioHotkey(modifier: config.audioHotkeyModifier, key: audioKey,
                            devices: config.audioDevices, shortcut: config.audioShortcutCallback)
        }
        bindMiscHotkeys(config)
        bindPomodoroHotkeys()
        logHotkeyConflicts()
    }

    /// Non-blocking: warn (stderr) about any combo bound to more than one action. The binds still
    /// happen — last-registered wins in Carbon — but the user is told which shortcuts collide so
    /// they can resolve it in Settings. Runs on startup and after every live reload.
    func logHotkeyConflicts() {
        let conflicts = config.hotkeyConflicts()
        guard !conflicts.isEmpty else { return }
        log("zt-agent: WARNING — \(conflicts.count) hotkey conflict(s):")
        for c in conflicts { log("  \(c.description)") }
    }

    // MARK: - Live config reload

    /// Watch config.toml; on a debounced change, re-decode + validate + apply in place. An
    /// invalid edit is logged and ignored (the running config is kept), never half-applied.
    func setupConfigWatch() {
        configWatcher = ConfigWatcher(url: configURL) { [weak self] in self?.reloadFromDisk() }
        configWatcher?.start()
    }

    /// Start the Unix-domain socket the zt-mcp shim forwards to. Actions route through the same
    /// dispatcher the hotkeys use; queries through the read-only (0-AX) arrangement provider. The
    /// handler runs on the main queue (AgentSocketServer's accept source), so touching the
    /// coordinator/config here is on-main like every other callback.
    /// Register for `zonetiler://` URLs (declared in the .app's CFBundleURLTypes). macOS delivers
    /// the GURL Apple Event to the running agent; we parse it through the shared ActionParser and
    /// dispatch. Only effective from the bundled .app — the bare dev binary registers no scheme.
    func setupURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let comps = URLComponents(string: raw) else { return }
        // zonetiler://<action>?<params> — the action name is the host (fall back to the path).
        let name = comps.host ?? String(comps.path.drop(while: { $0 == "/" }))
        var params: [String: String] = [:]
        for item in comps.queryItems ?? [] { params[item.name] = item.value ?? "" }
        switch ActionParser.parse(urlPath: name, query: params) {
        case .success(let request):
            log("zt-agent: url \(raw) → \(dispatcher.perform(request))")
        case .failure(let e):
            log("zt-agent: url \(raw) rejected: \(CLIFormat.describe(e))")
        }
    }

    /// Start the zone HUD's modifier monitor iff [zone_hud] enabled. Idempotent; reconciled on reload.
    func setupZoneHUD() { reconcileZoneHUD() }
    func reconcileZoneHUD() {
        if config.zoneHUDEnabled { zoneHUD.start() } else { zoneHUD.stop() }
    }

    /// Start the drag-to-snap mouse monitor iff [drag_snap] enabled. Idempotent; reconciled on reload.
    func setupDragSnap() { reconcileDragSnap() }
    func reconcileDragSnap() {
        if config.dragSnapEnabled { dragSnap.start() } else { dragSnap.stop() }
    }

    /// Start the focus-follows-mouse monitor iff [focus_follows_mouse] enabled. Idempotent; reconciled on reload.
    func setupFocusFollowsMouse() { reconcileFocusFollowsMouse() }
    func reconcileFocusFollowsMouse() {
        if config.focusFollowsMouseEnabled { ffm.start() } else { ffm.stop() }
    }

    /// Start the app-launcher hold-to-reveal HUD iff [app_launcher_hud] enabled. Idempotent; reconciled on reload.
    func reconcileAppLauncherHUD() {
        if config.appLauncherHUDEnabled { appLauncherHUD.start() } else { appLauncherHUD.stop() }
    }

    /// Start the arrangement event stream iff [events] enabled. Idempotent; reconciled on reload.
    func setupEventStream() { reconcileEventStream() }
    func reconcileEventStream() {
        if config.eventsEnabled { eventStream.start() } else { eventStream.stop() }
    }

    func setupIPCServer() { reconcileIPCServer() }

    /// Start/stop the IPC socket to match `[automation] enabled`. Idempotent — safe to call on
    /// startup and after every live reload.
    func reconcileIPCServer() {
        if config.automationEnabled {
            guard socketServer == nil else { return }   // already running
            let server = AgentSocketServer(path: AgentSocket.defaultPath()) { [weak self] request in
                guard let self else { return .error("agent shutting down") }
                switch request {
                case .action(let action): return .action(self.dispatcher.perform(action))
                case .query(let query):   return .query(self.arrangementQuery.answer(query))
                }
            }
            server.start()
            socketServer = server
        } else if socketServer != nil {
            socketServer?.stop()
            socketServer = nil
            log("zt-agent: automation disabled — IPC socket stopped")
        }
    }

}