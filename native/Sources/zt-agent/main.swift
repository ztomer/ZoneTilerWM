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

final class AgentController: NSObject {
    private let binder = CarbonHotkeyBinder()
    private let windowSystem: AXWindowSystem
    private let coordinator: TilerCoordinator
    private let autoTilerConfig: AutoTiler.Config
    private let appSwitcher: AppSwitcher.Config
    private let pomodoro: Pomodoro
    private var statusItem: NSStatusItem?
    private var pomodoroItem: NSStatusItem?
    private var pomodoroTimer: Timer?
    private let flash = FlashOverlay()
    private let pomodoroBar = PomodoroBar()
    private let enableColorBar: Bool
    private let pomodoroIndicatorHeight: Double
    private let pomodoroIndicatorAlpha: Double
    private let pomodoroColorRemaining: NSColor
    private let pomodoroColorUsed: NSColor
    private let config: ConfigLoader.LoadedConfig
    private let configURL: URL
    private let learnedMemory: WindowMemory?
    private var settings: SettingsWindowController?

    init(config: ConfigLoader.LoadedConfig, configURL: URL) {
        let screens = NSScreenProvider()
        windowSystem = AXWindowSystem(screenProvider: screens)

        // Adaptive memory: load persisted preferences; learn + persist on manual tiles.
        var memory: WindowMemory?
        var storage: Storage?
        let monitorManager = MonitorManager()
        if config.windowMemory.enabled {
            let store = JSONFileStorage(directory: URL(fileURLWithPath: config.windowMemory.cacheDir, isDirectory: true))
            let mem = WindowMemory(excludedApps: config.windowMemory.excludedApps, settleEnabled: true)
            if let saved = store.load("window_positions", as: WindowMemory.SaveData.self) { mem.load(saved) }
            memory = mem
            storage = store
        }
        self.config = config
        self.configURL = configURL
        self.learnedMemory = memory

        coordinator = TilerCoordinator(windowSystem: windowSystem, screenProvider: screens,
                                       zoneConfig: config.zoneConfig,
                                       placementStrategy: config.placementStrategy,
                                       memory: memory, monitorManager: monitorManager, storage: storage)
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

    func setupPomodoro(_ config: ConfigLoader.LoadedConfig) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = ""   // shown only while active
        pomodoroItem = item
        bindAction(config.resolvedHotkey("enable", in: config.pomodoroHotkeys), label: "pomodoro.enable") { [weak self] in
            self?.pomodoro.enable(); self?.refreshPomodoro()
        }
        bindAction(config.resolvedHotkey("disable", in: config.pomodoroHotkeys), label: "pomodoro.disable") { [weak self] in
            _ = self?.pomodoro.disable(); self?.refreshPomodoro()
        }
        bindAction(config.resolvedHotkey("reset", in: config.pomodoroHotkeys), label: "pomodoro.reset") { [weak self] in
            self?.pomodoro.resetWork(); self?.refreshPomodoro()
        }
        pomodoroTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            _ = self.pomodoro.tick()
            self.refreshPomodoro()
        }
    }

    private func refreshPomodoro() {
        pomodoroItem?.button?.title = pomodoro.isActive ? pomodoro.displayString : ""
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
    }

    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⊞"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "ZoneTilerWM — v2 agent", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc func openSettings() {
        if settings == nil {
            settings = SettingsWindowController(model: SettingsModel(configURL: configURL, config: config, memory: learnedMemory))
        }
        settings?.show()
    }
}

// Zone keys = union of keys across all layouts (excluding the "default" fallback marker).
var zoneKeys = Set<String>()
for (_, zones) in config.zoneConfig.layouts {
    for key in zones.keys where key != "default" { zoneKeys.insert(key) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menubar agent (LSUIElement-equivalent)

let controller = AgentController(config: config, configURL: configURL)
controller.setupStatusItem()
controller.setupPomodoro(config)
controller.bindZoneHotkeys(modifier: config.tilerModifier, zoneKeys: zoneKeys.sorted())
controller.bindFocusHotkeys(modifier: config.focusModifier, zoneKeys: zoneKeys.sorted())
if let hyper = config.aliases["HYPER"] { controller.bindAutoTile(modifier: hyper, key: "return") }
controller.bindAppHotkeys(config.appCuts, label: "appCuts")
controller.bindAppHotkeys(config.hyperAppCuts, label: "hyperAppCuts")
if let audioKey = config.audioHotkeyKey {
    controller.bindAudioHotkey(modifier: config.audioHotkeyModifier, key: audioKey,
                               devices: config.audioDevices, shortcut: config.audioShortcutCallback)
}
controller.bindMiscHotkeys(config)
log("zt-agent: ready — <modifier>+<zone> tiles the focused window; HYPER+return auto-tiles the screen. ⌘Q to quit.")
app.run()
