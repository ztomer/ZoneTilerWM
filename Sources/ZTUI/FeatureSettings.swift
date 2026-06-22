// FeatureSettings.swift — additional General-tab sections for features that were implemented
// in the agent but had no UI: Pomodoro, Audio switcher, Window Memory, and the advanced
// auto-tiler solver weights. Each is a Form Section composed into the General form. All writes
// go through the model's surgical TOML setters (and trip the live reload).

import SwiftUI
import AppKit
import ZTCore
import ZTSystem

// MARK: - Pomodoro

struct PomodoroSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        // Split into two semantic sections (Timer vs Color bar) instead of one dense 7-row block,
        // so the durations and the bar appearance read as distinct groups — and the tab gains the
        // same sectioned rhythm as the Keys tab (Modifiers / Actions).
        Section("Timer") {
            HStack(spacing: 18) {
                compactMinutes("Work", value: Binding(
                    get: { model.config.pomodoroWorkSec / 60 }, set: { model.setPomodoroWorkMinutes($0) }), range: 1...120)
                Divider().frame(height: 18)
                compactMinutes("Rest", value: Binding(
                    get: { model.config.pomodoroRestSec / 60 }, set: { model.setPomodoroRestMinutes($0) }), range: 1...60)
                Spacer()
            }
        }
        ToggleSection("Color bar", isOn: Binding(
            get: { model.config.pomodoroEnableColorBar }, set: { model.setPomodoroColorBar($0) })) {
            if model.config.pomodoroEnableColorBar {
                SliderRow(label: "Bar height", value: Binding(
                    get: { Int((model.config.pomodoroIndicatorHeight * 100).rounded()) },
                    set: { model.setPomodoroIndicatorHeight(Double($0) / 100) }), range: 5...100, step: 5, suffix: "%")
                SliderRow(label: "Bar opacity", value: Binding(
                    get: { Int((model.config.pomodoroIndicatorAlpha * 100).rounded()) },
                    set: { model.setPomodoroIndicatorAlpha(Double($0) / 100) }), range: 5...100, step: 5, suffix: "%")
                ColorSwatchRow(label: "Remaining color", selected: model.config.pomodoroColorRemaining) {
                    model.setPomodoroColor(remaining: true, $0)
                }
                ColorSwatchRow(label: "Used color", selected: model.config.pomodoroColorUsed) {
                    model.setPomodoroColor(remaining: false, $0)
                }
            }
        }
    }

    /// Compact "<label> [n] min [stepper]" cell so Work and Rest fit on one row.
    private func compactMinutes(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 4) {
            Text(label)
            TextField("", value: Binding(
                get: { value.wrappedValue },
                set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }), format: .number)
                .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 44).multilineTextAlignment(.trailing)
            Text("min").foregroundColor(.secondary)
            Stepper("", value: value, in: range).labelsHidden()
        }
    }
}

// MARK: - Window border (focus outline)

struct BordersSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        ToggleSection("Window border", isOn: Binding(
            get: { model.config.borders.enabled }, set: { model.setBordersEnabled($0) }),
            footer: "Draws a colored outline around the focused window and follows it as it moves. "
                  + "Motion prediction leads the outline to compensate for follow-lag.") {
            if model.config.borders.enabled {
                ColorSwatchRow(label: "Color", selected: model.config.borders.color) { model.setBordersColor($0) }
                BorderStyleRow(selected: model.config.borders.style) { model.setBorderStyle($0) }
                SliderRow(label: "Width", value: Binding(
                    get: { Int(model.config.borders.width.rounded()) },
                    set: { model.setBordersWidth($0) }), range: 1...12, suffix: "px")
                SliderRow(label: "Corner radius", value: Binding(
                    get: { Int(model.config.borders.cornerRadius.rounded()) },
                    set: { model.setBordersCornerRadius($0) }), range: 0...24, suffix: "px")
                Picker("Renderer", selection: Binding(
                    get: { model.config.borders.backend },
                    set: { model.setBordersBackend($0) })) {
                    Text("Overlay (default)").tag("overlay")
                    Text("Window server (experimental)").tag("skylight")
                }
                Toggle("Motion prediction", isOn: Binding(
                    get: { model.config.borders.prediction },
                    set: { model.setBordersPrediction($0) }))
            }
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
                ModifierSelector(model: model, alias: Keybinding.alias(forModifiers: model.config.audioHotkeyModifier, aliases: model.config.aliases) ?? (aliasNames.first ?? "HYPER")) {
                    model.setAudioHotkey(alias: $0, key: model.config.audioHotkeyKey ?? "'")
                }
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
                        .textFieldStyle(.roundedBorder).frame(width: 80).multilineTextAlignment(.center).lineLimit(1)
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
                TextField("zone", text: $newZone).textFieldStyle(.roundedBorder).frame(width: 80).multilineTextAlignment(.center).lineLimit(1)
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
    /// Search terms for the titlebar settings search (keep in sync with this pane's controls).
    static let searchKeywords: [String] = ["timer", "work", "rest", "work period", "rest period", "color bar", "bar height", "bar opacity", "remaining color", "used color", "break screen", "duration", "start", "pause", "reset count", "pomodoro"]
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            Section { PomodoroBarPreview(model: model) }
            PomodoroSettings(model: model)
            ToggleSection("Break screen", isOn: Binding(
                get: { model.config.breakScreenEnabled }, set: { model.setBreakScreenEnabled($0) }),
                footer: "A full-screen \"BREAK TIME\" overlay when a work period ends.") {
                HStack { Spacer(); BreakScreenPreview(); Spacer() }.padding(.vertical, 8)
                if model.config.breakScreenEnabled {
                    NumberRow(label: "Duration", value: Binding(
                        get: { model.config.breakScreenDurationSec },
                        set: { model.setBreakScreenDuration($0) }), range: 2...60, step: 1, suffix: "s")
                }
            }
            Section("Keys") {
                HotkeyRowView(model: model, label: "Start", section: "pomodoro.hotkeys", key: "enable", labelWidth: 120)
                HotkeyRowView(model: model, label: "Pause / reset", section: "pomodoro.hotkeys", key: "disable", labelWidth: 120)
                HotkeyRowView(model: model, label: "Reset count", section: "pomodoro.hotkeys", key: "reset", labelWidth: 120)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced tab (window memory + solver weights + learned data)

struct AdvancedTab: View {
    /// Search terms for the titlebar settings search (keep in sync with this pane's controls).
    static let searchKeywords: [String] = ["window memory", "learn", "restore window positions", "excluded apps", "auto-tiler weights", "solver weights", "weights", "reset to defaults", "experimental", "private apis", "real spaces", "debug", "telemetry", "usage", "privacy", "analytics"]
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            WindowMemorySection(model: model)
            AdvancedSettings(model: model)
            ToggleSection("Usage telemetry", isOn: Binding(
                get: { model.config.telemetryEnabled }, set: { model.setTelemetryEnabled($0) }),
                footer: "Off by default. When on, ZoneTilerWM appends one anonymous line per command — the action name + a timestamp, NO window titles or app names — to /tmp/zonetilerwm-telemetry.jsonl. Local only; nothing is sent anywhere (there's no collection backend).") {
                EmptyView()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Automation (MCP server + zonetiler-cli)

/// Exposes the programmable surface: a master enable toggle, the live socket status, copy-paste
/// snippets to connect Claude (MCP) and the CLI, and the full action/resource catalog so every
/// exposed verb is discoverable. All capability data is read from the shared ActionParser
/// catalog + QueryRequest, so this pane can never drift from what the agent actually supports.
struct AutomationTab: View {
    /// Search terms for the titlebar settings search (keep in sync with this pane's controls).
    static let searchKeywords: [String] = ["command palette", "natural language", "hotkey", "arrangement events", "poll interval", "sync folder", "enable mcp", "mcp", "state", "socket", "command line", "binary", "cli", "url scheme", "app intents", "rules", "events"]
    @ObservedObject var model: SettingsModel

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private func caption(_ s: String) -> some View { Text(s).font(.caption).foregroundColor(.secondary) }

    private var nlAvailable: Bool {
        if case .available = NLInterpreter.status { return true }
        return false
    }

    var body: some View {
        Form {
            ToggleSection("Command palette", isOn: Binding(
                get: { model.config.commandPaletteEnabled }, set: { model.setCommandPaletteEnabled($0) }),
                footer: paletteHint) {
                HStack { Spacer(); CommandPalettePreview(); Spacer() }.padding(.vertical, 8)
                if model.config.commandPaletteEnabled {
                    // Natural language is greyed out when the on-device model isn't available (no separate
                    // status row); the palette hotkey follows.
                    Toggle("Natural language", isOn: Binding(
                        get: { model.config.nlEnabled && nlAvailable }, set: { model.setNLEnabled($0) }))
                        .disabled(!nlAvailable)
                    HotkeyRowView(model: model, label: "Hotkey", section: "system_hotkeys", key: "command_palette")
                    caption(nlAvailable
                            ? "With Natural language on, ⏎ on an unmatched query asks the on-device model (\"put terminal left\"). 100% local."
                            : "Natural language needs Apple Intelligence, which isn't available on this Mac.")
                }
            }

            ToggleSection("Arrangement events", isOn: Binding(
                get: { model.config.eventsEnabled }, set: { model.setEventsEnabled($0) }),
                footer: "Append layout-change events to a file you can tail -f from scripts / status bars.") {
                if model.config.eventsEnabled {
                    NumberRow(label: "Poll interval", value: Binding(
                        get: { model.config.eventsIntervalMs },
                        set: { model.setEventsInterval($0) }), range: 250...10000, step: 250, suffix: "ms")
                }
            }

            Section {
                LabeledContent("Sync folder") {
                    HStack(spacing: 8) {
                        Text(model.config.syncFolder.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "none")
                            .foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Choose…") { chooseSyncFolder() }
                        if model.config.syncFolder != nil { Button("Clear") { model.setSyncFolder("") } }
                    }
                }
            } footer: {
                caption("A folder you already sync (iCloud / Dropbox) for sync-export / sync-import.")
            }

            ToggleSection("Enable MCP", isOn: Binding(
                get: { model.automationEnabled }, set: { model.setAutomationEnabled($0) }),
                footer: "Lets Claude (Desktop/Code) and zonetiler-cli drive the window manager over a local "
                      + "Unix socket. No model, key, or network is bundled.") {
                if model.automationEnabled {
                    LabeledContent("State") {
                        Label(model.automationListening ? "Listening" : "Starting…",
                              systemImage: model.automationListening ? "dot.radiowaves.left.and.right" : "clock")
                            .foregroundColor(model.automationListening ? .green : .orange)
                    }
                    LabeledContent("Socket") {
                        Text(model.agentSocketPath).foregroundColor(.secondary)
                            .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.mcpRegisterCommand).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                        Spacer()
                        Button("Copy") { copy(model.mcpRegisterCommand) }
                    }
                }
            }

            Section("Command line") {
                LabeledContent("Binary") {
                    HStack {
                        Text(model.cliBinaryPath).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                        Button("Copy") { copy(model.cliBinaryPath) }
                    }
                }
                caption("e.g.  zonetiler-cli tile --zone h   ·   zonetiler-cli get arrangement   ·   zonetiler-cli --help")
            }

            Section {
                DisclosureGroup("Capabilities (\(ActionParser.catalog.count) actions, \(QueryRequest.allCases.count) resources)") {
                    ForEach(ActionParser.catalog, id: \.name) { spec in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(spec.name).font(.system(.callout, design: .monospaced)).fontWeight(.medium)
                            Text(spec.description).font(.caption).foregroundColor(.secondary)
                        }.padding(.vertical, 1)
                    }
                    ForEach(QueryRequest.allCases, id: \.self) { q in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("get \(CLIFormat.cliName(q))").font(.system(.callout, design: .monospaced)).fontWeight(.medium)
                            Text(q.description).font(.caption).foregroundColor(.secondary)
                        }.padding(.vertical, 1)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// "Open with ⌃⌘K" from the configured command-palette hotkey, or a hint to set one.
    private var paletteHint: String {
        if let r = model.config.resolvedHotkey("command_palette", in: model.config.systemHotkeys) {
            return "Open with " + ModGlyph.string(r.modifier) + r.key.uppercased()
        }
        return "No hotkey set yet — add one under Keys → Feature actions."
    }

    /// Pick a sync folder with the standard open panel (directories only).
    private func chooseSyncFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { model.setSyncFolder(url.path) }
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
