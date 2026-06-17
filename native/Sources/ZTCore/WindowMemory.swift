// WindowMemory.swift — faithful port of the pure logic in modules/window_memory.lua:
// the learned-preference state machine (running means), the "last position" memory, the
// settle/debounce model, ranking queries, and the on-disk JSON format.
//
// The system-coupled parts of the Lua module (hs.timer scheduling, window_cache capture,
// hotkeys, shutdown callback) are NOT here — they belong to the system layer. The debounce
// is modeled purely: positionWindow() records a pending learn keyed by window id, replacing
// any prior pending for that window (the Lua "cancel previous timer" behavior); flush()
// commits it. A real Clock drives flush in the app; tests/oracle drive it explicitly.

import Foundation

public final class WindowMemory {

    public struct Position: Equatable {
        public var zone: String
        public var tile: TileIndex
    }

    public struct Stats: Equatable {
        public var count: Int
        public var meanAR: Double
        public var meanArea: Double
    }

    public struct Ranked: Equatable {
        public let zoneKey: String
        public let tile: TileIndex
        public let count: Int
        public let meanAR: Double
        public let meanArea: Double
    }

    private struct Pending {
        let app, monitor, zone: String
        let tile: TileIndex
        let winW, winH, screenW, screenH: Double
    }

    // positions[app][monitor] = Position
    private(set) var positions: [String: [String: Position]] = [:]
    // preferences[app][monitor][zone][tile] = Stats
    private(set) var preferences: [String: [String: [String: [TileIndex: Stats]]]] = [:]
    private var pending: [Int: Pending] = [:]

    private let excluded: Set<String>
    private let settleEnabled: Bool

    public init(excludedApps: [String] = [], settleEnabled: Bool = true) {
        self.excluded = Set(excludedApps)
        self.settleEnabled = settleEnabled
    }

    private func isExcluded(_ app: String) -> Bool { excluded.contains(app) }

    // MARK: - Learning (port of on_window_positioned + commit_learned_position)

    /// Records the immediate "last position" and, if settling is enabled, queues a pending
    /// learn for `windowId` (replacing any prior pending — the debounce/cancel behavior).
    public func positionWindow(windowId: Int, app: String, monitor: String,
                               zone: String, tile: TileIndex,
                               winW: Double, winH: Double, screenW: Double, screenH: Double) {
        if isExcluded(app) { return }
        positions[app, default: [:]][monitor] = Position(zone: zone, tile: tile)
        if settleEnabled {
            pending[windowId] = Pending(app: app, monitor: monitor, zone: zone, tile: tile,
                                        winW: winW, winH: winH, screenW: screenW, screenH: screenH)
        }
    }

    /// Commits the pending learn for a window (if any).
    public func flush(windowId: Int) {
        guard let p = pending[windowId] else { return }
        commit(p)
        pending[windowId] = nil
    }

    /// Commits all pending learns. Sorted by window id for deterministic ordering (the
    /// final means are order-independent, but this keeps behavior reproducible).
    public func flushAll() {
        for id in pending.keys.sorted() { flush(windowId: id) }
    }

    private func commit(_ p: Pending) {
        var stats = preferences[p.app]?[p.monitor]?[p.zone]?[p.tile]
            ?? Stats(count: 0, meanAR: 0, meanArea: 0)

        var newAR = 0.0
        var newAreaRatio = 0.0
        // Guard mirrors Lua exactly: it checks screen width > 0 but not height.
        if p.winW > 0 && p.winH > 0 && p.screenW > 0 {
            newAR = p.winW / p.winH
            newAreaRatio = (p.winW * p.winH) / (p.screenW * p.screenH)
        }

        let n = Double(stats.count)
        stats.meanAR = ((stats.meanAR * n) + newAR) / (n + 1)
        stats.meanArea = ((stats.meanArea * n) + newAreaRatio) / (n + 1)
        stats.count += 1

        preferences[p.app, default: [:]][p.monitor, default: [:]][p.zone, default: [:]][p.tile] = stats
    }

    // MARK: - Queries

    public func rememberedPosition(app: String, monitor: String) -> Position? {
        if isExcluded(app) { return nil }
        return positions[app]?[monitor]
    }

    /// Most-used tile in a zone. Ties break to the smallest tile sortKey (deterministic).
    public func preferredTile(app: String, monitor: String, zone: String) -> TileIndex? {
        guard let tilePrefs = preferences[app]?[monitor]?[zone] else { return nil }
        var best: TileIndex?
        var maxCount = -1
        for tile in tilePrefs.keys.sorted(by: { $0.sortKey < $1.sortKey }) {
            let count = tilePrefs[tile]!.count
            if count > maxCount { maxCount = count; best = tile }
        }
        return best
    }

    /// Most-used zone (by total count across its tiles). Ties break to smallest zone key.
    public func preferredZone(app: String, monitor: String) -> String? {
        guard let monitorPrefs = preferences[app]?[monitor] else { return nil }
        var best: String?
        var maxTotal = -1
        for zone in monitorPrefs.keys.sorted() {
            let total = monitorPrefs[zone]!.values.reduce(0) { $0 + $1.count }
            if total > maxTotal { maxTotal = total; best = zone }
        }
        return best
    }

    /// Preferences ranked by count desc, then zone asc, then tile sortKey asc.
    public func rankedPreferences(app: String, monitor: String) -> [Ranked] {
        guard let monitorPrefs = preferences[app]?[monitor] else { return [] }
        var ranked: [Ranked] = []
        for (zone, tiles) in monitorPrefs {
            for (tile, stats) in tiles {
                ranked.append(Ranked(zoneKey: zone, tile: tile, count: stats.count,
                                     meanAR: stats.meanAR, meanArea: stats.meanArea))
            }
        }
        ranked.sort { a, b in
            if a.count != b.count { return a.count > b.count }
            if a.zoneKey != b.zoneKey { return a.zoneKey < b.zoneKey }
            return a.tile.sortKey < b.tile.sortKey
        }
        return ranked
    }

    // MARK: - Serialization (matches window_positions.json)

    public struct SaveData: Codable, Equatable {
        public struct PositionEntry: Codable, Equatable {
            public var app_name: String
            public var monitor_id: String
            public var zone_key: String
            public var tile_index: TileIndex
        }
        public struct StatsData: Codable, Equatable {
            public var count: Int
            public var mean_ar: Double
            public var mean_area: Double
        }
        public struct PreferenceEntry: Codable, Equatable {
            public var app_name: String
            public var monitor_id: String
            public var zone_key: String
            public var tile_index: TileIndex
            public var data: StatsData
        }
        public var positions: [PositionEntry]
        public var preferences: [PreferenceEntry]
    }

    /// Serialize current state to the on-disk array form. Arrays are sorted for
    /// deterministic output (the Lua oracle sorts identically before comparison).
    public func save() -> SaveData {
        var pos: [SaveData.PositionEntry] = []
        for (app, monitors) in positions {
            for (monitor, p) in monitors {
                pos.append(.init(app_name: app, monitor_id: monitor, zone_key: p.zone, tile_index: p.tile))
            }
        }
        pos.sort { ($0.app_name, $0.monitor_id) < ($1.app_name, $1.monitor_id) }

        var prefs: [SaveData.PreferenceEntry] = []
        for (app, monitors) in preferences {
            for (monitor, zones) in monitors {
                for (zone, tiles) in zones {
                    for (tile, stats) in tiles {
                        prefs.append(.init(
                            app_name: app, monitor_id: monitor, zone_key: zone, tile_index: tile,
                            data: .init(count: stats.count, mean_ar: stats.meanAR, mean_area: stats.meanArea)))
                    }
                }
            }
        }
        prefs.sort {
            ($0.app_name, $0.monitor_id, $0.zone_key, $0.tile_index.sortKey)
                < ($1.app_name, $1.monitor_id, $1.zone_key, $1.tile_index.sortKey)
        }
        return SaveData(positions: pos, preferences: prefs)
    }

    /// Load state from the on-disk array form (inverse of `save`).
    public func load(_ data: SaveData) {
        for p in data.positions {
            positions[p.app_name, default: [:]][p.monitor_id] = Position(zone: p.zone_key, tile: p.tile_index)
        }
        for pref in data.preferences {
            preferences[pref.app_name, default: [:]][pref.monitor_id, default: [:]][pref.zone_key, default: [:]][pref.tile_index]
                = Stats(count: pref.data.count, meanAR: pref.data.mean_ar, meanArea: pref.data.mean_area)
        }
    }
}
