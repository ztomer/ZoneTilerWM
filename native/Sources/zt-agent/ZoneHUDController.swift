// ZoneHUDController.swift — shows the zone cheat-sheet while the tiling modifier is held past a
// short delay (so a quick, confident chord never triggers it; a hesitant hold gets the map).
// Gated by [zone_hud] enabled — the agent only start()s it when enabled. Reads config live so a
// reload's enable/delay change takes effect. Listens via a global flagsChanged monitor (the agent
// is an accessory app, so "global" catches the modifier whatever app is focused).

import AppKit
import ZTCore
import ZTSystem

final class ZoneHUDController {
    private let screens: NSScreenProvider
    private let windowSystem: AXWindowSystem
    private let monitorManager: MonitorManager
    private let zoneConfig: () -> ZoneConfig
    private let offset: (_ monitor: String, _ axis: String, _ index: Int) -> Double
    private let modifier: () -> [String]      // resolved tiling modifier
    private let holdDelayMs: () -> Int

    private let overlay = ZoneHUDOverlay()
    private var monitor: Any?
    private var timer: Timer?
    private var shown = false

    init(screens: NSScreenProvider, windowSystem: AXWindowSystem, monitorManager: MonitorManager,
         zoneConfig: @escaping () -> ZoneConfig,
         offset: @escaping (_ monitor: String, _ axis: String, _ index: Int) -> Double,
         modifier: @escaping () -> [String], holdDelayMs: @escaping () -> Int) {
        self.screens = screens; self.windowSystem = windowSystem; self.monitorManager = monitorManager
        self.zoneConfig = zoneConfig; self.offset = offset; self.modifier = modifier; self.holdDelayMs = holdDelayMs
    }

    var isRunning: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event.modifierFlags)
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        cancelTimer(); hide()
    }

    // MARK: - modifier tracking

    private func handle(_ flags: NSEvent.ModifierFlags) {
        let current = flags.intersection([.command, .control, .option, .shift])
        let target = Self.nsFlags(for: modifier())
        if !target.isEmpty, current == target {
            guard timer == nil, !shown else { return }   // already armed/shown
            timer = Timer.scheduledTimer(withTimeInterval: Double(holdDelayMs()) / 1000.0, repeats: false) {
                [weak self] _ in self?.present()
            }
        } else {
            cancelTimer(); hide()
        }
    }

    /// QA/debug: force the HUD on now (the normal trigger is the modifier hold).
    func forceShow() { present() }

    private func present() {
        timer = nil
        guard let uuid = windowSystem.focusedWindow()?.screenUUID ?? screens.mainScreen()?.uuid,
              let screen = screens.screen(uuid: uuid) else { return }
        let info = ZoneCalculator.ScreenInfo(name: screen.name, frame: screen.frame)
        let key = String(monitorManager.id(forUUID: uuid))
        let zones = ZoneCalculator.computeZones(screen: info, config: zoneConfig(),
                                                offsets: { [offset] axis, index in offset(key, axis, index) }).zones
        overlay.show(ZoneHUD.layout(zones: zones), screenCGFrame: screen.frame)
        shown = true
    }

    private func hide() { if shown { overlay.hide(); shown = false } }
    private func cancelTimer() { timer?.invalidate(); timer = nil }

    private static func nsFlags(for names: [String]) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        for n in names {
            switch n.lowercased() {
            case "cmd", "command": f.insert(.command)
            case "ctrl", "control": f.insert(.control)
            case "alt", "option", "opt": f.insert(.option)
            case "shift": f.insert(.shift)
            default: break
            }
        }
        return f
    }
}
