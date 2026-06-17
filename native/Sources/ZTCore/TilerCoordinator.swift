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
    private let offsets: ZoneCalculator.OffsetProvider
    private let overlapThreshold: Double
    private let focusCycler = FocusManager.Cycler()

    // Optional adaptive memory: when present, manual zone moves are learned + persisted, and
    // auto-tile becomes memory-augmented. monitorManager maps screen UUID -> the logical id
    // the on-disk window_positions.json is keyed by.
    private let memory: WindowMemory?
    private let monitorManager: MonitorManager?
    private let storage: Storage?

    public init(windowSystem: WindowSystem,
                screenProvider: ScreenProvider,
                zoneConfig: ZoneConfig,
                placementStrategy: String,
                overlapThreshold: Double = 0.5,
                offsets: @escaping ZoneCalculator.OffsetProvider = ZoneCalculator.zeroOffsets,
                memory: WindowMemory? = nil,
                monitorManager: MonitorManager? = nil,
                storage: Storage? = nil) {
        self.windowSystem = windowSystem
        self.screenProvider = screenProvider
        self.zoneConfig = zoneConfig
        self.strategy = PlacementStrategy.Strategy(config: placementStrategy)
        self.overlapThreshold = overlapThreshold
        self.offsets = offsets
        self.memory = memory
        self.monitorManager = monitorManager
        self.storage = storage
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
        let zones = ZoneCalculator.computeZones(screen: info, config: zoneConfig, offsets: offsets).zones
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

    /// Move the focused window into `zoneKey` on its current screen.
    public func moveFocusedToZone(_ zoneKey: String) -> Result<MoveOutcome, MoveError> {
        guard let focused = windowSystem.focusedWindow() else { return .failure(.noFocusedWindow) }
        guard let uuid = focused.screenUUID, let screen = screenProvider.screen(uuid: uuid) else {
            return .failure(.noScreenForWindow)
        }

        let info = ZoneCalculator.ScreenInfo(name: screen.name, frame: screen.frame)
        let zones = ZoneCalculator.computeZones(screen: info, config: zoneConfig, offsets: offsets).zones
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

    /// Auto-tile every window on the focused window's screen (or the main screen) using the
    /// ported AutoTiler, applying each planned move via the WindowSystem. Returns the moves.
    @discardableResult
    public func autoTileScreen(autoTilerConfig: AutoTiler.Config,
                               memory memoryOverride: [String: [MemoryPref]]? = nil,
                               now: Int) -> [AutoTiler.PlannedMove] {
        let uuid = windowSystem.focusedWindow()?.screenUUID ?? screenProvider.mainScreen()?.uuid
        guard let uuid, let screen = screenProvider.screen(uuid: uuid) else { return [] }

        let live = windowSystem.windows(onScreen: uuid)   // front-to-back
        let windows = live.map {
            AutoTiler.Window(id: $0.id, app: $0.appName, monitor: uuid, frame: $0.frame,
                             lastFocusedTime: now, isStandard: true, isMinimized: false)
        }
        let zOrder = live.map { $0.id }
        let focusedId = windowSystem.focusedWindow()?.id
        let screens = [AutoTiler.Screen(uuid: uuid, name: screen.name, frame: screen.frame)]

        // Memory-augmented: ranked preferences per app for this monitor (logical id key).
        let memory = memoryOverride ?? rankedMemory(forApps: Set(live.map { $0.appName }), screenUUID: uuid)

        let moves = AutoTiler.plan(config: autoTilerConfig, screens: screens, windows: windows,
                                   zOrder: zOrder, focusedId: focusedId, memory: memory, now: now)
        for m in moves { windowSystem.move(windowId: m.windowId, to: m.rect) }
        return moves
    }

    /// Per-app ranked memory preferences for a monitor, for AutoTiler.plan.
    private func rankedMemory(forApps apps: Set<String>, screenUUID: String) -> [String: [MemoryPref]] {
        guard let memory, let key = monitorKey(screenUUID) else { return [:] }
        var result: [String: [MemoryPref]] = [:]
        for app in apps {
            let ranked = memory.rankedPreferences(app: app, monitor: key)
            if !ranked.isEmpty {
                result[app] = ranked.map { MemoryPref(zone_key: $0.zoneKey, tile_index: $0.tile, count: $0.count) }
            }
        }
        return result
    }
}
