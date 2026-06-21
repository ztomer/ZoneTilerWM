// ZoneHUDController.swift — drives the interactive zone HUD: hold the tiling modifier past a short
// delay and the overlay appears (so a quick, confident chord never triggers it; a hesitant hold gets
// the map). In tile-on-release mode the overlay is a live picker — pressing a zone key highlights it
// (a preview), and releasing the modifier commits the move; tile-immediately keeps the legacy
// fire-on-keypress. Gated by [zone_hud] enabled. Picks the active screen with ZERO AX (screen under
// the mouse, not an AX focusedWindow() round trip). A modifier-state poll while shown is the safety
// net for a missed flagsChanged "up"; a screen/space-change observer dismisses a stale overlay.
//
// The state machine itself is the pure ZTCore `ZoneHUDSession`; this class executes its effects
// (timers, the overlay window, the commit dispatch). The zone keys are NOT monitored here — they're
// the existing global Carbon hotkeys, which call `previewIfShowing(_:)` so a keypress highlights
// instead of tiling while the picker is up. All on the main run loop.

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
    private let commitMode: () -> ZoneHUDSession.Mode
    private let commit: (String, Int?) -> Void   // tile a zone key (tile=index on release; nil=coordinator auto-cycle)

    private let overlay = ZoneHUDOverlay()
    private var session = ZoneHUDSession()
    private var tileCounts: [String: Int] = [:]  // placements per zone key, set on present → the session's cycle wrap
    private var gestureActive = false         // a modifier-hold gesture is in progress (drives session refresh)
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var armTimer: Timer?
    private var pollTimer: Timer?

    init(screens: NSScreenProvider, monitorManager: MonitorManager,
         zoneConfig: @escaping () -> ZoneConfig,
         offset: @escaping (_ monitor: String, _ axis: String, _ index: Int) -> Double,
         modifier: @escaping () -> [String], holdDelayMs: @escaping () -> Int,
         commitMode: @escaping () -> ZoneHUDSession.Mode = { .tileOnRelease },
         commit: @escaping (String, Int?) -> Void = { _, _ in }) {
        self.screens = screens; self.monitorManager = monitorManager
        self.zoneConfig = zoneConfig; self.offset = offset; self.modifier = modifier
        self.holdDelayMs = holdDelayMs; self.commitMode = commitMode; self.commit = commit
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
                                        object: nil, queue: .main) { [weak self] _ in self?.reset() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.reset() })
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        reset()
    }

    /// The Carbon zone-hotkey handler routes here first. If the picker is up in tile-on-release mode,
    /// the keypress PREVIEWS (highlights) the zone and we return true so the caller skips its immediate
    /// tile; otherwise false → the caller tiles right away (legacy / immediate mode / HUD not shown).
    func previewIfShowing(_ zoneKey: String) -> Bool {
        guard session.isShown, commitMode() == .tileOnRelease else { return false }
        execute(session.zoneKey(zoneKey))
        return true
    }

    var isShowing: Bool { session.isShown }

    // MARK: - modifier tracking

    private func handle(_ flags: NSEvent.ModifierFlags) {
        let current = flags.intersection(.tilingRelevant)
        let target = NSEvent.ModifierFlags(aliases: modifier())
        let matches = !target.isEmpty && current == target
        // Refresh the session with current config at the start of each fresh gesture (live-reload safe).
        if matches, !gestureActive {
            gestureActive = true
            session = freshSession()
        } else if !matches {
            gestureActive = false
        }
        execute(session.modifier(matchesTarget: matches, otherKeysDown: false))
    }

    private func clampedDelay() -> Int { max(80, min(2000, holdDelayMs())) }   // never instant, never effectively-off

    /// A session seeded with current config + the live per-key tile counts (so re-press cycles wrap).
    private func freshSession() -> ZoneHUDSession {
        ZoneHUDSession(mode: commitMode(), holdDelayMs: clampedDelay(),
                       tileCount: { [weak self] in self?.tileCounts[$0] ?? 1 })
    }

    /// QA/debug: force the overlay on now (no session, no release-commit — for screenshots).
    func forceShow() { presentOverlay(withPoll: false) }

    /// QA/debug: force the overlay on and preview a zone at a cycle tile (screenshot the highlighted state).
    func forceShow(highlight zoneKey: String, tile: Int = 0) {
        presentOverlay(withPoll: false)
        overlay.highlight(zoneKey, tile: tile)
    }

    // MARK: - effect execution

    private func execute(_ effects: [ZoneHUDSession.Effect]) {
        for effect in effects {
            switch effect {
            case .arm(let ms):
                armTimer?.invalidate()
                armTimer = Timer.scheduledTimer(withTimeInterval: Double(ms) / 1000.0, repeats: false) {
                    [weak self] _ in self?.execute(self?.session.armElapsed() ?? [])
                }
            case .disarm:
                armTimer?.invalidate(); armTimer = nil
            case .show:
                presentOverlay(withPoll: true)
            case .hide:
                pollTimer?.invalidate(); pollTimer = nil
                overlay.hide()
            case .highlight(let key, let tile):
                overlay.highlight(key, tile: tile)   // fill tiles[tile] → the preview resizes as you re-press
            case .commit(let key, let tile):
                commit(key, tile)
            }
        }
    }

    private func presentOverlay(withPoll: Bool) {
        guard let screen = screens.screenUnderMouse() else { log("zone-hud: no screen under mouse"); return }  // 0 AX
        let info = ZoneCalculator.ScreenInfo(name: screen.name, frame: screen.frame)
        let monKey = String(monitorManager.id(forUUID: screen.uuid))
        let cfg = zoneConfig()
        let resolved = ZoneCalculator.computeZones(screen: info, config: cfg,
                                                   offsets: { [offset] axis, index in offset(monKey, axis, index) })
        let zones = resolved.zones
        tileCounts = zones.mapValues { $0.count }   // for the session's re-press cycle wrap-around
        let grid = cfg.grids[resolved.layoutKey]
        let (gridV, gridH) = GridLines.positions(frame: screen.frame, cols: grid?.cols ?? 0, rows: grid?.rows ?? 0,
                                                 offset: { [offset] axis, index in offset(monKey, axis, index) })
        let caps = ZoneHUD.caps(zones: zones)
        log("zone-hud: showing \(caps.count) caps on \(screen.name) frame \(screen.frame)")
        overlay.show(tilesByKey: zones, caps: caps, gridV: gridV, gridH: gridH, screenCGFrame: screen.frame)
        guard withPoll else { return }
        // Safety net: if the "modifier released" flagsChanged is ever missed, this still tears down.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self else { return }
            let cur = NSEvent.modifierFlags.intersection(.tilingRelevant)
            if cur != NSEvent.ModifierFlags(aliases: self.modifier()) {
                self.gestureActive = false
                self.execute(self.session.modifier(matchesTarget: false, otherKeysDown: false))
            }
        }
    }

    /// Tear everything down (used by observers + stop): cancel timers, hide, drop the gesture.
    private func reset() {
        armTimer?.invalidate(); armTimer = nil
        pollTimer?.invalidate(); pollTimer = nil
        gestureActive = false
        session = freshSession()
        overlay.hide()
    }
}
