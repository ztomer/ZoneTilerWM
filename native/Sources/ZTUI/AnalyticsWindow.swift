// AnalyticsWindow.swift — the learned-placement analytics, opened from the menubar (not a
// setting). A zone-usage heatmap on the keyboard layout plus the full detail table. Read-only.

import AppKit
import SwiftUI
import ZTCore

public struct AnalyticsView: View {
    @ObservedObject var model: SettingsModel
    @State private var monitor = "all"
    public init(model: SettingsModel) { self.model = model }

    private var monitorFilter: String? { monitor == "all" ? nil : monitor }
    private var usage: [String: Int] { model.zoneUsage(monitor: monitorFilter) }
    private var maxCount: Int { max(usage.values.max() ?? 1, 1) }
    private func displayKey(_ k: String) -> String { k.count == 1 ? k.uppercased() : k }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Zone usage heatmap").font(.headline)
                Spacer()
                if !model.monitorsInData.isEmpty {
                    Picker("", selection: $monitor) {
                        Text("All monitors").tag("all")
                        ForEach(model.monitorsInData, id: \.self) { Text("Monitor \($0)").tag($0) }
                    }.labelsHidden().frame(width: 160)
                }
            }
            Text("How often windows have landed in each zone (learned over time). Hotter = more used.")
                .font(.caption).foregroundColor(.secondary)
            heatmap
            Divider()
            Text("Detail — \(model.preferences.count) learned placements").font(.headline)
            Table(model.preferences) {
                TableColumn("App") { Text($0.app.isEmpty ? "—" : $0.app) }.width(min: 120, ideal: 170)
                TableColumn("Monitor") { Text($0.monitor) }.width(min: 56, ideal: 64, max: 80)
                TableColumn("Zone") { Text($0.zone) }.width(min: 44, ideal: 52, max: 70)
                TableColumn("Tile") { Text($0.tile) }.width(min: 40, ideal: 48, max: 64)
                TableColumn("Count") { Text("\($0.count)") }.width(min: 56, ideal: 70, max: 90)
            }
            .frame(minHeight: 220)
        }
        .padding()
        .frame(minWidth: 580, minHeight: 560)
    }

    private var heatmap: some View {
        VStack(spacing: 4) {
            ForEach(model.keyboardRows.indices, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(model.keyboardRows[r], id: \.self) { key in cell(key) }
                }
            }
        }
    }

    private func cell(_ key: String) -> some View {
        let count = usage[key] ?? 0
        let intensity = count > 0 ? Double(count) / Double(maxCount) : 0
        return VStack(spacing: 1) {
            Text(displayKey(key)).font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(count > 0 ? .primary : .secondary.opacity(0.5))
            Text(count > 0 ? "\(count)" : "").font(.system(size: 8)).foregroundColor(.secondary)
        }
        .frame(width: 52, height: 38)
        .background(RoundedRectangle(cornerRadius: 5)
            .fill(count > 0 ? Color.accentColor.opacity(0.12 + 0.78 * intensity) : Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2)))
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
        w.setContentSize(NSSize(width: 620, height: 620))
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
