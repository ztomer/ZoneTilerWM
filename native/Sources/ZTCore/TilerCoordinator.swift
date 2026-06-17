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

    public init(windowSystem: WindowSystem,
                screenProvider: ScreenProvider,
                zoneConfig: ZoneConfig,
                placementStrategy: String,
                offsets: @escaping ZoneCalculator.OffsetProvider = ZoneCalculator.zeroOffsets) {
        self.windowSystem = windowSystem
        self.screenProvider = screenProvider
        self.zoneConfig = zoneConfig
        self.strategy = PlacementStrategy.Strategy(config: placementStrategy)
        self.offsets = offsets
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
        return .success(MoveOutcome(windowId: focused.id, zoneKey: zoneKey,
                                    tileIndex: tileIndex, target: target, applied: applied))
    }

    /// Auto-tile every window on the focused window's screen (or the main screen) using the
    /// ported AutoTiler, applying each planned move via the WindowSystem. Returns the moves.
    @discardableResult
    public func autoTileScreen(autoTilerConfig: AutoTiler.Config,
                               memory: [String: [MemoryPref]] = [:],
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

        let moves = AutoTiler.plan(config: autoTilerConfig, screens: screens, windows: windows,
                                   zOrder: zOrder, focusedId: focusedId, memory: memory, now: now)
        for m in moves { windowSystem.move(windowId: m.windowId, to: m.rect) }
        return moves
    }
}
