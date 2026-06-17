// FeatureSettings.swift — additional General-tab sections for features that were implemented
// in the agent but had no UI: Pomodoro, Audio switcher, Window Memory, and the advanced
// auto-tiler solver weights. Each is a Form Section composed into the General form. All writes
// go through the model's surgical TOML setters (and trip the live reload).

import SwiftUI
import ZTCore

private let colorNames = ["green", "red", "blue", "yellow", "orange", "purple", "white", "black", "gray"]

// MARK: - Pomodoro

struct PomodoroSettings: View {
    @ObservedObject var model: SettingsModel
    private var aliasNames: [String] { model.config.aliases.keys.sorted() }

    var body: some View {
        Section("Pomodoro") {
            Stepper("Work: \(model.config.pomodoroWorkSec / 60) min",
                    value: Binding(get: { model.config.pomodoroWorkSec / 60 },
                                   set: { model.setPomodoroWorkMinutes($0) }), in: 1...120)
            Stepper("Rest: \(model.config.pomodoroRestSec / 60) min",
                    value: Binding(get: { model.config.pomodoroRestSec / 60 },
                                   set: { model.setPomodoroRestMinutes($0) }), in: 1...60)
            Toggle("Show color bar", isOn: Binding(
                get: { model.config.pomodoroEnableColorBar },
                set: { model.setPomodoroColorBar($0) }))
            Stepper("Bar height: \(Int(model.config.pomodoroIndicatorHeight * 100))%",
                    value: Binding(get: { model.config.pomodoroIndicatorHeight },
                                   set: { model.setPomodoroIndicatorHeight($0) }), in: 0.05...1.0, step: 0.05)
                .disabled(!model.config.pomodoroEnableColorBar)
            Stepper("Bar opacity: \(Int(model.config.pomodoroIndicatorAlpha * 100))%",
                    value: Binding(get: { model.config.pomodoroIndicatorAlpha },
                                   set: { model.setPomodoroIndicatorAlpha($0) }), in: 0.05...1.0, step: 0.05)
                .disabled(!model.config.pomodoroEnableColorBar)
            colorPicker("Remaining color", value: model.config.pomodoroColorRemaining) { model.setPomodoroColor(remaining: true, $0) }
            colorPicker("Used color", value: model.config.pomodoroColorUsed) { model.setPomodoroColor(remaining: false, $0) }
        }
    }

    private func colorPicker(_ label: String, value: String, _ set: @escaping (String) -> Void) -> some View {
        Picker(label, selection: Binding(get: { value }, set: set)) {
            ForEach(colorNames, id: \.self) { Text($0).tag($0) }
        }
    }
}

// MARK: - Audio switcher

struct AudioSettings: View {
    @ObservedObject var model: SettingsModel
    @State private var devices: [String] = []
    @State private var loaded = false
    private var aliasNames: [String] { model.config.aliases.keys.sorted() }

    var body: some View {
        Section("Audio switcher") {
            ForEach(devices.indices, id: \.self) { i in
                HStack {
                    TextField("output device name", text: $devices[i]).textFieldStyle(.roundedBorder)
                    Button { devices.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            HStack {
                Button("Add device") { devices.append("") }
                Spacer()
                Button("Save devices") { model.setAudioDevices(devices.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }) }
            }
            LabeledContent("Switch hotkey") {
                HStack(spacing: 6) {
                    Picker("", selection: Binding(
                        get: { Keybinding.alias(forModifiers: model.config.audioHotkeyModifier, aliases: model.config.aliases) ?? (aliasNames.first ?? "HYPER") },
                        set: { model.setAudioHotkey(alias: $0, key: model.config.audioHotkeyKey ?? "'") })) {
                        ForEach(aliasNames, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 120)
                    Text("+").foregroundColor(.secondary)
                    TextField("key", text: Binding(
                        get: { model.config.audioHotkeyKey ?? "" },
                        set: { model.setAudioHotkey(alias: Keybinding.alias(forModifiers: model.config.audioHotkeyModifier, aliases: model.config.aliases) ?? (aliasNames.first ?? "HYPER"), key: $0) }))
                        .textFieldStyle(.roundedBorder).frame(width: 50)
                }
            }
            LabeledContent("Shortcut on change") {
                HStack {
                    TextField("macOS Shortcut name (blank = none)", text: $shortcutEdit).textFieldStyle(.roundedBorder)
                        .onSubmit { model.setAudioShortcut(shortcutEdit) }
                    Button("Save") { model.setAudioShortcut(shortcutEdit) }
                }
            }
        }
        .onAppear {
            if !loaded { devices = model.config.audioDevices; shortcutEdit = model.config.audioShortcutCallback ?? ""; loaded = true }
        }
    }
    @State private var shortcutEdit = ""
}

// MARK: - Window memory

struct MemorySettings: View {
    @ObservedObject var model: SettingsModel
    @State private var excluded: [String] = []
    @State private var zoneEdits: [String: String] = [:]
    @State private var newApp = ""
    @State private var newZone = ""
    @State private var loaded = false

    var body: some View {
        Section("Window memory") {
            Toggle("Learn & restore window positions", isOn: Binding(
                get: { model.config.windowMemory.enabled },
                set: { model.setWindowMemoryEnabled($0) }))
            Text("Excluded apps (never auto-tiled or learned):").font(.caption).foregroundColor(.secondary)
            ForEach(excluded.indices, id: \.self) { i in
                HStack {
                    TextField("app name", text: $excluded[i]).textFieldStyle(.roundedBorder)
                    Button { excluded.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            HStack {
                Button("Add app") { excluded.append("") }
                Spacer()
                Button("Save excluded") { model.setExcludedApps(excluded.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }) }
            }
        }
        Section("Default zone per app") {
            Text("A fresh window of these apps tiles into the given zone key when nothing is learned yet.")
                .font(.caption).foregroundColor(.secondary)
            ForEach(model.config.windowMemory.appZones.keys.sorted(), id: \.self) { app in
                HStack {
                    Text(app)
                    Spacer()
                    TextField("zone", text: Binding(
                        get: { zoneEdits[app] ?? model.config.windowMemory.appZones[app] ?? "" },
                        set: { zoneEdits[app] = $0 }))
                        .textFieldStyle(.roundedBorder).frame(width: 60).multilineTextAlignment(.center)
                        .onSubmit { model.setAppZone(app: app, zone: (zoneEdits[app] ?? "").trimmingCharacters(in: .whitespaces)) }
                    Button { model.removeAppZone(app: app) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("app name", text: $newApp).textFieldStyle(.roundedBorder)
                TextField("zone", text: $newZone).textFieldStyle(.roundedBorder).frame(width: 60).multilineTextAlignment(.center)
                Button("Add") {
                    let a = newApp.trimmingCharacters(in: .whitespaces), z = newZone.trimmingCharacters(in: .whitespaces)
                    guard !a.isEmpty, !z.isEmpty else { return }
                    model.setAppZone(app: a, zone: z); newApp = ""; newZone = ""
                }
            }
        }
        .onAppear { if !loaded { excluded = model.config.windowMemory.excludedApps; loaded = true } }
    }
}

// MARK: - Advanced (solver weights)

struct AdvancedSettings: View {
    @ObservedObject var model: SettingsModel
    @State private var edits: [String: String] = [:]
    @State private var loaded = false

    private struct W: Identifiable { let id: String; let label: String; let value: Int }
    private var weights: [W] {
        let w = model.config.solverWeights
        return [
            .init(id: "memory_exact", label: "Memory exact match", value: Int(w.memoryExact)),
            .init(id: "memory_zone", label: "Memory zone match", value: Int(w.memoryZone)),
            .init(id: "coverage", label: "Coverage reward", value: Int(w.coverage)),
            .init(id: "aspect_ratio", label: "Aspect-ratio penalty", value: Int(w.aspectRatio)),
            .init(id: "area_ratio", label: "Area penalty", value: Int(w.areaRatio)),
            .init(id: "moved_dist", label: "Move distance cost", value: Int(w.movedDist)),
            .init(id: "skip_window", label: "Skip-window cost", value: Int(w.skipWindow)),
        ]
    }

    var body: some View {
        Section("Advanced — auto-tiler weights") {
            Text("Negative = reward, positive = penalty. Higher magnitude = stronger.")
                .font(.caption).foregroundColor(.secondary)
            ForEach(weights) { w in
                LabeledContent(w.label) {
                    TextField("", text: Binding(
                        get: { edits[w.id] ?? "\(w.value)" },
                        set: { edits[w.id] = $0 }))
                        .textFieldStyle(.roundedBorder).frame(width: 90).multilineTextAlignment(.trailing)
                        .onSubmit { if let v = Int(edits[w.id] ?? "") { model.setSolverWeight(w.id, v) } }
                }
            }
        }
    }
}
