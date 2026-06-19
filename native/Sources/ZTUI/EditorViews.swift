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
    static let label: CGFloat = 170
    static let picker: CGFloat = 150
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
    @StateObject private var recorder = ChordRecorder()

    private var aliasNames: [String] { model.config.aliases.keys.sorted() }

    var body: some View {
        let v = model.hotkeyValue(section: section, key: key)
        let alias = v.first ?? (aliasNames.first ?? "mash")
        let keyName = v.count > 1 ? v[1] : ""
        let recording = recorder.recordingKey == key
        return HStack(spacing: 8) {
            Text(label).frame(width: labelWidth, alignment: .leading)
            Spacer(minLength: 12)
            Picker("", selection: Binding(
                get: { alias },
                set: { model.setHotkey(section: section, key: key, alias: $0, keyName: keyName) })) {
                ForEach(aliasNames, id: \.self) { ModGlyph.aliasLabel($0, aliases: model.config.aliases).tag($0) }
            }.labelsHidden().frame(width: KeyRowMetrics.picker)
            Text("+").foregroundColor(.secondary)
            Button(recording ? "press key…" : (keyName.isEmpty ? "Set key" : keyName.uppercased())) {
                recorder.start(id: key)
            }.frame(width: 84)
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
    @ObservedObject var model: SettingsModel

    private struct Row: Identifiable { let id: String; let label: String; let section: String; let key: String }

    // Pomodoro keys live in the Pomodoro tab; these are the tiling/movement/system keys.
    private let rows: [Row] = [
        .init(id: "resize_mode", label: "Resize mode", section: "tiler.hotkeys", key: "resize_mode"),
        .init(id: "placement_mode", label: "Move to next monitor", section: "tiler.hotkeys", key: "placement_mode"),
        .init(id: "zone_info", label: "Move to previous monitor", section: "tiler.hotkeys", key: "zone_info"),
        .init(id: "focus_next_screen", label: "Focus next screen", section: "tiler.hotkeys", key: "focus_next_screen"),
        .init(id: "focus_prev_screen", label: "Focus previous screen", section: "tiler.hotkeys", key: "focus_prev_screen"),
        .init(id: "window_hints", label: "Window hints", section: "system_hotkeys", key: "window_hints"),
        .init(id: "activity_monitor", label: "Activity Monitor", section: "system_hotkeys", key: "activity_monitor"),
        .init(id: "reload", label: "Reload config", section: "system_hotkeys", key: "reload"),
    ]

    // Gated / opt-in feature actions — no hotkey by default, so they need a binding row to be
    // reachable at all (the live review flagged "how do I open the command palette?").
    private let featureRows: [Row] = [
        .init(id: "command_palette", label: "Command palette", section: "system_hotkeys", key: "command_palette"),
        .init(id: "scratchpad", label: "Scratchpad summon/dismiss", section: "system_hotkeys", key: "scratchpad"),
        .init(id: "peek", label: "Window peek", section: "system_hotkeys", key: "peek"),
        .init(id: "sandbox", label: "Session sandbox", section: "system_hotkeys", key: "sandbox"),
        .init(id: "zen_mode", label: "Zen mode", section: "tiler.hotkeys", key: "zen_mode"),
        .init(id: "float", label: "Toggle float", section: "tiler.hotkeys", key: "float"),
        .init(id: "stack_next", label: "Stack: focus next", section: "tiler.hotkeys", key: "stack_next"),
        .init(id: "stack_prev", label: "Stack: focus previous", section: "tiler.hotkeys", key: "stack_prev"),
    ]

    private var aliasNames: [String] { model.config.aliases.keys.sorted() }
    private func defaultAlias() -> String { aliasNames.first ?? "mash" }

    var body: some View {
        let conflicts = model.config.hotkeyConflicts()
        return Form {
            if !conflicts.isEmpty {
                Section { ConflictBanner(conflicts: conflicts) }
            }
            Section("Modifiers") {
                modifierRow("Tile zones", key: "modifier", current: model.config.tilerModifier)
                modifierRow("Focus zones", key: "focus_modifier", current: model.config.focusModifier)
            }
            AliasEditorSection(model: model)
            Section("Actions") {
                ForEach(rows) { HotkeyRowView(model: model, label: $0.label, section: $0.section, key: $0.key) }
            }
            Section("Feature actions (opt-in — bind a key to use)") {
                ForEach(featureRows) { HotkeyRowView(model: model, label: $0.label, section: $0.section, key: $0.key) }
            }
        }
        .formStyle(.grouped)
    }

    private func modifierRow(_ label: String, key: String, current: [String]) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: KeyRowMetrics.label, alignment: .leading)
            Spacer(minLength: 12)
            Picker("", selection: Binding(
                get: { Keybinding.alias(forModifiers: current, aliases: model.config.aliases) ?? defaultAlias() },
                set: { model.setModifierAlias(key: key, alias: $0) })) {
                ForEach(aliasNames, id: \.self) { ModGlyph.aliasLabel($0, aliases: model.config.aliases).tag($0) }
            }.labelsHidden().frame(width: KeyRowMetrics.picker)
            // Reserve the action rows' "+ key" trailing columns so every picker shares one right edge.
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
    @State private var group = "appCuts"
    @State private var selectedKey: String?
    @State private var edit = ""

    private var keyRows: [[String]] { model.keyboardRows }
    private var aliasNames: [String] { model.config.aliases.keys.sorted() }
    private var currentGroup: ConfigLoader.AppHotkeyGroup {
        group == "appCuts" ? model.config.appCuts : model.config.hyperAppCuts
    }
    private func displayKey(_ k: String) -> String { k.count == 1 ? k.uppercased() : k }

    var body: some View {
        let apps = currentGroup.apps
        return VStack(alignment: .leading, spacing: 16) {   // more breathing room around the controls + keymap
            HStack(spacing: 12) {
                Picker("", selection: $group) {
                    Text("App launcher").tag("appCuts")
                    Text("Hyper apps").tag("hyperAppCuts")
                }.pickerStyle(.segmented).frame(width: 240).labelsHidden()
                Text("Modifier").foregroundColor(.secondary)
                Picker("", selection: Binding(
                    get: { Keybinding.alias(forModifiers: currentGroup.modifier, aliases: model.config.aliases) ?? (aliasNames.first ?? "mash") },
                    set: { model.setValue(section: group, key: "modifier", rawValue: "[\"\($0)\"]") })) {
                    ForEach(aliasNames, id: \.self) { ModGlyph.aliasLabel($0, aliases: model.config.aliases).tag($0) }
                }.labelsHidden().frame(width: 150)
                Spacer()
            }
            Text("Each key shows the app it launches with the selected modifier. Click a key to edit.")
                .font(.caption).foregroundColor(.secondary)
            // Wide keyboard rows (a 10–13 key qwerty row is ~600px+) scroll horizontally
            // rather than overflow / clip a narrow window.
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(keyRows.indices, id: \.self) { r in
                        HStack(spacing: 4) {
                            ForEach(keyRows[r], id: \.self) { key in keycap(key, app: apps[key] ?? "") }
                        }
                    }
                }
            }
            // Footer panel: assign/clear the selected key's app, or a hint when none is selected.
            // Same footprint either way, so selecting a key never shifts the layout.
            Group {
                if let k = selectedKey {
                    HStack(spacing: 8) {
                        Text(ModGlyph.string(currentGroup.modifier) + displayKey(k))
                            .font(.system(.body, design: .monospaced)).frame(width: 90, alignment: .leading)
                        TextField("app name (blank to clear)", text: $edit)
                            .textFieldStyle(.roundedBorder).frame(width: 240).onSubmit { commit(k) }
                        Button("Set") { commit(k) }
                        Button("Clear") { model.removeAppShortcut(group: group, key: k); selectedKey = nil; edit = "" }
                        Spacer()
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
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Match the inset the grouped-Form tabs (General/Keys/Pomodoro/Advanced) and the Layouts
        // cards land their content at (~46pt from the window edge). This view only got the shared
        // 16pt container padding, so its content sat ~30pt further left than every other tab.
        .padding(.horizontal, 30)
        .padding(.vertical, 4)
    }

    private func keycap(_ key: String, app: String) -> some View {
        let mapped = !app.isEmpty
        let sel = selectedKey == key
        return VStack(spacing: 2) {
            Text(displayKey(key)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(mapped ? .white : .secondary.opacity(0.7))
            Text(app).font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.7)   // shrink long names instead of truncating
                .truncationMode(.tail).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 3)
        .frame(width: 64, height: 44)
        .background(RoundedRectangle(cornerRadius: 6).fill(mapped ? Color.accentColor.opacity(0.22) : Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(sel ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: sel ? 2 : 0.5))
        .contentShape(Rectangle())
        .onTapGesture { selectedKey = key; edit = app }
    }

    private func commit(_ k: String) {
        let v = edit.trimmingCharacters(in: .whitespaces)
        if v.isEmpty { model.removeAppShortcut(group: group, key: k) }
        else { model.setAppShortcut(group: group, key: k, app: v) }
    }
}

// MARK: - Visual layout editor

/// A titled card matching the grouped-Form rhythm used by the other Settings tabs, so the
/// custom Layouts editor reads as the same design language (not a bare VStack of dividers).
struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
    }
}

struct LayoutEditorView: View {
    @ObservedObject var model: SettingsModel
    @State private var grid: String = ""
    @State private var zone: String = ""
    @State private var tiles: [String] = []        // editable copy of the zone's cycle list
    @State private var selectedTile: Int?           // index into tiles, for highlight/remove
    @State private var anchor: (c: Int, r: Int)?    // first corner of a new selection
    @State private var pending: GridCells.Span?     // current selection rectangle

    private var gridNames: [String] { model.config.zoneConfig.grids.keys.sorted() }
    private var cols: Int { model.config.zoneConfig.grids[grid]?.cols ?? 0 }
    private var rows: Int { model.config.zoneConfig.grids[grid]?.rows ?? 0 }
    private var zoneKeys: [String] { (model.config.zoneConfig.layouts[grid]?.keys.sorted()) ?? [] }

    private let autoTag = "__auto__"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {   // de-crowd the dense Layouts sections
                monitorsSection
                if !grid.isEmpty {
                    SectionCard(title: "Zones") {
                        HStack(spacing: 8) {
                            Text("Grid").foregroundColor(.secondary)
                            Text(grid).font(.system(.body, design: .monospaced).weight(.semibold)).foregroundColor(.accentColor)
                            Spacer()
                            Picker("Edit grid", selection: $grid) { ForEach(gridNames, id: \.self) { Text($0).tag($0) } }
                                .frame(width: 150).onChange(of: grid) { _ in syncZone() }
                        }
                        Text("Each key shows the zone mapped to it; the cells show its first tile. Click to edit.")
                            .font(.caption).foregroundColor(.secondary)
                        zonePreviews
                        Divider().padding(.vertical, 6)
                        HStack(alignment: .top, spacing: 20) { gridView; tileList }
                        Text("Click a cell, then another to span a rectangle. Add appends it to the zone's cycle; Save writes config.toml.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                SectionCard(title: "Default zone per app") { DefaultZonesSection(model: model) }
                if let err = model.lastWriteError { Text(err).font(.caption).foregroundColor(.red) }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { if grid.isEmpty { grid = model.monitors.first?.effective ?? gridNames.first ?? ""; syncZone() } }
    }

    private var monitorsSection: some View {
        SectionCard(title: "Monitors") {
            Text("Each monitor uses an auto-detected grid; override it here. Hierarchy: monitor → grid → zones.")
                .font(.caption).foregroundColor(.secondary)
            if model.monitors.isEmpty { Text("No displays detected.").font(.caption).foregroundColor(.secondary) }
            ForEach(model.monitors) { m in
                HStack(spacing: 10) {
                    Image(systemName: "display")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.name)
                        Text("auto-detected: \(m.autoDetected ?? "—")\(m.override != nil ? "  ·  overridden" : "")")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { m.override ?? autoTag },
                        set: { sel in model.setMonitorOverride(name: m.name, grid: sel == autoTag ? nil : sel) })) {
                        Text("Auto").tag(autoTag)
                        ForEach(gridNames, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 120)
                    Button("Edit zones") { grid = m.effective; syncZone() }
                }
                .padding(6)
                .background(grid == m.effective ? Color.accentColor.opacity(0.10) : .clear)
                .cornerRadius(6)
            }
        }
    }

    private func displayKey(_ k: String) -> String { k.count == 1 ? k.uppercased() : k }

    // Zones laid out on the physical keyboard so each zone visibly maps to its key.
    private var zonePreviews: some View {
        VStack(spacing: 4) {
            ForEach(model.keyboardRows.indices, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(model.keyboardRows[r], id: \.self) { key in zoneKeycap(key) }
                }
            }
        }
    }

    private func zoneKeycap(_ key: String) -> some View {
        let tiles = model.config.zoneConfig.layouts[grid]?[key]
        let isZone = tiles != nil
        let span = tiles?.first.flatMap(GridCells.parse)
        let sel = zone == key
        return VStack(spacing: 2) {
            miniGrid(span: span, dim: !isZone)
            Text(displayKey(key)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(isZone ? .white : .secondary.opacity(0.55))
        }
        .frame(width: 54, height: 48)
        .background(RoundedRectangle(cornerRadius: 6).fill(sel ? Color.accentColor.opacity(0.20)
            : (isZone ? Color(NSColor.controlBackgroundColor) : Color.clear)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(sel ? Color.accentColor : Color.secondary.opacity(isZone ? 0.3 : 0.12), lineWidth: sel ? 2 : 0.5))
        .contentShape(Rectangle())
        .onTapGesture { if isZone { zone = key; loadTiles() } }
    }

    private func miniGrid(span: GridCells.Span?, dim: Bool = false) -> some View {
        VStack(spacing: 1) {
            ForEach(1...max(rows, 1), id: \.self) { r in
                HStack(spacing: 1) {
                    ForEach(0..<max(cols, 1), id: \.self) { c in
                        Rectangle()
                            .fill(dim ? Color.secondary.opacity(0.12)
                                  : ((span.map { contains($0, c, r) } ?? false) ? Color.accentColor : Color.secondary.opacity(0.25)))
                            .frame(width: 8, height: 6)
                    }
                }
            }
        }
    }

    private var gridView: some View {
        VStack(spacing: 2) {
            ForEach(1...max(rows, 1), id: \.self) { r in
                HStack(spacing: 2) {
                    ForEach(0..<max(cols, 1), id: \.self) { c in cell(c: c, r: r) }
                }
            }
        }
    }

    private func cell(c: Int, r: Int) -> some View {
        let inSelected = selectedTile.flatMap { tiles.indices.contains($0) ? GridCells.parse(tiles[$0]) : nil }
            .map { contains($0, c, r) } ?? false
        let inPending = pending.map { contains($0, c, r) } ?? false
        let fill: Color = inPending ? .accentColor.opacity(0.7) : (inSelected ? .accentColor.opacity(0.3) : Color(NSColor.controlBackgroundColor))
        return RoundedRectangle(cornerRadius: 4)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))
            .frame(width: 46, height: 38)
            .overlay(Text("\(col(c))\(r)").font(.system(.caption2, design: .monospaced)).foregroundColor(.secondary))
            .onTapGesture { tap(c: c, r: r) }
    }

    // The tile editor as one self-contained card (Gemini: consolidate the cycle list + CRUD so
    // the buttons share a baseline and don't stack erratically beside the grid).
    private var tileList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tiles (cycle order)").font(.subheadline).bold()
            if tiles.isEmpty {
                Text("None yet — select cells on the grid, then Add.")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(tiles.indices, id: \.self) { i in
                    HStack(spacing: 6) {
                        Image(systemName: selectedTile == i ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(.accentColor)
                        Text(tiles[i]).font(.system(.body, design: .monospaced))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedTile = i }
                }
            }
            Divider().padding(.vertical, 2)
            HStack(spacing: 8) {
                Button("Add") { addPending() }.disabled(pending == nil)
                Button("Remove") { removeSelected() }.disabled(selectedTile == nil)
                Spacer()
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 220, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 0.5))
    }

    // MARK: helpers

    private func col(_ i: Int) -> String { String(UnicodeScalar(UInt8(97 + i))) }

    private func contains(_ s: GridCells.Span, _ c: Int, _ r: Int) -> Bool {
        c >= s.c0 && c <= s.c1 && r >= s.r0 && r <= s.r1
    }

    private func tap(c: Int, r: Int) {
        if let a = anchor {
            pending = GridCells.Span(c0: a.c, r0: a.r, c1: c, r1: r)
            anchor = nil   // completed a rectangle; next tap starts a new one
        } else {
            anchor = (c, r)
            pending = GridCells.Span(c0: c, r0: r, c1: c, r1: r)
        }
    }

    private func addPending() {
        guard let p = pending else { return }
        tiles.append(GridCells.format(p))
        selectedTile = tiles.count - 1
        pending = nil; anchor = nil
    }

    private func removeSelected() {
        guard let i = selectedTile, tiles.indices.contains(i) else { return }
        tiles.remove(at: i)
        selectedTile = tiles.isEmpty ? nil : min(i, tiles.count - 1)
    }

    private func save() {
        guard !grid.isEmpty, !zone.isEmpty else { return }
        model.setLayoutZone(grid: grid, zone: zone, tiles: tiles)
    }

    private func syncZone() {
        zone = zoneKeys.contains(zone) ? zone : (zoneKeys.first ?? "")
        loadTiles()
    }

    private func loadTiles() {
        tiles = model.config.zoneConfig.layouts[grid]?[zone] ?? []
        selectedTile = tiles.isEmpty ? nil : 0
        pending = nil; anchor = nil
    }
}
