// SettingsView.swift — v1 settings window for ZoneTilerWM. Reads the loaded config, edits a
// couple of settings via the surgical comment-preserving TOML writer, and shows a read-only
// memory inspector + layouts list. The full keybind editor + visual layout editor are v2.
//
// Purely visual — validate in a UI round. Built with SwiftUI, hosted by the agent.

import SwiftUI
import AppKit
import ZTCore
import ZTSystem

public final class SettingsModel: ObservableObject {
    public let configURL: URL
    @Published public var config: ConfigLoader.LoadedConfig
    @Published public var lastWriteError: String?
    private let memory: WindowMemory?

    public init(configURL: URL, config: ConfigLoader.LoadedConfig, memory: WindowMemory?) {
        self.configURL = configURL
        self.config = config
        self.memory = memory
    }

    /// Persist a scalar change to config.toml (comment-preserving) and reload the model.
    public func setValue(section: String, key: String, rawValue: String) {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8),
              let edited = TOMLEditor.setValue(text, section: section, key: key, rawValue: rawValue) else {
            lastWriteError = "could not edit \(section).\(key)"; return
        }
        do {
            try edited.data(using: .utf8)?.write(to: configURL, options: .atomic)
            config = try ConfigLoader.load(tomlString: edited,
                                           homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
            lastWriteError = nil
        } catch {
            lastWriteError = "\(error)"
        }
    }

    // MARK: - v2 editor writes (layouts + keybinds), all via the surgical TOML writer.

    /// Replace a layout zone's tile cycle list, e.g. [tiler.layouts."4x3"] "j" = ["b1:c3", ...].
    public func setLayoutZone(grid: String, zone: String, tiles: [String]) {
        let raw = "[" + tiles.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
        setValue(section: "tiler.layouts.\"\(grid)\"", key: zone, rawValue: raw)
    }

    /// Set a hotkey binding, e.g. [tiler.hotkeys] resize_mode = ["HYPER", "r"]. Uses setOrAppend so a
    /// binding the user's config doesn't have YET (e.g. the opt-in Feature actions: expose,
    /// command_palette, peek, …) is created rather than silently dropped — setValue only replaces
    /// existing keys.
    public func setHotkey(section: String, key: String, alias: String, keyName: String) {
        setOrAppend(section: section, key: key, rawValue: "[\"\(alias)\", \"\(keyName)\"]")
    }

    /// Set a scalar modifier alias, e.g. [tiler] modifier = "mash" (setOrAppend so a missing key is
    /// created, not dropped).
    public func setModifierAlias(key: String, alias: String) {
        setOrAppend(section: "tiler", key: key, rawValue: "\"\(alias)\"")
    }

    // MARK: - General settings

    public func setWorkingSetCapacity(_ n: Int) {
        setOrAppend(section: "tiler.working_set", key: "max_capacity", rawValue: "\(n)")
    }
    public func setMarginsEnabled(_ on: Bool) {
        setOrAppend(section: "tiler.margins", key: "enabled", rawValue: on ? "true" : "false")
    }
    public func setMarginsSize(_ px: Int) {
        setOrAppend(section: "tiler.margins", key: "size", rawValue: "\(px)")
    }
    public func setMarginsScreenEdge(_ on: Bool) {
        setOrAppend(section: "tiler.margins", key: "screen_edge", rawValue: on ? "true" : "false")
    }
    public func setWorkingSetMinutes(_ minutes: Int) {
        setOrAppend(section: "tiler.working_set", key: "time_limit_sec", rawValue: "\(minutes * 60)")
    }
    public func setCenterZones(_ zones: [String]) {
        setOrAppend(section: "tiler", key: "auto_tile_center_zones", rawValue: tomlArray(zones))
    }

    // Pomodoro
    public func setPomodoroWorkMinutes(_ m: Int) { setOrAppend(section: "pomodoro", key: "work_period_sec", rawValue: "\(m * 60)") }
    public func setPomodoroRestMinutes(_ m: Int) { setOrAppend(section: "pomodoro", key: "rest_period_sec", rawValue: "\(m * 60)") }
    public func setPomodoroColorBar(_ on: Bool) { setOrAppend(section: "pomodoro", key: "enable_color_bar", rawValue: on ? "true" : "false") }
    public func setPomodoroIndicatorHeight(_ v: Double) { setOrAppend(section: "pomodoro", key: "indicator_height", rawValue: String(format: "%.2f", v)) }
    public func setPomodoroIndicatorAlpha(_ v: Double) { setOrAppend(section: "pomodoro", key: "indicator_alpha", rawValue: String(format: "%.2f", v)) }
    public func setPomodoroColor(remaining: Bool, _ name: String) {
        setOrAppend(section: "pomodoro", key: remaining ? "color_time_remaining" : "color_time_used", rawValue: "\"\(name)\"")
    }

    // Borders
    public func setBordersEnabled(_ on: Bool) { setOrAppend(section: "borders", key: "enabled", rawValue: on ? "true" : "false") }
    public func setBordersBackend(_ b: String) { setOrAppend(section: "borders", key: "backend", rawValue: "\"\(b)\"") }
    public func setBordersColor(_ name: String) { setOrAppend(section: "borders", key: "color", rawValue: "\"\(name)\"") }
    public func setBordersWidth(_ v: Int) { setOrAppend(section: "borders", key: "width", rawValue: "\(v)") }
    public func setBordersCornerRadius(_ v: Int) { setOrAppend(section: "borders", key: "corner_radius", rawValue: "\(v)") }
    public func setBordersPrediction(_ on: Bool) { setOrAppend(section: "borders", key: "prediction", rawValue: on ? "true" : "false") }

    // Automation (MCP server + zonetiler-cli, over the local socket)
    public var automationEnabled: Bool { config.automationEnabled }
    public func setAutomationEnabled(_ on: Bool) { setOrAppend(section: "automation", key: "enabled", rawValue: on ? "true" : "false") }
    public var agentSocketPath: String { AgentSocket.defaultPath() }
    /// Whether the agent is currently serving on the socket (the file exists while bound).
    public var automationListening: Bool { FileManager.default.fileExists(atPath: agentSocketPath) }
    private func agentBinDir() -> URL { URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent() }
    public var mcpBinaryPath: String { agentBinDir().appendingPathComponent("zt-mcp").path }
    public var cliBinaryPath: String { agentBinDir().appendingPathComponent("zonetiler-cli").path }
    public var mcpRegisterCommand: String { "claude mcp add zonetiler -- \(mcpBinaryPath)" }

    // Audio
    public func setAudioDevices(_ devices: [String]) { setOrAppend(section: "audio_switcher", key: "devices", rawValue: tomlArray(devices)) }
    public func setAudioHotkey(alias: String, key: String) { setOrAppend(section: "audio_switcher", key: "hotkey", rawValue: "[\"\(alias)\", \"\(key)\"]") }
    public func setAudioShortcut(_ s: String) { setOrAppend(section: "audio_switcher", key: "shortcut_callback", rawValue: "\"\(s)\"") }

    // MARK: - Gated v3 features (all opt-in, default off) — persisted comment-preserving.
    public func setCommandPaletteEnabled(_ on: Bool) { setOrAppend(section: "command_palette", key: "enabled", rawValue: on ? "true" : "false") }
    public func setZoneHUDEnabled(_ on: Bool) { setOrAppend(section: "zone_hud", key: "enabled", rawValue: on ? "true" : "false") }
    public func setZoneHUDHoldDelay(_ ms: Int) { setOrAppend(section: "zone_hud", key: "hold_delay_ms", rawValue: "\(ms)") }
    public func setDragSnapEnabled(_ on: Bool) { setOrAppend(section: "drag_snap", key: "enabled", rawValue: on ? "true" : "false") }
    public func setBreakScreenEnabled(_ on: Bool) { setOrAppend(section: "break_screen", key: "enabled", rawValue: on ? "true" : "false") }
    public func setBreakScreenDuration(_ s: Int) { setOrAppend(section: "break_screen", key: "duration_sec", rawValue: "\(s)") }
    public func setScratchpadApps(_ apps: [String]) { setOrAppend(section: "scratchpad", key: "apps", rawValue: tomlArray(apps)) }
    public func setScratchpadAutoDismiss(_ on: Bool) { setOrAppend(section: "scratchpad", key: "auto_dismiss", rawValue: on ? "true" : "false") }
    public func setFocusFollowsMouseEnabled(_ on: Bool) { setOrAppend(section: "focus_follows_mouse", key: "enabled", rawValue: on ? "true" : "false") }
    public func setFocusFollowsMouseDelay(_ ms: Int) { setOrAppend(section: "focus_follows_mouse", key: "delay_ms", rawValue: "\(ms)") }
    public func setEventsEnabled(_ on: Bool) { setOrAppend(section: "events", key: "enabled", rawValue: on ? "true" : "false") }
    public func setEventsInterval(_ ms: Int) { setOrAppend(section: "events", key: "interval_ms", rawValue: "\(ms)") }
    public func setNLEnabled(_ on: Bool) { setOrAppend(section: "nl", key: "enabled", rawValue: on ? "true" : "false") }
    public func setSyncFolder(_ path: String) { setOrAppend(section: "sync", key: "folder", rawValue: "\"\(path)\"") }

    // Window memory
    public func setWindowMemoryEnabled(_ on: Bool) { setOrAppend(section: "window_memory", key: "enabled", rawValue: on ? "true" : "false") }
    public func setExcludedApps(_ apps: [String]) { setOrAppend(section: "window_memory", key: "excluded_apps", rawValue: tomlArray(apps)) }
    /// Per-app default zone (window_memory.app_zones), e.g. "Arc" = "k".
    public func setAppZone(app: String, zone: String) {
        setOrAppend(section: "window_memory.app_zones", key: "\"\(app)\"", rawValue: "\"\(zone)\"")
    }
    public func removeAppZone(app: String) {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8),
              let edited = TOMLEditor.removeKey(text, section: "window_memory.app_zones", key: app) else { return }
        persist(edited)
    }

    // Startup: launch-at-login (SMAppService; not config-backed — it's a system login item).
    public var launchAtLoginAvailable: Bool { LoginItem.isAvailable }
    public var launchAtLogin: Bool { LoginItem.isEnabled }
    public func setLaunchAtLogin(_ on: Bool) {
        do { try LoginItem.setEnabled(on) } catch { NSLog("ZoneTilerWM: launch-at-login toggle failed: \(error)") }
        objectWillChange.send()
    }

    // Advanced: auto-tiler solver weights (integers; negative = reward).
    public func setSolverWeight(_ key: String, _ v: Int) { setOrAppend(section: "tiler.solver_weights", key: key, rawValue: "\(v)") }

    /// Restore every solver weight to its CostWeights() default (one write/reload).
    public func resetSolverWeights() {
        let d = CostWeights()
        let defaults: [(String, Double)] = [
            ("memory_exact", d.memoryExact), ("memory_zone", d.memoryZone), ("coverage", d.coverage),
            ("aspect_ratio", d.aspectRatio), ("area_ratio", d.areaRatio),
            ("moved_dist", d.movedDist), ("skip_window", d.skipWindow),
        ]
        for (k, v) in defaults { setOrAppend(section: "tiler.solver_weights", key: k, rawValue: "\(Int(v))") }
    }

    private func tomlArray(_ items: [String]) -> String {
        "[" + items.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
    }
    /// One app shortcut, e.g. [appCuts] "q" = "BambuStudio".
    public func setAppShortcut(group: String, key: String, app: String) {
        setOrAppend(section: group, key: "\"\(key)\"", rawValue: "\"\(app)\"")
    }
    /// Clear a shortcut: delete the key line entirely.
    public func removeAppShortcut(group: String, key: String) {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8),
              let edited = TOMLEditor.removeKey(text, section: group, key: key) else { return }
        persist(edited)
    }

    /// Create / update a named app group ([app_groups."<name>"] subtable). hotkey is [alias, key]
    /// (empty = no shortcut). Three surgical writes (each reloads); the subtable form keeps it
    /// TOMLEditor-addressable, unlike an [[array]] of tables.
    public func setAppGroup(name: String, apps: [String], hotkey: [String], autoDismiss: Bool) {
        let section = "app_groups.\"\(name)\""
        setOrAppend(section: section, key: "apps", rawValue: tomlArray(apps))
        setOrAppend(section: section, key: "hotkey", rawValue: tomlArray(hotkey))
        setOrAppend(section: section, key: "auto_dismiss", rawValue: autoDismiss ? "true" : "false")
    }
    public func removeAppGroup(name: String) {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8),
              let edited = TOMLEditor.removeSection(text, section: "app_groups.\"\(name)\"") else { return }
        persist(edited)
    }

    /// Define / replace a modifier alias, e.g. [aliases] mash_shift = ["shift","ctrl","cmd"].
    /// The token order is normalised so the same combo always serialises identically.
    public func setAlias(name: String, modifiers: [String]) {
        let order = ["shift", "ctrl", "alt", "cmd"]
        let sorted = modifiers.filter { order.contains($0) }.sorted { (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99) }
        setOrAppend(section: "aliases", key: name, rawValue: tomlArray(sorted))
    }
    /// Delete an alias definition. (Keybindings still referencing it fall back to treating the name
    /// as a literal modifier — harmless, but the UI warns before removing one that's in use.)
    public func removeAlias(name: String) {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8),
              let edited = TOMLEditor.removeKey(text, section: "aliases", key: name) else { return }
        persist(edited)
    }
    /// Per-monitor grid override; passing nil clears it back to auto-detect.
    public func setMonitorOverride(name: String, grid: String?) {
        let section = "tiler.custom_screens.\"\(name)\""
        if let grid { setOrAppend(section: section, key: "layout", rawValue: "\"\(grid)\"") }
        else { removeSection(section) }
    }

    /// setOrAppend wrapper that writes + reloads (mirrors setValue's reload).
    private func setOrAppend(section: String, key: String, rawValue: String) {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else {
            lastWriteError = "could not read config"; return
        }
        let edited = TOMLEditor.setOrAppend(text, section: section, key: key, rawValue: rawValue)
        persist(edited)
    }
    private func removeSection(_ section: String) {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8),
              let edited = TOMLEditor.removeSection(text, section: section) else { return }
        persist(edited)
    }
    private func persist(_ edited: String) {
        do {
            try edited.data(using: .utf8)?.write(to: configURL, options: .atomic)
            config = try ConfigLoader.load(tomlString: edited,
                                           homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
            lastWriteError = nil
        } catch { lastWriteError = "\(error)" }
    }

    // MARK: - Keyboard layout (Apps + zone renders)

    /// The auto-detected layout preset name (qwerty/dvorak/colemak).
    public var detectedKeyboard: String { KeyboardLayoutDetector.current() }
    /// The user's choice: "auto" or a preset name.
    public var keyboardChoice: String { config.keyboardLayout }
    /// The effective physical key rows to render.
    public var keyboardRows: [[String]] {
        KeyboardLayout.rows(for: keyboardChoice == "auto" ? detectedKeyboard : keyboardChoice)
    }
    public func setKeyboardLayout(_ choice: String) {
        if choice == "auto" {
            guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return }
            if let edited = TOMLEditor.removeKey(text, section: "ui", key: "keyboard_layout") { persist(edited) }
        } else {
            setOrAppend(section: "ui", key: "keyboard_layout", rawValue: "\"\(choice)\"")
        }
    }

    public var exposeSpacesBarPositionChoice: String { config.exposeSpacesBarPosition }
    public func setExposeSpacesBarPosition(_ choice: String) {
        setOrAppend(section: "ui", key: "expose_spaces_bar_position", rawValue: "\"\(choice)\"")
    }

    public var exposeNavChoice: String { config.exposeNav }
    public func setExposeNav(_ choice: String) {
        setOrAppend(section: "ui", key: "expose_nav", rawValue: "\"\(choice)\"")
    }

    public var exposeScopeChoice: String { config.exposeScope }
    public func setExposeScope(_ choice: String) {
        setOrAppend(section: "ui", key: "expose_scope", rawValue: "\"\(choice)\"")
    }

    public var realSpacesEnabled: Bool { config.experimentalRealSpaces }
    public func setRealSpaces(_ on: Bool) {
        setOrAppend(section: "ui", key: "experimental_real_spaces", rawValue: on ? "true" : "false")
    }

    public var spacesMenubarEnabled: Bool { config.spacesMenubar }
    public func setSpacesMenubar(_ on: Bool) {
        setOrAppend(section: "ui", key: "spaces_menubar", rawValue: on ? "true" : "false")
    }

    public var spaceSwitchMethodChoice: String { config.spaceSwitchMethod }
    public func setSpaceSwitchMethod(_ choice: String) {
        setOrAppend(section: "ui", key: "space_switch_method", rawValue: "\"\(choice)\"")
    }

    public var spacesMenubarBracketChoice: String { config.spacesMenubarBracket }
    public func setSpacesMenubarBracket(_ choice: String) {
        setOrAppend(section: "ui", key: "spaces_menubar_bracket", rawValue: "\"\(choice)\"")
    }

    // MARK: - Monitors (Layouts tab)

    private let screenProvider = NSScreenProvider()

    public struct MonitorInfo: Identifiable {
        public var id: String { name }
        public let name: String
        public let autoDetected: String?   // grid the detector picks ignoring overrides
        public let override: String?        // explicit per-monitor grid, if any
        public var effective: String { override ?? autoDetected ?? "2x2" }
    }

    public var monitors: [MonitorInfo] {
        screenProvider.allScreens().map { s in
            let info = ZoneCalculator.ScreenInfo(name: s.name, frame: s.frame)
            var noOverride = config.zoneConfig; noOverride.custom_screens = nil
            return MonitorInfo(name: s.name,
                               autoDetected: ZoneCalculator.layoutKey(for: info, config: noOverride),
                               override: config.zoneConfig.custom_screens?[s.name]?.layout)
        }
    }

    public func revealConfigInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([configURL])
    }
    public func openConfigInEditor() {
        NSWorkspace.shared.open(configURL)
    }

    /// Current raw [alias, key] for a hotkey, by config section.
    public func hotkeyValue(section: String, key: String) -> [String] {
        switch section {
        case "tiler.hotkeys": return config.tilerHotkeys[key] ?? []
        case "pomodoro.hotkeys": return config.pomodoroHotkeys[key] ?? []
        case "system_hotkeys": return config.systemHotkeys[key] ?? []
        default: return []
        }
    }

    public struct Pref: Identifiable {
        public let id = UUID()
        public let app: String, monitor: String, zone: String, tile: String
        public let count: Int
        public let lastSeen: Int
        public let meanAR: Double      // mean window aspect ratio (w/h) when learned
        public let meanArea: Double    // mean window area as a fraction of the screen
    }

    public var preferences: [Pref] {
        guard let memory else { return [] }
        return memory.save().preferences
            .map { Pref(app: $0.app_name, monitor: $0.monitor_id, zone: $0.zone_key,
                        tile: $0.tile_index.sortKey, count: $0.data.count, lastSeen: $0.data.last_seen,
                        meanAR: $0.data.mean_ar, meanArea: $0.data.mean_area) }
            .sorted { $0.count > $1.count }
    }

    /// Half-life (2 weeks) for the analytics recency weighting.
    private static let recencyHalfLife = 1_209_600.0
    /// A preference's count, optionally recency-decayed (legacy rows with no timestamp aren't decayed).
    private func weight(_ p: Pref, recency: Bool) -> Int {
        guard recency, p.lastSeen > 0 else { return p.count }
        let age = Double(max(0, Int(Date().timeIntervalSince1970) - p.lastSeen))
        return Int((Double(p.count) * pow(0.5, age / Self.recencyHalfLife)).rounded())
    }

    /// Total (optionally recency-weighted) count per zone key, filtered by app/monitor.
    public func zoneUsage(app: String? = nil, monitor: String? = nil, recency: Bool = false) -> [String: Int] {
        var out: [String: Int] = [:]
        for p in preferences where (app == nil || p.app == app) && (monitor == nil || p.monitor == monitor) {
            out[p.zone, default: 0] += weight(p, recency: recency)
        }
        return out
    }

    /// Spatial occupancy per grid cell ([col][row-1]) for a given grid, filtered by app/monitor:
    /// each learned (zone, tile) is resolved to its cell span in that grid and its (optionally
    /// recency-weighted) count added to every covered cell.
    public func cellUsage(grid: String, app: String? = nil, monitor: String? = nil, recency: Bool = false)
        -> (cols: Int, rows: Int, cells: [[Int]], max: Int) {
        guard let g = config.zoneConfig.grids[grid], let layout = config.zoneConfig.layouts[grid] else {
            return (0, 0, [], 0)
        }
        var cells = Array(repeating: Array(repeating: 0, count: g.rows), count: g.cols)
        for p in preferences where (app == nil || p.app == app) && (monitor == nil || p.monitor == monitor) {
            guard let tiles = layout[p.zone], let idx = Int(p.tile), idx >= 1, idx <= tiles.count,
                  let span = GridCells.parse(tiles[idx - 1]) else { continue }
            let w = weight(p, recency: recency)
            for c in span.c0...span.c1 where c < g.cols {
                for r in span.r0...span.r1 where r >= 1 && r - 1 < g.rows { cells[c][r - 1] += w }
            }
        }
        return (g.cols, g.rows, cells, cells.flatMap { $0 }.max() ?? 0)
    }

    public var monitorsInData: [String] { Array(Set(preferences.map { $0.monitor })).sorted() }
    public var appsInData: [String] { Array(Set(preferences.map { $0.app }.filter { !$0.isEmpty })).sorted() }

    /// Daily placement counts (dayIndex = epoch/86400, ascending) for the Analytics trend.
    public func dailyPlacements() -> [(day: Int, count: Int)] { memory?.dailyCounts() ?? [] }
}

public struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var sel: String
    @State private var search = ""   // the titlebar search field (filters the sidebar; ↵ jumps to first match)

    /// The sidebar groups, in display order. SF Symbols stand in for the Kare/Rams custom icons.
    /// `keywords` lets the titlebar search match a pane by what's *inside* it, not just its title.
    private struct Group: Identifiable { let id: String; let title: String; let icon: String; var keywords: [String] = [] }
    // `keywords` is a comprehensive index of EVERY control label in each pane (not just its title),
    // so searching any setting name — "corner radius", "bar opacity", "dwell", "poll interval" —
    // jumps to the pane that holds it. Keep in sync when adding a setting.
    private let groups: [Group] = [
        .init(id: "general",    title: "General",        icon: "gearshape",                     keywords: GeneralTab.searchKeywords),
        .init(id: "tiling",     title: "Tiling",         icon: "square.grid.3x3",               keywords: TilingTab.searchKeywords),
        .init(id: "layouts",    title: "Layouts",        icon: "rectangle.3.group",             keywords: LayoutEditorView.searchKeywords),
        .init(id: "previews",   title: "Exposé & Hints", icon: "window.badge.exclamationmark",  keywords: PreviewsTab.searchKeywords),
        .init(id: "keys",       title: "Keys",           icon: "keyboard",                      keywords: KeybindEditorView.searchKeywords),
        .init(id: "io",         title: "Input & Output", icon: "slider.horizontal.3",           keywords: IOTab.searchKeywords),
        .init(id: "apps",       title: "App Launcher",   icon: "square.grid.2x2",               keywords: AppLauncherTab.searchKeywords),
        .init(id: "pomodoro",   title: "Pomodoro",       icon: "timer",                         keywords: PomodoroTab.searchKeywords),
        .init(id: "appearance", title: "Appearance",     icon: "paintbrush",                    keywords: AppearanceTab.searchKeywords),
        .init(id: "automation", title: "Automation",     icon: "terminal",                      keywords: AutomationTab.searchKeywords),
        .init(id: "advanced",   title: "Advanced",       icon: "wrench.and.screwdriver",        keywords: AdvancedTab.searchKeywords),
    ]

    /// Panes matching the titlebar search (title or keyword substring). Empty query → all panes.
    private var filteredGroups: [Group] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return groups }
        return groups.filter { g in
            g.title.lowercased().contains(q) || g.keywords.contains { $0.contains(q) }
        }
    }

    public init(model: SettingsModel) {
        self.model = model
        // QA hook: ZT_SETTINGS_TAB opens a specific group directly (for screenshot review).
        _sel = State(initialValue: ProcessInfo.processInfo.environment["ZT_SETTINGS_TAB"] ?? "general")
    }

    public var body: some View {
        NavigationSplitView {
            List(filteredGroups, selection: $sel) { g in
                Label { Text(g.title) } icon: { SidebarGlyph(id: g.id) }.tag(g.id)
            }
            .navigationSplitViewColumnWidth(155)
            .listStyle(.sidebar)
            .overlay {   // honest empty state when a search matches nothing
                if filteredGroups.isEmpty {
                    Text("No settings match “\(search)”")
                        .font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(.center).padding()
                }
            }
        } detail: {
            SettingsGroupDetail(model: model, id: sel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationTitle("")   // the titlebar hosts the search field, not a duplicate pane name
        }
        .frame(minWidth: 960, idealWidth: 1000, minHeight: 560, idealHeight: 620)
        // The search field fills the once-empty titlebar. Filters the sidebar as you type; ↵ jumps to
        // the first match so you can drive it entirely from the keyboard.
        .searchable(text: $search, placement: .toolbar, prompt: "Search settings")
        .onSubmit(of: .search) { if let first = filteredGroups.first { sel = first.id } }
    }
}

/// The detail pane for the selected sidebar group. Factored out (and reused by SettingsRender) so a
/// single group can be rendered in isolation for screenshot QA.
struct SettingsGroupDetail: View {
    @ObservedObject var model: SettingsModel
    let id: String
    var body: some View {
        switch id {
        case "tiling":     TilingTab(model: model)
        case "layouts":    LayoutEditorView(model: model)
        case "previews":   PreviewsTab(model: model)
        case "keys":       KeybindEditorView(model: model)
        case "io":         IOTab(model: model)
        case "apps":       AppLauncherTab(model: model)
        case "pomodoro":   PomodoroTab(model: model)
        case "appearance": AppearanceTab(model: model)
        case "automation": AutomationTab(model: model)
        case "advanced":   AdvancedTab(model: model)
        default:           GeneralTab(model: model)
        }
    }
}
