// ConfigLoader.swift — reads the existing config.toml into ZTCore models, using the
// maintained TOMLKit parser (toml++-backed) rather than a hand-rolled parser. Replicates
// the config.lua post-processing relevant to the ported core (cache_dir ~ expansion).
//
// Alias resolution (mash -> [ctrl,cmd]) and color-name conversion are deferred to the
// hotkey / UI work — they don't affect the algorithmic config loaded here. Unknown TOML
// sections (pomodoro, audio_switcher, appCuts, …) are ignored by Codable.

import Foundation
import TOMLKit
import ZTCore

public enum ConfigLoader {

    public struct WindowMemorySettings: Equatable {
        public var enabled: Bool
        public var excludedApps: [String]
        public var settleDelaySec: Double
        public var saveIntervalSec: Int
        public var cacheDir: String        // ~ expanded
        public var defaultZone: String?
        public var appZones: [String: String]
        public var autoTileFallback: Bool
    }

    public struct LoadedConfig: Equatable {
        public var version: String
        public var zoneConfig: ZoneConfig
        public var solverWeights: CostWeights
        public var autoTileCenterZones: [String]
        public var autoTilingMode: String
        public var workingSetTimeLimit: Int
        public var workingSetMaxCapacity: Int
        public var placementStrategy: String
        public var windowMemory: WindowMemorySettings
        public var aliases: [String: [String]]
        public var tilerModifier: [String]   // resolved (e.g. mash -> [ctrl, cmd])
        public var focusModifier: [String]
        public var appSwitcher: AppSwitcher.Config
        public var appCuts: AppHotkeyGroup
        public var hyperAppCuts: AppHotkeyGroup
        public var audioDevices: [String]
        public var audioHotkeyModifier: [String]
        public var audioHotkeyKey: String?
        public var audioShortcutCallback: String?
    }

    // MARK: - TOML decode model (only the sections the ported core needs)

    private struct RawWeights: Decodable {
        var memory_exact, memory_zone, aspect_ratio, area_ratio, moved_dist, skip_window, coverage: Double?
        enum CodingKeys: String, CodingKey {
            case memory_exact, memory_zone, aspect_ratio, area_ratio, moved_dist, skip_window, coverage
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            memory_exact = try c.decodeFlexDoubleIfPresent(.memory_exact)
            memory_zone = try c.decodeFlexDoubleIfPresent(.memory_zone)
            aspect_ratio = try c.decodeFlexDoubleIfPresent(.aspect_ratio)
            area_ratio = try c.decodeFlexDoubleIfPresent(.area_ratio)
            moved_dist = try c.decodeFlexDoubleIfPresent(.moved_dist)
            skip_window = try c.decodeFlexDoubleIfPresent(.skip_window)
            coverage = try c.decodeFlexDoubleIfPresent(.coverage)
        }
    }

    private struct RawWorkingSet: Decodable { var time_limit_sec: Int?; var max_capacity: Int? }

    private struct RawTiler: Decodable {
        var grids: [String: GridConfig]
        var layouts: [String: [String: [String]]]
        var margins: Margins?
        var screen_detection: ScreenDetection?
        var custom_screens: [String: CustomScreen]?
        var solver_weights: RawWeights?
        var auto_tile_center_zones: [String]?
        var auto_tiling_mode: String?
        var working_set: RawWorkingSet?
        var placement_strategy: String?
        var modifier: String?
        var focus_modifier: String?
    }

    private struct RawWindowMemory: Decodable {
        var enabled: Bool?
        var settle_delay_sec: Double?
        var save_interval_sec: Int?
        var cache_dir: String?
        var excluded_apps: [String]?
        var auto_tile_fallback: Bool?
        var default_zone: String?
        var app_zones: [String: String]?
    }

    private struct RawAppSwitcher: Decodable {
        var hide_workaround_apps: [String]?
        var ambiguous_apps: [[String]]?
        var special_app_mappings: [String: String]?
    }

    /// An [appCuts]/[hyperAppCuts] table: a `modifier` array plus key->app entries mixed in.
    private struct RawAppCuts: Decodable {
        var modifier: [String]
        var apps: [String: String]
        private struct Key: CodingKey {
            var stringValue: String; init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }; init?(intValue: Int) { nil }
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            var mods: [String] = []
            var entries: [String: String] = [:]
            for key in c.allKeys {
                if key.stringValue == "modifier" {
                    mods = (try? c.decode([String].self, forKey: key)) ?? []
                } else if let app = try? c.decode(String.self, forKey: key) {
                    entries[key.stringValue] = app
                }
            }
            modifier = mods; apps = entries
        }
    }

    private struct RawAudio: Decodable {
        var devices: [String]?
        var hotkey: [String]?
        var shortcut_callback: String?
    }

    private struct RawConfig: Decodable {
        var version: String?
        var tiler: RawTiler
        var window_memory: RawWindowMemory?
        var aliases: [String: [String]]?
        var app_switcher: RawAppSwitcher?
        var appCuts: RawAppCuts?
        var hyperAppCuts: RawAppCuts?
        var audio_switcher: RawAudio?
    }

    /// A resolved app-shortcut group: the actual modifier names + key->app entries.
    public struct AppHotkeyGroup: Equatable {
        public let modifier: [String]
        public let apps: [String: String]
    }

    // MARK: - API

    public static func load(tomlString: String, homeDirectory: String) throws -> LoadedConfig {
        let raw = try TOMLDecoder().decode(RawConfig.self, from: tomlString)
        let t = raw.tiler

        var weights = CostWeights()
        if let w = t.solver_weights {
            if let v = w.memory_exact { weights.memoryExact = v }
            if let v = w.memory_zone { weights.memoryZone = v }
            if let v = w.aspect_ratio { weights.aspectRatio = v }
            if let v = w.area_ratio { weights.areaRatio = v }
            if let v = w.moved_dist { weights.movedDist = v }
            if let v = w.skip_window { weights.skipWindow = v }
            if let v = w.coverage { weights.coverage = v }
        }

        let zoneConfig = ZoneConfig(
            grids: t.grids, layouts: t.layouts, margins: t.margins,
            screen_detection: t.screen_detection, custom_screens: t.custom_screens)

        let wm = raw.window_memory
        func expandTilde(_ path: String) -> String {
            path.hasPrefix("~") ? homeDirectory + String(path.dropFirst()) : path
        }
        let windowMemory = WindowMemorySettings(
            enabled: wm?.enabled ?? true,
            excludedApps: wm?.excluded_apps ?? [],
            settleDelaySec: wm?.settle_delay_sec ?? 2.0,
            saveIntervalSec: wm?.save_interval_sec ?? 0,
            cacheDir: expandTilde(wm?.cache_dir ?? "~/.config/ZoneTilerWM"),
            defaultZone: wm?.default_zone,
            appZones: wm?.app_zones ?? [:],
            autoTileFallback: wm?.auto_tile_fallback ?? false)

        let aliases = raw.aliases ?? [:]
        func resolveMod(_ name: String?) -> [String] {
            guard let name else { return [] }
            return aliases[name] ?? [name]
        }
        // A modifier list whose single element may itself be an alias (e.g. ["mash_app"]).
        func resolveModList(_ mods: [String]) -> [String] {
            if mods.count == 1, let resolved = aliases[mods[0]] { return resolved }
            return mods
        }

        let appSwitcher = AppSwitcher.Config(
            specialMappings: raw.app_switcher?.special_app_mappings ?? [:],
            ambiguousApps: raw.app_switcher?.ambiguous_apps ?? [],
            hideWorkaroundApps: raw.app_switcher?.hide_workaround_apps ?? [])
        let appCuts = AppHotkeyGroup(modifier: resolveModList(raw.appCuts?.modifier ?? []),
                                     apps: raw.appCuts?.apps ?? [:])
        let hyperAppCuts = AppHotkeyGroup(modifier: resolveModList(raw.hyperAppCuts?.modifier ?? []),
                                          apps: raw.hyperAppCuts?.apps ?? [:])

        return LoadedConfig(
            version: raw.version ?? "Unknown",
            zoneConfig: zoneConfig,
            solverWeights: weights,
            autoTileCenterZones: t.auto_tile_center_zones ?? ["j", "center", "0"],
            autoTilingMode: t.auto_tiling_mode ?? "usage",
            workingSetTimeLimit: t.working_set?.time_limit_sec ?? 1800,
            workingSetMaxCapacity: t.working_set?.max_capacity ?? 6,
            placementStrategy: t.placement_strategy ?? "rotate",
            windowMemory: windowMemory,
            aliases: aliases,
            tilerModifier: resolveMod(t.modifier),
            focusModifier: resolveMod(t.focus_modifier),
            appSwitcher: appSwitcher,
            appCuts: appCuts,
            hyperAppCuts: hyperAppCuts,
            audioDevices: raw.audio_switcher?.devices ?? [],
            audioHotkeyModifier: resolveMod((raw.audio_switcher?.hotkey ?? []).first),
            audioHotkeyKey: (raw.audio_switcher?.hotkey ?? []).count >= 2 ? raw.audio_switcher?.hotkey?[1] : nil,
            audioShortcutCallback: raw.audio_switcher?.shortcut_callback)
    }

    public static func load(contentsOf url: URL) throws -> LoadedConfig {
        let text = try String(contentsOf: url, encoding: .utf8)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return try load(tomlString: text, homeDirectory: home)
    }
}

extension ConfigLoader.LoadedConfig {
    /// Convenience: assemble the AutoTiler config from the loaded values.
    public func autoTilerConfig() -> AutoTiler.Config {
        AutoTiler.Config(
            centerZones: autoTileCenterZones,
            workingSetTimeLimit: workingSetTimeLimit,
            workingSetMaxCapacity: workingSetMaxCapacity,
            mode: autoTilingMode,
            weights: solverWeights,
            zoneConfig: zoneConfig)
    }
}
