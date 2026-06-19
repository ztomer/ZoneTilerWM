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

    /// `[borders]` — the focus-follow window outline.
    public struct Borders: Equatable {
        public var enabled: Bool
        public var backend: String       // "overlay" | "skylight"
        public var color: String         // config color name
        public var width: Double
        public var cornerRadius: Double
        public var prediction: Bool      // motion prediction to compensate follow-lag
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
        public var pomodoroWorkSec: Int
        public var pomodoroRestSec: Int
        public var pomodoroEnableColorBar: Bool
        public var pomodoroIndicatorHeight: Double        // ratio of menubar height (0..1)
        public var pomodoroIndicatorAlpha: Double
        public var pomodoroColorRemaining: String         // color name, e.g. "green"
        public var pomodoroColorUsed: String              // color name, e.g. "red"
        public var pomodoroHotkeys: [String: [String]]   // action -> [modifierAlias, key]
        public var tilerHotkeys: [String: [String]]      // action -> [modifierAlias, key]
        public var systemHotkeys: [String: [String]]     // action -> [modifierAlias, key]
        public var keyboardLayout: String                 // [ui] keyboard_layout: auto/qwerty/dvorak/colemak
        public var borders: Borders
        public var automationEnabled: Bool                 // [automation] enabled — the MCP/CLI socket
        public var commandPaletteEnabled: Bool             // [command_palette] enabled (opt-in, default off)
        public var zoneHUDEnabled: Bool                    // [zone_hud] enabled (opt-in, default off)
        public var zoneHUDHoldDelayMs: Int                 // hold the modifier this long before the HUD shows
        public var dragSnapEnabled: Bool                   // [drag_snap] enabled (opt-in, default off; EDR-sensitive)
        public var syncFolder: String?                     // [sync] folder — a synced dir for export/import (nil = off)
        public var breakScreenEnabled: Bool                // [break_screen] enabled (opt-in, default off)
        public var breakScreenDurationSec: Int             // how long the break overlay stays up
        public var scratchpadApps: [String]                // [scratchpad] apps — summon/dismiss together ([] = off)
        public var scratchpadAutoDismiss: Bool             // hide the set when focus leaves it
        public var appGroups: [AppGroupProfile]            // [[app_groups]] — named app sets, each with its own hotkey
        public var clusters: [ClusterProfile]              // [[clusters]] — named app→zone profiles ([] = none)
        public var displayPresets: [DisplayPreset]         // [[display_presets]] — auto-action on display-set change
        public var focusFollowsMouseEnabled: Bool          // [focus_follows_mouse] enabled (opt-in, default off; AX-sensitive)
        public var focusFollowsMouseDelayMs: Int           // dwell: cursor must settle this long before focusing
        public var eventsEnabled: Bool                     // [events] enabled — append arrangement-change events to a file
        public var eventsPath: String?                     // events file path (nil = cacheDir/events.jsonl)
        public var eventsIntervalMs: Int                   // arrangement poll interval
        public var nlEnabled: Bool                         // [nl] enabled — on-device natural-language layout box
        public var rules: [Rule]                           // [[rules]] — declarative window rules

        /// Resolve a config hotkey pair [modifierAlias, key] into (resolved modifier, key).
        public func resolvedHotkey(_ action: String, in group: [String: [String]]) -> (modifier: [String], key: String)? {
            guard let pair = group[action], pair.count >= 2 else { return nil }
            let modifier = aliases[pair[0]] ?? [pair[0]]
            return (modifier, pair[1])
        }
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
        var hotkeys: [String: [String]]?
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

    private struct RawPomodoro: Decodable {
        var work_period_sec: Int?
        var rest_period_sec: Int?
        var enable_color_bar: Bool?
        var indicator_height: Double?
        var indicator_alpha: Double?
        var color_time_remaining: String?
        var color_time_used: String?
        var hotkeys: [String: [String]]?
    }

    private struct RawBorders: Decodable {
        var enabled: Bool?
        var backend: String?
        var color: String?
        var width: Int?            // integer px (TOMLKit is strict Int-vs-Double)
        var corner_radius: Int?
        var prediction: Bool?
    }

    private struct RawConfig: Decodable {
        var version: String?
        var tiler: RawTiler
        var pomodoro: RawPomodoro?
        var borders: RawBorders?
        var window_memory: RawWindowMemory?
        var aliases: [String: [String]]?
        var app_switcher: RawAppSwitcher?
        var appCuts: RawAppCuts?
        var hyperAppCuts: RawAppCuts?
        var audio_switcher: RawAudio?
        var system_hotkeys: [String: [String]]?
        var ui: RawUI?
        var automation: RawAutomation?
        var command_palette: RawCommandPalette?
        var zone_hud: RawZoneHUD?
        var drag_snap: RawDragSnap?
        var sync: RawSync?
        var break_screen: RawBreakScreen?
        var scratchpad: RawScratchpad?
        var app_groups: [String: RawAppGroup]?     // [app_groups.<name>] subtables, keyed by group name
        var clusters: [RawCluster]?
        var display_presets: [RawDisplayPreset]?
        var focus_follows_mouse: RawFocusFollowsMouse?
        var events: RawEvents?
        var nl: RawNL?
        var rules: [RawRule]?
    }

    private struct RawUI: Decodable { var keyboard_layout: String? }

    private struct RawAutomation: Decodable { var enabled: Bool? }
    private struct RawCommandPalette: Decodable { var enabled: Bool? }
    private struct RawZoneHUD: Decodable { var enabled: Bool?; var hold_delay_ms: Int? }
    private struct RawDragSnap: Decodable { var enabled: Bool? }
    private struct RawSync: Decodable { var folder: String? }
    private struct RawBreakScreen: Decodable { var enabled: Bool?; var duration_sec: Int? }
    private struct RawScratchpad: Decodable { var apps: [String]?; var auto_dismiss: Bool? }
    private struct RawAppGroup: Decodable { var apps: [String]?; var hotkey: [String]?; var auto_dismiss: Bool? }
    private struct RawCluster: Decodable { var name: String?; var windows: [RawClusterWindow]? }
    private struct RawClusterWindow: Decodable { var app: String?; var zone: String?; var monitor: String? }
    private struct RawDisplayPreset: Decodable {
        var displays: [String]?; var action: String?
        var zone: String?; var direction: String?; var command: String?; var name: String?; var device: String?
    }
    private struct RawFocusFollowsMouse: Decodable { var enabled: Bool?; var delay_ms: Int? }
    private struct RawEvents: Decodable { var enabled: Bool?; var path: String?; var interval_ms: Int? }
    private struct RawNL: Decodable { var enabled: Bool? }

    /// `[[rules]]` — declarative window rules. `action` + its params mirror the CLI/MCP contract
    /// (so a rule's action is parsed through the same ActionParser). Known param keys only.
    private struct RawRule: Decodable {
        var app: String?
        var trigger: String?
        var action: String?
        var zone: String?
        var direction: String?
        var command: String?
        var name: String?
        var device: String?
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
            audioShortcutCallback: raw.audio_switcher?.shortcut_callback,
            pomodoroWorkSec: raw.pomodoro?.work_period_sec ?? 3120,
            pomodoroRestSec: raw.pomodoro?.rest_period_sec ?? 1020,
            pomodoroEnableColorBar: raw.pomodoro?.enable_color_bar ?? true,
            pomodoroIndicatorHeight: raw.pomodoro?.indicator_height ?? 0.2,
            pomodoroIndicatorAlpha: raw.pomodoro?.indicator_alpha ?? 0.3,
            pomodoroColorRemaining: raw.pomodoro?.color_time_remaining ?? "green",
            pomodoroColorUsed: raw.pomodoro?.color_time_used ?? "red",
            pomodoroHotkeys: raw.pomodoro?.hotkeys ?? [:],
            tilerHotkeys: t.hotkeys ?? [:],
            systemHotkeys: raw.system_hotkeys ?? [:],
            keyboardLayout: raw.ui?.keyboard_layout ?? "auto",
            borders: Borders(
                enabled: raw.borders?.enabled ?? false,
                backend: raw.borders?.backend ?? "overlay",
                color: raw.borders?.color ?? "blue",
                width: Double(raw.borders?.width ?? 4),
                cornerRadius: Double(raw.borders?.corner_radius ?? 9),
                prediction: raw.borders?.prediction ?? false),   // default off: raw 1:1 tracking
            automationEnabled: raw.automation?.enabled ?? true,  // on by default; the local socket is low-risk
            commandPaletteEnabled: raw.command_palette?.enabled ?? false,  // opt-in
            zoneHUDEnabled: raw.zone_hud?.enabled ?? false,                // opt-in
            zoneHUDHoldDelayMs: raw.zone_hud?.hold_delay_ms ?? 400,
            dragSnapEnabled: raw.drag_snap?.enabled ?? false,              // opt-in; installs a passive mouse monitor
            syncFolder: raw.sync?.folder.flatMap { $0.isEmpty ? nil : $0 },  // nil/empty = sync disabled
            breakScreenEnabled: raw.break_screen?.enabled ?? false,         // opt-in
            breakScreenDurationSec: raw.break_screen?.duration_sec ?? 6,
            scratchpadApps: raw.scratchpad?.apps ?? [],                     // empty = scratchpad off
            scratchpadAutoDismiss: raw.scratchpad?.auto_dismiss ?? true,
            appGroups: parseAppGroups(raw.app_groups),
            clusters: parseClusters(raw.clusters),
            displayPresets: parseDisplayPresets(raw.display_presets),
            focusFollowsMouseEnabled: raw.focus_follows_mouse?.enabled ?? false,   // opt-in; AX-sensitive
            focusFollowsMouseDelayMs: raw.focus_follows_mouse?.delay_ms ?? 250,
            eventsEnabled: raw.events?.enabled ?? false,                           // opt-in
            eventsPath: raw.events?.path.flatMap { $0.isEmpty ? nil : $0 },
            eventsIntervalMs: raw.events?.interval_ms ?? 1000,
            nlEnabled: raw.nl?.enabled ?? false,                                   // opt-in
            rules: parseRules(raw.rules))
    }

    /// Build [Rule] from the raw [[rules]] entries. A rule's `action` + params are parsed through
    /// the shared ActionParser (same contract as CLI/MCP); malformed rules are dropped.
    private static func parseRules(_ raw: [RawRule]?) -> [Rule] {
        guard let raw else { return [] }
        var out: [Rule] = []
        for r in raw {
            guard let app = r.app, !app.isEmpty,
                  let triggerRaw = r.trigger, let trigger = Rule.Trigger(rawValue: triggerRaw),
                  let actionName = r.action else { continue }
            var params: [String: String] = [:]
            if let v = r.zone { params["zone"] = v }
            if let v = r.direction { params["direction"] = v }
            if let v = r.command { params["command"] = v }
            if let v = r.name { params["name"] = v }
            if let v = r.device { params["device"] = v }
            guard case .success(let action) = ActionParser.parse(name: actionName, params: params) else { continue }
            out.append(Rule(app: app, trigger: trigger, action: action))
        }
        return out
    }

    /// Build [AppGroupProfile] from the raw [[app_groups]] entries. Entries missing a name or with
    /// no apps are dropped. The hotkey is kept raw ([alias, key]); it's resolved (alias → modifiers)
    /// when bound, exactly like the other hotkeys.
    private static func parseAppGroups(_ raw: [String: RawAppGroup]?) -> [AppGroupProfile] {
        guard let raw else { return [] }
        // Keep named groups even with no apps yet, so a just-created group stays editable in the UI
        // (an empty group is simply a no-op at runtime).
        return raw.sorted { $0.key < $1.key }.compactMap { (name, g) -> AppGroupProfile? in
            guard !name.isEmpty else { return nil }
            return AppGroupProfile(name: name, apps: g.apps ?? [], hotkey: g.hotkey ?? [], autoDismiss: g.auto_dismiss ?? true)
        }
    }

    /// Build [ClusterProfile] from the raw [[clusters]] entries (each with [[clusters.windows]]).
    /// Entries missing a name, or with no valid app→zone windows, are dropped.
    private static func parseClusters(_ raw: [RawCluster]?) -> [ClusterProfile] {
        guard let raw else { return [] }
        return raw.compactMap { c -> ClusterProfile? in
            guard let name = c.name, !name.isEmpty else { return nil }
            let placements = (c.windows ?? []).compactMap { w -> ClusterPlacement? in
                guard let app = w.app, !app.isEmpty, let zone = w.zone, !zone.isEmpty else { return nil }
                return ClusterPlacement(app: app, zone: zone, monitor: w.monitor)
            }
            return placements.isEmpty ? nil : ClusterProfile(name: name, placements: placements)
        }
    }

    /// Build [DisplayPreset] from [[display_presets]]; the action is parsed via the shared
    /// ActionParser (same vocabulary as rules/CLI). Entries with an unparseable action are dropped.
    private static func parseDisplayPresets(_ raw: [RawDisplayPreset]?) -> [DisplayPreset] {
        guard let raw else { return [] }
        return raw.compactMap { p -> DisplayPreset? in
            guard let actionName = p.action else { return nil }
            var params: [String: String] = [:]
            if let v = p.zone { params["zone"] = v }
            if let v = p.direction { params["direction"] = v }
            if let v = p.command { params["command"] = v }
            if let v = p.name { params["name"] = v }
            if let v = p.device { params["device"] = v }
            guard case .success(let action) = ActionParser.parse(name: actionName, params: params) else { return nil }
            return DisplayPreset(displays: p.displays ?? [], action: action)
        }
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

    /// Zone keys across all layouts (excluding the "default" marker) — what the tiler binds.
    public var zoneKeys: [String] {
        var keys = Set<String>()
        for (_, zones) in zoneConfig.layouts { for k in zones.keys where k != "default" { keys.insert(k) } }
        return keys.sorted()
    }

    /// Every global hotkey the agent binds, resolved to (modifier tokens, key, action name).
    public func allBindings() -> [HotkeyConflicts.Binding] {
        var b: [HotkeyConflicts.Binding] = []
        for k in zoneKeys { b.append(.init(modifier: tilerModifier, key: k, label: "Tile zone \(k)")) }
        for k in zoneKeys { b.append(.init(modifier: focusModifier, key: k, label: "Focus zone \(k)")) }
        for (k, app) in appCuts.apps { b.append(.init(modifier: appCuts.modifier, key: k, label: "Launch \(app)")) }
        for (k, app) in hyperAppCuts.apps { b.append(.init(modifier: hyperAppCuts.modifier, key: k, label: "Launch \(app)")) }
        func add(_ group: [String: [String]], _ name: (String) -> String) {
            for (action, _) in group {
                if let r = resolvedHotkey(action, in: group), !r.key.isEmpty {
                    b.append(.init(modifier: r.modifier, key: r.key, label: name(action)))
                }
            }
        }
        add(tilerHotkeys) { "Tiler: \($0)" }
        add(pomodoroHotkeys) { "Pomodoro: \($0)" }
        add(systemHotkeys) { "System: \($0)" }
        if let key = audioHotkeyKey, !key.isEmpty {
            b.append(.init(modifier: audioHotkeyModifier, key: key, label: "Audio switch"))
        }
        return b
    }

    /// Hotkey conflicts (same modifier+key bound to multiple actions), for warnings.
    public func hotkeyConflicts() -> [HotkeyConflicts.Conflict] {
        HotkeyConflicts.find(allBindings())
    }
}
