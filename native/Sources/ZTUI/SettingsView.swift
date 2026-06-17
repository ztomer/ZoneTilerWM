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
            memory.tabItem { Text("Memory") }
            layouts.tabItem { Text("Layouts") }
        }
        .frame(width: 520, height: 420)
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
            Table(model.preferences) {
                TableColumn("App") { Text($0.app) }
                TableColumn("Monitor") { Text($0.monitor) }
                TableColumn("Zone") { Text($0.zone) }
                TableColumn("Tile") { Text($0.tile) }
                TableColumn("Count") { Text("\($0.count)") }
            }
        }
    }

    private var layouts: some View {
        List {
            ForEach(model.config.zoneConfig.layouts.keys.sorted(), id: \.self) { key in
                let zones = model.config.zoneConfig.layouts[key]?.keys.sorted().joined(separator: " ") ?? ""
                LabeledContent(key, value: zones)
            }
        }
    }
}
