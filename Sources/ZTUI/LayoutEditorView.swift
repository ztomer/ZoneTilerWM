// LayoutEditorView.swift — the visual zone/grid editor (monitors, keycap zone previews, cell-grid
// selection, cycle list). Split out of EditorViews.swift to keep files focused. Shares SectionCard.

import SwiftUI
import AppKit
import ZTCore
import ZTSystem

struct LayoutEditorView: View {
    /// Search terms for the titlebar settings search (keep in sync with this pane's controls).
    static let searchKeywords: [String] = ["grid", "edit grid", "monitor", "monitors", "zones", "edit zones", "tiles", "cycle order", "cells", "default zone per app"]
    @ObservedObject var model: SettingsModel
    /// The default-zone-per-app section moves to the Tiles → Advanced tab; hide it here so it isn't shown twice.
    var showDefaultZones = true
    /// Zone HUD + drag-to-snap render here (they belong with zones, not in Advanced).
    var showInteractive = false
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
                ZoneTilePrimer()                          // convey the zone-vs-tile mental model first (feedback 6)
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
                            .frame(maxWidth: .infinity, alignment: .center)   // centre the cell-grid + cycle editor
                        Text("Click a cell, then another to span a rectangle. Add appends it to the zone's cycle; Save writes config.toml.")
                            .font(.caption).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                if showInteractive { zoneHUDCard; dragSnapCard }   // HUD + drag-snap belong WITH zones
                if showDefaultZones { SectionCard(title: "Default zone per app") { DefaultZonesSection(model: model) } }
                if let err = model.lastWriteError { Text(err).font(.caption).foregroundColor(.red) }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { if grid.isEmpty { grid = model.monitors.first?.effective ?? gridNames.first ?? ""; syncZone() } }
    }

    // The zone picker (HUD) + drag-to-snap — interactive zone features (not "advanced"). The preview
    // shows even when the toggle is off, so you can see what you'd get.
    private var zoneHUDCard: some View {
        SectionCard(title: "Zone picker (HUD)") {
            Toggle("Show the zone picker while you hold the modifier", isOn: boolBind(model, \.zoneHUDEnabled, model.setZoneHUDEnabled))
                .toggleStyle(.switch)
            ShortcutLine(lead: "Hold", tokens: model.config.tilerModifier, trail: "to show each zone's key, then tap one.")
            HStack { Spacer(); ZoneHUDPreview(); Spacer() }.padding(.top, 2)
            if model.config.zoneHUDEnabled {
                Stepper("Hold delay: \(model.config.zoneHUDHoldDelayMs) ms", value: Binding(
                    get: { model.config.zoneHUDHoldDelayMs }, set: { model.setZoneHUDHoldDelay($0) }),
                    in: 120...2000, step: 20).frame(maxWidth: 280)
            }
        }
    }

    private var dragSnapCard: some View {
        SectionCard(title: "Drag-to-snap") {
            Toggle("Drag a window with the modifier held to snap it", isOn: boolBind(model, \.dragSnapEnabled, model.setDragSnapEnabled))
                .toggleStyle(.switch)
            ShortcutLine(lead: "Hold", tokens: model.config.tilerModifier, trail: "while dragging; drop to snap to the zone under the cursor.")
            HStack { Spacer(); DragSnapPreview(); Spacer() }.padding(.top, 2)
        }
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
        .frame(maxWidth: .infinity, alignment: .center)   // centre the keyboard grid (matches the cell-grid below)
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
