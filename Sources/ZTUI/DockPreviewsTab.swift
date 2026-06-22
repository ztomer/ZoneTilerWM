// DockPreviewsTab.swift — the "Dock Previews" settings pane (Wave 4). Enables the DockDoor-style
// hover previews, sets the per-window thumbnail size with a slider, and shows a LIVE dynamic preview
// of the panel (so the user sees exactly what they'll get, including the per-window traffic lights).

import SwiftUI
import ZTSystem

struct DockPreviewsTab: View {
    static let searchKeywords: [String] = [
        "dock", "previews", "hover", "window thumbnails", "dock previews", "thumbnail size",
        "preview size", "dockdoor", "peek", "raise window", "traffic lights", "close", "minimize", "fullscreen"]
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            ToggleSection("Dock hover previews", isOn: Binding(
                get: { model.config.dockPreviewsEnabled }, set: { model.setDockPreviewsEnabled($0) }),
                footer: "Hover a Dock icon to see live thumbnails of that app's windows. Click a thumbnail "
                    + "to bring that window forward, or use its traffic-light buttons to close, minimize, or "
                    + "full-screen it. Works at any Dock position, including auto-hidden. Off by default.") {
                SliderRow(label: "Thumbnail width", value: Binding(
                    get: { model.config.dockPreviewWidth },
                    set: { model.setDockPreviewWidth($0) }), range: 120...420, step: 20, suffix: "pt")
            }

            Section("Preview") {
                Text("This is how a window preview looks at the current size:")
                    .font(.caption).foregroundColor(.secondary)
                HStack { Spacer(); DockPreviewMock(width: CGFloat(model.config.dockPreviewWidth)); Spacer() }
                    .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
    }
}

/// A static SwiftUI mock of the live Dock-preview panel — the dark card + app name + one window
/// thumbnail (with hover traffic lights + title) at the chosen width. Lets the settings pane show
/// "what you'll get" without a live capture.
struct DockPreviewMock: View {
    let width: CGFloat
    private var thumbH: CGFloat { (width * 0.6).rounded() }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Arc").font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.92))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12)))
                    .overlay(Image(systemName: "macwindow").font(.system(size: width * 0.16))
                        .foregroundColor(.white.opacity(0.18)))
                HStack(spacing: 5) {                                  // the per-window traffic lights
                    Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 9, height: 9)
                    Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 9, height: 9)
                    Circle().fill(Color(red: 0.31, green: 0.79, blue: 0.31)).frame(width: 9, height: 9)
                }
                .padding(7)
            }
            .frame(width: width, height: thumbH)
            Text("(2) Home / X").font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                .frame(width: width, alignment: .center)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.10)))
    }
}
