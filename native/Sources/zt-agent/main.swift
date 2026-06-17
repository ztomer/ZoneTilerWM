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

let home = FileManager.default.homeDirectoryForCurrentUser
let configURL = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : home.appendingPathComponent(".hammerspoon/config.toml")

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
    // Resize mode: grid-line offsets (persisted independently of window memory).
    private let resizeManager = ResizeManager()
    private let resizeStorage: Storage
    private let gridOverlay = GridOverlay()
    private var resizeActive = false
    private var resizeModalIDs: [UInt32] = []
    private var resizeMonitorKey = ""
    private var resizeScreenFrame = ZTRect(x: 0, y: 0, w: 0, h: 0)
    private var resizeCols = 1
    private var resizeRows = 1
    private var resizeVIndex: Int?
    private var resizeHIndex: Int?
    // Window hints: label badges + a transient key-capture modal.
    private let hintOverlay = HintOverlay()
    private var hintsActive = false
    private var hintModalIDs: [UInt32] = []
    private var hintTargets: [String: Int] = [:]
    // Config-derived state — rebuilt in place by applyConfig() on a live reload.
    private var coordinator: TilerCoordinator
    private var autoTilerConfig: AutoTiler.Config
    private var appSwitcher: AppSwitcher.Config
    private let pomodoro: Pomodoro
    private var statusItem: NSStatusItem?
    private var pomodoroItem: NSStatusItem?
    private var pomodoroPill: PomodoroPillView?
    private var pomodoroTimer: Timer?
    private var focusTimer: Timer?
    private let flash = FlashOverlay()
    private let pomodoroBar = PomodoroBar()
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
        let resize = resizeManager

        coordinator = AgentController.makeCoordinator(config: config, windowSystem: windowSystem,
                                                      screens: screens, memory: memory,
                                                      monitorManager: monitorManager, storage: store,
                                                      resizeManager: resize)
        autoTilerConfig = config.autoTilerConfig()
        appSwitcher = config.appSwitcher
        pomodoro = Pomodoro(config: .init(workPeriodSec: config.pomodoroWorkSec,
                                          restPeriodSec: config.pomodoroRestSec,
                                          enableColorBar: config.pomodoroEnableColorBar))
        enableColorBar = config.pomodoroEnableColorBar
        pomodoroIndicatorHeight = config.pomodoroIndicatorHeight
        pomodoroIndicatorAlpha = config.pomodoroIndicatorAlpha
        pomodoroColorRemaining = PomodoroBar.color(named: config.pomodoroColorRemaining)
        pomodoroColorUsed = PomodoroBar.color(named: config.pomodoroColorUsed)
        super.init()
        log("zt-agent: window memory \(memory != nil ? "enabled (\(config.windowMemory.cacheDir))" : "disabled")")
    }

    private static func makeCoordinator(config: ConfigLoader.LoadedConfig, windowSystem: WindowSystem,
                                        screens: ScreenProvider, memory: WindowMemory?,
                                        monitorManager: MonitorManager, storage: Storage?,
                                        resizeManager: ResizeManager) -> TilerCoordinator {
        TilerCoordinator(windowSystem: windowSystem, screenProvider: screens,
                         zoneConfig: config.zoneConfig, placementStrategy: config.placementStrategy,
                         offsetProvider: { [weak resizeManager] m, a, i in
                             resizeManager?.getOffset(monitor: m, axis: a, index: i) ?? 0
                         },
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
            let cfg = appSwitcher
            if binder.bind(keyCode: code, modifiers: mask, action: { AppController.toggle(app: app, config: cfg) }) {
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
            let now = Int(Date().timeIntervalSince1970)
            let moves = self.coordinator.autoTileScreen(autoTilerConfig: self.autoTilerConfig, memory: [:], now: now)
            log("zt-agent: auto-tile -> \(moves.count) moves")
        }
        log("zt-agent: auto-tile hotkey \(modifier)+\(key) -> \(ok ? "ok" : "FAILED")")
    }

    func bindZoneHotkeys(modifier: [String], zoneKeys: [String]) {
        let mask = KeyMap.modifierMask(for: modifier)
        guard mask != 0 else { log("zt-agent: empty/unknown modifier \(modifier)"); return }
        var bound = 0
        for zoneKey in zoneKeys {
            guard let code = KeyMap.keyCode(for: zoneKey) else { continue }
            let ok = binder.bind(keyCode: code, modifiers: mask) { [weak self] in
                guard let self else { return }
                switch self.coordinator.moveFocusedToZone(zoneKey) {
                case .success(let o):
                    log("zt-agent: '\(zoneKey)' -> tile \(o.tileIndex) applied=\(o.applied)")
                    self.flash.flash(o.target)
                case .failure(let e): log("zt-agent: '\(zoneKey)' -> \(e)")
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
                if self.coordinator.cycleFocus(zoneKey) != nil, let f = self.windowSystem.focusedWindow()?.frame {
                    self.flash.flash(f)
                }
            }) { bound += 1 }
        }
        log("zt-agent: bound \(bound)/\(zoneKeys.count) focus-cycle hotkeys with modifier \(modifier)")
    }

    func bindAudioHotkey(modifier: [String], key: String, devices: [String], shortcut: String?) {
        guard devices.count >= 2, let code = KeyMap.keyCode(for: key) else { return }
        let mask = KeyMap.modifierMask(for: modifier)
        guard mask != 0 else { return }
        let ok = binder.bind(keyCode: code, modifiers: mask) {
            let current = AudioDevices.defaultOutputName()
            guard let next = AudioSwitcher.nextDevice(configured: devices, currentName: current) else { return }
            if AudioDevices.setDefaultOutput(named: next) {
                log("zt-agent: audio -> \(next)")
                if let shortcut, !shortcut.isEmpty { AudioDevices.runShortcut(shortcut) }
            }
        }
        log("zt-agent: audio hotkey \(modifier)+\(key) -> \(ok ? "ok" : "FAILED")")
    }

    /// Generic hotkey binder for resolved (modifier, key) pairs.
    func bindAction(_ resolved: (modifier: [String], key: String)?, label: String, action: @escaping () -> Void) {
        guard let h = resolved, let code = KeyMap.keyCode(for: h.key) else { return }
        let mask = KeyMap.modifierMask(for: h.modifier)
        guard mask != 0 else { return }
        let ok = binder.bind(keyCode: code, modifiers: mask, action: action)
        log("zt-agent: \(label) hotkey \(h.modifier)+\(h.key) -> \(ok ? "ok" : "FAILED")")
    }

    /// Passive focus-time tracking (port of window_cache.lua's windowFocused subscription):
    /// seed all visible windows once, then poll the focused window every second so the
    /// auto-tiler's working-set age cull sees real per-window focus times. Poll granularity is
    /// negligible against the 1800s default cull threshold.
    func setupFocusTracking() {
        let now = Int(Date().timeIntervalSince1970)
        coordinator.seedFocusTimes(now: now)
        focusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.coordinator.noteFocusedWindow(now: Int(Date().timeIntervalSince1970))
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
            _ = self.pomodoro.tick()
            self.refreshPomodoro()
        }
    }

    private func bindPomodoroHotkeys() {
        bindAction(config.resolvedHotkey("enable", in: config.pomodoroHotkeys), label: "pomodoro.enable") { [weak self] in
            self?.pomodoro.enable(); self?.refreshPomodoro()
        }
        bindAction(config.resolvedHotkey("disable", in: config.pomodoroHotkeys), label: "pomodoro.disable") { [weak self] in
            _ = self?.pomodoro.disable(); self?.refreshPomodoro()
        }
        bindAction(config.resolvedHotkey("reset", in: config.pomodoroHotkeys), label: "pomodoro.reset") { [weak self] in
            self?.pomodoro.resetWork(); self?.refreshPomodoro()
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

    private func reloadFromDisk() {
        guard let newConfig = try? ConfigLoader.load(contentsOf: configURL) else {
            log("zt-agent: config reload skipped — could not parse \(configURL.lastPathComponent)")
            return
        }
        let problems = ConfigValidator.validate(newConfig)
        guard problems.isEmpty else {
            log("zt-agent: config reload skipped — invalid: \(problems.joined(separator: "; "))")
            return   // keep the running config
        }
        applyConfig(newConfig)
        log("zt-agent: config reloaded from \(configURL.lastPathComponent)")
    }

    /// Apply a validated config in place: rebuild config-derived state, then rebind hotkeys.
    /// Stable subsystems (window memory/storage, the running Pomodoro session, the menubar
    /// item + timer) are preserved.
    private func applyConfig(_ newConfig: ConfigLoader.LoadedConfig) {
        config = newConfig
        coordinator = AgentController.makeCoordinator(config: newConfig, windowSystem: windowSystem,
                                                      screens: screens, memory: learnedMemory,
                                                      monitorManager: monitorManager, storage: storage,
                                                      resizeManager: resizeManager)
        autoTilerConfig = newConfig.autoTilerConfig()
        appSwitcher = newConfig.appSwitcher
        pomodoro.updateConfig(.init(workPeriodSec: newConfig.pomodoroWorkSec,
                                    restPeriodSec: newConfig.pomodoroRestSec,
                                    enableColorBar: newConfig.pomodoroEnableColorBar))
        enableColorBar = newConfig.pomodoroEnableColorBar
        pomodoroIndicatorHeight = newConfig.pomodoroIndicatorHeight
        pomodoroIndicatorAlpha = newConfig.pomodoroIndicatorAlpha
        pomodoroColorRemaining = PomodoroBar.color(named: newConfig.pomodoroColorRemaining)
        pomodoroColorUsed = PomodoroBar.color(named: newConfig.pomodoroColorUsed)
        bindAllHotkeys()
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
            self?.coordinator.toggleZen()
        }
        // System: toggle Activity Monitor.
        let cfg = appSwitcher
        bindAction(config.resolvedHotkey("activity_monitor", in: config.systemHotkeys), label: "activity_monitor") {
            AppController.toggle(app: "Activity Monitor", config: cfg)
        }
        // Resize mode: toggle the grid-line adjustment modal.
        bindAction(config.resolvedHotkey("resize_mode", in: config.tilerHotkeys), label: "resize_mode") { [weak self] in
            self?.toggleResizeMode()
        }
        // Multi-monitor: move focused window to next/previous monitor (placement_mode/zone_info),
        // and focus next/previous screen. No-ops on a single display.
        bindAction(config.resolvedHotkey("placement_mode", in: config.tilerHotkeys), label: "move_to_next_monitor") { [weak self] in
            _ = self?.coordinator.moveFocusedToMonitor(.next)
        }
        bindAction(config.resolvedHotkey("zone_info", in: config.tilerHotkeys), label: "move_to_prev_monitor") { [weak self] in
            _ = self?.coordinator.moveFocusedToMonitor(.previous)
        }
        bindAction(config.resolvedHotkey("focus_next_screen", in: config.tilerHotkeys), label: "focus_next_screen") { [weak self] in
            self?.coordinator.focusScreen(.next)
        }
        bindAction(config.resolvedHotkey("focus_prev_screen", in: config.tilerHotkeys), label: "focus_prev_screen") { [weak self] in
            self?.coordinator.focusScreen(.previous)
        }
        // System: window hints (label each window, type to focus) + config reload hotkey.
        bindAction(config.resolvedHotkey("window_hints", in: config.systemHotkeys), label: "window_hints") { [weak self] in
            self?.toggleWindowHints()
        }
        bindAction(config.resolvedHotkey("reload", in: config.systemHotkeys), label: "reload") { [weak self] in
            self?.reloadFromDisk()
        }
    }

    // MARK: - Window hints (port of hs.hints.windowHints)

    private func toggleWindowHints() { hintsActive ? exitWindowHints() : enterWindowHints() }

    private func enterWindowHints() {
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
        let labels = WindowHints.spatialLabels(centers: centers, keys: hintKeyRows())
        let labeled = zip(labels, wins).filter { !$0.0.isEmpty }
        if labeled.count < wins.count {
            log("zt-agent: window hints — \(wins.count) windows, \(labeled.count) labeled")
        }
        hintTargets = [:]
        var badges: [(label: String, app: String, icon: NSImage?, center: ZTRect)] = []
        for (label, w) in labeled {
            hintTargets[label] = w.id
            let center = ZTRect(x: w.frame.x + w.frame.w / 2, y: w.frame.y + w.frame.h / 2, w: 0, h: 0)
            badges.append((label, w.appName, appIcon(for: w.appName), center))
        }
        hintsActive = true
        hintOverlay.show(badges)
        bindHintModal(labels: labeled.map { $0.0 })
        log("zt-agent: window hints ON (\(hintTargets.count) windows) — type a label, ESC cancels")
    }

    /// The 3 letter rows of the active keyboard layout, used as spatially-assignable hint keys.
    private func hintKeyRows() -> [[String]] {
        let name = config.keyboardLayout == "auto" ? KeyboardLayoutDetector.current() : config.keyboardLayout
        return Array(KeyboardLayout.rows(for: name).suffix(3))
    }

    private var iconCache: [String: NSImage?] = [:]
    /// The running app's icon by display name (cached to avoid re-querying every hint pass).
    private func appIcon(for name: String) -> NSImage? {
        if let cached = iconCache[name] { return cached }
        let icon = NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.icon
        iconCache[name] = icon
        return icon
    }

    private func exitWindowHints() {
        guard hintsActive else { return }
        hintsActive = false
        for id in hintModalIDs { binder.unbind(id) }
        hintModalIDs = []
        hintTargets = [:]
        hintOverlay.hide()
    }

    private func bindHintModal(labels: [String]) {
        for label in labels {
            guard let code = KeyMap.keyCode(for: label) else { continue }
            if let id = binder.register(keyCode: code, modifiers: 0, action: { [weak self] in
                guard let self, let wid = self.hintTargets[label] else { return }
                self.windowSystem.focus(windowId: wid)
                self.exitWindowHints()
            }) { hintModalIDs.append(id) }
        }
        if let esc = KeyMap.keyCode(for: "escape"),
           let id = binder.register(keyCode: esc, modifiers: 0, action: { [weak self] in self?.exitWindowHints() }) {
            hintModalIDs.append(id)
        }
    }

    // MARK: - Resize mode (coherent port: arrows nudge the zone grid lines)

    private func toggleResizeMode() { resizeActive ? exitResizeMode() : enterResizeMode() }

    /// Enter: pick the interior grid lines nearest the focused window, show the overlay, and
    /// bind bare arrows + escape. Arrows nudge those lines' offsets; the overlay redraws live.
    private func enterResizeMode() {
        guard let focused = windowSystem.focusedWindow(), let uuid = focused.screenUUID,
              let screen = screens.screen(uuid: uuid) else { return }
        let info = ZoneCalculator.ScreenInfo(name: screen.name, frame: screen.frame)
        guard let key = ZoneCalculator.layoutKey(for: info, config: config.zoneConfig),
              let grid = config.zoneConfig.grids[key] else {
            log("zt-agent: resize mode — no grid for the focused screen"); return
        }
        resizeMonitorKey = String(monitorManager.id(forUUID: uuid))
        resizeScreenFrame = screen.frame
        resizeCols = grid.cols; resizeRows = grid.rows
        let cx = focused.frame.x + focused.frame.w / 2, cy = focused.frame.y + focused.frame.h / 2
        resizeVIndex = GridLines.nearestInteriorIndex(to: cx, start: screen.frame.x, total: screen.frame.w, count: grid.cols)
        resizeHIndex = GridLines.nearestInteriorIndex(to: cy, start: screen.frame.y, total: screen.frame.h, count: grid.rows)

        resizeActive = true
        redrawGridOverlay()
        bindResizeModal()
        log("zt-agent: resize mode ON (grid \(grid.cols)x\(grid.rows), monitor \(resizeMonitorKey)) — arrows nudge lines, ESC exits")
    }

    private func exitResizeMode() {
        guard resizeActive else { return }
        resizeActive = false
        for id in resizeModalIDs { binder.unbind(id) }
        resizeModalIDs = []
        gridOverlay.hide()
        resizeManager.save(to: resizeStorage)
        log("zt-agent: resize mode OFF (offsets saved)")
    }

    private func bindResizeModal() {
        func reg(_ keyName: String, _ action: @escaping () -> Void) {
            if let code = KeyMap.keyCode(for: keyName), let id = binder.register(keyCode: code, modifiers: 0, action: action) {
                resizeModalIDs.append(id)
            }
        }
        reg("left")  { [weak self] in self?.adjustResize(axis: "x", delta: -1) }
        reg("right") { [weak self] in self?.adjustResize(axis: "x", delta: +1) }
        reg("up")    { [weak self] in self?.adjustResize(axis: "y", delta: -1) }
        reg("down")  { [weak self] in self?.adjustResize(axis: "y", delta: +1) }
        reg("escape") { [weak self] in self?.exitResizeMode() }
    }

    private func adjustResize(axis: String, delta: Double) {
        guard resizeActive else { return }
        let index = axis == "x" ? resizeVIndex : resizeHIndex
        guard let index else { return }   // no interior line on this axis (1xN / Nx1)
        resizeManager.adjust(monitor: resizeMonitorKey, axis: axis, index: index, delta: delta)
        redrawGridOverlay()
    }

    private func redrawGridOverlay() {
        let lines = GridLines.positions(frame: resizeScreenFrame, cols: resizeCols, rows: resizeRows) { [resizeManager, resizeMonitorKey] axis, idx in
            resizeManager.getOffset(monitor: resizeMonitorKey, axis: axis, index: idx)
        }
        gridOverlay.show(screenCGFrame: resizeScreenFrame, verticalX: lines.vertical, horizontalY: lines.horizontal)
    }

    /// The menubar mark: a 2x2 zone grid with the top-left zone in an amber accent (matches the
    /// app icon). Colored (not a template), so the grid lines flip for light/dark menubars while
    /// the accent stays — call updateMenubarGlyph() on appearance change.
    private static func menubarGlyph(dark: Bool) -> NSImage {
        let s: CGFloat = 18
        let lineColor = dark ? NSColor.white.withAlphaComponent(0.92) : NSColor.black.withAlphaComponent(0.82)
        let amber = NSColor(red: 0.98, green: 0.70, blue: 0.20, alpha: 1)
        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
            let inset: CGFloat = 2.5
            let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
            let cx = rect.midX, cy = rect.midY
            let lw: CGFloat = 1.4
            let outline = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            // Amber top-left quadrant, clipped to the rounded outline.
            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            amber.set()
            NSBezierPath(rect: NSRect(x: rect.minX, y: cy, width: cx - rect.minX, height: rect.maxY - cy)).fill()
            NSGraphicsContext.restoreGraphicsState()
            // Outline + cross lines in the appearance-appropriate ink.
            lineColor.set()
            outline.lineWidth = lw; outline.stroke()
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: cx, y: rect.minY)); cross.line(to: NSPoint(x: cx, y: rect.maxY))
            cross.move(to: NSPoint(x: rect.minX, y: cy)); cross.line(to: NSPoint(x: rect.maxX, y: cy))
            cross.lineWidth = lw; cross.stroke()
            return true
        }
        img.isTemplate = false   // keep the amber accent; we manage light/dark ourselves
        return img
    }

    private func isDarkMenubar() -> Bool {
        let appearance = statusItem?.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    @objc func updateMenubarGlyph() {
        statusItem?.button?.image = AgentController.menubarGlyph(dark: isDarkMenubar())
    }

    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.image = AgentController.menubarGlyph(dark: isDarkMenubar())
        item.button?.title = ""
        // Re-render the colored glyph when the system appearance flips.
        DistributedNotificationCenter.default.addObserver(
            self, selector: #selector(updateMenubarGlyph),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "ZoneTilerWM — v2 agent", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
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
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menubar agent (LSUIElement-equivalent)

let controller = AgentController(config: config, configURL: configURL)
controller.setupStatusItem()
controller.setupPomodoro()
controller.setupFocusTracking()
controller.bindAllHotkeys()
controller.setupConfigWatch()
log("zt-agent: ready — <modifier>+<zone> tiles the focused window; HYPER+return auto-tiles the screen. Edits to config.toml live-reload. ⌘Q to quit.")
app.run()
