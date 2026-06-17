// EditorViews.swift — ZTUI v2: the keybind editor and the visual layout editor.
//
// Design intent (Rams / Kare): as little UI as the task needs; direct manipulation over typed
// strings; legible symbols (⇧⌃⌥⌘ + a monospaced grid); state is always visible, nothing
// hidden. Every edit is written back to config.toml through the surgical comment-preserving
// writer, so the user's hand-authored file keeps its comments and ordering.

import SwiftUI
import AppKit
import ZTCore

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
            let tokens = ModGlyph.tokens(from: ev.modifierFlags)
            guard !tokens.isEmpty, !key.isEmpty else { return nil }   // need a modifier+key
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

struct KeybindEditorView: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var recorder = ChordRecorder()
    @State private var note: String?

    private struct Row: Identifiable { let id: String; let label: String; let section: String; let key: String }

    private let rows: [Row] = [
        .init(id: "resize_mode", label: "Resize mode", section: "tiler.hotkeys", key: "resize_mode"),
        .init(id: "placement_mode", label: "Move to next monitor", section: "tiler.hotkeys", key: "placement_mode"),
        .init(id: "zone_info", label: "Move to previous monitor", section: "tiler.hotkeys", key: "zone_info"),
        .init(id: "focus_next_screen", label: "Focus next screen", section: "tiler.hotkeys", key: "focus_next_screen"),
        .init(id: "focus_prev_screen", label: "Focus previous screen", section: "tiler.hotkeys", key: "focus_prev_screen"),
        .init(id: "pom_enable", label: "Pomodoro start", section: "pomodoro.hotkeys", key: "enable"),
        .init(id: "pom_disable", label: "Pomodoro pause/reset", section: "pomodoro.hotkeys", key: "disable"),
        .init(id: "pom_reset", label: "Pomodoro reset count", section: "pomodoro.hotkeys", key: "reset"),
        .init(id: "window_hints", label: "Window hints", section: "system_hotkeys", key: "window_hints"),
        .init(id: "activity_monitor", label: "Activity Monitor", section: "system_hotkeys", key: "activity_monitor"),
        .init(id: "reload", label: "Reload config", section: "system_hotkeys", key: "reload"),
    ]

    private var aliasNames: [String] { model.config.aliases.keys.sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modifierRow("Tile modifier", key: "modifier", current: model.config.tilerModifier)
            modifierRow("Focus modifier", key: "focus_modifier", current: model.config.focusModifier)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { row in hotkeyRow(row) }
                }
            }
            if let note { Text(note).font(.caption).foregroundColor(.secondary) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            recorder.onCapture = { tokens, key in
                // The recorder's active row id is captured at start(); resolve it here.
                guard let id = pendingRowID else { return }
                guard let alias = Keybinding.alias(forModifiers: tokens, aliases: model.config.aliases) else {
                    note = "\(ModGlyph.string(tokens))\(key.uppercased()) isn't a known modifier set — use one of: \(aliasNames.joined(separator: ", "))"
                    return
                }
                if let row = rows.first(where: { $0.id == id }) {
                    model.setHotkey(section: row.section, key: row.key, alias: alias, keyName: key)
                    note = "\(row.label) → \(ModGlyph.string(tokens))\(key.uppercased())"
                }
                pendingRowID = nil
            }
        }
        .padding(.vertical, 4)
    }

    @State private var pendingRowID: String?

    private func modifierRow(_ label: String, key: String, current: [String]) -> some View {
        HStack {
            Text(label).frame(width: 160, alignment: .trailing)
            Picker("", selection: Binding(
                get: { Keybinding.alias(forModifiers: current, aliases: model.config.aliases) ?? (aliasNames.first ?? "mash") },
                set: { model.setModifierAlias(key: key, alias: $0) })) {
                ForEach(aliasNames, id: \.self) { Text("\($0)  \(ModGlyph.string(model.config.aliases[$0] ?? []))").tag($0) }
            }.labelsHidden().frame(width: 200)
            Spacer()
        }
    }

    private func hotkeyRow(_ row: Row) -> some View {
        let value = model.hotkeyValue(section: row.section, key: row.key)
        let isRecording = recorder.recordingKey == row.id
        return HStack {
            Text(row.label).frame(width: 220, alignment: .trailing)
            Text(isRecording ? "press a chord…" : ModGlyph.chord(value, aliases: model.config.aliases))
                .font(.system(.body, design: .monospaced))
                .frame(width: 110, alignment: .leading)
                .foregroundColor(isRecording ? .accentColor : .primary)
            Button(isRecording ? "Cancel" : "Record") {
                if isRecording { recorder.stop() }
                else { pendingRowID = row.id; recorder.start(id: row.id) }
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Visual layout editor

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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Grid", selection: $grid) { ForEach(gridNames, id: \.self) { Text($0).tag($0) } }
                    .frame(width: 160).onChange(of: grid) { _ in syncZone() }
                Picker("Zone", selection: $zone) { ForEach(zoneKeys, id: \.self) { Text($0).tag($0) } }
                    .frame(width: 120).onChange(of: zone) { _ in loadTiles() }
                Spacer()
            }
            HStack(alignment: .top, spacing: 20) {
                gridView
                tileList
            }
            Text("Click a cell, then another to span a rectangle. Add to append it to the zone's cycle.")
                .font(.caption).foregroundColor(.secondary)
            if let err = model.lastWriteError { Text(err).font(.caption).foregroundColor(.red) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { if grid.isEmpty { grid = gridNames.first ?? ""; syncZone() } }
        .padding(.vertical, 4)
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

    private var tileList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tiles (cycle order)").font(.subheadline).bold()
            ForEach(tiles.indices, id: \.self) { i in
                HStack {
                    Image(systemName: selectedTile == i ? "largecircle.fill.circle" : "circle")
                        .foregroundColor(.accentColor)
                    Text(tiles[i]).font(.system(.body, design: .monospaced))
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedTile = i }
            }
            HStack(spacing: 8) {
                Button("Add") { addPending() }.disabled(pending == nil)
                Button("Remove") { removeSelected() }.disabled(selectedTile == nil)
                Button("Save") { save() }
            }.padding(.top, 4)
        }.frame(width: 200, alignment: .leading)
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
