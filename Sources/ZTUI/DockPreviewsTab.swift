// DockPreviewsTab.swift — the "Dock Previews" settings pane (Wave 4). Enables the DockDoor-style
// hover previews, sets the per-window thumbnail size with a slider, and shows a LIVE dynamic preview
// of the panel as it actually appears — anchored to the Dock in its CURRENT position, with two
// window thumbnails (each with its own traffic lights + window title), so the user sees exactly what
// they'll get.

import SwiftUI
import ZTCore
import ZTSystem

struct DockPreviewsTab: View {
    static let searchKeywords: [String] = [
        "dock", "previews", "hover", "window thumbnails", "dock previews", "thumbnail size",
        "preview size", "dockdoor", "peek", "raise window", "traffic lights", "close", "minimize", "fullscreen"]
    @ObservedObject var model: SettingsModel

    // The Dock's current edge (read from com.apple.dock prefs — no AX), so the preview is oriented
    // the way the user's real Dock is.
    private var edge: DockEdge { DockObserver().dockEdge() }

    var body: some View {
        Form {
            // F1: the preview comes FIRST (no redundant "Preview" header/caption) — it IS the headline.
            Section {
                HStack { Spacer()
                    DockPreviewMock(width: CGFloat(model.config.dockPreviewWidth), edge: edge)
                    Spacer() }
                    .padding(.vertical, 10)
                    .listRowBackground(Color.clear)
            }

            ToggleSection("Hover previews", isOn: Binding(
                get: { model.config.dockPreviewsEnabled }, set: { model.setDockPreviewsEnabled($0) }),
                footer: "Hover a Dock icon to see live thumbnails of that app's windows. Click a thumbnail "
                    + "to bring that window forward, or use its traffic-light buttons to close, minimize, or "
                    + "full-screen it. Works at any Dock position, including auto-hidden. Off by default.") {
                SliderRow(label: "Thumbnail width", value: Binding(
                    get: { model.config.dockPreviewWidth },
                    set: { model.setDockPreviewWidth($0) }), range: 120...420, step: 20, suffix: "pt")
            }
        }
        .formStyle(.grouped)
    }
}

/// A live SwiftUI mock of the hover panel as it actually appears: the Dock strip on its current edge,
/// a hovered app tile, and the dark preview panel popping out from it with TWO window thumbnails —
/// each with its own traffic lights + window title (F2/F3). Scales with the chosen thumbnail width.
struct DockPreviewMock: View {
    let width: CGFloat
    var edge: DockEdge = .bottom

    // Cap the per-thumbnail size so two side-by-side still fit the settings pane, but keep it tracking
    // the slider so the size control visibly does something.
    private var thumbW: CGFloat { min(max(width * 0.42, 96), 168) }
    private var thumbH: CGFloat { (thumbW * 0.62).rounded() }

    // Two representative windows for the hovered app.
    private let windows = [("Inbox — Mail", "tray.full"), ("Drafts", "square.and.pencil")]

    var body: some View {
        switch edge {
        case .bottom: VStack(spacing: 10) { panel; dockStrip(horizontal: true) }
        case .left:   HStack(spacing: 10) { dockStrip(horizontal: false); panel }
        case .right:  HStack(spacing: 10) { panel; dockStrip(horizontal: false) }
        }
    }

    // The popup panel: the dark card with the two window thumbnails (no app-name header — F3).
    private var panel: some View {
        HStack(spacing: 10) {
            ForEach(windows, id: \.0) { win in thumbnail(title: win.0, glyph: win.1) }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.10)))
    }

    private func thumbnail(title: String, glyph: String) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12)))
                    .overlay(Image(systemName: glyph).font(.system(size: thumbW * 0.18))
                        .foregroundColor(.white.opacity(0.18)))
                HStack(spacing: 5) {                                  // the per-window traffic lights
                    Circle().fill(ZTPalette.trafficCloseColor).frame(width: 9, height: 9)
                    Circle().fill(ZTPalette.trafficMinimizeColor).frame(width: 9, height: 9)
                    Circle().fill(ZTPalette.trafficFullscreenColor).frame(width: 9, height: 9)
                }
                .padding(7)
            }
            .frame(width: thumbW, height: thumbH)
            // F3: the WINDOW title (not the app name, which the Dock icon already tells you).
            Text(title).font(.system(size: 10)).foregroundColor(.white.opacity(0.7))
                .lineLimit(1).truncationMode(.tail).frame(width: thumbW, alignment: .center)
        }
    }

    // A short slice of the Dock on the correct edge, with the hovered tile highlighted.
    @ViewBuilder
    private func dockStrip(horizontal: Bool) -> some View {
        let tiles = ["safari", "envelope", "message", "music.note", "folder"]
        let hovered = 1   // the Mail tile, matching the windows mocked above
        let content = ForEach(Array(tiles.enumerated()), id: \.offset) { i, sym in
            RoundedRectangle(cornerRadius: 7)
                .fill(i == hovered ? ZTPalette.accentColor.opacity(0.28) : Color.white.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(i == hovered ? ZTPalette.accentColor : Color.white.opacity(0.15)))
                .overlay(Image(systemName: sym).font(.system(size: 16)).foregroundColor(.white.opacity(0.8)))
                .frame(width: 30, height: 30)
        }
        Group {
            if horizontal { HStack(spacing: 8) { content } } else { VStack(spacing: 8) { content } }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.10)))
    }
}
