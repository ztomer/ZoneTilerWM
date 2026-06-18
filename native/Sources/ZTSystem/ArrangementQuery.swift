// ArrangementQuery.swift — answers the read-only resource queries (arrangement / zones /
// placement stats) entirely from CGWindowList + the in-memory config and learned store. ZERO
// AX calls: window enumeration goes through the same CGWindowList path the rest of the app uses
// for reads, never per-window Accessibility. No window titles are read (would need Screen
// Recording — see QueryRequest header).

import Foundation
import ZTCore

public struct ArrangementQuery {
    private let windowSystem: WindowSystem
    private let screenProvider: ScreenProvider
    private let monitorManager: MonitorManager
    // Closures so a live config reload / resize-offset change is reflected without rebuilding.
    private let zoneConfig: () -> ZoneConfig
    private let offset: (_ monitor: String, _ axis: String, _ index: Int) -> Double
    private let memory: () -> WindowMemory?

    public init(windowSystem: WindowSystem,
                screenProvider: ScreenProvider,
                monitorManager: MonitorManager,
                zoneConfig: @escaping () -> ZoneConfig,
                offset: @escaping (_ monitor: String, _ axis: String, _ index: Int) -> Double,
                memory: @escaping () -> WindowMemory?) {
        self.windowSystem = windowSystem
        self.screenProvider = screenProvider
        self.monitorManager = monitorManager
        self.zoneConfig = zoneConfig
        self.offset = offset
        self.memory = memory
    }

    public func answer(_ query: QueryRequest) -> QueryResult {
        switch query {
        case .arrangement:    return .arrangement(windows: arrangement())
        case .zones:          return .zones(screens: zoneList())
        case .placementStats: return placementStats()
        }
    }

    // MARK: arrangement

    private func arrangement() -> [WindowInfo] {
        var out: [WindowInfo] = []
        for screen in screenProvider.allScreens() {
            let monitor = String(monitorManager.id(forUUID: screen.uuid))
            let zones = computeZones(screen)
            for w in windowSystem.windows(onScreen: screen.uuid) {
                out.append(WindowInfo(windowId: w.id, app: w.appName, frame: w.frame,
                                      monitor: monitor, zone: ZoneOccupancy.bestZone(window: w.frame, zones: zones)))
            }
        }
        return out
    }

    // MARK: zones

    private func zoneList() -> [ScreenZones] {
        screenProvider.allScreens().map { screen in
            let keys = computeZones(screen).keys.filter { $0 != "default" }.sorted()
            return ScreenZones(monitor: String(monitorManager.id(forUUID: screen.uuid)),
                               screenName: screen.name, zones: keys)
        }
    }

    // MARK: placement stats

    private func placementStats() -> QueryResult {
        guard let mem = memory() else { return .unavailable(reason: "window memory disabled") }
        let prefs = mem.save().preferences.map {
            PlacementStat(app: $0.app_name, monitor: $0.monitor_id, zone: $0.zone_key,
                          tile: $0.tile_index, count: $0.data.count)
        }
        return .placementStats(stats: prefs.sorted { ($0.app, $0.monitor, $0.zone) < ($1.app, $1.monitor, $1.zone) })
    }

    // MARK: helpers

    private func computeZones(_ screen: ScreenSnapshot) -> [String: [ZTRect]] {
        let info = ZoneCalculator.ScreenInfo(name: screen.name, frame: screen.frame)
        let key = String(monitorManager.id(forUUID: screen.uuid))
        let offsets: ZoneCalculator.OffsetProvider = { [offset] axis, index in offset(key, axis, index) }
        return ZoneCalculator.computeZones(screen: info, config: zoneConfig(), offsets: offsets).zones
    }
}
