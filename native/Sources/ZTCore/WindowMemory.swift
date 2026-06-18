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

/// Decodes a value that may be persisted as String, Int, or Double, returning its string
/// form. Legacy window_positions.json files store monitor ids (and occasionally other
/// fields) as numbers; the native model keys everything by String.
extension KeyedDecodingContainer {
    public func decodeStringy(_ key: Key) throws -> String {
        if let s = try? decode(String.self, forKey: key) { return s }
        if let i = try? decode(Int.self, forKey: key) { return String(i) }
        if let d = try? decode(Double.self, forKey: key) {
            return d == d.rounded() ? String(Int(d)) : String(d)
        }
        throw DecodingError.dataCorruptedError(
            forKey: key, in: self,
            debugDescription: "expected String, Int, or Double for \(key.stringValue)")
    }

    /// Decodes a number that may be an Int or a Double, returning Double. TOML distinguishes
    /// integer/float literals, so config values like `size = 5` (Int) must coerce.
    public func decodeFlexDouble(_ key: Key) throws -> Double {
        if let d = try? decode(Double.self, forKey: key) { return d }
        if let i = try? decode(Int.self, forKey: key) { return Double(i) }
        throw DecodingError.dataCorruptedError(
            forKey: key, in: self,
            debugDescription: "expected Int or Double for \(key.stringValue)")
    }

    public func decodeFlexDoubleIfPresent(_ key: Key) throws -> Double? {
        guard contains(key) else { return nil }
        return try decodeFlexDouble(key)
    }
}

public final class WindowMemory {

    public struct Position: Equatable {
        public var zone: String
        public var tile: TileIndex
    }

    public struct Stats: Equatable {
        public var count: Int
        public var meanAR: Double
        public var meanArea: Double
        public var lastSeen: Int = 0   // epoch seconds of the most recent learn; 0 = unknown
    }

    public struct Ranked: Equatable {
        public let zoneKey: String
        public let tile: TileIndex
        public let count: Int
        public let meanAR: Double
        public let meanArea: Double
        public let lastSeen: Int
        public let weight: Double   // recency-decayed count (== count when no `now` is supplied)
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
    // Daily placement histogram: dayIndex (epoch / 86400, timezone-free) -> placements that day.
    // Powers the Analytics trend. Empty under the default {0} clock (tests/oracle) and for
    // legacy on-disk data. Capped on save.
    private var daily: [Int: Int] = [:]
    private static let dailyRetentionDays = 180

    private let excluded: Set<String>
    private let settleEnabled: Bool
    private let clock: () -> Int   // injected; default {0} keeps tests/oracle timestamp-free

    public init(excludedApps: [String] = [], settleEnabled: Bool = true, clock: @escaping () -> Int = { 0 }) {
        self.excluded = Set(excludedApps)
        self.settleEnabled = settleEnabled
        self.clock = clock
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
        // Require BOTH screen dimensions positive: a zero screen height would make the area
        // ratio +Inf and permanently poison the running mean. (The original Lua only checked
        // width; parity is no longer a constraint, so this is hardened.)
        if p.winW > 0 && p.winH > 0 && p.screenW > 0 && p.screenH > 0 {
            newAR = p.winW / p.winH
            newAreaRatio = (p.winW * p.winH) / (p.screenW * p.screenH)
        }

        let n = Double(stats.count)
        stats.meanAR = ((stats.meanAR * n) + newAR) / (n + 1)
        stats.meanArea = ((stats.meanArea * n) + newAreaRatio) / (n + 1)
        stats.count += 1
        stats.lastSeen = clock()   // 0 under the default clock (oracle/tests); real epoch live
        daily[clock() / 86400, default: 0] += 1   // one placement on this day-bucket

        preferences[p.app, default: [:]][p.monitor, default: [:]][p.zone, default: [:]][p.tile] = stats
    }

    /// Daily placement counts, ascending by day-bucket (epoch / 86400). For the Analytics trend.
    public func dailyCounts() -> [(day: Int, count: Int)] {
        daily.sorted { $0.key < $1.key }.map { (day: $0.key, count: $0.value) }
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

    /// Preferences ranked by weight desc, then zone asc, then tile sortKey asc. With `now` nil
    /// (the default — and what the differential oracle uses), weight == count, so the order is
    /// exactly count-desc as before. With `now` supplied and a learned timestamp, the count is
    /// recency-decayed with the given half-life, so recent habits outrank stale ones.
    public func rankedPreferences(app: String, monitor: String,
                                  now: Int? = nil, halfLifeSec: Double = 1_209_600) -> [Ranked] {
        guard let monitorPrefs = preferences[app]?[monitor] else { return [] }
        var ranked: [Ranked] = []
        for (zone, tiles) in monitorPrefs {
            for (tile, stats) in tiles {
                let weight: Double
                if let now, stats.lastSeen > 0 {
                    weight = Double(stats.count) * pow(0.5, Double(max(0, now - stats.lastSeen)) / halfLifeSec)
                } else {
                    weight = Double(stats.count)
                }
                ranked.append(Ranked(zoneKey: zone, tile: tile, count: stats.count,
                                     meanAR: stats.meanAR, meanArea: stats.meanArea,
                                     lastSeen: stats.lastSeen, weight: weight))
            }
        }
        ranked.sort { a, b in
            if a.weight != b.weight { return a.weight > b.weight }
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

            public init(app_name: String, monitor_id: String, zone_key: String, tile_index: TileIndex) {
                self.app_name = app_name; self.monitor_id = monitor_id
                self.zone_key = zone_key; self.tile_index = tile_index
            }

            enum CodingKeys: String, CodingKey { case app_name, monitor_id, zone_key, tile_index }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                app_name = try c.decodeStringy(.app_name)
                monitor_id = try c.decodeStringy(.monitor_id)   // legacy files store this as a number
                zone_key = try c.decodeStringy(.zone_key)
                tile_index = try c.decode(TileIndex.self, forKey: .tile_index)
            }
        }

        public struct StatsData: Codable, Equatable {
            public var count: Int
            public var mean_ar: Double
            public var mean_area: Double
            public var last_seen: Int   // epoch seconds of last learn; 0 / absent for legacy data
            public init(count: Int, mean_ar: Double, mean_area: Double, last_seen: Int = 0) {
                self.count = count; self.mean_ar = mean_ar; self.mean_area = mean_area; self.last_seen = last_seen
            }
            enum CodingKeys: String, CodingKey { case count, mean_ar, mean_area, last_seen }
            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                count = (try? c.decode(Int.self, forKey: .count)) ?? 0
                mean_ar = (try? c.decode(Double.self, forKey: .mean_ar)) ?? 0
                mean_area = (try? c.decode(Double.self, forKey: .mean_area)) ?? 0
                last_seen = (try? c.decode(Int.self, forKey: .last_seen)) ?? 0   // tolerant of legacy
            }
        }

        public struct PreferenceEntry: Codable, Equatable {
            public var app_name: String
            public var monitor_id: String
            public var zone_key: String
            public var tile_index: TileIndex
            public var data: StatsData

            public init(app_name: String, monitor_id: String, zone_key: String,
                        tile_index: TileIndex, data: StatsData) {
                self.app_name = app_name; self.monitor_id = monitor_id; self.zone_key = zone_key
                self.tile_index = tile_index; self.data = data
            }

            enum CodingKeys: String, CodingKey { case app_name, monitor_id, zone_key, tile_index, data, count }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                app_name = try c.decodeStringy(.app_name)
                monitor_id = try c.decodeStringy(.monitor_id)
                zone_key = try c.decodeStringy(.zone_key)
                tile_index = try c.decode(TileIndex.self, forKey: .tile_index)
                // New format: a stats object under `data`. Legacy (per window_memory.lua's
                // load_positions): a bare numeric `count`, or `data` itself a number.
                if let d = try? c.decode(StatsData.self, forKey: .data) {
                    data = d
                } else if let count = try? c.decode(Int.self, forKey: .count) {
                    data = StatsData(count: count, mean_ar: 0, mean_area: 0)
                } else if let count = try? c.decode(Int.self, forKey: .data) {
                    data = StatsData(count: count, mean_ar: 0, mean_area: 0)
                } else {
                    data = StatsData(count: 0, mean_ar: 0, mean_area: 0)
                }
            }

            public func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(app_name, forKey: .app_name)
                try c.encode(monitor_id, forKey: .monitor_id)
                try c.encode(zone_key, forKey: .zone_key)
                try c.encode(tile_index, forKey: .tile_index)
                try c.encode(data, forKey: .data)
            }
        }

        public var positions: [PositionEntry]
        public var preferences: [PreferenceEntry]
        public var daily: [String: Int]   // dayIndex (epoch/86400) string -> count; empty for legacy

        public init(positions: [PositionEntry], preferences: [PreferenceEntry], daily: [String: Int] = [:]) {
            self.positions = positions; self.preferences = preferences; self.daily = daily
        }
        enum CodingKeys: String, CodingKey { case positions, preferences, daily }
        // Tolerant decode so files written before the `daily` field still load.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            positions = (try? c.decode([PositionEntry].self, forKey: .positions)) ?? []
            preferences = (try? c.decode([PreferenceEntry].self, forKey: .preferences)) ?? []
            daily = (try? c.decode([String: Int].self, forKey: .daily)) ?? [:]
        }
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
                            data: .init(count: stats.count, mean_ar: stats.meanAR, mean_area: stats.meanArea,
                                        last_seen: stats.lastSeen)))
                    }
                }
            }
        }
        prefs.sort {
            ($0.app_name, $0.monitor_id, $0.zone_key, $0.tile_index.sortKey)
                < ($1.app_name, $1.monitor_id, $1.zone_key, $1.tile_index.sortKey)
        }
        // Keep only the most recent retention window so the histogram can't grow unbounded.
        var trimmed = daily
        if let newest = daily.keys.max() {
            let cutoff = newest - Self.dailyRetentionDays
            trimmed = daily.filter { $0.key > cutoff }
        }
        let dailyOut = Dictionary(uniqueKeysWithValues: trimmed.map { (String($0.key), $0.value) })
        return SaveData(positions: pos, preferences: prefs, daily: dailyOut)
    }

    /// Load state from the on-disk array form (inverse of `save`).
    public func load(_ data: SaveData) {
        for p in data.positions {
            positions[p.app_name, default: [:]][p.monitor_id] = Position(zone: p.zone_key, tile: p.tile_index)
        }
        for pref in data.preferences {
            preferences[pref.app_name, default: [:]][pref.monitor_id, default: [:]][pref.zone_key, default: [:]][pref.tile_index]
                = Stats(count: pref.data.count, meanAR: pref.data.mean_ar, meanArea: pref.data.mean_area,
                        lastSeen: pref.data.last_seen)
        }
        for (k, v) in data.daily { if let day = Int(k) { daily[day] = v } }
    }
}
