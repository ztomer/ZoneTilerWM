// zt-agent — minimal LSUIElement menubar agent: binds the config's tiler modifier + each
// zone key (e.g. ⌃⌘h) to TilerCoordinator.moveFocusedToZone via global Carbon hotkeys, shows
// a status-bar item, and runs the app run loop. First real keypress -> tile.
//
//   zt-agent [config_path]   (default ~/.hammerspoon/config.toml)

import Foundation
import AppKit
import ZTCore
import ZTSystem

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
    private var statusItem: NSStatusItem?

    init(config: ConfigLoader.LoadedConfig) {
        let screens = NSScreenProvider()
        windowSystem = AXWindowSystem(screenProvider: screens)
        coordinator = TilerCoordinator(windowSystem: windowSystem, screenProvider: screens,
                                       zoneConfig: config.zoneConfig,
                                       placementStrategy: config.placementStrategy)
        autoTilerConfig = config.autoTilerConfig()
        appSwitcher = config.appSwitcher
        super.init()
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
                case .success(let o): log("zt-agent: '\(zoneKey)' -> tile \(o.tileIndex) applied=\(o.applied)")
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
                _ = self?.coordinator.cycleFocus(zoneKey)
            }) { bound += 1 }
        }
        log("zt-agent: bound \(bound)/\(zoneKeys.count) focus-cycle hotkeys with modifier \(modifier)")
    }

    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⊞"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "ZoneTilerWM — v2 agent", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
}

// Zone keys = union of keys across all layouts (excluding the "default" fallback marker).
var zoneKeys = Set<String>()
for (_, zones) in config.zoneConfig.layouts {
    for key in zones.keys where key != "default" { zoneKeys.insert(key) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menubar agent (LSUIElement-equivalent)

let controller = AgentController(config: config)
controller.setupStatusItem()
controller.bindZoneHotkeys(modifier: config.tilerModifier, zoneKeys: zoneKeys.sorted())
controller.bindFocusHotkeys(modifier: config.focusModifier, zoneKeys: zoneKeys.sorted())
if let hyper = config.aliases["HYPER"] { controller.bindAutoTile(modifier: hyper, key: "return") }
controller.bindAppHotkeys(config.appCuts, label: "appCuts")
controller.bindAppHotkeys(config.hyperAppCuts, label: "hyperAppCuts")
log("zt-agent: ready — <modifier>+<zone> tiles the focused window; HYPER+return auto-tiles the screen. ⌘Q to quit.")
app.run()
