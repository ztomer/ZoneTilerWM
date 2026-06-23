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

// Shared helpers (tilingGlyphs, KeyCaps, ShortcutLine, ToggleSection, boolBind) live in
// SettingsHelpers.swift.

struct PreviewsTab: View {
    /// Search terms for the titlebar settings search (keep in sync with this pane's controls).
    static let searchKeywords: [String] = ["window hints", "window hints hotkey", "exposé", "expose", "mission control", "window grid", "spaces bar position", "navigation keys", "arrows", "vim", "wasd", "show windows from", "active monitor", "all monitors", "switching spaces", "switching method", "auto", "keyboard shortcuts", "trackpad gesture", "gesture", "show spaces in the menu bar", "menu bar", "menubar", "bracket style", "use real macos spaces", "real spaces", "liquid glass"]
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            // Each preview sits with the options that affect it (no shared "Settings" dump; keyboard
            // layout lives in Input & Output, not duplicated here).
            ToggleSection("Window Hints", isOn: Binding(
                get: { model.config.windowHintsEnabled }, set: { model.setWindowHintsEnabled($0) }),
                footer: "Label every window with a key; type it to jump focus. Off unbinds the hotkey.") {
                HStack { Spacer(); WindowHintsPreview(model: model); Spacer() }.padding(.vertical, 8)
                if model.config.windowHintsEnabled {
                    HotkeyRowView(model: model, label: "Hotkey", section: "system_hotkeys", key: "window_hints")
                }
            }

            ToggleSection("Exposé / Window Grid", isOn: Binding(
                get: { model.config.exposeEnabled }, set: { model.setExposeEnabled($0) }),
                footer: "Lay every window out in a labeled grid; type a label to focus. Off unbinds the hotkey.") {
                HStack { Spacer(); ExposePreview(model: model); Spacer() }.padding(.vertical, 8)
                if model.config.exposeEnabled {
                    HotkeyRowView(model: model, label: "Hotkey", section: "system_hotkeys", key: "expose")
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
            }

        }
        .formStyle(.grouped)
    }
}

/// Spaces — its own pane (was buried in "Exposé & Hints"): the menu-bar Spaces widget + how the app
/// switches Spaces.
struct SpacesTab: View {
    static let searchKeywords: [String] = ["spaces", "switching spaces", "switching method", "auto", "keyboard shortcuts", "trackpad gesture", "gesture", "mission control", "show spaces in the menu bar", "menu bar", "menubar", "bracket style", "use real macos spaces", "real spaces", "desktops", "virtual desktops"]
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            ToggleSection("Show Spaces in the menu bar", isOn: Binding(
                get: { model.spacesMenubarEnabled }, set: { model.setSpacesMenubar($0) }),
                footer: "The menu bar + Exposé list ALL your Spaces, grouped per monitor, highlighting the current one live. OFF uses NO private API (reads the layout from a public preferences file + a tiny per-Space marker window; a monitor with 3+ Spaces may briefly mis-highlight until visited once). ON adds via the private API: a guaranteed-exact highlight, per-Space wallpapers, and native full-screen Spaces. Switching Spaces needs neither.") {
                if model.spacesMenubarEnabled {
                    MenubarBracketPicker(model: model)
                }
                Toggle("Use real macOS Spaces (experimental)", isOn: Binding(
                    get: { model.realSpacesEnabled }, set: { model.setRealSpaces($0) }))
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
        }
        .formStyle(.grouped)
    }
}

// MARK: - General

struct GeneralTab: View {
    /// Search terms for the titlebar settings search (keep in sync with this pane's controls).
    static let searchKeywords: [String] = ["startup", "launch at login", "login", "config", "config file", "reveal", "open", "version", "reload", "keyboard", "keyboard layout", "qwerty", "dvorak", "colemak", "focus follows mouse", "dwell"]
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            ToggleSection("Launch at login", isOn: Binding(
                get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }),
                footer: model.launchAtLoginAvailable ? nil
                    : "Available when running the installed ZoneTilerWM.app (not the dev binary).")
                .disabled(!model.launchAtLoginAvailable)

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

/// Tiles → Hotkeys: the tiling + focus/navigation hotkeys (their own tab, per feedback — they're not
/// "advanced").
struct TilesHotkeysTab: View {
    static let searchKeywords: [String] = ["move to next monitor", "move to previous monitor", "focus next screen", "focus previous screen", "resize mode", "auto-tile screen", "zen mode", "session sandbox", "toggle float", "float", "stack focus next", "stack focus previous", "stacks", "hotkeys", "shortcuts"]
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
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
    }
}

/// Tiles → Advanced: tiling internals + the per-app default zone.
struct TilesAdvancedTab: View {
    static let searchKeywords: [String] = ["placement strategy", "rotate", "largest free space", "hybrid", "auto-tiling mode", "usage", "session", "working-set capacity", "working-set staleness", "working set", "auto-tile center zones", "center zones", "default zone per app", "per app"]
    @ObservedObject var model: SettingsModel
    @State private var centerZonesEdit = ""
    private func commitCenterZones() { model.setCenterZones(splitList(centerZonesEdit)) }
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
            Section("Default zone per app") {
                Text("When an app first opens, auto-tile sends it to this zone if it has no learned position yet.")
                    .font(.caption).foregroundColor(.secondary)
                DefaultZonesSection(model: model)
            }
            if let err = model.lastWriteError { Text(err).foregroundColor(.red).font(.caption) }
        }
        .formStyle(.grouped)
        .onAppear { centerZonesEdit = model.config.autoTileCenterZones.joined(separator: ", ") }
    }
}

/// The "Tiles" pane (feedback: Tiling + Layouts are one feature). Three segments: the visual zone
/// editor + zone HUD + drag-to-snap (Zones), the tiling hotkeys (Hotkeys), and the tiling internals +
/// per-app defaults (Advanced).
struct TilesTab: View {
    static let searchKeywords: [String] = LayoutEditorView.searchKeywords
        + ["zone hud", "hud", "hold delay", "drag-to-snap", "drag", "snap"]
        + TilesHotkeysTab.searchKeywords + TilesAdvancedTab.searchKeywords
    @ObservedObject var model: SettingsModel
    // QA: ZT_TILES_SEG=N opens segment N directly (0 Zones / 1 Hotkeys / 2 Advanced).
    @State private var section = Int(ProcessInfo.processInfo.environment["ZT_TILES_SEG"] ?? "0") ?? 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                Text("Zones").tag(0)
                Text("Hotkeys").tag(1)
                Text("Advanced").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden()
            .frame(maxWidth: 340).padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)

            switch section {
            case 1:  TilesHotkeysTab(model: model)
            case 2:  TilesAdvancedTab(model: model)
            default: LayoutEditorView(model: model, showDefaultZones: false, showInteractive: true)
            }
        }
    }
}

// MARK: - Input & Output (keyboard layout, audio, focus-follows-mouse)

struct AudioTab: View {
    /// Search terms for the titlebar settings search (keep in sync with this pane's controls).
    static let searchKeywords: [String] = ["audio", "audio switcher", "output device", "switch hotkey", "run shortcut on change", "add device", "save devices"]
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            AudioSettings(model: model)
        }
        .formStyle(.grouped)
    }
}

// MARK: - App Launcher (app cuts + hyper cuts + scratchpad)

struct AppLauncherTab: View {
    /// Search terms for the titlebar settings search (keep in sync with this pane's controls).
    static let searchKeywords: [String] = ["app launcher", "hyper apps", "apps", "launch", "app cuts", "modifier", "layer", "app integrations", "chrome", "chrome toggle tab strip"]
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppShortcutsView(model: model).padding(16)
            Divider()
            Form {
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
        // E5/A6: the header enable toggle (gates all app-group hotkeys); Scratchpad removed — app
        // groups supersede it.
        ToggleSection("App groups", isOn: Binding(
            get: { model.config.appGroupsEnabled }, set: { model.setAppGroupsEnabled($0) }),
            footer: "Named sets of apps summoned and dismissed together, each with its own hotkey. "
                + "Press ⏎ in a field to save. Off unbinds every group hotkey.") {
            caption("Each group toggles its apps to the foreground (and hides them again) with its hotkey.")
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

/// The "App Groups" pane (E1: split out of App Launcher to fill the empty gap there). Just the
/// named-group editor with its header enable toggle.
struct AppGroupsTab: View {
    static let searchKeywords: [String] = ["app groups", "groups", "scratchpad", "summon", "dismiss",
        "auto-dismiss", "add group", "clusters", "utility apps", "enable app groups"]
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            AppGroupsSection(model: model)
        }
        .formStyle(.grouped)
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
            ToggleSection("Margins", isOn: Binding(
                get: { model.config.zoneConfig.margins?.enabled ?? false },
                set: { model.setMarginsEnabled($0) }),
                footer: "Gaps between tiled windows (and optionally the screen edge).") {
                if model.config.zoneConfig.margins?.enabled ?? false {
                    SliderRow(label: "Size", value: Binding(
                        get: { Int(model.config.zoneConfig.margins?.size ?? 0) },
                        set: { model.setMarginsSize($0) }), range: 0...40, suffix: "px")
                    Toggle("Apply at screen edges", isOn: Binding(
                        get: { model.config.zoneConfig.margins?.screen_edge ?? false },
                        set: { model.setMarginsScreenEdge($0) }))
                }
            }

        }
        .formStyle(.grouped)
    }
}
