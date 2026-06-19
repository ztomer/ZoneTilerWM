// ZoneHUDController.swift — shows the zone cheat-sheet while the tiling modifier is held past a
// short delay (so a quick, confident chord never triggers it; a hesitant hold gets the map).
// Gated by [zone_hud] enabled. Picks the active screen with ZERO AX (screen under the mouse, not
// an AX focusedWindow() round trip). A modifier-state poll while shown is the safety net for a
// missed flagsChanged "up" event (Space switch / app grabbing the event stream), and a
// screen-change / space-change observer dismisses a stale overlay. All on the main run loop.

import AppKit
import ZTCore
import ZTSystem

final class ZoneHUDController {
    private let screens: NSScreenProvider
    private let monitorManager: MonitorManager
    private let zoneConfig: () -> ZoneConfig
    private let offset: (_ monitor: String, _ axis: String, _ index: Int) -> Double
    private let modifier: () -> [String]      // resolved tiling modifier
    private let holdDelayMs: () -> Int

    private let overlay = ZoneHUDOverlay()
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var armTimer: Timer?
    private var pollTimer: Timer?
    private var shown = false

    init(screens: NSScreenProvider, monitorManager: MonitorManager,
         zoneConfig: @escaping () -> ZoneConfig,
         offset: @escaping (_ monitor: String, _ axis: String, _ index: Int) -> Double,
         modifier: @escaping () -> [String], holdDelayMs: @escaping () -> Int) {
        self.screens = screens; self.monitorManager = monitorManager
        self.zoneConfig = zoneConfig; self.offset = offset; self.modifier = modifier; self.holdDelayMs = holdDelayMs
    }

    var isRunning: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event.modifierFlags)
        }
        // Dismiss a stale/orphaned overlay on display rearrange or Space switch.
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                        object: nil, queue: .main) { [weak self] _ in self?.dismiss() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.dismiss() })
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        dismiss()
    }

    // MARK: - modifier tracking

    private func handle(_ flags: NSEvent.ModifierFlags) {
        let current = flags.intersection(.tilingRelevant)
        let target = NSEvent.ModifierFlags(aliases: modifier())
        if !target.isEmpty, current == target {
            guard armTimer == nil, !shown else { return }
            let ms = max(120, min(2000, holdDelayMs()))   // clamp: never instant, never effectively-off
            armTimer = Timer.scheduledTimer(withTimeInterval: Double(ms) / 1000.0, repeats: false) {
                [weak self] _ in self?.present()
            }
        } else {
            dismiss()
        }
    }

    /// QA/debug: force the HUD on now (no modifier-release poll — the normal trigger is the hold).
    func forceShow() { showHUD(withPoll: false) }

    private func present() { armTimer = nil; showHUD(withPoll: true) }

    private func showHUD(withPoll: Bool) {
        if shown { return }
        guard let screen = screens.screenUnderMouse() else { return }   // 0 AX
        let info = ZoneCalculator.ScreenInfo(name: screen.name, frame: screen.frame)
        let key = String(monitorManager.id(forUUID: screen.uuid))
        let zones = ZoneCalculator.computeZones(screen: info, config: zoneConfig(),
                                                offsets: { [offset] axis, index in offset(key, axis, index) }).zones
        overlay.show(ZoneHUD.layout(zones: zones), screenCGFrame: screen.frame)
        shown = true
        guard withPoll else { return }
        // Safety net: if the "modifier released" flagsChanged is ever missed, this still hides it.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self else { return }
            let cur = NSEvent.modifierFlags.intersection(.tilingRelevant)
            if cur != NSEvent.ModifierFlags(aliases: self.modifier()) { self.dismiss() }
        }
    }

    private func dismiss() {
        armTimer?.invalidate(); armTimer = nil
        pollTimer?.invalidate(); pollTimer = nil
        if shown { overlay.hide(); shown = false }
    }

}
