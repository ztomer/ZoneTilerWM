// SettingsView.swift — v1 settings window for ZoneTilerWM. Reads the loaded config, edits a
// couple of settings via the surgical comment-preserving TOML writer, and shows a read-only
// memory inspector + layouts list. The full keybind editor + visual layout editor are v2.
//
// Purely visual — validate in a UI round. Built with SwiftUI, hosted by the agent.

import SwiftUI
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
}

public struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    public init(model: SettingsModel) { self.model = model }

    public var body: some View {
        TabView {
            general.tabItem { Text("General") }
            KeybindEditorView(model: model).tabItem { Text("Keybinds") }
            LayoutEditorView(model: model).tabItem { Text("Layouts") }
            memory.tabItem { Text("Memory") }
        }
        .frame(width: 620, height: 460)
        .padding()
    }

    private var general: some View {
        Form {
            LabeledContent("Config", value: model.configURL.lastPathComponent)
            LabeledContent("Version", value: model.config.version)

            Picker("Placement strategy", selection: Binding(
                get: { model.config.placementStrategy },
                set: { model.setValue(section: "tiler", key: "placement_strategy", rawValue: "\"\($0)\"") })) {
                Text("rotate").tag("rotate")
                Text("largest_free_space").tag("largest_free_space")
                Text("hybrid").tag("hybrid")
            }

            Picker("Auto-tiling mode", selection: Binding(
                get: { model.config.autoTilingMode },
                set: { model.setValue(section: "tiler", key: "auto_tiling_mode", rawValue: "\"\($0)\"") })) {
                Text("usage").tag("usage")
                Text("session").tag("session")
            }

            LabeledContent("Working-set capacity", value: "\(model.config.workingSetMaxCapacity)")
            LabeledContent("Margins", value: (model.config.zoneConfig.margins?.enabled ?? false)
                           ? "on (\(Int(model.config.zoneConfig.margins?.size ?? 0))px)" : "off")
            if let err = model.lastWriteError { Text(err).foregroundColor(.red).font(.caption) }
        }
    }

    private var memory: some View {
        VStack(alignment: .leading) {
            Text("Learned placements (by frequency)").font(.headline)
            // Explicit widths so the numeric columns (esp. Count) never clip; App flexes.
            Table(model.preferences) {
                TableColumn("App") { Text($0.app.isEmpty ? "—" : $0.app) }.width(min: 120, ideal: 150)
                TableColumn("Monitor") { Text($0.monitor) }.width(min: 56, ideal: 64, max: 80)
                TableColumn("Zone") { Text($0.zone) }.width(min: 44, ideal: 52, max: 70)
                TableColumn("Tile") { Text($0.tile) }.width(min: 40, ideal: 48, max: 64)
                TableColumn("Count") { Text("\($0.count)") }.width(min: 56, ideal: 70, max: 90)
            }
        }
    }

}
