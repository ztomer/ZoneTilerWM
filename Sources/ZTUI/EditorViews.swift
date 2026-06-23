// EditorViews.swift — ZTUI v2: the keybind editor and the visual layout editor.
//
// Design intent (Rams / Kare): as little UI as the task needs; direct manipulation over typed
// strings; legible symbols (⇧⌃⌥⌘ + a monospaced grid); state is always visible, nothing
// hidden. Every edit is written back to config.toml through the surgical comment-preserving
// writer, so the user's hand-authored file keeps its comments and ordering.

import SwiftUI
import AppKit
import ZTCore
import ZTSystem

// MARK: - Modifier glyphs

enum ModGlyph {
    static let order = ["shift", "ctrl", "alt", "cmd"]
    static let glyph = ["shift": "⇧", "ctrl": "⌃", "alt": "⌥", "cmd": "⌘"]

    /// Tokens captured from an NSEvent, in canonical order.
    static func tokens(from flags: NSEvent.ModifierFlags) -> [String] {
        var t: [String] = []
        if flags.contains(.shift) { t.append("shift") }
        if flags.contains(.control) { t.append("ctrl") }
        if flags.contains(.option) { t.append("alt") }
        if flags.contains(.command) { t.append("cmd") }
        return t
    }

    static func string(_ tokens: [String]) -> String {
        order.filter(tokens.contains).compactMap { glyph[$0] }.joined()
    }

    /// Render a stored [alias, key] (or [token, key]) as glyphs + key, resolving the alias.
    static func chord(_ value: [String], aliases: [String: [String]]) -> String {
        guard let first = value.first else { return "—" }
        let mods = aliases[first] ?? [first]
        let key = value.count > 1 ? value[1].uppercased() : ""
        return string(mods) + key
    }

    /// A self-documenting picker option: the alias name (primary) followed by its modifier
    /// glyphs (muted). Inlining the glyphs at the point of choice is what lets us drop the
    /// separate, inconsistently-placed ModifierLegend entirely (Rams: make it unnecessary).
    static func aliasLabel(_ alias: String, aliases: [String: [String]]) -> Text {
        let g = string(aliases[alias] ?? [])
        return g.isEmpty ? Text(alias) : Text(alias) + Text("  \(g)").foregroundColor(.secondary)
    }
}

// MARK: - Chord recorder (captures the next key chord via a local event monitor)

final class ChordRecorder: ObservableObject {
    @Published var recordingKey: String?   // identifies which row is recording
    private var monitor: Any?
    var onCapture: ((_ tokens: [String], _ key: String) -> Void)?

    func start(id: String) {
        stop()
        recordingKey = id
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self else { return ev }
            let key = ev.charactersIgnoringModifiers?.lowercased() ?? ""
            if key == "\u{1b}" { self.stop(); return nil }   // escape cancels
            guard !key.isEmpty else { return nil }
            let tokens = ModGlyph.tokens(from: ev.modifierFlags)
            self.onCapture?(tokens, key)
            self.stop()
            return nil   // swallow so the chord doesn't leak into the field
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        recordingKey = nil
    }
}

// MARK: - Keybind editor

/// Non-blocking warning shown atop the Keys tab when one combo drives more than one action
/// (e.g. ⇧⌃⌘0 bound to both Pomodoro reset and Focus-zone-0). Hidden entirely when clean.
struct ConflictBanner: View {
    let conflicts: [HotkeyConflicts.Conflict]
    var body: some View {
        if !conflicts.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(conflicts.count) shortcut conflict\(conflicts.count == 1 ? "" : "s")",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.orange)
                ForEach(conflicts, id: \.combo) { c in
                    Text(c.description).font(.caption).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.orange.opacity(0.12))
            .cornerRadius(8)
        }
    }
}

/// Shared column widths so every hotkey/modifier row on a tab lines up: labels left-align in a
/// fixed column, a Spacer pushes the controls to a common right edge, and the alias pickers
/// share one width — the same two-column rhythm the grouped Form tabs use.
enum KeyRowMetrics {
    static let label: CGFloat = 200
    // The modifier is split into three fixed columns so every row aligns regardless of content:
    // [alias name | glyphs | selector chevron]. alias + glyphs left-align; the selector right-aligns.
    static let alias: CGFloat = 92     // widest alias name (e.g. "mash_shift")
    static let glyphs: CGFloat = 58    // widest glyph set (⇧⌃⌥⌘)
    static let selector: CGFloat = 24  // the dropdown chevron
    static let picker: CGFloat = alias + glyphs + selector + 16   // total modifier-control width
}

/// The shared modifier control: three fixed columns [alias | glyphs | selector] so every hotkey /
/// modifier row aligns regardless of alias-name or glyph-count length. Use this everywhere a modifier
/// alias is chosen — NEVER a bare `Picker`, because a SwiftUI menu Picker sizes to its selected label
/// and ignores `.frame(width:)`, which is what made the rows ragged.
struct ModifierSelector: View {
    @ObservedObject var model: SettingsModel
    let alias: String
    let onSelect: (String) -> Void
    private var aliasNames: [String] { model.config.aliases.keys.sorted() }
    var body: some View {
        let glyphs = ModGlyph.string(model.config.aliases[alias] ?? [])
        HStack(spacing: 8) {
            Text(alias).frame(width: KeyRowMetrics.alias, alignment: .leading)
            Text(glyphs).foregroundColor(.secondary).frame(width: KeyRowMetrics.glyphs, alignment: .leading)
            Menu {
                ForEach(aliasNames, id: \.self) { name in
                    Button { onSelect(name) } label: { ModGlyph.aliasLabel(name, aliases: model.config.aliases) }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .frame(width: KeyRowMetrics.selector, alignment: .trailing)
        }
    }
}

/// One reusable hotkey row: label | modifier-alias picker | key recorder. Self-contained
/// (its own recorder) so a feature can host its own keys (e.g. the Pomodoro tab) without the
/// generic Keybinds tab. Names are shown bare; a ModifierLegend explains the glyphs.
struct HotkeyRowView: View {
    @ObservedObject var model: SettingsModel
    let label: String
    let section: String
    let key: String
    var labelWidth: CGFloat = KeyRowMetrics.label
    var help: String? = nil
    @StateObject private var recorder = ChordRecorder()
    @State private var showHelp = false

    private var aliasNames: [String] { model.config.aliases.keys.sorted() }

    var body: some View {
        let v = model.hotkeyValue(section: section, key: key)
        let alias = v.first ?? (aliasNames.first ?? "mash")
        let keyName = v.count > 1 ? v[1] : ""
        let recording = recorder.recordingKey == key
        return HStack(spacing: 8) {
            Text(label).frame(width: labelWidth, alignment: .leading)
            Spacer(minLength: 12)
            ModifierSelector(model: model, alias: alias) { model.setHotkey(section: section, key: key, alias: $0, keyName: keyName) }
            Text("+").foregroundColor(.secondary)
            Button(recording ? "press key…" : (keyName.isEmpty ? "Set key" : keyName.uppercased())) {
                recorder.start(id: key)
            }.frame(width: 84)
            if let help {
                Button { showHelp.toggle() } label: { Image(systemName: "questionmark.circle") }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showHelp, arrowEdge: .trailing) {
                        Text(help).font(.callout).padding(14).frame(width: 300)
                    }
            }
        }
        .onAppear {
            recorder.onCapture = { _, k in
                let a = model.hotkeyValue(section: section, key: key).first ?? (aliasNames.first ?? "mash")
                model.setHotkey(section: section, key: key, alias: a, keyName: k)
            }
        }
    }
}

struct KeybindEditorView: View {
    /// Search terms for the titlebar settings search (keep in sync with this pane's controls).
    static let searchKeywords: [String] = ["modifiers", "actions", "modifier aliases", "app launcher", "hyper apps", "hotkeys", "shortcuts", "bindings", "conflicts"]
    @ObservedObject var model: SettingsModel

    private struct Row: Identifiable { let id: String; let label: String; let section: String; let key: String; var help: String? = nil }

    // Pomodoro keys live in the Pomodoro tab; these are the tiling/movement/system keys.
    private let rows: [Row] = [
        .init(id: "resize_mode", label: "Resize mode", section: "tiler.hotkeys", key: "resize_mode"),
        .init(id: "placement_mode", label: "Move to next monitor", section: "tiler.hotkeys", key: "placement_mode"),
        .init(id: "zone_info", label: "Move to previous monitor", section: "tiler.hotkeys", key: "zone_info"),
        .init(id: "focus_next_screen", label: "Focus next screen", section: "tiler.hotkeys", key: "focus_next_screen"),
        .init(id: "focus_prev_screen", label: "Focus previous screen", section: "tiler.hotkeys", key: "focus_prev_screen"),
        .init(id: "expose", label: "Exposé / Window grid", section: "system_hotkeys", key: "expose"),
        .init(id: "window_hints", label: "Window hints", section: "system_hotkeys", key: "window_hints"),
        .init(id: "activity_monitor", label: "Activity Monitor", section: "system_hotkeys", key: "activity_monitor"),
        // No "Reload config" hotkey: the agent watches config.toml and live-reloads, and Settings writes
        // apply immediately — a manual reload binding is redundant (the menu-bar item remains as a fallback).
    ]

    private var aliasNames: [String] { model.config.aliases.keys.sorted() }
    private func defaultAlias() -> String { aliasNames.first ?? "mash" }

    var body: some View {
        let conflicts = model.config.hotkeyConflicts()
        return Form {
            if !conflicts.isEmpty {
                Section { ConflictBanner(conflicts: conflicts) }
            }
            // Aliases first — you define the named combos, then assign them as modifiers below.
            AliasEditorSection(model: model)
            Section("Modifiers") {
                modifierRow("Tile zones", key: "modifier", current: model.config.tilerModifier)
                modifierRow("Focus zones", key: "focus_modifier", current: model.config.focusModifier)
            }
            Section("Actions") {
                ForEach(rows) { HotkeyRowView(model: model, label: $0.label, section: $0.section, key: $0.key) }
            }
        }
        .formStyle(.grouped)
    }

    private func modifierRow(_ label: String, key: String, current: [String]) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: KeyRowMetrics.label, alignment: .leading)
            Spacer(minLength: 12)
            ModifierSelector(model: model, alias: Keybinding.alias(forModifiers: current, aliases: model.config.aliases) ?? defaultAlias()) {
                model.setModifierAlias(key: key, alias: $0)
            }
            // Reserve the action rows' "+ key" trailing columns so every row shares one right edge.
            Text("+").hidden()
            Color.clear.frame(width: 84, height: 1)
        }
    }
}

// MARK: - Modifier-alias editor

/// Define + edit the named modifier combos ([aliases] in config.toml): mash, mash_shift, HYPER, …
/// Each row is the alias name + a toggle per modifier; the bottom row adds a new alias. These are
/// the names every modifier/hotkey picker in the app offers, so adding one here makes it assignable
/// everywhere (the live review asked to "define and assign modifier aliases from the UI").
struct AliasEditorSection: View {
    @ObservedObject var model: SettingsModel
    @State private var newName = ""

    private let tokens = ["shift", "ctrl", "alt", "cmd"]
    private var aliasNames: [String] { model.config.aliases.keys.sorted() }

    private func toggle(_ name: String, _ tok: String, _ isOn: Bool) {
        var mods = Set(model.config.aliases[name] ?? [])
        if isOn { mods.insert(tok) } else { mods.remove(tok) }
        guard !mods.isEmpty else { return }   // an alias with no modifiers is meaningless; keep ≥1
        model.setAlias(name: name, modifiers: Array(mods))
    }

    var body: some View {
        Section("Modifier aliases") {
            Text("Named modifier combos you can assign above, in App Launcher, and to the audio hotkey.")
                .font(.caption).foregroundColor(.secondary)
            ForEach(aliasNames, id: \.self) { name in
                HStack(spacing: 6) {
                    Text(name).font(.system(.body, design: .monospaced))
                        .frame(width: 118, alignment: .leading).lineLimit(1)
                    ForEach(tokens, id: \.self) { tok in
                        Toggle(ModGlyph.glyph[tok] ?? tok, isOn: Binding(
                            get: { (model.config.aliases[name] ?? []).contains(tok) },
                            set: { toggle(name, tok, $0) }))
                            .toggleStyle(.button)
                    }
                    Spacer()
                    Button { model.removeAlias(name: name) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).help("Delete alias")
                }
            }
            HStack {
                TextField("new alias (e.g. mash_shift)", text: $newName).labelsHidden()   // in-field prompt, not a wrapping Form label
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Button("Add") {
                    let n = newName.trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty, model.config.aliases[n] == nil else { return }
                    model.setAlias(name: n, modifiers: ["cmd"])   // seed with ⌘; user toggles the rest
                    newName = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }
        }
    }
}

// MARK: - App shortcuts (visual keyboard map)

/// A keyboard render of the app-launch shortcuts: each keycap shows the app the key launches
/// for the selected modifier group. Click a key to assign / change / clear its app.
struct AppShortcutsView: View {
    @ObservedObject var model: SettingsModel
    @State private var selLayer: String?            // which layer the selected key belongs to
    @State private var selectedKey: String?
    @State private var edit = ""
    @State private var newLayerName = ""            // N1: add-a-layer field

    init(model: SettingsModel) {
        self.model = model
        // QA: ZT_APPS_SEED="layer:key:text" pre-selects a key + seeds the picker text, so the footer /
        // fuzzy dropdown / collision warning render for a screenshot without a real click.
        if let seed = ProcessInfo.processInfo.environment["ZT_APPS_SEED"] {
            let p = seed.split(separator: ":", maxSplits: 2).map(String.init)
            if p.count >= 2 { _selLayer = State(initialValue: p[0]); _selectedKey = State(initialValue: p[1]); _edit = State(initialValue: p.count >= 3 ? p[2] : "") }
        }
    }

    // E2: both built-in app-launch layers + N1 custom layers are shown at once (no inner tabs). EVERY
    // layer is removable now — the two built-ins are kept BY DEFAULT as examples, but a built-in whose
    // table was removed simply drops out of the list (its [appCuts]/[hyperAppCuts] section is gone).
    private struct LayerInfo: Identifiable { let id: String; let title: String; let isBuiltin: Bool }
    private func layerId(forCustom name: String) -> String { "app_layers.\"\(name)\"" }
    private var layers: [LayerInfo] {
        var out: [LayerInfo] = []
        let ac = model.config.appCuts
        if !ac.modifier.isEmpty || !ac.apps.isEmpty { out.append(.init(id: "appCuts", title: "App launcher", isBuiltin: true)) }
        let hc = model.config.hyperAppCuts
        if !hc.modifier.isEmpty || !hc.apps.isEmpty { out.append(.init(id: "hyperAppCuts", title: "Hyper apps", isBuiltin: true)) }
        out += model.config.appLayers.map { .init(id: layerId(forCustom: $0.name), title: $0.name, isBuiltin: false) }
        return out
    }
    private var keyRows: [[String]] { model.keyboardRows }
    private var aliasNames: [String] { model.config.aliases.keys.sorted() }
    private func group(_ id: String) -> ConfigLoader.AppHotkeyGroup {
        switch id {
        case "appCuts":      return model.config.appCuts
        case "hyperAppCuts": return model.config.hyperAppCuts
        default:             return model.config.appLayers.first { layerId(forCustom: $0.name) == id }?.group
                                 ?? ConfigLoader.AppHotkeyGroup(modifier: [], apps: [:])
        }
    }
    private func displayKey(_ k: String) -> String { k.count == 1 ? k.uppercased() : k }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("App-launch layers, each on its own modifier. Click a key to assign the app it "
                 + "launches; all layers are editable at once. Add your own layers below.")
                .font(.caption).foregroundColor(.secondary)
            ForEach(layers) { layer in layerCard(layer) }
            addLayerRow
            hudCard
            footerPanel
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 30)
        .padding(.vertical, 4)
    }

    private func layerCard(_ layer: LayerInfo) -> some View {
        let id = layer.id
        let g = group(id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(layer.title).font(.headline)
                Text("Modifier").foregroundColor(.secondary)
                ModifierSelector(model: model, alias: Keybinding.alias(forModifiers: g.modifier, aliases: model.config.aliases) ?? (aliasNames.first ?? "mash")) {
                    model.setValue(section: id, key: "modifier", rawValue: "[\"\($0)\"]")
                }
                Spacer()
                Button { removeLayer(layer) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help(layer.isBuiltin ? "Remove this built-in layer (kept by default as an example)" : "Remove this layer")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(keyRows.indices, id: \.self) { r in
                        HStack(spacing: 4) {
                            ForEach(keyRows[r], id: \.self) { key in keycap(layer: id, key: key, app: g.apps[key] ?? "") }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
    }

    // N1: add a custom layer (starts on HYPER; change its modifier in the new card).
    private var addLayerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.rectangle.on.rectangle").foregroundColor(.secondary)
            TextField("new layer name", text: $newLayerName).labelsHidden()
                .textFieldStyle(.roundedBorder).frame(maxWidth: 180)
            Button("Add layer") {
                let n = newLayerName.trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty, !n.contains("\""), n != "appCuts", n != "hyperAppCuts",
                      !model.config.appLayers.contains(where: { $0.name == n }) else { return }
                model.addAppLayer(name: n, modifier: "HYPER")
                newLayerName = ""
            }
            .disabled(newLayerName.trimmingCharacters(in: .whitespaces).isEmpty)
            Text("Starts on HYPER — set its modifier in the new card.").font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.04)))
    }

    private func removeLayer(_ layer: LayerInfo) {
        if selLayer == layer.id { selLayer = nil; selectedKey = nil; edit = "" }
        if layer.isBuiltin { model.removeBuiltInAppLayer(section: layer.id) }
        else { model.removeAppLayer(name: layer.title) }
    }

    // The hold-to-reveal HUD: hold a layer's modifier → its shortcuts appear as a palette. Its home is
    // here, with the layers (its hold-delay is its own, decoupled from the zone HUD).
    private var hudCard: some View {
        SectionCard(title: "Hold-to-reveal HUD", toggle: Binding(
            get: { model.config.appLauncherHUDEnabled }, set: { model.setAppLauncherHUDEnabled($0) })) {
            Text("Hold a layer's modifier to see its shortcuts as a palette; release to dismiss.")
                .font(.caption).foregroundColor(.secondary)
            HStack { Spacer(); AppLauncherHUDPreview(model: model); Spacer() }.padding(.vertical, 2)
            if model.config.appLauncherHUDEnabled {
                Stepper("Hold delay: \(model.config.appLauncherHUDHoldDelayMs) ms", value: Binding(
                    get: { model.config.appLauncherHUDHoldDelayMs }, set: { model.setAppLauncherHUDHoldDelay($0) }),
                    in: 80...2000, step: 20).frame(maxWidth: 280)
            }
        }
    }

    // Footer: assign/clear the selected key's app (fuzzy app picker — E3), with a collision warning
    // (E4). Fixed footprint so selecting a key never shifts the layout.
    @ViewBuilder private var footerPanel: some View {
        Group {
            if let k = selectedKey, let layer = selLayer {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(ModGlyph.string(group(layer).modifier) + displayKey(k))
                            .font(.system(.body, design: .monospaced)).frame(width: 90, alignment: .leading)
                            .padding(.top, 3)
                        AppPickerField(installed: model.installedApps, text: $edit) { picked in
                            edit = picked; commit(layer: layer, key: k)
                        }
                        Button("Set") { commit(layer: layer, key: k) }.padding(.top, 1)
                        Button("Clear") { model.removeAppShortcut(group: layer, key: k); selectedKey = nil; edit = "" }.padding(.top, 1)
                        Spacer()
                    }
                    if let warn = collision(layer: layer, key: k) {
                        Label(warn, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundColor(ZTPalette.accentColor)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "cursorarrow.rays").foregroundColor(.secondary)
                    Text("Select a key above to assign or change its app.").foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
    }

    private func keycap(layer: String, key: String, app: String) -> some View {
        let mapped = !app.isEmpty
        let sel = selectedKey == key && selLayer == layer
        return VStack(spacing: 2) {
            Text(displayKey(key)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(mapped ? .white : .secondary.opacity(0.7))
            Text(app).font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.7)
                .truncationMode(.tail).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 3)
        .frame(width: 64, height: 44)
        .background(RoundedRectangle(cornerRadius: 6).fill(mapped ? Color.accentColor.opacity(0.22) : Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(sel ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: sel ? 2 : 0.5))
        .contentShape(Rectangle())
        .onTapGesture { selLayer = layer; selectedKey = key; edit = app }
    }

    private func commit(layer: String, key: String) {
        let v = edit.trimmingCharacters(in: .whitespaces)
        if v.isEmpty { model.removeAppShortcut(group: layer, key: key) }
        else { model.setAppShortcut(group: layer, key: key, app: v) }
    }

    /// E4: warn if the selected (modifier, key) is already bound elsewhere — the other app layer, a
    /// tiling / system / pomodoro hotkey, an app-group hotkey, or (when this layer shares the tiling
    /// modifier) the per-zone tiling keys. Same modifier SET + same key = a real conflict.
    private func collision(layer: String, key: String) -> String? {
        let mod = group(layer).modifier
        guard !mod.isEmpty, !key.isEmpty else { return nil }
        let modSet = Set(mod.map { $0.lowercased() })
        let keyLC = key.lowercased()
        func sameMod(_ other: [String]) -> Bool { Set(other.map { $0.lowercased() }) == modSet }
        func aliasMods(_ a: String) -> [String] { model.config.aliases[a] ?? [a] }

        // The other app-launch layer.
        for other in layers where other.id != layer {
            let og = group(other.id)
            if sameMod(og.modifier), let app = og.apps[key] { return "Also \(other.title): \(app)" }
        }
        // Explicit [alias, key] hotkey tables — name the precise conflicting action.
        let tables: [(String, [String: [String]])] = [
            ("tiling", model.config.tilerHotkeys), ("system", model.config.systemHotkeys),
            ("pomodoro", model.config.pomodoroHotkeys)]
        for (kind, table) in tables {
            for (name, hk) in table where hk.count >= 2 {
                if sameMod(aliasMods(hk[0])), hk[1].lowercased() == keyLC { return "Also \(kind) hotkey ‘\(name)’" }
            }
        }
        // App-group hotkeys.
        for grp in model.config.appGroups where grp.hotkey.count >= 2 {
            if sameMod(aliasMods(grp.hotkey[0])), grp.hotkey[1].lowercased() == keyLC { return "Also app group ‘\(grp.name)’" }
        }
        // Broad: this layer shares the tiling modifier, so its keys also fire the per-zone tile hotkeys.
        if sameMod(model.config.tilerModifier) { return "Shares the tiling modifier — this key may also tile a zone" }
        return nil
    }
}

/// A text field for an app name with a live fuzzy-match dropdown sourced from installed apps (E3).
/// Typing filters the list (prefix matches first, shortest names next); clicking a row fills it.
struct AppPickerField: View {
    let installed: [String]
    @Binding var text: String
    let onPick: (String) -> Void

    private var matches: [String] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        if installed.contains(where: { $0.caseInsensitiveCompare(text.trimmingCharacters(in: .whitespaces)) == .orderedSame }) { return [] }
        return Array(installed.filter { $0.lowercased().contains(q) }.sorted { a, b in
            let ap = a.lowercased().hasPrefix(q), bp = b.lowercased().hasPrefix(q)
            return ap != bp ? (ap && !bp) : a.count < b.count
        }.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            TextField("app name (blank to clear)", text: $text)
                .textFieldStyle(.roundedBorder).frame(width: 240)
            if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(matches, id: \.self) { m in
                        Button { onPick(m) } label: {
                            HStack { Text(m).font(.system(size: 12)); Spacer() }
                                .padding(.horizontal, 8).padding(.vertical, 3).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                .frame(width: 240, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
            }
        }
    }
}

/// A live mock of the hold-to-reveal app-launcher HUD — the dark glass palette of a layer's mapped
/// keys (key → app) that appears while you hold its modifier. Mirrors the live AppLauncherOverlay's
/// look so the settings preview shows what you'll get. Uses the first non-empty layer's shortcuts.
struct AppLauncherHUDPreview: View {
    @ObservedObject var model: SettingsModel

    private var sample: ConfigLoader.AppHotkeyGroup? {
        let ac = model.config.appCuts
        if !ac.apps.isEmpty { return ac }
        let hc = model.config.hyperAppCuts
        if !hc.apps.isEmpty { return hc }
        return model.config.appLayers.first { !$0.group.apps.isEmpty }?.group
    }

    var body: some View {
        let items = (sample?.apps ?? [:]).sorted { $0.key < $1.key }.prefix(8)
        return VStack(spacing: 0) {
            if items.isEmpty {
                Text("Assign a few apps above to preview the HUD.")
                    .font(.caption2).foregroundColor(.white.opacity(0.6)).padding(.vertical, 10)
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(items), id: \.key) { k, app in
                        VStack(spacing: 2) {
                            Text(k.uppercased()).font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                            Text(app).font(.system(size: 8)).foregroundColor(.white.opacity(0.6))
                                .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: 50)
                        }
                        .frame(width: 54, height: 38)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.14)))
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.10)))
    }
}

// MARK: - Visual layout editor

/// A titled card matching the grouped-Form rhythm used by the other Settings tabs, so the
/// custom Layouts editor reads as the same design language (not a bare VStack of dividers).
struct SectionCard<Content: View>: View {
    let title: String
    /// Optional enable toggle shown IN the header, so a single-toggle card doesn't restate its title
    /// in a separate row.
    var toggle: Binding<Bool>? = nil
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                if let toggle {
                    Spacer()
                    Toggle("", isOn: toggle).labelsHidden().toggleStyle(.switch)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
    }
}
