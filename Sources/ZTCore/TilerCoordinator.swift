// TilerCoordinator.swift — the live "move-to-zone" orchestration (port of
// window_actions.move_window_to_zone's decision path). Pure: takes a WindowSystem +
// ScreenProvider and the loaded config, computes the target tile via the ported
// ZoneCalculator + PlacementStrategy, and asks the WindowSystem to move the focused window.
// The actual AX move lives behind WindowSystem; this is testable against a fake.

public final class TilerCoordinator {

    public struct MoveOutcome: Equatable {
        public let windowId: Int
        public let zoneKey: String
        public let tileIndex: Int     // 1-based index within the zone
        public let target: ZTRect
        public let applied: Bool
    }

    public enum MoveError: Error, Equatable {
        case noFocusedWindow
        case noScreenForWindow
        case noZone(String)          // zone key not present in the resolved layout
        case noTile                  // placement strategy found nothing
    }

    private let windowSystem: WindowSystem
    private let screenProvider: ScreenProvider
    private let zoneConfig: ZoneConfig
    private let strategy: PlacementStrategy.Strategy
    // Monitor-aware grid-line offset lookup (resize mode). Keyed by the logical monitor id
    // string (same key window memory uses). Default: no offsets.
    private let offsetProvider: (_ monitor: String, _ axis: String, _ index: Int) -> Double
    private let overlapThreshold: Double
    // Per-window float: auto-tile skips windows for which this returns true. Default: none float.
    private let isFloated: (_ windowId: Int) -> Bool
    private let focusCycler = FocusManager.Cycler()
    private let focusTracker = WindowFocusTracker()
    // Repeated auto-tile of the same focused window cycles its centre ("j") zone through its tiles.
    private var autoTileCycle: (id: Int, index: Int)?

    // Optional adaptive memory: when present, manual zone moves are learned + persisted, and
    // auto-tile becomes memory-augmented. monitorManager maps screen UUID -> the logical id
    // the on-disk window_positions.json is keyed by.
    private let memory: WindowMemory?
    private let monitorManager: MonitorManager?
    private let storage: Storage?
    // Per-app default zone (window_memory.app_zones): used during auto-tile when an app has no
    // learned position yet. Empty = no defaults.
    private let appZones: [String: String]

    public init(windowSystem: WindowSystem,
                screenProvider: ScreenProvider,
                zoneConfig: ZoneConfig,
                placementStrategy: String,
                overlapThreshold: Double = 0.5,
                offsetProvider: @escaping (_ monitor: String, _ axis: String, _ index: Int) -> Double = { _, _, _ in 0 },
                isFloated: @escaping (_ windowId: Int) -> Bool = { _ in false },
                memory: WindowMemory? = nil,
                monitorManager: MonitorManager? = nil,
                storage: Storage? = nil,
                appZones: [String: String] = [:]) {
        self.windowSystem = windowSystem
        self.screenProvider = screenProvider
        self.zoneConfig = zoneConfig
        self.strategy = PlacementStrategy.Strategy(config: placementStrategy)
        self.overlapThreshold = overlapThreshold
        self.offsetProvider = offsetProvider
        self.isFloated = isFloated
        self.memory = memory
        self.monitorManager = monitorManager
        self.storage = storage
        self.appZones = appZones
    }

    private var zenActive = false
    private var zenHidden: [Int] = []

    /// Zen mode: minimize every other window on the focused window's screen; toggle restores.
    public func toggleZen() {
        guard let focused = windowSystem.focusedWindow(), let uuid = focused.screenUUID else { return }
        if zenActive {
            for id in zenHidden { windowSystem.setMinimized(false, windowId: id) }
            zenHidden = []
            zenActive = false
        } else {
            zenHidden = []
            for w in windowSystem.windows(onScreen: uuid) where w.id != focused.id {
                if windowSystem.setMinimized(true, windowId: w.id) { zenHidden.append(w.id) }
            }
            zenActive = true
        }
    }

    /// Per-screen offset provider for ZoneCalculator, keyed by the screen's logical monitor id
    /// (falls back to the uuid when no MonitorManager is present).
    private func offsets(forScreen uuid: String) -> ZoneCalculator.OffsetProvider {
        let key = monitorKey(uuid) ?? uuid
        return { [offsetProvider] axis, index in offsetProvider(key, axis, index) }
    }

    /// Logical monitor id (string) for memory keys, via MonitorManager. nil if no manager.
    private func monitorKey(_ uuid: String) -> String? {
        monitorManager.map { String($0.id(forUUID: uuid)) }
    }

    /// Learn + persist a manual placement (no-op if memory isn't configured).
    private func learn(window: LiveWindow, screen: ScreenSnapshot, zoneKey: String, tileIndex: Int) {
        guard let memory, let key = monitorKey(screen.uuid) else { return }
        memory.positionWindow(windowId: window.id, app: window.appName, monitor: key,
                              zone: zoneKey, tile: .int(tileIndex),
                              winW: window.frame.w, winH: window.frame.h,
                              screenW: screen.frame.w, screenH: screen.frame.h)
        memory.flush(windowId: window.id)
        storage?.save("window_positions", memory.save())
    }

    /// Cycle focus among the windows in `zoneKey` on the focused window's screen. Returns the
    /// window id now focused, or nil. Overlap-based collection (no explicit tiler state yet).
    @discardableResult
    public func cycleFocus(_ zoneKey: String) -> Int? {
        guard let focused = windowSystem.focusedWindow(),
              let uuid = focused.screenUUID, let screen = screenProvider.screen(uuid: uuid) else { return nil }
        let info = ZoneCalculator.ScreenInfo(name: screen.name, frame: screen.frame)
        let zones = ZoneCalculator.computeZones(screen: info, config: zoneConfig, offsets: offsets(forScreen: uuid)).zones
        guard let tiles = zones[zoneKey], !tiles.isEmpty else { return nil }

        let live = windowSystem.windows(onScreen: uuid)
        let screenWindows = live.enumerated().map { (i, w) in
            FocusManager.ScreenWindow(windowId: w.id, appName: w.appName, frame: w.frame, zOrder: i + 1)
        }
        let zoneWindows = FocusManager.collectZoneWindows(
            monitorId: uuid, zoneKey: zoneKey, windowsOnScreen: screenWindows,
            stateForWindow: { _ in nil }, zoneTiles: tiles, overlapThreshold: overlapThreshold)
        let freshOrder = zoneWindows.map { $0.windowId }
        guard let next = focusCycler.cycle(focusedId: focused.id, zoneKey: zoneKey,
                                           monitorId: uuid, freshOrder: freshOrder) else { return nil }
        windowSystem.focus(windowId: next)
        return next
    }

    /// Cycle focus through the windows stacked in the FOCUSED window's current zone, stepping in
    /// `direction` (wrapping). The zone is auto-detected from the focused window's frame, so no
    /// zone key is needed. Same AX profile as `cycleFocus`: enumeration is 0 AX (CGWindowList),
    /// the only mutate is the final focus. Returns the newly-focused id, or nil if the focused
    /// window isn't in a zone or its zone has fewer than two windows.
    @discardableResult
    public func cycleZoneStack(_ direction: NavDirection) -> Int? {
        guard let focused = windowSystem.focusedWindow(),
              let uuid = focused.screenUUID, let screen = screenProvider.screen(uuid: uuid) else { return nil }
        let info = ZoneCalculator.ScreenInfo(name: screen.name, frame: screen.frame)
        let zones = ZoneCalculator.computeZones(screen: info, config: zoneConfig, offsets: offsets(forScreen: uuid)).zones
        guard let zoneKey = ZoneOccupancy.bestZone(window: focused.frame, zones: zones),
              let tiles = zones[zoneKey], !tiles.isEmpty else { return nil }

        let live = windowSystem.windows(onScreen: uuid)
        let screenWindows = live.enumerated().map { (i, w) in
            FocusManager.ScreenWindow(windowId: w.id, appName: w.appName, frame: w.frame, zOrder: i + 1)
        }
        let zoneWindows = FocusManager.collectZoneWindows(
            monitorId: uuid, zoneKey: zoneKey, windowsOnScreen: screenWindows,
            stateForWindow: { _ in nil }, zoneTiles: tiles, overlapThreshold: overlapThreshold)
        let ordered = zoneWindows.map { $0.windowId }
        guard let next = ZoneStack.adjacent(focusedId: focused.id, ordered: ordered, direction: direction) else { return nil }
        windowSystem.focus(windowId: next)
        return next
    }

    /// Move the focused window into `zoneKey` on its current screen.
    public func moveFocusedToZone(_ zoneKey: String) -> Result<MoveOutcome, MoveError> {
        guard let focused = windowSystem.focusedWindow() else { return .failure(.noFocusedWindow) }
        guard let uuid = focused.screenUUID, let screen = screenProvider.screen(uuid: uuid) else {
            return .failure(.noScreenForWindow)
        }

        let info = ZoneCalculator.ScreenInfo(name: screen.name, frame: screen.frame)
        let zones = ZoneCalculator.computeZones(screen: info, config: zoneConfig, offsets: offsets(forScreen: uuid)).zones
        guard let tiles = zones[zoneKey], !tiles.isEmpty else { return .failure(.noZone(zoneKey)) }

        // Occupancy = other standard windows on this screen.
        let occupied = windowSystem.windows(onScreen: uuid)
            .filter { $0.id != focused.id }
            .map { PlacementStrategy.OccupiedWindow(id: $0.id, frame: $0.frame) }

        // First move has no prior tiler state for this window (nil zone/tile index).
        guard let target = PlacementStrategy.findBestTile(
            strategy: strategy, tiles: tiles, zoneKey: zoneKey,
            currentFrame: focused.frame, stateZoneKey: nil, stateTileIndex: nil,
            occupied: occupied, selfId: focused.id) else {
            return .failure(.noTile)
        }

        let tileIndex = (tiles.firstIndex(of: target) ?? 0) + 1
        let applied = windowSystem.moveFocusedWindow(to: target)
        if applied { learn(window: focused, screen: screen, zoneKey: zoneKey, tileIndex: tileIndex) }
        return .success(MoveOutcome(windowId: focused.id, zoneKey: zoneKey,
                                    tileIndex: tileIndex, target: target, applied: applied))
    }

    /// Move the focused window to a SPECIFIC placement in `zoneKey`'s cycle (0-based, wrapping) —
    /// the WYSIWYG path for the zone-HUD tile-on-release picker, where the user has already cycled the
    /// preview to an exact tile. Unlike `moveFocusedToZone`, this bypasses the occupancy-driven
    /// `findBestTile` auto-pick so what commits equals what was previewed.
    public func moveFocusedToZone(_ zoneKey: String, tileIndex: Int) -> Result<MoveOutcome, MoveError> {
        guard let focused = windowSystem.focusedWindow() else { return .failure(.noFocusedWindow) }
        guard let uuid = focused.screenUUID, let screen = screenProvider.screen(uuid: uuid) else {
            return .failure(.noScreenForWindow)
        }
        let info = ZoneCalculator.ScreenInfo(name: screen.name, frame: screen.frame)
        let zones = ZoneCalculator.computeZones(screen: info, config: zoneConfig, offsets: offsets(forScreen: uuid)).zones
        guard let tiles = zones[zoneKey], !tiles.isEmpty else { return .failure(.noZone(zoneKey)) }
        let idx = ((tileIndex % tiles.count) + tiles.count) % tiles.count   // safe wrap for any Int
        let target = tiles[idx]
        let applied = windowSystem.moveFocusedWindow(to: target)
        if applied { learn(window: focused, screen: screen, zoneKey: zoneKey, tileIndex: idx + 1) }
        return .success(MoveOutcome(windowId: focused.id, zoneKey: zoneKey,
                                    tileIndex: idx + 1, target: target, applied: applied))
    }

    /// Tile a SPECIFIC window (by id) into `zoneKey` on its current screen — the rules-engine
    /// entry point, where the target window is the one that just opened, not necessarily the
    /// focused one. Mirrors moveFocusedToZone but resolves the window by id and moves it via
    /// `WindowSystem.move(windowId:to:)`. Returns nil if the window/screen/zone/tile can't be
    /// resolved. Learns + persists on success, like a manual tile.
    @discardableResult
    public func moveWindow(windowId: Int, toZone zoneKey: String) -> MoveOutcome? {
        // Resolve the window + its screen via the zero-AX enumeration. (Scans once per screen; the
        // WindowSystem protocol has no all-windows read, so this stays in-protocol — zero AX, CPU-only.)
        var found: (window: LiveWindow, uuid: String)?
        for s in screenProvider.allScreens() {
            if let w = windowSystem.windows(onScreen: s.uuid).first(where: { $0.id == windowId }) {
                found = (w, s.uuid); break
            }
        }
        guard let (window, uuid) = found, let screen = screenProvider.screen(uuid: uuid) else { return nil }

        let info = ZoneCalculator.ScreenInfo(name: screen.name, frame: screen.frame)
        let zones = ZoneCalculator.computeZones(screen: info, config: zoneConfig, offsets: offsets(forScreen: uuid)).zones
        guard let tiles = zones[zoneKey], !tiles.isEmpty else { return nil }

        let occupied = windowSystem.windows(onScreen: uuid)
            .filter { $0.id != window.id }
            .map { PlacementStrategy.OccupiedWindow(id: $0.id, frame: $0.frame) }
        guard let target = PlacementStrategy.findBestTile(
            strategy: strategy, tiles: tiles, zoneKey: zoneKey,
            currentFrame: window.frame, stateZoneKey: nil, stateTileIndex: nil,
            occupied: occupied, selfId: window.id) else { return nil }

        let tileIndex = (tiles.firstIndex(of: target) ?? 0) + 1
        let applied = windowSystem.move(windowId: window.id, to: target)
        if applied { learn(window: window, screen: screen, zoneKey: zoneKey, tileIndex: tileIndex) }
        return MoveOutcome(windowId: window.id, zoneKey: zoneKey, tileIndex: tileIndex, target: target, applied: applied)
    }

    /// Auto-tile every window on the focused window's screen (or the main screen) using the
    /// ported AutoTiler, applying each planned move via the WindowSystem. Returns the moves.
    @discardableResult
    public func autoTileScreen(autoTilerConfig: AutoTiler.Config,
                               memory memoryOverride: [String: [MemoryPref]]? = nil,
                               now: Int) -> [AutoTiler.PlannedMove] {
        let uuid = windowSystem.focusedWindow()?.screenUUID ?? screenProvider.mainScreen()?.uuid
        guard let uuid, let screen = screenProvider.screen(uuid: uuid) else { return [] }

        let live = windowSystem.windows(onScreen: uuid).filter { !isFloated($0.id) }   // front-to-back, floats excluded
        // Feed real per-window focus times so the working-set age cull behaves like the Lua
        // (window_cache last_focused_time). Unseen windows fall back to `now`, matching the
        // Lua `info and info.last_focused_time or now`; baseline-seed them so they can age out.
        let windows = live.map { w -> AutoTiler.Window in
            focusTracker.recordIfAbsent(id: w.id, at: now)
            return AutoTiler.Window(id: w.id, app: w.appName, monitor: uuid, frame: w.frame,
                                    lastFocusedTime: focusTracker.lastFocused(id: w.id) ?? now,
                                    isStandard: true, isMinimized: false)
        }
        let zOrder = live.map { $0.id }
        let focusedId = windowSystem.focusedWindow()?.id
        let screens = [AutoTiler.Screen(uuid: uuid, name: screen.name, frame: screen.frame)]

        // Cycle the centre zone: re-tiling the SAME focused window advances its "j" tile; a different
        // (or no) focused window restarts at tile 0.
        let cycleIndex: Int
        if let fid = focusedId, let prev = autoTileCycle, prev.id == fid { cycleIndex = prev.index + 1 }
        else { cycleIndex = 0 }
        autoTileCycle = focusedId.map { ($0, cycleIndex) }

        // Memory-augmented: ranked preferences per app for this monitor (logical id key),
        // recency-weighted by `now` so recent habits outrank stale ones.
        let memory = memoryOverride ?? rankedMemory(forApps: Set(live.map { $0.appName }), screenUUID: uuid, now: now)

        let moves = AutoTiler.plan(config: autoTilerConfig, screens: screens, windows: windows,
                                   zOrder: zOrder, focusedId: focusedId, memory: memory, now: now,
                                   centerTileIndex: cycleIndex)
        for m in moves { windowSystem.move(windowId: m.windowId, to: m.rect) }
        return moves
    }

    // MARK: - Multi-monitor navigation (ports tiler.lua focus_*_screen + move_window_to_monitor)

    /// Focus the frontmost window of the *currently focused app* on the next/previous screen
    /// (matches the Lua, which iterates the focused app's windows). Returns the focused id, or
    /// nil (single screen / no same-app window there). Live-validatable only with 2+ displays.
    @discardableResult
    public func focusScreen(_ direction: ScreenNav.Direction) -> Int? {
        guard let focused = windowSystem.focusedWindow(), let uuid = focused.screenUUID else { return nil }
        let ordered = ScreenNav.ordered(screenProvider.allScreens()).map { $0.uuid }
        guard let ti = ScreenNav.targetIndex(orderedUUIDs: ordered, current: uuid, direction: direction) else { return nil }
        let targetUUID = ordered[ti]
        guard let next = windowSystem.windows(onScreen: targetUUID).first(where: { $0.appName == focused.appName }) else { return nil }
        windowSystem.focus(windowId: next.id)
        return next.id
    }

    /// Move the focused window to the next/previous monitor, placing it via the remembered
    /// position → default-zone → untiled cascade. Returns the move (applied) or nil.
    @discardableResult
    public func moveFocusedToMonitor(_ direction: ScreenNav.Direction) -> MoveOutcome? {
        guard let focused = windowSystem.focusedWindow(), let uuid = focused.screenUUID else { return nil }
        let orderedScreens = ScreenNav.ordered(screenProvider.allScreens())
        let ordered = orderedScreens.map { $0.uuid }
        guard let ti = ScreenNav.targetIndex(orderedUUIDs: ordered, current: uuid, direction: direction),
              let target = screenProvider.screen(uuid: ordered[ti]) else { return nil }

        let info = ZoneCalculator.ScreenInfo(name: target.name, frame: target.frame)
        let zones = ZoneCalculator.computeZones(screen: info, config: zoneConfig,
                                                offsets: offsets(forScreen: target.uuid)).zones
        // Remembered app position on the target monitor (top-ranked preference), if any.
        var remembered: (zone: String, tile: Int)?
        if let key = monitorKey(target.uuid),
           let top = memory?.rankedPreferences(app: focused.appName, monitor: key).first,
           case let .int(tileIdx) = top.tile {
            remembered = (top.zoneKey, tileIdx)
        }
        guard let pick = ScreenNav.monitorPlacement(targetZones: zones, remembered: remembered),
              let tiles = zones[pick.zone], pick.tile >= 1, pick.tile <= tiles.count else {
            // Untiled fallback: move the window to the target screen's top-left work area.
            let dst = ZTRect(x: target.frame.x, y: target.frame.y, w: focused.frame.w, h: focused.frame.h)
            let ok = windowSystem.move(windowId: focused.id, to: dst)
            return MoveOutcome(windowId: focused.id, zoneKey: "", tileIndex: 0, target: dst, applied: ok)
        }
        let rect = tiles[pick.tile - 1]
        let ok = windowSystem.move(windowId: focused.id, to: rect)
        if ok { learn(window: focused, screen: target, zoneKey: pick.zone, tileIndex: pick.tile) }
        return MoveOutcome(windowId: focused.id, zoneKey: pick.zone, tileIndex: pick.tile, target: rect, applied: ok)
    }

    // MARK: - Directional ops (nudge / throw / swap)

    private func focusedWindowAndScreen() -> (LiveWindow, ScreenSnapshot)? {
        guard let w = windowSystem.focusedWindow(), let uuid = w.screenUUID,
              let s = screenProvider.screen(uuid: uuid) else { return nil }
        return (w, s)
    }

    /// Shift the focused window a step in `dir` (5% of the screen), clamped on-screen.
    @discardableResult
    public func nudgeFocused(_ dir: MoveDirection) -> MoveOutcome? {
        guard let (w, s) = focusedWindowAndScreen() else { return nil }
        let target = WindowMove.nudge(w.frame, screen: s.frame, dir)
        let ok = windowSystem.move(windowId: w.id, to: target)
        return MoveOutcome(windowId: w.id, zoneKey: "", tileIndex: 0, target: target, applied: ok)
    }

    /// Snap the focused window to the screen edge in `dir`.
    @discardableResult
    public func throwFocused(_ dir: MoveDirection) -> MoveOutcome? {
        guard let (w, s) = focusedWindowAndScreen() else { return nil }
        let target = WindowMove.throwTo(w.frame, screen: s.frame, dir)
        let ok = windowSystem.move(windowId: w.id, to: target)
        return MoveOutcome(windowId: w.id, zoneKey: "", tileIndex: 0, target: target, applied: ok)
    }

    /// Swap the focused window's frame with its nearest neighbour in `dir`. Returns the two ids
    /// + whether both moves applied, or nil if there's no neighbour in that direction.
    @discardableResult
    public func swapFocused(_ dir: MoveDirection) -> (a: Int, b: Int, applied: Bool)? {
        guard let w = windowSystem.focusedWindow(), let uuid = w.screenUUID else { return nil }
        let others = windowSystem.windows(onScreen: uuid).filter { $0.id != w.id }.map { (id: $0.id, frame: $0.frame) }
        guard let targetId = WindowMove.swapTarget(focused: w.frame, others: others, dir),
              let target = others.first(where: { $0.id == targetId }) else { return nil }
        let okA = windowSystem.move(windowId: w.id, to: target.frame)
        let okB = windowSystem.move(windowId: targetId, to: w.frame)
        return (w.id, targetId, okA && okB)
    }

    /// Stamp the currently-focused window's focus time (drive from a periodic poll / focus
    /// event in the agent). Mirrors window_cache.lua's windowFocused subscription.
    public func noteFocusedWindow(now: Int) {
        if let id = windowSystem.focusedWindow()?.id { focusTracker.record(id: id, at: now) }
    }

    /// Baseline-seed focus times for all currently-visible windows across all screens, once at
    /// startup (window_cache.refresh equivalent) so pre-existing windows can age out of the
    /// working set. Does not overwrite times already tracked.
    public func seedFocusTimes(now: Int) {
        for s in screenProvider.allScreens() {
            for w in windowSystem.windows(onScreen: s.uuid) { focusTracker.recordIfAbsent(id: w.id, at: now) }
        }
    }

    /// Drop focus-time entries for windows no longer live (pass all current window ids).
    public func pruneFocusTimes(liveIds: Set<Int>) { focusTracker.prune(keepingIds: liveIds) }

    /// Per-app ranked memory preferences for a monitor, for AutoTiler.plan. Apps with no learned
    /// position fall back to their configured default zone (window_memory.app_zones), so a fresh
    /// window of a known app still has a target. Learned positions always win.
    private func rankedMemory(forApps apps: Set<String>, screenUUID: String, now: Int? = nil) -> [String: [MemoryPref]] {
        let key = monitorKey(screenUUID)
        var result: [String: [MemoryPref]] = [:]
        for app in apps {
            if let memory, let key {
                let ranked = memory.rankedPreferences(app: app, monitor: key, now: now)
                if !ranked.isEmpty {
                    // Use the recency-decayed weight as the effective usage count (>=1 so a known
                    // preference is never lost to decay), preserving ranked order.
                    result[app] = ranked.map { MemoryPref(zone_key: $0.zoneKey, tile_index: $0.tile,
                                                          count: max(1, Int($0.weight.rounded()))) }
                    continue
                }
            }
            if let zone = appZones[app] {
                result[app] = [MemoryPref(zone_key: zone, tile_index: .int(1), count: 1)]
            }
        }
        return result
    }
}
