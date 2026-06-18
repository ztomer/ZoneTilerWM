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
    @State private var minCount = 1             // hide apps below this many placements (long-tail noise)
    @State private var sortOrder = [KeyPathComparator(\SettingsModel.Pref.count, order: .reverse)]
    public init(model: SettingsModel) { self.model = model }

    private var monitorFilter: String? { monitor == "all" ? nil : monitor }
    private var appFilter: String? { app == "all" ? nil : app }
    private var gridNames: [String] { model.config.zoneConfig.grids.keys.sorted() }
    private func displayKey(_ k: String) -> String { k.count == 1 ? k.uppercased() : k }

    private var filtered: [SettingsModel.Pref] {
        let base = model.preferences.filter {
            (appFilter == nil || $0.app == appFilter) && (monitorFilter == nil || $0.monitor == monitorFilter)
        }
        // Data hygiene: drop the long tail of rarely-seen apps (renamed/helper/one-off
        // processes inflate the raw app count). Only applies when not filtered to one app.
        guard minCount > 1, appFilter == nil else { return base }
        let totals = Dictionary(grouping: base, by: { $0.app }).mapValues { $0.reduce(0) { $0 + $1.count } }
        return base.filter { (totals[$0.app] ?? 0) >= minCount }
    }
    private var sortedRows: [SettingsModel.Pref] { filtered.sorted(using: sortOrder) }
    /// An app's most-used zone on the current monitor filter (independent of the app filter, so
    /// every small-multiple card shows its own top zone).
    private func topZone(forApp a: String) -> String? {
        Dictionary(grouping: model.preferences.filter { $0.app == a && (monitorFilter == nil || $0.monitor == monitorFilter) },
                   by: { $0.zone })
            .mapValues { $0.reduce(0) { $0 + $1.count } }.max { $0.value < $1.value }?.key
    }
    private func intensityColor(_ count: Int, _ maxCount: Int) -> Color {
        count > 0 ? Color.accentColor.opacity(0.12 + 0.78 * (Double(count) / Double(max(maxCount, 1))))
                  : Color(NSColor.controlBackgroundColor)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title + filters sit in the transparent titlebar band, aligned with the close
            // button (which floats at the left). See AnalyticsWindowController.
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
            .padding(.leading, 80).padding(.trailing, 16)
            .frame(height: 38)

            VStack(alignment: .leading, spacing: 12) {
                summary
                HStack {
                    Picker("", selection: $mode) {
                        Text("Screen").tag("screen")
                        Text("Keyboard").tag("keyboard")
                        Text("By app").tag("apps")
                        Text("Trend").tag("trend")
                    }.pickerStyle(.segmented).frame(width: 300).labelsHidden()
                    if mode == "screen" || mode == "apps" {
                        Text("Grid").foregroundColor(.secondary)
                        Picker("", selection: $grid) { ForEach(gridNames, id: \.self) { Text($0).tag($0) } }
                            .labelsHidden().frame(width: 90)
                    }
                    Toggle("Recency", isOn: $recency).toggleStyle(.switch).fixedSize()
                        .help("Weight recent placements higher (2-week half-life)")
                    if appFilter == nil {
                        Stepper(value: $minCount, in: 1...50) { Text("min \(minCount)") }
                            .help("Hide apps with fewer than this many placements (trims rarely-seen / helper apps)")
                            .fixedSize()
                    }
                    Spacer()
                }
                Text(mode == "screen" ? "Where windows land on screen (hotter = more used)."
                     : mode == "keyboard" ? "Which zone keys windows land in."
                     : mode == "trend" ? "Placements per day (last 30 days)."
                     : "Each app's placement footprint — tap one to filter.")
                    .font(.caption).foregroundColor(.secondary)

                if model.preferences.isEmpty {
                    emptyState("No placements learned yet.",
                               "Tile some windows and ZoneTilerWM will start learning where you put each app.")
                } else {
                    // Fixed-height visual area so the detail table below stays put across modes.
                    Group {
                        switch mode {
                        case "keyboard": keyboardHeatmap
                        case "apps": smallMultiples
                        case "trend": trendView
                        default: spatialHeatmap
                        }
                    }
                    .frame(height: 300, alignment: .top)
                    Divider()
                    Text("Detail — \(filtered.count.formatted()) learned patterns\(appFilter.map { " · \($0)" } ?? "")").font(.headline)
                    if filtered.isEmpty {
                        Text("Nothing matches this filter — lower “min” or clear the app/monitor filter.")
                            .font(.callout).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                    } else {
                        Table(sortedRows, sortOrder: $sortOrder) {
                            TableColumn("App", value: \.app) { Text($0.app.isEmpty ? "—" : $0.app) }.width(min: 120, ideal: 170)
                            TableColumn("Monitor", value: \.monitor) { Text("Mon \($0.monitor)") }.width(min: 56, ideal: 72, max: 90)
                            TableColumn("Zone", value: \.zone) { Text(displayKey($0.zone)) }.width(min: 44, ideal: 52, max: 70)
                            TableColumn("Tile", value: \.tile) { Text($0.tile) }.width(min: 40, ideal: 48, max: 60)
                            TableColumn("Shape", value: \.meanAR) { Text($0.meanAR > 0 ? String(format: "%.2f", $0.meanAR) : "—") }
                                .width(min: 50, ideal: 58, max: 72)
                            TableColumn("Count", value: \.count) { Text($0.count.formatted()) }.width(min: 60, ideal: 76, max: 96)
                        }
                        .frame(minHeight: 200)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(minWidth: 620, idealWidth: 680, minHeight: 640)
        .ignoresSafeArea(.container, edges: .top)   // draw the header into the titlebar band
        .onAppear { if grid.isEmpty { grid = gridNames.last ?? "" } }   // default to the richest grid
    }

    private var summary: some View {
        let total = filtered.reduce(0) { $0 + $1.count }
        let patterns = filtered.count
        let appCount = Set(filtered.filter { !$0.app.isEmpty }.map { $0.app }).count
        let topZone = Dictionary(grouping: filtered, by: { $0.zone })
            .mapValues { $0.reduce(0) { $0 + $1.count } }.max { $0.value < $1.value }?.key
        let topApp = Dictionary(grouping: filtered.filter { !$0.app.isEmpty }, by: { $0.app })
            .mapValues { $0.reduce(0) { $0 + $1.count } }.max { $0.value < $1.value }?.key
        let byMon = Dictionary(grouping: filtered, by: { $0.monitor })
            .mapValues { $0.reduce(0) { $0 + $1.count } }
        let busiest = byMon.max { $0.value < $1.value }
        // Concentration: share of placements in the top 3 zones (focused vs spread-out habits).
        let zoneTotals = Dictionary(grouping: filtered, by: { $0.zone }).mapValues { $0.reduce(0) { $0 + $1.count } }
        let top3 = zoneTotals.values.sorted(by: >).prefix(3).reduce(0, +)
        // Layout in an even grid so the tiles line up regardless of how many show.
        return HStack(alignment: .top, spacing: 28) {
            stat(total.formatted(), "placements")
            stat(patterns.formatted(), "patterns")
            if appFilter == nil { stat(appCount.formatted(), appCount == 1 ? "app" : "apps") }
            if let topZone { stat(displayKey(topZone), "top zone") }
            if appFilter == nil, let topApp { stat(topApp, "top app") }
            if total > 0 { stat("\(Int((Double(top3) / Double(total) * 100).rounded()))%", "top-3 zones") }
            if byMon.count > 1, let busiest, total > 0 {
                stat("Mon \(busiest.key) · \(Int((Double(busiest.value) / Double(total) * 100).rounded()))%", "busiest")
            }
            Spacer(minLength: 0)
        }
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(.title3, design: .rounded)).bold().lineLimit(1)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .fixedSize()
    }

    private func emptyState(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.doc.horizontal").font(.system(size: 34)).foregroundColor(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func dayLabel(_ dayIndex: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: Date(timeIntervalSince1970: Double(dayIndex) * 86400))
    }

    // Trend: placements per day over the last 30 day-buckets (data accrues going forward).
    private var trendView: some View {
        let data = Array(model.dailyPlacements().suffix(30))
        let maxC = data.map { $0.count }.max() ?? 1
        let total = data.reduce(0) { $0 + $1.count }
        return Group {
            if data.isEmpty {
                emptyState("Collecting activity…",
                           "The daily trend fills in as you tile windows over the coming days.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(total.formatted()) placements over \(data.count) day\(data.count == 1 ? "" : "s")")
                        .font(.caption).foregroundColor(.secondary)
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(data, id: \.day) { d in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor.opacity(0.85))
                                .frame(height: max(2, 150 * CGFloat(d.count) / CGFloat(max(maxC, 1))))
                                .frame(maxWidth: .infinity)
                                .help("\(dayLabel(d.day)): \(d.count.formatted())")
                        }
                    }
                    .frame(height: 150)
                    HStack {
                        Text(dayLabel(data.first!.day)); Spacer(); Text(dayLabel(data.last!.day))
                    }.font(.caption2).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
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

    // Small multiples: one mini spatial heatmap per app (uniform card + grid), to compare
    // placement habits. Sorted by total usage; the per-app count is shown so the cards double
    // as a usage ranking.
    private var topApps: [(app: String, count: Int)] {
        let totals = Dictionary(grouping: model.preferences.filter { !$0.app.isEmpty }, by: { $0.app })
            .mapValues { $0.filter { monitorFilter == nil || $0.monitor == monitorFilter }.reduce(0) { $0 + $1.count } }
        return totals.filter { $0.value >= max(minCount, 1) }.sorted { $0.value > $1.value }.prefix(16).map { (app: $0.key, count: $0.value) }
    }

    private var smallMultiples: some View {
        // Fixed-width columns (not adaptive) so every card is identical and the grid is regular.
        let columns = Array(repeating: GridItem(.fixed(150), spacing: 12), count: 4)
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(topApps, id: \.app) { item in
                    let selected = app == item.app
                    VStack(spacing: 5) {
                        Text(item.app).font(.caption).fontWeight(.semibold).lineLimit(1).truncationMode(.tail)
                        miniHeatmap(app: item.app)
                        HStack(spacing: 4) {
                            Text(item.count.formatted())
                            if let tz = topZone(forApp: item.app) {
                                Text("· \(displayKey(tz))").foregroundColor(.secondary)
                            }
                        }.font(.caption2).foregroundColor(.secondary)
                    }
                    .frame(width: 150, height: 138)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor).opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.2)))
                    .contentShape(Rectangle())
                    .onTapGesture { app = (selected ? "all" : item.app) }
                    .help("\(item.app): \(item.count.formatted()) placements — tap to filter")
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 300)
    }

    /// A small, uniform footprint glyph: square cells, identical size for every app (all share
    /// the selected grid), so the cards compare cleanly with no warping.
    private func miniHeatmap(app: String) -> some View {
        let u = model.cellUsage(grid: grid, app: app, monitor: monitorFilter, recency: recency)
        let cols = max(u.cols, 1), rows = max(u.rows, 1)
        let side = min(CGFloat(22), 96 / CGFloat(cols))   // square cell, capped so wide grids still fit the card
        return VStack(spacing: 1) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 1) {
                    ForEach(0..<cols, id: \.self) { c in
                        let count = (c < u.cells.count && r < u.cells[c].count) ? u.cells[c][r] : 0
                        RoundedRectangle(cornerRadius: 2).fill(intensityColor(count, u.max))
                            .frame(width: side, height: side)
                    }
                }
            }
        }
        .frame(height: side * CGFloat(rows) + CGFloat(rows - 1))   // stable card height across grids
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
        // Same unified "appbar" chrome as Settings: transparent full-size titlebar, no title
        // text, close button only. The header row sits in the titlebar (see AnalyticsView).
        w.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true
        w.standardWindowButton(.zoomButton)?.isHidden = true
        w.setContentSize(NSSize(width: 680, height: 760))
        w.contentMinSize = NSSize(width: 620, height: 520)
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
