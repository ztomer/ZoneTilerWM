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

    /// Replace a hotkey binding, e.g. [tiler.hotkeys] resize_mode = ["HYPER", "r"].
    public func setHotkey(section: String, key: String, alias: String, keyName: String) {
        setValue(section: section, key: key, rawValue: "[\"\(alias)\", \"\(keyName)\"]")
    }

    /// Replace a scalar modifier alias, e.g. [tiler] modifier = "mash".
    public func setModifierAlias(key: String, alias: String) {
        setValue(section: "tiler", key: key, rawValue: "\"\(alias)\"")
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

    // Audio
    public func setAudioDevices(_ devices: [String]) { setOrAppend(section: "audio_switcher", key: "devices", rawValue: tomlArray(devices)) }
    public func setAudioHotkey(alias: String, key: String) { setOrAppend(section: "audio_switcher", key: "hotkey", rawValue: "[\"\(alias)\", \"\(key)\"]") }
    public func setAudioShortcut(_ s: String) { setOrAppend(section: "audio_switcher", key: "shortcut_callback", rawValue: "\"\(s)\"") }

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

    // Advanced: auto-tiler solver weights (integers; negative = reward).
    public func setSolverWeight(_ key: String, _ v: Int) { setOrAppend(section: "tiler.solver_weights", key: key, rawValue: "\(v)") }

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
    }

    public var preferences: [Pref] {
        guard let memory else { return [] }
        return memory.save().preferences
            .map { Pref(app: $0.app_name, monitor: $0.monitor_id, zone: $0.zone_key,
                        tile: $0.tile_index.sortKey, count: $0.data.count) }
            .sorted { $0.count > $1.count }
    }

    /// Total learned count per zone key (optionally for one monitor), for the usage heatmap.
    public func zoneUsage(monitor: String?) -> [String: Int] {
        var out: [String: Int] = [:]
        for p in preferences where monitor == nil || p.monitor == monitor {
            out[p.zone, default: 0] += p.count
        }
        return out
    }
    public var monitorsInData: [String] { Array(Set(preferences.map { $0.monitor })).sorted() }
}

public struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    public init(model: SettingsModel) { self.model = model }

    public var body: some View {
        TabView {
            general.tabItem { Text("General") }
            KeybindEditorView(model: model).tabItem { Text("Keys") }
            AppShortcutsView(model: model).tabItem { Text("Apps") }
            LayoutEditorView(model: model).tabItem { Text("Layouts") }
            PomodoroTab(model: model).tabItem { Text("Pomodoro") }
            AdvancedTab(model: model).tabItem { Text("Advanced") }
        }
        .frame(width: 680, height: 560)
        .padding()
    }

    private var general: some View {
        Form {
            Section("Config") {
                LabeledContent("File") {
                    HStack(spacing: 8) {
                        Text(model.configURL.lastPathComponent).foregroundColor(.secondary)
                        Button("Reveal") { model.revealConfigInFinder() }
                        Button("Open") { model.openConfigInEditor() }
                    }
                }
                LabeledContent("Version", value: model.config.version)
            }
            Section("Tiling") {
                Picker("Placement strategy", selection: Binding(
                    get: { model.config.placementStrategy },
                    set: { model.setValue(section: "tiler", key: "placement_strategy", rawValue: "\"\($0)\"") })) {
                    Text("rotate").tag("rotate")
                    Text("largest free space").tag("largest_free_space")
                    Text("hybrid").tag("hybrid")
                }
                Picker("Auto-tiling mode", selection: Binding(
                    get: { model.config.autoTilingMode },
                    set: { model.setValue(section: "tiler", key: "auto_tiling_mode", rawValue: "\"\($0)\"") })) {
                    Text("usage").tag("usage")
                    Text("session").tag("session")
                }
                Stepper("Working-set capacity: \(model.config.workingSetMaxCapacity)",
                        value: Binding(get: { model.config.workingSetMaxCapacity },
                                       set: { model.setWorkingSetCapacity($0) }), in: 1...12)
                Stepper("Working-set staleness: \(model.config.workingSetTimeLimit / 60) min",
                        value: Binding(get: { model.config.workingSetTimeLimit / 60 },
                                       set: { model.setWorkingSetMinutes($0) }), in: 1...240)
                LabeledContent("Auto-tile center zones") {
                    HStack {
                        TextField("e.g. j, center, 0", text: $centerZonesEdit).textFieldStyle(.roundedBorder)
                            .onSubmit { commitCenterZones() }
                        Button("Save") { commitCenterZones() }
                    }
                }
            }
            Section("Input") {
                Picker("Keyboard layout", selection: Binding(
                    get: { model.keyboardChoice },
                    set: { model.setKeyboardLayout($0) })) {
                    Text("Auto (\(model.detectedKeyboard))").tag("auto")
                    ForEach(KeyboardLayout.presets, id: \.self) { Text($0).tag($0) }
                }
                Text("Used to render the Apps and Layouts key maps. Auto follows the active macOS input source.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Margins") {
                Toggle("Enable margins", isOn: Binding(
                    get: { model.config.zoneConfig.margins?.enabled ?? false },
                    set: { model.setMarginsEnabled($0) }))
                Stepper("Size: \(Int(model.config.zoneConfig.margins?.size ?? 0)) px",
                        value: Binding(get: { Int(model.config.zoneConfig.margins?.size ?? 0) },
                                       set: { model.setMarginsSize($0) }), in: 0...40)
                    .disabled(!(model.config.zoneConfig.margins?.enabled ?? false))
                Toggle("Apply margin at screen edges", isOn: Binding(
                    get: { model.config.zoneConfig.margins?.screen_edge ?? false },
                    set: { model.setMarginsScreenEdge($0) }))
                    .disabled(!(model.config.zoneConfig.margins?.enabled ?? false))
            }
            AudioSettings(model: model)
            if let err = model.lastWriteError { Text(err).foregroundColor(.red).font(.caption) }
        }
        .formStyle(.grouped)
        .onAppear { centerZonesEdit = model.config.autoTileCenterZones.joined(separator: ", ") }
    }

    @State private var centerZonesEdit = ""
    private func commitCenterZones() {
        let zones = centerZonesEdit.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        model.setCenterZones(zones)
    }

}
