// DockPreviewsTab.swift — the "Dock Previews" settings pane (Wave 4). Enables the DockDoor-style
// hover previews and sets the per-window thumbnail size. Opt-in, off by default.

import SwiftUI

struct DockPreviewsTab: View {
    static let searchKeywords: [String] = [
        "dock", "previews", "hover", "window thumbnails", "dock previews", "thumbnail size",
        "preview size", "dockdoor", "peek", "raise window"]
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            ToggleSection("Dock hover previews", isOn: Binding(
                get: { model.config.dockPreviewsEnabled }, set: { model.setDockPreviewsEnabled($0) }),
                footer: "Hover a Dock icon to see live thumbnails of that app's windows; click one to "
                    + "bring it forward. Works at any Dock position, including auto-hidden. Reads the "
                    + "Dock layout once and caches it, so it stays light on Accessibility calls. Off by default.") {
                Stepper("Thumbnail width: \(model.config.dockPreviewWidth) pt",
                        value: Binding(get: { model.config.dockPreviewWidth },
                                       set: { model.setDockPreviewWidth($0) }),
                        in: 120...420, step: 20)
            }
        }
        .formStyle(.grouped)
    }
}
