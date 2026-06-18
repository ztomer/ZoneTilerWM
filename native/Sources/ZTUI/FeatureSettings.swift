// FeatureSettings.swift — additional General-tab sections for features that were implemented
// in the agent but had no UI: Pomodoro, Audio switcher, Window Memory, and the advanced
// auto-tiler solver weights. Each is a Form Section composed into the General form. All writes
// go through the model's surgical TOML setters (and trip the live reload).

import SwiftUI
import ZTCore

private let colorNames = ["green", "red", "blue", "yellow", "orange", "purple", "white", "black", "gray"]

private let swatchColor: [String: Color] = [
    "green": .green, "red": .red, "blue": .blue, "yellow": .yellow, "orange": .orange,
    "purple": .purple, "white": .white, "black": .black, "gray": .gray,
]

/// Label + editable number field + stepper: type a precise value OR nudge it. Replaces the
/// stepper-only rows so a value can be entered directly. Trailing-aligned to match the grouped
/// Form's native two-column rhythm (label left, control right). Shared across the settings tabs.
struct NumberRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var suffix: String = ""

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField("", value: Binding(
                    get: { value },
                    set: { value = min(max($0, range.lowerBound), range.upperBound) }), format: .number)
                    .labelsHidden().textFieldStyle(.roundedBorder)
                    .frame(width: 48).multilineTextAlignment(.trailing)
                if !suffix.isEmpty { Text(suffix).foregroundColor(.secondary) }
                Stepper("", value: $value, in: range, step: step).labelsHidden()
            }
        }
    }
}

/// Label + a row of tappable colour swatches (the nine config colour names). Replaces a
/// name-dropdown so the choice is visual and direct (the selected swatch is ringed).
private struct ColorSwatchRow: View {
    let label: String
    let selected: String
    let set: (String) -> Void

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                ForEach(colorNames, id: \.self) { name in
                    Circle().fill(swatchColor[name] ?? .gray)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))   // edge for white/black
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: name == selected ? 2.5 : 0))
                        .overlay(name == selected   // checkmark so selection reads without relying on the ring color
                                 ? Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                     .foregroundColor(["white", "yellow", "gray"].contains(name) ? .black : .white)
                                 : nil)
                        .contentShape(Circle())
                        .onTapGesture { set(name) }
                        .help(name)
                }
            }
        }
    }
}

// MARK: - Pomodoro

struct PomodoroSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Section("Pomodoro") {
            NumberRow(label: "Work", value: Binding(
                get: { model.config.pomodoroWorkSec / 60 },
                set: { model.setPomodoroWorkMinutes($0) }), range: 1...120, suffix: "min")
            NumberRow(label: "Rest", value: Binding(
                get: { model.config.pomodoroRestSec / 60 },
                set: { model.setPomodoroRestMinutes($0) }), range: 1...60, suffix: "min")
            Toggle("Show color bar", isOn: Binding(
                get: { model.config.pomodoroEnableColorBar },
                set: { model.setPomodoroColorBar($0) }))
            NumberRow(label: "Bar height", value: Binding(
                get: { Int((model.config.pomodoroIndicatorHeight * 100).rounded()) },
                set: { model.setPomodoroIndicatorHeight(Double($0) / 100) }), range: 5...100, step: 5, suffix: "%")
                .disabled(!model.config.pomodoroEnableColorBar)
            NumberRow(label: "Bar opacity", value: Binding(
                get: { Int((model.config.pomodoroIndicatorAlpha * 100).rounded()) },
                set: { model.setPomodoroIndicatorAlpha(Double($0) / 100) }), range: 5...100, step: 5, suffix: "%")
                .disabled(!model.config.pomodoroEnableColorBar)
            ColorSwatchRow(label: "Remaining color", selected: model.config.pomodoroColorRemaining) {
                model.setPomodoroColor(remaining: true, $0)
            }
            ColorSwatchRow(label: "Used color", selected: model.config.pomodoroColorUsed) {
                model.setPomodoroColor(remaining: false, $0)
            }
        }
    }
}

// MARK: - Window border (focus outline)

struct BordersSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Section("Window border") {
            Toggle("Outline the focused window", isOn: Binding(
                get: { model.config.borders.enabled },
                set: { model.setBordersEnabled($0) }))
            ColorSwatchRow(label: "Color", selected: model.config.borders.color) { model.setBordersColor($0) }
            NumberRow(label: "Width", value: Binding(
                get: { Int(model.config.borders.width.rounded()) },
                set: { model.setBordersWidth($0) }), range: 1...12, suffix: "px")
                .disabled(!model.config.borders.enabled)
            NumberRow(label: "Corner radius", value: Binding(
                get: { Int(model.config.borders.cornerRadius.rounded()) },
                set: { model.setBordersCornerRadius($0) }), range: 0...24, suffix: "px")
                .disabled(!model.config.borders.enabled)
            Picker("Renderer", selection: Binding(
                get: { model.config.borders.backend },
                set: { model.setBordersBackend($0) })) {
                Text("Overlay (default)").tag("overlay")
                Text("Window server (experimental)").tag("skylight")
            }.disabled(!model.config.borders.enabled)
            Toggle("Motion prediction", isOn: Binding(
                get: { model.config.borders.prediction },
                set: { model.setBordersPrediction($0) }))
                .disabled(!model.config.borders.enabled)
            Text("Draws a colored outline around the focused window that follows it as it moves. "
                 + "Motion prediction leads the outline to compensate for follow-lag.")
                .font(.caption).foregroundColor(.secondary)
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
                    TextField("output device name", text: $devices[i]).textFieldStyle(.roundedBorder).labelsHidden()
                    Button { devices.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            HStack {
                Button("Add device") { devices.append("") }
                Spacer()
                Button("Save devices") { model.setAudioDevices(devices.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }) }
            }
            // Explicit label + Spacer + fixed-width controls (LabeledContent compressed these
            // until "key" wrapped vertically and the helper text spilled).
            HStack(spacing: 6) {
                Text("Switch hotkey")
                Spacer(minLength: 12)
                Picker("", selection: Binding(
                    get: { Keybinding.alias(forModifiers: model.config.audioHotkeyModifier, aliases: model.config.aliases) ?? (aliasNames.first ?? "HYPER") },
                    set: { model.setAudioHotkey(alias: $0, key: model.config.audioHotkeyKey ?? "'") })) {
                    ForEach(aliasNames, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().fixedSize()
                Text("+").foregroundColor(.secondary)
                TextField("", text: Binding(
                    get: { model.config.audioHotkeyKey ?? "" },
                    set: { model.setAudioHotkey(alias: Keybinding.alias(forModifiers: model.config.audioHotkeyModifier, aliases: model.config.aliases) ?? (aliasNames.first ?? "HYPER"), key: $0) }))
                    .textFieldStyle(.roundedBorder).frame(width: 56).multilineTextAlignment(.center)
            }
            HStack(spacing: 8) {
                Text("Run Shortcut on change")
                Spacer(minLength: 12)
                TextField("Shortcut name", text: $shortcutEdit).textFieldStyle(.roundedBorder).frame(width: 200)
                    .onSubmit { model.setAudioShortcut(shortcutEdit) }
                Button("Save") { model.setAudioShortcut(shortcutEdit) }
            }
            Text("Runs a macOS Shortcut by name when the output device changes (blank = none).")
                .font(.caption).foregroundColor(.secondary)
        }
        .onAppear {
            if !loaded { devices = model.config.audioDevices; shortcutEdit = model.config.audioShortcutCallback ?? ""; loaded = true }
        }
    }
    @State private var shortcutEdit = ""
}

// MARK: - Window memory

/// Window memory: enable + the exclusion list (lives in the Advanced tab).
struct WindowMemorySection: View {
    @ObservedObject var model: SettingsModel
    @State private var excluded: [String] = []
    @State private var loaded = false

    var body: some View {
        Section("Window memory") {
            Toggle("Learn & restore window positions", isOn: Binding(
                get: { model.config.windowMemory.enabled },
                set: { model.setWindowMemoryEnabled($0) }))
            Text("Excluded apps (never auto-tiled or learned):").font(.caption).foregroundColor(.secondary)
            ForEach(excluded.indices, id: \.self) { i in
                HStack {
                    TextField("app name", text: $excluded[i]).textFieldStyle(.roundedBorder).labelsHidden()
                    Button { excluded.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            HStack {
                Button("Add app") { excluded.append("") }
                Spacer()
                Button("Save excluded") { model.setExcludedApps(excluded.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }) }
            }
        }
        .onAppear { if !loaded { excluded = model.config.windowMemory.excludedApps; loaded = true } }
    }
}

/// Per-app default zone (window_memory.app_zones) — lives under Layouts, since it assigns zones.
struct DefaultZonesSection: View {
    @ObservedObject var model: SettingsModel
    @State private var zoneEdits: [String: String] = [:]
    @State private var newApp = ""
    @State private var newZone = ""
    @FocusState private var focusedApp: String?
    @State private var lastFocusedApp: String?

    /// Persist a row's edit (on Return or when it loses focus), so clicking away never drops it.
    private func commit(_ app: String) {
        guard let edit = zoneEdits[app] else { return }
        model.setAppZone(app: app, zone: edit.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                        .focused($focusedApp, equals: app)
                        .onSubmit { commit(app) }
                    Button { model.removeAppZone(app: app) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            .onChange(of: focusedApp) { newValue in
                if let previous = lastFocusedApp { commit(previous) }   // commit the row that lost focus
                lastFocusedApp = newValue
            }
            HStack {
                TextField("app name", text: $newApp).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                TextField("zone", text: $newZone).textFieldStyle(.roundedBorder).frame(width: 60).multilineTextAlignment(.center)
                Button("Add") {
                    let a = newApp.trimmingCharacters(in: .whitespaces), z = newZone.trimmingCharacters(in: .whitespaces)
                    guard !a.isEmpty, !z.isEmpty else { return }
                    model.setAppZone(app: a, zone: z); newApp = ""; newZone = ""
                }
                Spacer()
            }
        }
    }
}

// MARK: - Pomodoro tab (settings + its own keys)

struct PomodoroTab: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            PomodoroSettings(model: model)
            Section("Keys") {
                HotkeyRowView(model: model, label: "Start", section: "pomodoro.hotkeys", key: "enable", labelWidth: 120)
                HotkeyRowView(model: model, label: "Pause / reset", section: "pomodoro.hotkeys", key: "disable", labelWidth: 120)
                HotkeyRowView(model: model, label: "Reset count", section: "pomodoro.hotkeys", key: "reset", labelWidth: 120)
                ModifierLegend(aliases: model.config.aliases)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced tab (window memory + solver weights + learned data)

struct AdvancedTab: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            WindowMemorySection(model: model)
            AdvancedSettings(model: model)
        }
        .formStyle(.grouped)
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

    @FocusState private var focusedWeight: String?
    @State private var lastFocusedWeight: String?

    /// Persist a weight on Return or when it loses focus, so clicking away never drops it.
    private func commit(_ id: String) {
        if let v = Int((edits[id] ?? "").trimmingCharacters(in: .whitespaces)) { model.setSolverWeight(id, v) }
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
                        .focused($focusedWeight, equals: w.id)
                        .onSubmit { commit(w.id) }
                }
            }
            .onChange(of: focusedWeight) { newValue in
                if let previous = lastFocusedWeight { commit(previous) }
                lastFocusedWeight = newValue
            }
            HStack {
                Spacer()
                Button("Reset to defaults") { edits.removeAll(); model.resetSolverWeights() }
            }
        }
    }
}
