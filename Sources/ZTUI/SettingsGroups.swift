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

struct PreviewsTab: View {
    /// Search terms for the titlebar settings search (keep in sync with this pane's controls).
    static let searchKeywords: [String] = ["window hints", "window hints hotkey", "exposé", "expose", "mission control", "window grid", "spaces bar position", "navigation keys", "arrows", "vim", "wasd", "show windows from", "active monitor", "all monitors", "switching spaces", "switching method", "auto", "keyboard shortcuts", "trackpad gesture", "gesture", "show spaces in the menu bar", "menu bar", "menubar", "bracket style", "use real macos spaces", "real spaces", "liquid glass"]
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            // Each preview sits with the options that affect it (no shared "Settings" dump; keyboard
            // layout lives in Input & Output, not duplicated here).
            Section("Window Hints") {
                HStack { Spacer(); WindowHintsPreview(model: model); Spacer() }.padding(.vertical, 8)
                HotkeyRowView(model: model, label: "Window hints hotkey", section: "system_hotkeys", key: "window_hints")
            }

            Section("Exposé / Window Grid") {
                HStack { Spacer(); ExposePreview(model: model); Spacer() }.padding(.vertical, 8)
                HotkeyRowView(model: model, label: "Exposé / Window grid hotkey", section: "system_hotkeys", key: "expose")
                Picker("Spaces bar position", selection: Binding(
                    get: { model.exposeSpacesBarPositionChoice },
                    set: { model.setExposeSpacesBarPosition($0) })) {
                    Text("Top").tag("top"); Text("Left").tag("left")
                    Text("Right").tag("right"); Text("Bottom").tag("bottom")
                }
                Picker("Navigation keys", selection: Binding(
                    get: { model.exposeNavChoice },
                    set: { model.setExposeNav($0) })) {
                    Text("Arrows").tag("arrows"); Text("Vim (hjkl)").tag("vim"); Text("WASD").tag("wasd")
                }
                Picker("Show windows from", selection: Binding(
                    get: { model.exposeScopeChoice },
                    set: { model.setExposeScope($0) })) {
                    Text("Active monitor").tag("active"); Text("All monitors").tag("all")
                }
            }

            Section("Switching Spaces") {
                Picker("Switching method", selection: Binding(
                    get: { model.spaceSwitchMethodChoice },
                    set: { model.setSpaceSwitchMethod($0) })) {
                    Text("Auto").tag("auto")
                    Text("Keyboard shortcuts").tag("keyboard")
                    Text("Trackpad gesture").tag("gesture")
                }
                Text("All public — no private APIs, works in any build. “Keyboard shortcuts” rides your “Switch to Desktop N” shortcuts (set them up first); “Trackpad gesture” simulates a swipe (same display only); “Auto” gestures on the active display and falls back to shortcuts.")
                    .font(.caption).foregroundColor(.secondary)
                Button("Open Mission Control Shortcuts…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                }
            }

            Section("Show Spaces (menu bar + Exposé)") {
                Toggle("Show Spaces in the menu bar", isOn: Binding(
                    get: { model.spacesMenubarEnabled }, set: { model.setSpacesMenubar($0) }))
                    .disabled(!model.realSpacesEnabled)
                if model.spacesMenubarEnabled && model.realSpacesEnabled {
                    MenubarBracketPicker(model: model)
                }
                Toggle("Use real macOS Spaces (experimental)", isOn: Binding(
                    get: { model.realSpacesEnabled }, set: { model.setRealSpaces($0) }))
                Text("Switching (above) needs none of this. Showing WHICH Spaces exist, which is current, and their wallpapers reads live desktop info via private APIs — experimental, excluded from App Store builds. Off → Exposé shows the current Space only.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - General

struct GeneralTab: View {
    /// Search terms for the titlebar settings search (keep in sync with this pane's controls).
    static let searchKeywords: [String] = ["startup", "launch at login", "login", "config", "config file", "reveal", "open", "version", "reload"]
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
    /// Search terms for the titlebar settings search (keep in sync with this pane's controls).
    static let searchKeywords: [String] = ["zones", "auto-tile", "autotile", "auto-tiling mode", "usage", "session", "placement strategy", "rotate", "largest free space", "hybrid", "working-set capacity", "working-set staleness", "working set", "auto-tile center zones", "center zones", "zone hud", "hud", "hold delay", "drag-to-snap", "drag", "snap", "move to next monitor", "move to previous monitor", "focus next screen", "focus previous screen", "resize mode", "auto-tile screen", "zen mode", "session sandbox", "toggle float", "float", "stack focus next", "stack focus previous", "stacks"]
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
                HStack { Spacer(); ZoneHUDPreview(); Spacer() }.padding(.vertical, 8)
                if model.config.zoneHUDEnabled {
                    NumberRow(label: "Hold delay", value: Binding(
                        get: { model.config.zoneHUDHoldDelayMs },
                        set: { model.setZoneHUDHoldDelay($0) }), range: 120...2000, step: 20, suffix: "ms")
                }
            }

            ToggleSection("Drag-to-snap", isOn: boolBind(model, \.dragSnapEnabled, model.setDragSnapEnabled),
                          footer: "Hold \(mods) while dragging a window; dropping it snaps to the zone under the cursor.") {
                HStack { Spacer(); DragSnapPreview(); Spacer() }.padding(.vertical, 8)
            }

            Section("Tiling Hotkeys") {
                HotkeyRowView(model: model, label: "Move to next monitor", section: "tiler.hotkeys", key: "placement_mode")
                HotkeyRowView(model: model, label: "Move to previous monitor", section: "tiler.hotkeys", key: "zone_info")
                HotkeyRowView(model: model, label: "Focus next screen", section: "tiler.hotkeys", key: "focus_next_screen")
                HotkeyRowView(model: model, label: "Focus previous screen", section: "tiler.hotkeys", key: "focus_prev_screen")
                HotkeyRowView(model: model, label: "Resize mode", section: "tiler.hotkeys", key: "resize_mode")
                HotkeyRowView(model: model, label: "Auto-tile screen", section: "tiler.hotkeys", key: "auto_tile_screen")
            }

            Section("Focus & Navigation Hotkeys") {
                HotkeyRowView(model: model, label: "Zen mode", section: "tiler.hotkeys", key: "zen_mode")
                HotkeyRowView(model: model, label: "Session sandbox", section: "system_hotkeys", key: "sandbox")
                HotkeyRowView(model: model, label: "Toggle float", section: "tiler.hotkeys", key: "float")
                HotkeyRowView(model: model, label: "Stack: focus next", section: "tiler.hotkeys", key: "stack_next")
                HotkeyRowView(model: model, label: "Stack: focus previous", section: "tiler.hotkeys", key: "stack_prev")
            }

            if let err = model.lastWriteError { Text(err).foregroundColor(.red).font(.caption) }
        }
        .formStyle(.grouped)
        .onAppear { centerZonesEdit = model.config.autoTileCenterZones.joined(separator: ", ") }
    }
}

// MARK: - Input & Output (keyboard layout, audio, focus-follows-mouse)

struct IOTab: View {
    /// Search terms for the titlebar settings search (keep in sync with this pane's controls).
    static let searchKeywords: [String] = ["keyboard", "keyboard layout", "qwerty", "dvorak", "colemak", "focus follows mouse", "dwell", "audio", "audio switcher", "output device", "switch hotkey", "run shortcut on change", "add device", "save devices"]
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            Section("Keyboard") {
                Picker("Keyboard layout", selection: Binding(
                    get: { model.keyboardChoice },
                    set: { model.setKeyboardLayout($0) })) {
                    Text("Auto (\(model.detectedKeyboard))").tag("auto")
                    ForEach(KeyboardLayout.presets, id: \.self) { Text($0).tag($0) }
                }
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
    /// Search terms for the titlebar settings search (keep in sync with this pane's controls).
    static let searchKeywords: [String] = ["app launcher", "hyper apps", "apps", "launch", "app groups", "auto-dismiss", "scratchpad", "app integrations", "chrome", "chrome toggle tab strip", "add group", "clusters"]
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppShortcutsView(model: model).padding(16)
            Divider()
            Form {
                AppGroupsSection(model: model)
                ToggleSection("Scratchpad", isOn: Binding(
                    get: { !model.config.scratchpadApps.isEmpty },
                    set: { on in
                        if on {
                            model.setScratchpadApps(["Terminal"])
                        } else {
                            model.setScratchpadApps([])
                        }
                    }
                ), footer: "Summon a set of utility apps together and dismiss them together.") {
                    if !model.config.scratchpadApps.isEmpty {
                        HotkeyRowView(model: model, label: "Hotkey", section: "system_hotkeys", key: "scratchpad")
                        LabeledContent("Apps") {
                            TextField("e.g. Terminal, Notes", text: Binding(
                                get: { model.config.scratchpadApps.joined(separator: ", ") },
                                set: { val in
                                    let apps = val.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                    model.setScratchpadApps(apps)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                        Toggle("Auto-dismiss", isOn: Binding(
                            get: { model.config.scratchpadAutoDismiss },
                            set: { model.setScratchpadAutoDismiss($0) }
                        ))
                    }
                }
                Section {
                    HotkeyRowView(model: model, label: "Chrome: toggle tab strip", section: "system_hotkeys", key: "chrome_tabs")
                } header: {
                    Text("App Integrations")
                } footer: {
                    Text("Collapses/expands vertical tabs in Google Chrome (shortcut only active when Chrome is frontmost).")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
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
                        ModifierSelector(model: model, alias: aliasOf(g)) { save(g, alias: $0) }
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

struct AppearanceTab: View {
    /// Search terms for the titlebar settings search (keep in sync with this pane's controls).
    static let searchKeywords: [String] = ["window border", "focus border", "color", "width", "corner radius", "renderer", "overlay", "window server", "motion prediction", "margins", "enable margins", "size", "apply margin at screen edges", "theme", "glyph"]
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            Section { AppearancePreview(model: model) }
            BordersSettings(model: model)
            Section("Margins") {
                Toggle("Enable margins", isOn: Binding(
                    get: { model.config.zoneConfig.margins?.enabled ?? false },
                    set: { model.setMarginsEnabled($0) }))
                SliderRow(label: "Size", value: Binding(
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
