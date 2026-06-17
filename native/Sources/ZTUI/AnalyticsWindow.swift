// AnalyticsWindow.swift — the learned-placement analytics, opened from the menubar (not a
// setting). A zone-usage heatmap on the keyboard layout plus the full detail table. Read-only.

import AppKit
import SwiftUI
import ZTCore

public struct AnalyticsView: View {
    @ObservedObject var model: SettingsModel
    @State private var monitor = "all"
    @State private var app = "all"
    @State private var mode = "screen"          // "screen" (spatial cells) | "keyboard" (zone keys) | "apps"
    @State private var grid = ""
    @State private var recency = false          // weight by recency (decays stale habits)
    public init(model: SettingsModel) { self.model = model }

    private var monitorFilter: String? { monitor == "all" ? nil : monitor }
    private var appFilter: String? { app == "all" ? nil : app }
    private var gridNames: [String] { model.config.zoneConfig.grids.keys.sorted() }
    private func displayKey(_ k: String) -> String { k.count == 1 ? k.uppercased() : k }

    private var filtered: [SettingsModel.Pref] {
        model.preferences.filter { (appFilter == nil || $0.app == appFilter) && (monitorFilter == nil || $0.monitor == monitorFilter) }
    }
    private func intensityColor(_ count: Int, _ maxCount: Int) -> Color {
        count > 0 ? Color.accentColor.opacity(0.12 + 0.78 * (Double(count) / Double(max(maxCount, 1))))
                  : Color(NSColor.controlBackgroundColor)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Placement analytics").font(.headline)
                Spacer()
                Picker("", selection: $app) {
                    Text("All apps").tag("all")
                    ForEach(model.appsInData, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 170)
                if !model.monitorsInData.isEmpty {
                    Picker("", selection: $monitor) {
                        Text("All monitors").tag("all")
                        ForEach(model.monitorsInData, id: \.self) { Text("Mon \($0)").tag($0) }
                    }.labelsHidden().frame(width: 110)
                }
            }
            summary
            HStack {
                Picker("", selection: $mode) {
                    Text("Screen").tag("screen")
                    Text("Keyboard").tag("keyboard")
                    Text("By app").tag("apps")
                }.pickerStyle(.segmented).frame(width: 230).labelsHidden()
                if mode != "keyboard" {
                    Text("Grid").foregroundColor(.secondary)
                    Picker("", selection: $grid) { ForEach(gridNames, id: \.self) { Text($0).tag($0) } }
                        .labelsHidden().frame(width: 90)
                }
                Toggle("Recency", isOn: $recency).toggleStyle(.switch).help("Weight recent placements higher (2-week half-life)")
                Spacer()
                Text(mode == "screen" ? "Where windows land on screen (hotter = more used)."
                     : mode == "keyboard" ? "Which zone keys windows land in."
                     : "Each app's placement footprint — tap one to filter.")
                    .font(.caption).foregroundColor(.secondary)
            }
            switch mode {
            case "keyboard": keyboardHeatmap
            case "apps": smallMultiples
            default: spatialHeatmap
            }
            Divider()
            Text("Detail — \(filtered.count) learned placements\(appFilter.map { " · \($0)" } ?? "")").font(.headline)
            Table(filtered) {
                TableColumn("App") { Text($0.app.isEmpty ? "—" : $0.app) }.width(min: 120, ideal: 170)
                TableColumn("Monitor") { Text("Mon \($0.monitor)") }.width(min: 56, ideal: 72, max: 90)
                TableColumn("Zone") { Text($0.zone) }.width(min: 44, ideal: 52, max: 70)
                TableColumn("Tile") { Text($0.tile) }.width(min: 40, ideal: 48, max: 64)
                TableColumn("Count") { Text("\($0.count)") }.width(min: 56, ideal: 70, max: 90)
            }
            .frame(minHeight: 200)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(minWidth: 600, idealWidth: 660, minHeight: 640, idealHeight: 720)   // ideal matches the window default
        .onAppear { if grid.isEmpty { grid = gridNames.last ?? "" } }   // default to the richest grid
    }

    private var summary: some View {
        let total = filtered.reduce(0) { $0 + $1.count }
        let topZone = Dictionary(grouping: filtered, by: { $0.zone })
            .mapValues { $0.reduce(0) { $0 + $1.count } }.max { $0.value < $1.value }?.key
        let topApp = Dictionary(grouping: filtered.filter { !$0.app.isEmpty }, by: { $0.app })
            .mapValues { $0.reduce(0) { $0 + $1.count } }.max { $0.value < $1.value }?.key
        return HStack(spacing: 16) {
            stat("placements", "\(total)")
            if let topZone { stat("top zone", topZone) }
            if appFilter == nil, let topApp { stat("top app", topApp) }
            Spacer()
        }
    }
    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(.title3, design: .rounded)).bold()
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }

    // Spatial: the monitor's grid cells colored by occupancy.
    private var spatialHeatmap: some View {
        let u = model.cellUsage(grid: grid, app: appFilter, monitor: monitorFilter, recency: recency)
        return VStack(spacing: 3) {
            if u.cols == 0 { Text("No grid").foregroundColor(.secondary) }
            ForEach(0..<max(u.rows, 1), id: \.self) { r in
                HStack(spacing: 3) {
                    ForEach(0..<max(u.cols, 1), id: \.self) { c in
                        let count = (c < u.cells.count && r < u.cells[c].count) ? u.cells[c][r] : 0
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(intensityColor(count, u.max))
                            RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25))
                            if count > 0 { Text("\(count)").font(.system(.caption, design: .rounded)).foregroundColor(.primary) }
                        }
                        .frame(maxWidth: .infinity).frame(height: min(84, 260 / CGFloat(max(u.rows, 1))))
                    }
                }
            }
        }
        .frame(maxWidth: 520)
    }

    // Small multiples: one mini spatial heatmap per app, to compare placement habits.
    private var topApps: [String] {
        let totals = Dictionary(grouping: model.preferences.filter { !$0.app.isEmpty }, by: { $0.app })
            .mapValues { $0.filter { monitorFilter == nil || $0.monitor == monitorFilter }.reduce(0) { $0 + $1.count } }
        return totals.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(16).map { $0.key }
    }

    private var smallMultiples: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(topApps, id: \.self) { a in
                    VStack(spacing: 5) {
                        Text(a).font(.caption).fontWeight(.semibold).lineLimit(1).truncationMode(.tail)
                        miniHeatmap(app: a)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(app == a ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor).opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(app == a ? Color.accentColor : Color.secondary.opacity(0.2)))
                    .contentShape(Rectangle())
                    .onTapGesture { app = (app == a ? "all" : a) }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 280)
    }

    private func miniHeatmap(app: String) -> some View {
        let u = model.cellUsage(grid: grid, app: app, monitor: monitorFilter, recency: recency)
        return VStack(spacing: 1) {
            ForEach(0..<max(u.rows, 1), id: \.self) { r in
                HStack(spacing: 1) {
                    ForEach(0..<max(u.cols, 1), id: \.self) { c in
                        let count = (c < u.cells.count && r < u.cells[c].count) ? u.cells[c][r] : 0
                        Rectangle().fill(intensityColor(count, u.max)).frame(width: 16, height: 13)
                    }
                }
            }
        }
    }

    // Keyboard: zone keys colored by usage.
    private var keyboardHeatmap: some View {
        let usage = model.zoneUsage(app: appFilter, monitor: monitorFilter, recency: recency)
        let maxCount = max(usage.values.max() ?? 1, 1)
        return VStack(spacing: 4) {
            ForEach(model.keyboardRows.indices, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(model.keyboardRows[r], id: \.self) { key in
                        let count = usage[key] ?? 0
                        VStack(spacing: 1) {
                            Text(displayKey(key)).font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(count > 0 ? .primary : .secondary.opacity(0.5))
                            Text(count > 0 ? "\(count)" : "").font(.system(size: 8)).foregroundColor(.secondary)
                        }
                        .frame(width: 52, height: 38)
                        .background(RoundedRectangle(cornerRadius: 5).fill(intensityColor(count, maxCount)))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2)))
                    }
                }
            }
        }
    }
}

public final class AnalyticsWindowController {
    private var window: NSWindow?
    private let model: SettingsModel
    public init(model: SettingsModel) { self.model = model }

    public func show() {
        if let window {
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let hosting = NSHostingController(rootView: AnalyticsView(model: model))
        let w = NSWindow(contentViewController: hosting)
        w.title = "ZoneTilerWM Analytics"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 660, height: 720))
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
