// zt-agent — minimal LSUIElement menubar agent: binds the config's tiler modifier + each
// zone key (e.g. ⌃⌘h) to TilerCoordinator.moveFocusedToZone via global Carbon hotkeys, shows
// a status-bar item, and runs the app run loop. First real keypress -> tile.
//
//   zt-agent [config_path]   (default ~/.hammerspoon/config.toml)

import Foundation
import AppKit
import ZTCore
import ZTSystem
import ZTUI

func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

/// Runtime set of "floated" window ids (excluded from auto-tile). A reference type so the
/// coordinator's isFloated closure can capture it without capturing the controller.
final class FloatSet {
    private var ids = Set<Int>()
    func contains(_ id: Int) -> Bool { ids.contains(id) }
    @discardableResult func toggle(_ id: Int) -> Bool {
        if ids.contains(id) { ids.remove(id); return false }
        ids.insert(id); return true
    }
}

let home = FileManager.default.homeDirectoryForCurrentUser

/// Resolve the config path. An explicit arg (CLI / `run.sh`) wins. Otherwise — the bundled
/// `.app` case, launched with no args by Finder/Dock/login — use the standard user location
/// `~/.config/ZoneTilerWM/config.toml`, seeding it from the bundled default on first run so a
/// freshly-installed app starts with a working config instead of failing to launch.
func resolveConfigURL() -> URL {
    // The live config ALWAYS lives in the standard user location, alongside the JSON state —
    // never the project folder or the app bundle. The agent reads/writes only this file.
    let fm = FileManager.default
    let dir = home.appendingPathComponent(".config/ZoneTilerWM", isDirectory: true)
    let url = dir.appendingPathComponent("config.toml")
    guard !fm.fileExists(atPath: url.path) else { return url }

    // First run only: migrate an existing config into the canonical location, then never look
    // elsewhere again. Source priority: an explicit path arg (dev / run.sh), the legacy
    // Hammerspoon config, then the bundled default.
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let argPath = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : nil
    let legacy = home.appendingPathComponent(".hammerspoon/config.toml")
    let sources = [argPath, legacy, Bundle.main.url(forResource: "config", withExtension: "toml")]
        .compactMap { $0 }
    if let source = sources.first(where: { fm.fileExists(atPath: $0.path) }) {
        try? fm.copyItem(at: source, to: url)
        log("zt-agent: migrated config to \(url.path) (from \(source.path))")
    } else {
        log("zt-agent: no config found to migrate; expected \(url.path)")
    }
    return url
}

let configURL = resolveConfigURL()

guard let config = try? ConfigLoader.load(contentsOf: configURL) else {
    log("zt-agent: cannot load config at \(configURL.path)")
    exit(2)
}

/// A frosted-glass capsule for the Pomodoro time in the menubar: a behind-window
/// NSVisualEffectView (real vibrancy) clipped to a rounded capsule, with the time on top.
final class PomodoroPillView: NSView {
    private let effect = NSVisualEffectView()
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        effect.translatesAutoresizingMaskIntoConstraints = false
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.separatorColor.cgColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.alignment = .center
        label.textColor = .labelColor
        label.backgroundColor = .clear
        addSubview(effect)
        addSubview(label)   // on top of the effect
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            effect.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Set the text; returns the total width to use for the status-item length.
    @discardableResult func update(_ text: String) -> CGFloat {
        label.stringValue = text
        let w = (text as NSString).size(withAttributes: [.font: label.font as Any]).width
        return ceil(w) + 18
    }
}

final class AgentController: NSObject {
    private let binder = CarbonHotkeyBinder()
    private let screens: NSScreenProvider
    private let windowSystem: AXWindowSystem
    private let monitorManager: MonitorManager
    // System objects that survive a config reload (memory/storage are reloaded from disk only
    // on restart; in-session learning is persisted as it happens).
    private let learnedMemory: WindowMemory?
    private let storage: Storage?
    // Resize mode: grid-line offsets (persisted independently of window memory). The manager is
    // shared with the coordinator's offsetProvider; the modal UI lives in ResizeModeController.
    private let resizeManager = ResizeManager()
    private let resizeStorage: Storage
    private let floats = FloatSet()   // per-window float state (excluded from auto-tile)
    // The two modal sub-controllers (extracted from this composition root).
    private var resizeMode: ResizeModeController!
    private var windowHints: WindowHintsController!
    private var commandPalette: CommandPaletteController!   // gated by [command_palette] enabled
    private var zoneHUD: ZoneHUDController!                 // gated by [zone_hud] enabled
    private var dragSnap: DragSnapController!               // gated by [drag_snap] enabled
    private var breakScreen: BreakScreenController!         // gated by [break_screen] enabled
    private var scratchpad: ScratchpadController!           // gated by [scratchpad] apps
    private let sandbox = SandboxController()               // session sandbox (toggle action)
    private var ffm: FocusFollowsMouseController!           // gated by [focus_follows_mouse] enabled
    private var eventStream: EventStreamController!         // gated by [events] enabled
    // Config-derived state — rebuilt in place by applyConfig() on a live reload.
    private var coordinator: TilerCoordinator
    private var autoTilerConfig: AutoTiler.Config
    private var appSwitcher: AppSwitcher.Config
    // Declarative window rules (rebuilt on live reload). on-open detection diffs the CGWindowList
    // window-id set (0 AX) each focus tick; baseline-seeded so pre-existing windows don't fire.
    private var rulesEngine: RulesEngine
    private var lastWindowIds: Set<Int> = []
    private var rulesSeeded = false
    private var lastFocusedRuleWindowId: Int?   // on-focus: fire only when the focused window changes
    private var focusRulesSeeded = false
    // The single source of truth for executing actions. Every hotkey (and the MCP server)
    // routes through this. Built after super.init (its hooks reference self).
    private var dispatcher: ActionDispatcher!
    // Read-only resource provider (CGWindowList + config + learned store; 0 AX) and the IPC
    // socket the zt-mcp shim forwards to.
    private var arrangementQuery: ArrangementQuery!
    private var socketServer: AgentSocketServer?
    // Named layout snapshots (persisted to "layouts" under the cache dir).
    private var layouts: LayoutLibrary
    private let pomodoro: Pomodoro
    private var statusItem: NSStatusItem?
    private var pomodoroItem: NSStatusItem?
    private var pomodoroPill: PomodoroPillView?
    private var pomodoroTimer: Timer?
    private var focusTimer: Timer?
    private let flash = FlashOverlay()
    private let pomodoroBar = PomodoroBar()
    private let focusBorder = FocusBorderController()
    private var enableColorBar: Bool
    private var pomodoroIndicatorHeight: Double
    private var pomodoroIndicatorAlpha: Double
    private var pomodoroColorRemaining: NSColor
    private var pomodoroColorUsed: NSColor
    private var config: ConfigLoader.LoadedConfig
    private let configURL: URL
    private var configWatcher: ConfigWatcher?
    private var settings: SettingsWindowController?
    private var analytics: AnalyticsWindowController?
    private var about: AboutWindowController?
    private var tutorial: TutorialWindowController?
    private let onboarding = AccessibilityOnboardingController()

    init(config: ConfigLoader.LoadedConfig, configURL: URL) {
        let screens = NSScreenProvider()
        self.screens = screens
        windowSystem = AXWindowSystem(screenProvider: screens)
        monitorManager = MonitorManager()

        // Adaptive memory: load persisted preferences; learn + persist on manual tiles.
        var memory: WindowMemory?
        var store: Storage?
        if config.windowMemory.enabled {
            let s = JSONFileStorage(directory: URL(fileURLWithPath: config.windowMemory.cacheDir, isDirectory: true))
            let mem = WindowMemory(excludedApps: config.windowMemory.excludedApps, settleEnabled: true,
                                   clock: { Int(Date().timeIntervalSince1970) })
            if let saved = s.load("window_positions", as: WindowMemory.SaveData.self) { mem.load(saved) }
            memory = mem
            store = s
        }
        self.config = config
        self.configURL = configURL
        self.learnedMemory = memory
        self.storage = store

        // Resize-mode offsets persist to grid_offsets.json under the same cache dir, whether or
        // not window memory is enabled.
        let rstore = JSONFileStorage(directory: URL(fileURLWithPath: config.windowMemory.cacheDir, isDirectory: true))
        resizeStorage = rstore
        resizeManager.load(from: rstore)
        layouts = rstore.load("layouts", as: LayoutLibrary.self) ?? LayoutLibrary()
        let resize = resizeManager

        coordinator = AgentController.makeCoordinator(config: config, windowSystem: windowSystem,
                                                      screens: screens, memory: memory,
                                                      monitorManager: monitorManager, storage: store,
                                                      resizeManager: resize, floats: floats)
        autoTilerConfig = config.autoTilerConfig()
        appSwitcher = config.appSwitcher
        rulesEngine = RulesEngine(rules: config.rules)
        pomodoro = Pomodoro(config: .init(workPeriodSec: config.pomodoroWorkSec,
                                          restPeriodSec: config.pomodoroRestSec,
                                          enableColorBar: config.pomodoroEnableColorBar))
        enableColorBar = config.pomodoroEnableColorBar
        pomodoroIndicatorHeight = config.pomodoroIndicatorHeight
        pomodoroIndicatorAlpha = config.pomodoroIndicatorAlpha
        pomodoroColorRemaining = PomodoroBar.color(named: config.pomodoroColorRemaining)
        pomodoroColorUsed = PomodoroBar.color(named: config.pomodoroColorUsed)
        super.init()
        // Modal sub-controllers; their config-derived inputs read self.config so a live reload
        // is picked up automatically.
        resizeMode = ResizeModeController(
            binder: binder, screens: screens, windowSystem: windowSystem, monitorManager: monitorManager,
            resizeManager: resizeManager, resizeStorage: resizeStorage,
            zoneConfig: { [weak self] in self?.config.zoneConfig ?? ZoneConfig(grids: [:], layouts: [:], margins: Margins(enabled: false, size: 0, screen_edge: false)) })
        windowHints = WindowHintsController(
            binder: binder, screens: screens, windowSystem: windowSystem,
            keyboardLayout: { [weak self] in self?.config.keyboardLayout ?? "auto" },
            zoneConfig: { [weak self] in self?.config.zoneConfig ?? ZoneConfig(grids: [:], layouts: [:]) })
        // The action dispatcher: hooks read live state via `unowned self` (the dispatcher is owned
        // by self and never outlives it). The coordinator/config getters are closures so a live
        // reload is picked up automatically. The pomodoro hook also refreshes the menubar UI, so
        // an MCP/URL-triggered pomodoro command updates the pill immediately, not on the next tick.
        dispatcher = ActionDispatcher(hooks: .init(
            coordinator: { [unowned self] in self.coordinator },
            autoTilerConfig: { [unowned self] in self.autoTilerConfig },
            appSwitcherConfig: { [unowned self] in self.appSwitcher },
            audioDevices: { [unowned self] in self.config.audioDevices },
            audioShortcut: { [unowned self] in self.config.audioShortcutCallback },
            now: { Int(Date().timeIntervalSince1970) },
            pomodoro: { [unowned self] cmd in
                switch cmd {
                case .enable: self.pomodoro.enable()
                case .disable: _ = self.pomodoro.disable()
                case .reset: self.pomodoro.resetWork()
                }
                self.refreshPomodoro()
                return .pomodoroUpdated(active: self.pomodoro.isActive,
                                        phase: self.pomodoro.phase.rawValue,
                                        timeLeftSec: self.pomodoro.timeLeft)
            },
            toggleResizeMode: { [unowned self] in self.resizeMode.toggle() },
            toggleWindowHints: { [unowned self] in self.windowHints.toggle() },
            peekZone: { [unowned self] in self.windowHints.enterZone() },
            toggleFloat: { [unowned self] in
                guard let id = self.windowSystem.focusedWindow()?.id else { return .failed(reason: .noFocusedWindow) }
                let floating = self.floats.toggle(id)
                log("zt-agent: float window \(id) → \(floating)")
                return .floatToggled(windowId: id, floating: floating)
            },
            reloadConfig: { [unowned self] in self.reloadFromDisk() },
            saveLayout: { [unowned self] name in self.saveLayout(name) },
            applyLayout: { [unowned self] name in self.applyLayout(name) },
            syncExport: { [unowned self] in self.syncEngine().run(.export) },
            syncImport: { [unowned self] in
                let r = self.syncEngine().run(.import)
                if case .synced = r { self.adoptImportedSettings() }
                return r
            },
            applySuggestions: { [unowned self] in self.applyPlacementSuggestions() },
            scratchpad: { [unowned self] in self.scratchpad.toggle() },
            applyCluster: { [unowned self] name in self.applyCluster(name) },
            sandbox: { [unowned self] in self.sandbox.toggle() }))
        commandPalette = CommandPaletteController(perform: { [unowned self] in self.dispatcher.perform($0) })
        zoneHUD = ZoneHUDController(
            screens: screens, monitorManager: monitorManager,
            zoneConfig: { [unowned self] in self.config.zoneConfig },
            offset: { [weak resize] m, a, i in resize?.getOffset(monitor: m, axis: a, index: i) ?? 0 },
            modifier: { [unowned self] in self.config.tilerModifier },
            holdDelayMs: { [unowned self] in self.config.zoneHUDHoldDelayMs })
        dragSnap = DragSnapController(
            screens: screens, monitorManager: monitorManager,
            zoneConfig: { [unowned self] in self.config.zoneConfig },
            offset: { [weak resize] m, a, i in resize?.getOffset(monitor: m, axis: a, index: i) ?? 0 },
            modifier: { [unowned self] in self.config.tilerModifier },
            snap: { [unowned self] zone in _ = self.dispatcher.perform(.tileFocusedToZone(zone: zone)) })
        breakScreen = BreakScreenController(
            screens: screens,
            enabled: { [unowned self] in self.config.breakScreenEnabled },
            durationSec: { [unowned self] in self.config.breakScreenDurationSec })
        scratchpad = ScratchpadController(
            apps: { [unowned self] in self.config.scratchpadApps },
            autoDismiss: { [unowned self] in self.config.scratchpadAutoDismiss })
        ffm = FocusFollowsMouseController(
            windowSystem: windowSystem, screens: screens,
            delayMs: { [unowned self] in self.config.focusFollowsMouseDelayMs })
        // Read-only resource provider for the MCP `resources/*` queries. Closures read live state
        // so a config reload / resize-offset change is reflected. All reads are CGWindowList — 0 AX.
        arrangementQuery = ArrangementQuery(
            windowSystem: windowSystem, screenProvider: screens, monitorManager: monitorManager,
            zoneConfig: { [unowned self] in self.config.zoneConfig },
            offset: { [weak resizeManager] m, a, i in resizeManager?.getOffset(monitor: m, axis: a, index: i) ?? 0 },
            memory: { [unowned self] in self.learnedMemory },
            now: { Int(Date().timeIntervalSince1970) })
        eventStream = EventStreamController(
            arrangement: { [unowned self] in
                if case .arrangement(let w) = self.arrangementQuery.answer(.arrangement) { return w }
                return []
            },
            path: { [unowned self] in
                self.config.eventsPath ?? (self.config.windowMemory.cacheDir as NSString).appendingPathComponent("events.jsonl")
            },
            intervalMs: { [unowned self] in self.config.eventsIntervalMs })
        log("zt-agent: window memory \(memory != nil ? "enabled (\(config.windowMemory.cacheDir))" : "disabled")")
        applyBorders(config)
    }

    /// Apply the [borders] config to the focus-border controller (also on every live reload).
    /// ZT_BORDERS=1 force-enables it for QA regardless of the config toggle.
    private func applyBorders(_ cfg: ConfigLoader.LoadedConfig) {
        let b = cfg.borders
        let env = ProcessInfo.processInfo.environment
        let forced = env["ZT_BORDERS"] == "1"
        let backendName = env["ZT_BORDERS_BACKEND"] ?? b.backend   // QA override
        focusBorder.apply(
            enabled: b.enabled || forced,
            backend: BorderBackend(rawValue: backendName) ?? .overlay,
            style: BorderStyle(color: b.color, width: b.width, cornerRadius: b.cornerRadius, inset: 0),
            prediction: b.prediction)
    }

    private static func makeCoordinator(config: ConfigLoader.LoadedConfig, windowSystem: WindowSystem,
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
    private func zoneKeys() -> [String] {
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
                switch self.dispatcher.perform(.tileFocusedToZone(zone: zoneKey)) {
                case .tiled(_, _, let tileIndex, let target, let applied):
                    log("zt-agent: '\(zoneKey)' -> tile \(tileIndex) applied=\(applied)")
                    self.flash.flash(target)
                case .failed(let reason): log("zt-agent: '\(zoneKey)' -> \(reason)")
                default: break
                }
            }
            if ok { bound += 1 } else { log("zt-agent: hotkey for '\(zoneKey)' FAILED to register (taken by another app?)") }
        }
        log("zt-agent: bound \(bound)/\(zoneKeys.count) zone hotkeys with modifier \(modifier)")
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
        focusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.coordinator.noteFocusedWindow(now: Int(Date().timeIntervalSince1970))
            self.evaluateOnOpenRules()
            self.evaluateOnFocusRules()
        }
    }

    /// All currently-live windows as id → app name (0 AX, CGWindowList via the WindowSystem).
    private func enumerateWindows() -> [Int: String] {
        var map: [Int: String] = [:]
        for s in screens.allScreens() {
            for w in windowSystem.windows(onScreen: s.uuid) { map[w.id] = w.appName }
        }
        return map
    }

    /// Fire on-open rules for windows that appeared since the last tick. Baseline-seeded on the
    /// first run so rules never retro-fire on windows that already existed (at launch or when a
    /// rule is added via live reload).
    private func evaluateOnOpenRules() {
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
    private func evaluateOnFocusRules() {
        guard rulesEngine.hasRules(for: .onFocus), let focused = windowSystem.focusedWindow() else { return }
        guard focused.id != lastFocusedRuleWindowId else { return }
        lastFocusedRuleWindowId = focused.id
        guard focusRulesSeeded else { focusRulesSeeded = true; return }
        for rule in rulesEngine.matching(app: focused.appName, trigger: .onFocus) { apply(rule, toWindow: focused.id) }
    }

    /// Fire on-display-change rules for every current window of a matching app (re-place apps on
    /// dock/undock). Called after monitors are re-registered.
    private func evaluateDisplayChangeRules() {
        guard rulesEngine.hasRules(for: .onDisplayChange) else { return }
        for (id, app) in enumerateWindows() {
            for rule in rulesEngine.matching(app: app, trigger: .onDisplayChange) { apply(rule, toWindow: id) }
        }
    }

    /// Execute a rule for a specific window. Tile actions target that window directly; other
    /// actions fall back to focused-window semantics (a new window is usually focused anyway).
    private func apply(_ rule: Rule, toWindow id: Int) {
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

    private func bindPomodoroHotkeys() {
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

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent _: NSAppleEventDescriptor) {
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
    private func reconcileZoneHUD() {
        if config.zoneHUDEnabled { zoneHUD.start() } else { zoneHUD.stop() }
    }

    /// Start the drag-to-snap mouse monitor iff [drag_snap] enabled. Idempotent; reconciled on reload.
    func setupDragSnap() { reconcileDragSnap() }
    private func reconcileDragSnap() {
        if config.dragSnapEnabled { dragSnap.start() } else { dragSnap.stop() }
    }

    /// Start the focus-follows-mouse monitor iff [focus_follows_mouse] enabled. Idempotent; reconciled on reload.
    func setupFocusFollowsMouse() { reconcileFocusFollowsMouse() }
    private func reconcileFocusFollowsMouse() {
        if config.focusFollowsMouseEnabled { ffm.start() } else { ffm.stop() }
    }

    /// Start the arrangement event stream iff [events] enabled. Idempotent; reconciled on reload.
    func setupEventStream() { reconcileEventStream() }
    private func reconcileEventStream() {
        if config.eventsEnabled { eventStream.start() } else { eventStream.stop() }
    }

    func setupIPCServer() { reconcileIPCServer() }

    /// Start/stop the IPC socket to match `[automation] enabled`. Idempotent — safe to call on
    /// startup and after every live reload.
    private func reconcileIPCServer() {
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

    // MARK: - Layout snapshots

    /// Current arrangement as value snapshots via the read-only query provider (0 AX).
    private func currentArrangement() -> [WindowInfo] {
        if case .arrangement(let windows) = arrangementQuery.answer(.arrangement) { return windows }
        return []
    }

    /// Capture the current arrangement into a named snapshot and persist it.
    /// A SyncEngine bound to the live config dir (where config.toml actually lives) + the state dir
    /// (cache_dir) + the [sync] folder, rebuilt per call so a config reload is reflected. File-based
    /// settings sync — 0 AX, no network, no entitlements.
    private func syncEngine() -> SyncEngine {
        SyncEngine(configDir: configURL.deletingLastPathComponent().path,
                   stateDir: config.windowMemory.cacheDir,
                   syncFolder: { [unowned self] in self.config.syncFolder })
    }

    /// After a successful sync-import: re-read config.toml AND the imported state JSON so the new
    /// settings are live immediately (and the in-memory state can't overwrite the import on the
    /// next save). Layouts replace wholesale; learned positions merge (imported wins per app/monitor).
    private func adoptImportedSettings() {
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
    private func applyPlacementSuggestions() -> ActionResult {
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
    private func applyCluster(_ name: String) -> ActionResult {
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

    private func saveLayout(_ name: String) -> ActionResult {
        let snapshot = LayoutSnapshots.capture(name: name, from: currentArrangement())
        layouts = layouts.upserting(snapshot)
        resizeStorage.save("layouts", layouts)
        log("zt-agent: saved layout '\(name)' (\(snapshot.assignments.count) windows)")
        return .layoutSaved(name: name, windowCount: snapshot.assignments.count)
    }

    /// Restore a named snapshot: tile each matched window to its saved zone (window-targeted).
    private func applyLayout(_ name: String) -> ActionResult {
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
    private func applyDisplayPreset() {
        guard !config.displayPresets.isEmpty else { return }
        let names = screens.allScreens().map { $0.name }
        guard let action = DisplayPresetEngine.match(current: names, presets: config.displayPresets) else { return }
        log("zt-agent: display preset matched (\(names.joined(separator: ", "))) → \(dispatcher.perform(action))")
    }

    @discardableResult
    private func reloadFromDisk() -> Bool {
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
    private func applyConfig(_ newConfig: ConfigLoader.LoadedConfig) {
        config = newConfig
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

    private func refreshPomodoro() {
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
        bindAction(config.resolvedHotkey("reload", in: config.systemHotkeys), label: "reload") { [weak self] in
            self?.dispatcher.perform(.reloadConfig)
        }
        // Command palette — opt-in: only bound when [command_palette] enabled.
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
    private static func menubarGlyph() -> NSImage {
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
        let reloadItem = NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    @objc func reloadConfig() { reloadFromDisk() }

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
    func showZoneHUDForQA() { zoneHUD.forceShow() }
    func dragSnapForQA() { dragSnap.forceSnap() }
    func breakScreenForQA() { breakScreen.forceShow() }

    /// Deterministic, windowless render of a visual overlay to a PNG (QA / Gemini visual grading).
    /// No app loop, no display capture — draws the overlay view into a bitmap over a neutral backdrop.
    func renderOverlayPNG(_ which: String, to path: String) {
        guard let screen = screens.screenUnderMouse() ?? screens.mainScreen() else { log("render: no screen"); return }
        // Optional real-desktop backdrop (ZT_RENDER_BG=/path.png) so the dim is judged over content.
        let bg = ProcessInfo.processInfo.environment["ZT_RENDER_BG"].flatMap { NSImage(contentsOfFile: $0) }
        var data: Data?
        switch which {
        case "hud":
            let info = ZoneCalculator.ScreenInfo(name: screen.name, frame: screen.frame)
            let zones = ZoneCalculator.computeZones(screen: info, config: config.zoneConfig).zones
            data = ZoneHUDOverlay.renderPNG(cells: ZoneHUD.layout(zones: zones), screenCGFrame: screen.frame, backdropImage: bg)
        case "break":
            let m = BreakScreen.message(restSec: 300, workCount: 3)
            data = BreakScreenOverlay.renderPNG(title: m.title, subtitle: m.subtitle,
                                                size: NSSize(width: screen.fullFrame.w, height: screen.fullFrame.h), backdropImage: bg)
        default: break
        }
        if let data, (try? data.write(to: URL(fileURLWithPath: path))) != nil { log("zt-agent: rendered \(which) → \(path)") }
        else { log("zt-agent: render \(which) failed") }
    }

    /// First run: if Accessibility isn't granted yet, guide the user through it (window moves
    /// need it). No-op when already trusted.
    func showOnboardingIfNeeded() {
        onboarding.showIfNeeded { log("zt-agent: Accessibility granted — window moves enabled") }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menubar agent (LSUIElement-equivalent)

let controller = AgentController(config: config, configURL: configURL)
controller.setupStatusItem()
controller.setupPomodoro()
controller.seedMonitors()          // before any tile/move op, so logical ids match on-disk data
controller.setupScreenWatch()
controller.setupFocusTracking()
controller.bindAllHotkeys()
controller.setupConfigWatch()
controller.setupIPCServer()        // MCP shim talks to the agent over this socket
controller.setupURLHandler()       // zonetiler:// scheme (effective in the bundled .app)
controller.setupZoneHUD()          // modifier-held zone cheat-sheet (gated by [zone_hud] enabled)
controller.setupDragSnap()         // drag-to-snap mouse monitor (gated by [drag_snap] enabled)
controller.setupFocusFollowsMouse()  // focus-follows-mouse (gated by [focus_follows_mouse] enabled)
controller.setupEventStream()        // arrangement event stream (gated by [events] enabled)
controller.showOnboardingIfNeeded()
// Debug aid: open a window on launch for screenshot/QA (the status-item menu isn't AX-drivable).
switch ProcessInfo.processInfo.environment["ZT_OPEN_WINDOW"] {
case "analytics": DispatchQueue.main.async { controller.openAnalytics() }
case "settings":  DispatchQueue.main.async { controller.openSettings() }
case "about":     DispatchQueue.main.async { controller.openAbout() }
case "tutorial":  DispatchQueue.main.async { controller.openTutorial() }
case "palette":   DispatchQueue.main.async { controller.showCommandPalette() }
case "hud":       DispatchQueue.main.async { controller.showZoneHUDForQA() }
case "dragsnap":  DispatchQueue.main.async { controller.dragSnapForQA() }
case "break":     DispatchQueue.main.async { controller.breakScreenForQA() }
default: break
}
// Deterministic overlay render for QA / Gemini grading: "ZT_RENDER=hud:/path.png" → render + exit.
if let render = ProcessInfo.processInfo.environment["ZT_RENDER"] {
    let parts = render.split(separator: ":", maxSplits: 1).map(String.init)
    if parts.count == 2 { controller.renderOverlayPNG(parts[0], to: parts[1]) }
    exit(0)
}

log("zt-agent: ready — <modifier>+<zone> tiles the focused window; HYPER+return auto-tiles the screen. Edits to config.toml live-reload. ⌘Q to quit.")
app.run()
