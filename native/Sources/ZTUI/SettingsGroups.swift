// SettingsGroups.swift — the v4 sidebar group containers. The Settings window moved from a row of
// top segmented tabs to a sidebar (NavigationSplitView, see SettingsView). Each group is a Form
// composing the same section-emitting views and setters as before, just re-bucketed into the v4
// taxonomy the user asked for:
//   General · Tiling · Layouts · Keys · Input & Output · App Launcher · Pomodoro · Appearance ·
//   Automation · Advanced
// The old "Features" catch-all tab is dissolved: its sections live with the feature they configure
// (Zone HUD / drag-snap → Tiling, focus-follows-mouse → I/O, break screen → Pomodoro, command
// palette + on-device AI → Automation, scratchpad → App Launcher).

import SwiftUI
import AppKit
import ZTCore
import ZTSystem

// MARK: - small shared helpers

/// A muted caption line (the same style the dissolved FeaturesTab used).
private func caption(_ s: String) -> some View { Text(s).font(.caption).foregroundColor(.secondary) }

private func splitList(_ s: String) -> [String] {
    s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

/// Resolved tiling-modifier glyphs (e.g. "⌃⌘") for "hold X" trigger hints.
func tilingGlyphs(_ model: SettingsModel) -> String { ModGlyph.string(model.config.tilerModifier) }

/// A Form section whose enable toggle lives IN the header (instead of a row that just restates the
/// title), with the explanation as a footer rather than a header-duplicating caption. Extra controls
/// go in `content` and are typically only built when `isOn`.
struct ToggleSection<Content: View>: View {
    let title: String
    @Binding var isOn: Bool
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    init(_ title: String, isOn: Binding<Bool>, footer: String? = nil,
         @ViewBuilder content: @escaping () -> Content = { EmptyView() }) {
        self.title = title; self._isOn = isOn; self.footer = footer; self.content = content
    }

    var body: some View {
        // The toggle is the section's first row (its de-facto header) — one label for the feature,
        // no duplicate title row or header-restating caption. (A Toggle in a Section `header:` does
        // not reliably reflect its bound state, so it lives in the body.)
        Section {
            Toggle(isOn: $isOn) { Text(title).font(.body.weight(.semibold)) }
                .toggleStyle(.switch)
            content()
        } footer: {
            if let footer { Text(footer).font(.caption).foregroundColor(.secondary) }
        }
    }
}

/// Bool binding from a config keypath + a model setter (the common toggle wiring).
func boolBind(_ model: SettingsModel, _ keyPath: KeyPath<ConfigLoader.LoadedConfig, Bool>,
              _ setter: @escaping (Bool) -> Void) -> Binding<Bool> {
    Binding(get: { model.config[keyPath: keyPath] }, set: { setter($0) })
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    .disabled(!model.launchAtLoginAvailable)
                if !model.launchAtLoginAvailable {
                    caption("Available when running the installed ZoneTilerWM.app (not the dev binary).")
                }
            }
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
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tiling

struct TilingTab: View {
    @ObservedObject var model: SettingsModel
    @State private var centerZonesEdit = ""

    private func commitCenterZones() {
        model.setCenterZones(splitList(centerZonesEdit))
    }

    var body: some View {
        Form {
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
                NumberRow(label: "Working-set capacity", value: Binding(
                    get: { model.config.workingSetMaxCapacity },
                    set: { model.setWorkingSetCapacity($0) }), range: 1...12)
                NumberRow(label: "Working-set staleness", value: Binding(
                    get: { model.config.workingSetTimeLimit / 60 },
                    set: { model.setWorkingSetMinutes($0) }), range: 1...240, suffix: "min")
                LabeledContent("Auto-tile center zones") {
                    HStack(spacing: 8) {
                        TextField("e.g. j, center, 0", text: $centerZonesEdit).textFieldStyle(.roundedBorder)
                            .frame(width: 200).onSubmit { commitCenterZones() }
                        Button("Save") { commitCenterZones() }
                    }
                }
            }

            let mods = tilingGlyphs(model)
            ToggleSection("Zone HUD", isOn: boolBind(model, \.zoneHUDEnabled, model.setZoneHUDEnabled),
                          footer: "Hold \(mods) to show each zone's key on screen. Self-silences for quick chords.") {
                if model.config.zoneHUDEnabled {
                    NumberRow(label: "Hold delay", value: Binding(
                        get: { model.config.zoneHUDHoldDelayMs },
                        set: { model.setZoneHUDHoldDelay($0) }), range: 120...2000, step: 20, suffix: "ms")
                }
            }

            ToggleSection("Drag-to-snap", isOn: boolBind(model, \.dragSnapEnabled, model.setDragSnapEnabled),
                          footer: "Hold \(mods) while dragging a window; dropping it snaps to the zone under the cursor.")

            if let err = model.lastWriteError { Text(err).foregroundColor(.red).font(.caption) }
        }
        .formStyle(.grouped)
        .onAppear { centerZonesEdit = model.config.autoTileCenterZones.joined(separator: ", ") }
    }
}

// MARK: - Input & Output (keyboard layout, audio, focus-follows-mouse)

struct IOTab: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            // Input
            Section {
                Picker("Keyboard layout", selection: Binding(
                    get: { model.keyboardChoice },
                    set: { model.setKeyboardLayout($0) })) {
                    Text("Auto (\(model.detectedKeyboard))").tag("auto")
                    ForEach(KeyboardLayout.presets, id: \.self) { Text($0).tag($0) }
                }
            } header: { Text("Input") } footer: {
                Text("Renders the Apps and Layouts key maps. Auto follows the active macOS input source.")
                    .font(.caption).foregroundColor(.secondary)
            }
            ToggleSection("Focus follows mouse", isOn: boolBind(model, \.focusFollowsMouseEnabled, model.setFocusFollowsMouseEnabled),
                          footer: "Focuses the window the cursor settles on. The one feature that adds per-interaction "
                                + "Accessibility calls — leave off unless you want it.") {
                if model.config.focusFollowsMouseEnabled {
                    NumberRow(label: "Dwell", value: Binding(
                        get: { model.config.focusFollowsMouseDelayMs },
                        set: { model.setFocusFollowsMouseDelay($0) }), range: 50...2000, step: 25, suffix: "ms")
                }
            }
            // Output
            AudioSettings(model: model)
        }
        .formStyle(.grouped)
    }
}

// MARK: - App Launcher (app cuts + hyper cuts + scratchpad)

struct AppLauncherTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppShortcutsView(model: model).padding(16)
            Divider()
            Form { AppGroupsSection(model: model) }.formStyle(.grouped)
        }
    }
}

/// Editor for the named [[app_groups]] — each a set of apps summoned/dismissed together by its own
/// hotkey (supersedes the single scratchpad). Add / rename-by-recreate / delete; edit apps, hotkey
/// (alias + key), and auto-dismiss inline.
struct AppGroupsSection: View {
    @ObservedObject var model: SettingsModel
    @State private var appEdits: [String: String] = [:]   // group → apps CSV in progress
    @State private var keyEdits: [String: String] = [:]   // group → hotkey key in progress
    @State private var newName = ""

    private var aliasNames: [String] { model.config.aliases.keys.sorted() }
    private func aliasOf(_ g: AppGroupProfile) -> String { g.hotkey.first ?? (aliasNames.first ?? "mash") }
    private func keyOf(_ g: AppGroupProfile) -> String { g.hotkey.count >= 2 ? g.hotkey[1] : "" }

    /// One surgical write covering whichever fields changed (others keep their current value).
    private func save(_ g: AppGroupProfile, apps: [String]? = nil, alias: String? = nil,
                      key: String? = nil, autoDismiss: Bool? = nil) {
        let k = key ?? keyOf(g)
        let hotkey = k.isEmpty ? [] : [alias ?? aliasOf(g), k]
        model.setAppGroup(name: g.name, apps: apps ?? g.apps, hotkey: hotkey, autoDismiss: autoDismiss ?? g.autoDismiss)
    }

    var body: some View {
        Section("App groups") {
            caption("Named sets of apps summoned and dismissed together, each with its own hotkey "
                    + "(supersedes the single scratchpad). Press ⏎ in a field to save.")
            ForEach(model.config.appGroups, id: \.name) { g in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(g.name).font(.system(.body, design: .monospaced)).fontWeight(.medium)
                        Spacer()
                        Button { model.removeAppGroup(name: g.name) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("Delete group")
                    }
                    HStack {
                        Text("Apps").foregroundColor(.secondary).frame(width: 56, alignment: .leading)
                        TextField("Slack, Mail", text: Binding(
                            get: { appEdits[g.name] ?? g.apps.joined(separator: ", ") },
                            set: { appEdits[g.name] = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { save(g, apps: splitList(appEdits[g.name] ?? "")) }
                    }
                    HStack(spacing: 6) {
                        Text("Hotkey").foregroundColor(.secondary).frame(width: 56, alignment: .leading)
                        Picker("", selection: Binding(
                            get: { aliasOf(g) }, set: { save(g, alias: $0) })) {
                            ForEach(aliasNames, id: \.self) { ModGlyph.aliasLabel($0, aliases: model.config.aliases).tag($0) }
                        }.labelsHidden().frame(width: 132)
                        Text("+").foregroundColor(.secondary)
                        TextField("key", text: Binding(
                            get: { keyEdits[g.name] ?? keyOf(g) },
                            set: { keyEdits[g.name] = $0 }))
                            .textFieldStyle(.roundedBorder).frame(width: 50).multilineTextAlignment(.center)
                            .onSubmit { save(g, key: keyEdits[g.name] ?? "") }
                        Spacer()
                        Toggle("Auto-dismiss", isOn: Binding(
                            get: { g.autoDismiss }, set: { save(g, autoDismiss: $0) }))
                            .toggleStyle(.switch).controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
            HStack {
                TextField("new group name", text: $newName).labelsHidden()   // in-field prompt, not a wrapping Form label
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                Button("Add group") {
                    let n = newName.trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty, !n.contains("\""), model.config.appGroups.allSatisfy({ $0.name != n }) else { return }
                    model.setAppGroup(name: n, apps: [], hotkey: [], autoDismiss: true)
                    newName = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }
        }
    }
}

// MARK: - Appearance (window border + margins, with a shared live preview)

/// Config colour-name → SwiftUI Color (mirrors the swatch set used in the editors).
private let configSwatch: [String: Color] = [
    "green": .green, "red": .red, "blue": .blue, "yellow": .yellow, "orange": .orange,
    "purple": .purple, "white": .white, "black": .black, "gray": .gray,
]

/// A live mock of a focused window so border colour/width/corner-radius + margins are visible as you
/// change them (the live review asked for "a live preview … margins can use the same preview").
struct AppearancePreview: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let b = model.config.borders
        let m = model.config.zoneConfig.margins
        let marginsOn = m?.enabled ?? false
        let marginInset = CGFloat(min(max(m?.size ?? 0, 0), 40)) * 0.5
        let color = b.enabled ? (configSwatch[b.color] ?? .accentColor) : .clear
        return VStack(spacing: 6) {
            ZStack {
                // "desktop"
                RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.30))
                // "focused window" with the configured border, inset by the margin when enabled
                RoundedRectangle(cornerRadius: CGFloat(b.cornerRadius))
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: CGFloat(b.cornerRadius))
                        .strokeBorder(color, lineWidth: CGFloat(b.width)))
                    .overlay(Text("focused window").font(.caption2).foregroundColor(.secondary))
                    .padding(12 + (marginsOn ? marginInset : 0))
            }
            .frame(height: 132)
            Text(marginsOn ? "Preview · margins \(Int(m?.size ?? 0))px"
                           : "Preview · margins off")
                .font(.caption2).foregroundColor(.secondary)
        }
        .listRowInsets(EdgeInsets())
        .padding(.vertical, 4)
    }
}

/// Live mock of the Pomodoro color bar — a top-edge strip (used on the left, remaining on the
/// right) across a mock screen, reflecting the colours / opacity / height as you change them (the
/// review asked to "see a preview of how the bar will look and where, updated live").
struct PomodoroBarPreview: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let on = model.config.pomodoroEnableColorBar
        let heightRatio = model.config.pomodoroIndicatorHeight        // 0…1 of the menubar
        let alpha = model.config.pomodoroIndicatorAlpha
        let used = configSwatch[model.config.pomodoroColorUsed] ?? .red
        let remaining = configSwatch[model.config.pomodoroColorRemaining] ?? .green
        let barH = max(3.0, 26.0 * heightRatio)                       // scale onto a ~26pt mock menubar
        return VStack(spacing: 6) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.30))   // mock screen
                if on {
                    HStack(spacing: 0) {
                        Rectangle().fill(used.opacity(alpha)).frame(width: 90)       // ~35% elapsed
                        Rectangle().fill(remaining.opacity(alpha))
                    }
                    .frame(height: barH)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .padding(.horizontal, 1).padding(.top, 1)
                }
            }
            .frame(height: 120)
            Text(on ? "Preview · strip across the top of the screen (used │ remaining)"
                    : "Color bar off")
                .font(.caption2).foregroundColor(.secondary)
        }
        .listRowInsets(EdgeInsets())
        .padding(.vertical, 4)
    }
}

struct AppearanceTab: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            Section("Preview") { AppearancePreview(model: model) }
            BordersSettings(model: model)
            Section("Margins") {
                Toggle("Enable margins", isOn: Binding(
                    get: { model.config.zoneConfig.margins?.enabled ?? false },
                    set: { model.setMarginsEnabled($0) }))
                NumberRow(label: "Size", value: Binding(
                    get: { Int(model.config.zoneConfig.margins?.size ?? 0) },
                    set: { model.setMarginsSize($0) }), range: 0...40, suffix: "px")
                    .disabled(!(model.config.zoneConfig.margins?.enabled ?? false))
                Toggle("Apply margin at screen edges", isOn: Binding(
                    get: { model.config.zoneConfig.margins?.screen_edge ?? false },
                    set: { model.setMarginsScreenEdge($0) }))
                    .disabled(!(model.config.zoneConfig.margins?.enabled ?? false))
            }
        }
        .formStyle(.grouped)
    }
}
