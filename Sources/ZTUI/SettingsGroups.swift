// SettingsGroups.swift — the v4 sidebar group containers. The Settings window moved from a row of
// top segmented tabs to a sidebar (NavigationSplitView, see SettingsView). Each group is a Form
// composing the same section-emitting views and setters as before, just re-bucketed into the v4
// taxonomy the user asked for:
//   General · Tiling · Layouts · Keys · Input & Output · App Launcher · Pomodoro · Appearance ·
//   Automation · Advanced
// The old "Features" catch-all tab is dissolved: its sections live with the feature they configure
// (Zone HUD / drag-snap → Tiling, focus-follows-mouse → I/O, break screen → Pomodoro, command
// palette + on-device AI → Automation, scratchpad → App Launcher).

import SwiftUI
import AppKit
import ZTCore
import ZTSystem

// MARK: - small shared helpers

/// A muted caption line (the same style the dissolved FeaturesTab used).
private func caption(_ s: String) -> some View { Text(s).font(.caption).foregroundColor(.secondary) }

private func splitList(_ s: String) -> [String] {
    s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

/// Resolved tiling-modifier glyphs (e.g. "⌃⌘") for "hold X" trigger hints.
func tilingGlyphs(_ model: SettingsModel) -> String { ModGlyph.string(model.config.tilerModifier) }

/// A Form section whose enable toggle lives IN the header (instead of a row that just restates the
/// title), with the explanation as a footer rather than a header-duplicating caption. Extra controls
/// go in `content` and are typically only built when `isOn`.
struct ToggleSection<Content: View>: View {
    let title: String
    @Binding var isOn: Bool
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    init(_ title: String, isOn: Binding<Bool>, footer: String? = nil,
         @ViewBuilder content: @escaping () -> Content = { EmptyView() }) {
        self.title = title; self._isOn = isOn; self.footer = footer; self.content = content
    }

    var body: some View {
        // The toggle is the section's first row (its de-facto header) — one label for the feature,
        // no duplicate title row or header-restating caption. (A Toggle in a Section `header:` does
        // not reliably reflect its bound state, so it lives in the body.)
        Section {
            Toggle(isOn: $isOn) { Text(title).font(.body.weight(.semibold)) }
                .toggleStyle(.switch)
            content()
        } footer: {
            if let footer { Text(footer).font(.caption).foregroundColor(.secondary) }
        }
    }
}

/// Bool binding from a config keypath + a model setter (the common toggle wiring).
func boolBind(_ model: SettingsModel, _ keyPath: KeyPath<ConfigLoader.LoadedConfig, Bool>,
              _ setter: @escaping (Bool) -> Void) -> Binding<Bool> {
    Binding(get: { model.config[keyPath: keyPath] }, set: { setter($0) })
}

private func miniBadge(icon: String, key: String, name: String, color: Color) -> some View {
    HStack(spacing: 5) {
        Image(systemName: icon)
            .font(.system(size: 11))
            .foregroundColor(.black)
        Text(key)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundColor(.black)
        if !name.isEmpty {
            Text(name)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.black.opacity(0.7))
        }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .background(color)
    .cornerRadius(5)
    .overlay(
        RoundedRectangle(cornerRadius: 5)
            .stroke(Color.black.opacity(0.85), lineWidth: 1)
    )
}

struct WindowHintsPreview: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Screen Background
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            
            // Window 3 (Finder, background/center)
            mockWindow(title: "Finder", icon: "folder.fill", key: "F", badgeColor: Color(red: 0.94, green: 0.94, blue: 0.94), showAppName: true)
                .frame(width: 170, height: 110)
                .offset(x: 80, y: 15)

            // Window 1 (Safari, left)
            mockWindow(title: "Safari", icon: "safari", key: "S", badgeColor: Color(red: 0.85, green: 0.92, blue: 0.97), showAppName: true)
                .frame(width: 180, height: 130)
                .offset(x: 15, y: 40)

            // Window 2 (Terminal, right)
            mockWindow(title: "Terminal", icon: "terminal", key: "T", badgeColor: Color(red: 0.85, green: 0.95, blue: 0.88), showAppName: true)
                .frame(width: 180, height: 120)
                .offset(x: 135, y: 65)
        }
        .frame(width: 330, height: 200)
    }

    private func mockWindow(title: String, icon: String, key: String, badgeColor: Color, showAppName: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(white: 0.22).opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .overlay(
                VStack(spacing: 0) {
                    // Title Bar
                    HStack(spacing: 4) {
                        Circle().fill(Color.red.opacity(0.7)).frame(width: 6, height: 6)
                        Circle().fill(Color.yellow.opacity(0.7)).frame(width: 6, height: 6)
                        Circle().fill(Color.green.opacity(0.7)).frame(width: 6, height: 6)
                        Spacer()
                        Text(title)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Color.white.opacity(0.04))
                    
                    Spacer()
                    
                    // Central Badge
                    miniBadge(icon: icon, key: key, name: showAppName ? title : "", color: badgeColor)
                        .padding(.bottom, 12)
                    
                    Spacer()
                }
            )
            .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
    }
}

/// Live preview of the Zone HUD: holding the tiling modifier overlays each zone's key where pressing
/// it lands the window. Mirrors `ZoneHUD.layout` on the default y/u/i/o · h/j/k/l · n/m/,/. grid.
struct ZoneHUDPreview: View {
    private let rows = [["y", "u", "i", "o"], ["h", "j", "k", "l"], ["n", "m", ",", "."]]
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
            VStack(spacing: 6) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 6) { ForEach(row, id: \.self) { cell($0) } }
                }
            }
            .padding(12)
        }
        .frame(width: 330, height: 200)
    }
    private func cell(_ key: String) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.black.opacity(0.32))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.55), lineWidth: 1))
            .overlay(Text(key.uppercased()).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundColor(.accentColor))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Preview of the retro Pomodoro break overlay — near-black with CRT scanlines and an amber
/// monospace headline, mirroring `BreakScreenOverlay` (amber 0.98/0.70/0.20, 3px scanlines).
struct BreakScreenPreview: View {
    private let amber = Color(red: 0.98, green: 0.70, blue: 0.20)
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.92))
            Canvas { ctx, size in
                var y = 0.0
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(0.05)))
                    y += 3
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(spacing: 8) {
                Text("BREAK").font(.system(size: 46, weight: .bold, design: .monospaced))
                    .foregroundColor(amber).kerning(6).shadow(color: amber.opacity(0.6), radius: 8)
                Text("STEP AWAY FROM THE SCREEN").font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(amber.opacity(0.75)).kerning(3)
            }
        }
        .frame(width: 330, height: 200)
        .overlay(alignment: .bottom) {
            Text("click to dismiss").font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.45)).kerning(2).padding(.bottom, 10)
        }
    }
}

/// Preview of drag-to-snap: a window mid-drag over a highlighted target zone (left half), so the
/// "drop here → snaps to this zone" behaviour reads at a glance. Mirrors the live drop highlight.
struct DragSnapPreview: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
            // Target zone (left half) lit up as the drop target.
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.22))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2))
                Color.clear
            }
            .padding(12)
            // The window being dragged, overlapping the target, with a cursor.
            RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.24))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.25), lineWidth: 1))
                .overlay(alignment: .top) {
                    HStack(spacing: 4) {
                        Circle().fill(.red.opacity(0.7)).frame(width: 6, height: 6)
                        Circle().fill(.yellow.opacity(0.7)).frame(width: 6, height: 6)
                        Circle().fill(.green.opacity(0.7)).frame(width: 6, height: 6)
                        Spacer()
                    }.padding(6)
                }
                .frame(width: 130, height: 88)
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                .offset(x: -8, y: 6)
            Image(systemName: "cursorarrow").font(.system(size: 18))
                .foregroundColor(.white).shadow(radius: 2).offset(x: 36, y: 34)
        }
        .frame(width: 330, height: 200)
    }
}

/// Preview of the ⌘K command palette — a search field over a few matched result rows (first
/// selected), mirroring `CommandPaletteController` (dark card, accent-highlighted selection).
struct CommandPalettePreview: View {
    private let rows: [(icon: String, name: String)] = [
        ("rectangle.lefthalf.inset.filled", "Tile · left half"),
        ("squares.below.rectangle", "Auto-tile screen"),
        ("speaker.wave.2", "Switch audio output"),
        ("arrow.up.left.and.arrow.down.right", "Zen mode"),
    ]
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                Text("tile h · zen · “put terminal left”").foregroundColor(.secondary).lineLimit(1)
                Spacer()
                Text("⌘K").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.white.opacity(0.08)).cornerRadius(4)
            }
            .font(.system(size: 15)).padding(12)
            Divider().opacity(0.5)
            VStack(spacing: 2) {
                ForEach(rows.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        Image(systemName: rows[i].icon).frame(width: 16).foregroundColor(i == 0 ? .accentColor : .secondary)
                        Text(rows[i].name).foregroundColor(i == 0 ? .primary : .secondary)
                        Spacer()
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(i == 0 ? Color.accentColor.opacity(0.28) : .clear)
                    .cornerRadius(6)
                }
            }
            .padding(8)
            Divider().opacity(0.5)
            Text("↑↓ select · ⏎ run · ⎋ close").font(.system(size: 10))
                .foregroundColor(.secondary).padding(7)
        }
        .frame(width: 330)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.16)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

/// Live preview of the menu-bar Spaces widget + a bracket-style selector (each option IS a preview of
/// how the widget looks in that style, rendered on a simulated menu-bar background).
struct MenubarBracketPicker: View {
    @ObservedObject var model: SettingsModel

    private func image(_ style: SpacesMenubarRenderer.BracketStyle) -> NSImage {
        let groups = [
            SpacesMenubar.InputGroup(monitorLabel: "A", spaces: [.init(label: "1", isCurrent: true), .init(label: "2", isCurrent: false)]),
            SpacesMenubar.InputGroup(monitorLabel: "B", spaces: [.init(label: "1", isCurrent: true)]),
        ]
        let layout = SpacesMenubar.layout(groups, showGlyph: false)
        return SpacesMenubarRenderer.image(layout, template: true, showGlyph: false, bracket: style)
    }

    private func chip(_ style: SpacesMenubarRenderer.BracketStyle, selected: Bool) -> some View {
        let img = image(style)
        return VStack(spacing: 5) {
            Image(nsImage: img).renderingMode(.template).interpolation(.high).foregroundStyle(.white)
                .frame(width: img.size.width, height: 22)
                .padding(.horizontal, 7).padding(.vertical, 5)
                .background(Color(white: 0.14))   // simulate the menu bar
                .cornerRadius(5)
            Text(style.rawValue.capitalized).font(.caption2).foregroundColor(selected ? .accentColor : .secondary)
        }
        .padding(6)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
    }

    var body: some View {
        let current = model.spacesMenubarBracketChoice
        VStack(alignment: .leading, spacing: 6) {
            Text("Bracket style (click a preview)").foregroundColor(.secondary).font(.caption)
            HStack(spacing: 10) {
                ForEach(SpacesMenubarRenderer.BracketStyle.allCases, id: \.rawValue) { style in
                    Button { model.setSpacesMenubarBracket(style.rawValue) } label: {
                        chip(style, selected: current == style.rawValue)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct ExposePreview: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let pos = model.exposeSpacesBarPositionChoice
        let dx: CGFloat = (pos == "left" ? 35 : (pos == "right" ? -35 : 0))
        let dy: CGFloat = (pos == "top" ? 25 : (pos == "bottom" ? -25 : 0))

        ZStack(alignment: .topLeading) {
            // Wallpaper Background
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.16, blue: 0.24), Color(red: 0.05, green: 0.07, blue: 0.12)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

            // Grid zones representation
            Path { path in
                // Horizontal splitter
                path.move(to: CGPoint(x: 0, y: 135 + dy))
                path.addLine(to: CGPoint(x: 330, y: 135 + dy))
                // Vertical splitter
                path.move(to: CGPoint(x: 165 + dx, y: pos == "top" ? 40 : 0))
                path.addLine(to: CGPoint(x: 165 + dx, y: pos == "bottom" ? 160 : 200))
            }
            .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 1.5, dash: [4]))

            // Exposed Window 1 (Safari, left zone)
            mockExposedWindow(title: "Safari", icon: "safari", key: "S", badgeColor: Color(red: 0.85, green: 0.92, blue: 0.97))
                .frame(width: 130, height: 95)
                .offset(x: 20 + dx, y: 20 + dy)

            // Exposed Window 2 (Terminal, right zone)
            mockExposedWindow(title: "Terminal", icon: "terminal", key: "T", badgeColor: Color(red: 0.85, green: 0.95, blue: 0.88))
                .frame(width: 130, height: 95)
                .offset(x: 180 + dx, y: 20 + dy)

            // Exposed Window 3 (Finder, center/bottom zone)
            mockExposedWindow(title: "Finder", icon: "folder.fill", key: "F", badgeColor: Color(red: 0.94, green: 0.94, blue: 0.94))
                .frame(width: 180, height: 45)
                .offset(x: 75 + dx, y: 145 + dy)

            // Spaces Bar overlay
            mockSpacesBar(position: pos)
        }
        .frame(width: 330, height: 200)
        .clipped()   // keep the preview inside its card (the position offset could push tiles out)
    }

    private func mockSpacesBar(position: String) -> some View {
        let isVertical = (position == "left" || position == "right")
        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.45))
            
            if isVertical {
                VStack(spacing: 8) {
                    mockTinyDesktop(isSelected: true, label: "1")
                    mockTinyDesktop(isSelected: false, label: "2")
                }
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 8) {
                    mockTinyDesktop(isSelected: true, label: "1")
                    mockTinyDesktop(isSelected: false, label: "2")
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(
            width: isVertical ? 60 : 330,
            height: isVertical ? 200 : 40
        )
        .offset(
            x: position == "right" ? 270 : 0,
            y: position == "bottom" ? 160 : 0
        )
    }

    private func mockTinyDesktop(isSelected: Bool, label: String) -> some View {
        Text(label)
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(isSelected ? .blue : .secondary)
            .frame(width: 35, height: 22)
            .background(Color.white.opacity(0.08))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.blue : Color.white.opacity(0.2), lineWidth: 1)
            )
    }

    private func mockExposedWindow(title: String, icon: String, key: String, badgeColor: Color) -> some View {
        ZStack(alignment: .topLeading) {
            // Window Frame
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(white: 0.18).opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .overlay(
                    VStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: 3) {
                            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.15)).frame(width: 80, height: 4)
                            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.1)).frame(width: 100, height: 4)
                            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.1)).frame(width: 60, height: 4)
                        }
                        .padding(10)
                        Spacer()
                        miniBadge(icon: icon, key: key, name: "", color: badgeColor)
                            .padding(.bottom, 6)
                    }
                )
            
            Button(action: {}) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.9))
                        .frame(width: 14, height: 14)
                    Image(systemName: "xmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .buttonStyle(.plain)
            .offset(x: -5, y: -5)
        }
        .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
    }
}

struct PreviewsTab: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            // Each preview sits with the options that affect it (no shared "Settings" dump; keyboard
            // layout lives in Input & Output, not duplicated here).
            Section("Window Hints") {
                HStack { Spacer(); WindowHintsPreview(model: model); Spacer() }.padding(.vertical, 8)
                HotkeyRowView(model: model, label: "Window hints hotkey", section: "system_hotkeys", key: "window_hints")
            }

            Section("Exposé / Window Grid") {
                HStack { Spacer(); ExposePreview(model: model); Spacer() }.padding(.vertical, 8)
                HotkeyRowView(model: model, label: "Exposé / Window grid hotkey", section: "system_hotkeys", key: "expose")
                Picker("Spaces bar position", selection: Binding(
                    get: { model.exposeSpacesBarPositionChoice },
                    set: { model.setExposeSpacesBarPosition($0) })) {
                    Text("Top").tag("top"); Text("Left").tag("left")
                    Text("Right").tag("right"); Text("Bottom").tag("bottom")
                }
                Picker("Navigation keys", selection: Binding(
                    get: { model.exposeNavChoice },
                    set: { model.setExposeNav($0) })) {
                    Text("Arrows").tag("arrows"); Text("Vim (hjkl)").tag("vim"); Text("WASD").tag("wasd")
                }
                Picker("Show windows from", selection: Binding(
                    get: { model.exposeScopeChoice },
                    set: { model.setExposeScope($0) })) {
                    Text("Active monitor").tag("active"); Text("All monitors").tag("all")
                }
            }

            Section("Switching Spaces") {
                Picker("Switching method", selection: Binding(
                    get: { model.spaceSwitchMethodChoice },
                    set: { model.setSpaceSwitchMethod($0) })) {
                    Text("Auto").tag("auto")
                    Text("Keyboard shortcuts").tag("keyboard")
                    Text("Trackpad gesture").tag("gesture")
                }
                Text("All public — no private APIs, works in any build. “Keyboard shortcuts” rides your “Switch to Desktop N” shortcuts (set them up first); “Trackpad gesture” simulates a swipe (same display only); “Auto” gestures on the active display and falls back to shortcuts.")
                    .font(.caption).foregroundColor(.secondary)
                Button("Open Mission Control Shortcuts…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                }
            }

            Section("Show Spaces (menu bar + Exposé)") {
                Toggle("Show Spaces in the menu bar", isOn: Binding(
                    get: { model.spacesMenubarEnabled }, set: { model.setSpacesMenubar($0) }))
                    .disabled(!model.realSpacesEnabled)
                if model.spacesMenubarEnabled && model.realSpacesEnabled {
                    MenubarBracketPicker(model: model)
                }
                Toggle("Use real macOS Spaces (experimental)", isOn: Binding(
                    get: { model.realSpacesEnabled }, set: { model.setRealSpaces($0) }))
                Text("Switching (above) needs none of this. Showing WHICH Spaces exist, which is current, and their wallpapers reads live desktop info via private APIs — experimental, excluded from App Store builds. Off → Exposé shows the current Space only.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    .disabled(!model.launchAtLoginAvailable)
                if !model.launchAtLoginAvailable {
                    caption("Available when running the installed ZoneTilerWM.app (not the dev binary).")
                }
            }
            Section("Config") {
                LabeledContent("File") {
                    HStack(spacing: 8) {
                        Text(model.configURL.lastPathComponent).foregroundColor(.secondary)
                        Button("Reveal") { model.revealConfigInFinder() }
                        Button("Open") { model.openConfigInEditor() }
                    }
                }
                LabeledContent("Version", value: model.config.version)
            }

        }
        .formStyle(.grouped)
    }
}

// MARK: - Tiling

struct TilingTab: View {
    @ObservedObject var model: SettingsModel
    @State private var centerZonesEdit = ""

    private func commitCenterZones() {
        model.setCenterZones(splitList(centerZonesEdit))
    }

    var body: some View {
        Form {
            Section("Tiling") {
                Picker("Placement strategy", selection: Binding(
                    get: { model.config.placementStrategy },
                    set: { model.setValue(section: "tiler", key: "placement_strategy", rawValue: "\"\($0)\"") })) {
                    Text("rotate").tag("rotate")
                    Text("largest free space").tag("largest_free_space")
                    Text("hybrid").tag("hybrid")
                }
                Picker("Auto-tiling mode", selection: Binding(
                    get: { model.config.autoTilingMode },
                    set: { model.setValue(section: "tiler", key: "auto_tiling_mode", rawValue: "\"\($0)\"") })) {
                    Text("usage").tag("usage")
                    Text("session").tag("session")
                }
                NumberRow(label: "Working-set capacity", value: Binding(
                    get: { model.config.workingSetMaxCapacity },
                    set: { model.setWorkingSetCapacity($0) }), range: 1...12)
                NumberRow(label: "Working-set staleness", value: Binding(
                    get: { model.config.workingSetTimeLimit / 60 },
                    set: { model.setWorkingSetMinutes($0) }), range: 1...240, suffix: "min")
                LabeledContent("Auto-tile center zones") {
                    HStack(spacing: 8) {
                        TextField("e.g. j, center, 0", text: $centerZonesEdit).textFieldStyle(.roundedBorder)
                            .frame(width: 200).onSubmit { commitCenterZones() }
                        Button("Save") { commitCenterZones() }
                    }
                }
            }

            let mods = tilingGlyphs(model)
            ToggleSection("Zone HUD", isOn: boolBind(model, \.zoneHUDEnabled, model.setZoneHUDEnabled),
                          footer: "Hold \(mods) to show each zone's key on screen. Self-silences for quick chords.") {
                HStack { Spacer(); ZoneHUDPreview(); Spacer() }.padding(.vertical, 8)
                if model.config.zoneHUDEnabled {
                    NumberRow(label: "Hold delay", value: Binding(
                        get: { model.config.zoneHUDHoldDelayMs },
                        set: { model.setZoneHUDHoldDelay($0) }), range: 120...2000, step: 20, suffix: "ms")
                }
            }

            ToggleSection("Drag-to-snap", isOn: boolBind(model, \.dragSnapEnabled, model.setDragSnapEnabled),
                          footer: "Hold \(mods) while dragging a window; dropping it snaps to the zone under the cursor.") {
                HStack { Spacer(); DragSnapPreview(); Spacer() }.padding(.vertical, 8)
            }

            Section("Tiling Hotkeys") {
                HotkeyRowView(model: model, label: "Move to next monitor", section: "tiler.hotkeys", key: "placement_mode")
                HotkeyRowView(model: model, label: "Move to previous monitor", section: "tiler.hotkeys", key: "zone_info")
                HotkeyRowView(model: model, label: "Focus next screen", section: "tiler.hotkeys", key: "focus_next_screen")
                HotkeyRowView(model: model, label: "Focus previous screen", section: "tiler.hotkeys", key: "focus_prev_screen")
                HotkeyRowView(model: model, label: "Resize mode", section: "tiler.hotkeys", key: "resize_mode")
                HotkeyRowView(model: model, label: "Auto-tile screen", section: "tiler.hotkeys", key: "auto_tile_screen")
            }

            Section("Focus & Navigation Hotkeys") {
                HotkeyRowView(model: model, label: "Zen mode", section: "tiler.hotkeys", key: "zen_mode")
                HotkeyRowView(model: model, label: "Session sandbox", section: "system_hotkeys", key: "sandbox")
                HotkeyRowView(model: model, label: "Toggle float", section: "tiler.hotkeys", key: "float")
                HotkeyRowView(model: model, label: "Stack: focus next", section: "tiler.hotkeys", key: "stack_next")
                HotkeyRowView(model: model, label: "Stack: focus previous", section: "tiler.hotkeys", key: "stack_prev")
            }

            if let err = model.lastWriteError { Text(err).foregroundColor(.red).font(.caption) }
        }
        .formStyle(.grouped)
        .onAppear { centerZonesEdit = model.config.autoTileCenterZones.joined(separator: ", ") }
    }
}

// MARK: - Input & Output (keyboard layout, audio, focus-follows-mouse)

struct IOTab: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            Section("Keyboard") {
                Picker("Keyboard layout", selection: Binding(
                    get: { model.keyboardChoice },
                    set: { model.setKeyboardLayout($0) })) {
                    Text("Auto (\(model.detectedKeyboard))").tag("auto")
                    ForEach(KeyboardLayout.presets, id: \.self) { Text($0).tag($0) }
                }
            }
            ToggleSection("Focus follows mouse", isOn: boolBind(model, \.focusFollowsMouseEnabled, model.setFocusFollowsMouseEnabled),
                          footer: "Focuses the window the cursor settles on. The one feature that adds per-interaction "
                                + "Accessibility calls — leave off unless you want it.") {
                if model.config.focusFollowsMouseEnabled {
                    NumberRow(label: "Dwell", value: Binding(
                        get: { model.config.focusFollowsMouseDelayMs },
                        set: { model.setFocusFollowsMouseDelay($0) }), range: 50...2000, step: 25, suffix: "ms")
                }
            }
            // Output
            AudioSettings(model: model)
        }
        .formStyle(.grouped)
    }
}

// MARK: - App Launcher (app cuts + hyper cuts + scratchpad)

struct AppLauncherTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppShortcutsView(model: model).padding(16)
            Divider()
            Form {
                AppGroupsSection(model: model)
                ToggleSection("Scratchpad", isOn: Binding(
                    get: { !model.config.scratchpadApps.isEmpty },
                    set: { on in
                        if on {
                            model.setScratchpadApps(["Terminal"])
                        } else {
                            model.setScratchpadApps([])
                        }
                    }
                ), footer: "Summon a set of utility apps together and dismiss them together.") {
                    if !model.config.scratchpadApps.isEmpty {
                        HotkeyRowView(model: model, label: "Hotkey", section: "system_hotkeys", key: "scratchpad")
                        LabeledContent("Apps") {
                            TextField("e.g. Terminal, Notes", text: Binding(
                                get: { model.config.scratchpadApps.joined(separator: ", ") },
                                set: { val in
                                    let apps = val.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                    model.setScratchpadApps(apps)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                        Toggle("Auto-dismiss", isOn: Binding(
                            get: { model.config.scratchpadAutoDismiss },
                            set: { model.setScratchpadAutoDismiss($0) }
                        ))
                    }
                }
                Section {
                    HotkeyRowView(model: model, label: "Chrome: toggle tab strip", section: "system_hotkeys", key: "chrome_tabs")
                } header: {
                    Text("App Integrations")
                } footer: {
                    Text("Collapses/expands vertical tabs in Google Chrome (shortcut only active when Chrome is frontmost).")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }
}

/// Editor for the named [[app_groups]] — each a set of apps summoned/dismissed together by its own
/// hotkey (supersedes the single scratchpad). Add / rename-by-recreate / delete; edit apps, hotkey
/// (alias + key), and auto-dismiss inline.
struct AppGroupsSection: View {
    @ObservedObject var model: SettingsModel
    @State private var appEdits: [String: String] = [:]   // group → apps CSV in progress
    @State private var keyEdits: [String: String] = [:]   // group → hotkey key in progress
    @State private var newName = ""

    private var aliasNames: [String] { model.config.aliases.keys.sorted() }
    private func aliasOf(_ g: AppGroupProfile) -> String { g.hotkey.first ?? (aliasNames.first ?? "mash") }
    private func keyOf(_ g: AppGroupProfile) -> String { g.hotkey.count >= 2 ? g.hotkey[1] : "" }

    /// One surgical write covering whichever fields changed (others keep their current value).
    private func save(_ g: AppGroupProfile, apps: [String]? = nil, alias: String? = nil,
                      key: String? = nil, autoDismiss: Bool? = nil) {
        let k = key ?? keyOf(g)
        let hotkey = k.isEmpty ? [] : [alias ?? aliasOf(g), k]
        model.setAppGroup(name: g.name, apps: apps ?? g.apps, hotkey: hotkey, autoDismiss: autoDismiss ?? g.autoDismiss)
    }

    var body: some View {
        Section("App groups") {
            caption("Named sets of apps summoned and dismissed together, each with its own hotkey "
                    + "(supersedes the single scratchpad). Press ⏎ in a field to save.")
            ForEach(model.config.appGroups, id: \.name) { g in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(g.name).font(.system(.body, design: .monospaced)).fontWeight(.medium)
                        Spacer()
                        Button { model.removeAppGroup(name: g.name) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("Delete group")
                    }
                    HStack {
                        Text("Apps").foregroundColor(.secondary).frame(width: 56, alignment: .leading)
                        TextField("Slack, Mail", text: Binding(
                            get: { appEdits[g.name] ?? g.apps.joined(separator: ", ") },
                            set: { appEdits[g.name] = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { save(g, apps: splitList(appEdits[g.name] ?? "")) }
                    }
                    HStack(spacing: 6) {
                        Text("Hotkey").foregroundColor(.secondary).frame(width: 56, alignment: .leading)
                        ModifierSelector(model: model, alias: aliasOf(g)) { save(g, alias: $0) }
                        Text("+").foregroundColor(.secondary)
                        TextField("key", text: Binding(
                            get: { keyEdits[g.name] ?? keyOf(g) },
                            set: { keyEdits[g.name] = $0 }))
                            .textFieldStyle(.roundedBorder).frame(width: 50).multilineTextAlignment(.center)
                            .onSubmit { save(g, key: keyEdits[g.name] ?? "") }
                        Spacer()
                        Toggle("Auto-dismiss", isOn: Binding(
                            get: { g.autoDismiss }, set: { save(g, autoDismiss: $0) }))
                            .toggleStyle(.switch).controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
            HStack {
                TextField("new group name", text: $newName).labelsHidden()   // in-field prompt, not a wrapping Form label
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                Button("Add group") {
                    let n = newName.trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty, !n.contains("\""), model.config.appGroups.allSatisfy({ $0.name != n }) else { return }
                    model.setAppGroup(name: n, apps: [], hotkey: [], autoDismiss: true)
                    newName = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }
        }
    }
}

// MARK: - Appearance (window border + margins, with a shared live preview)

/// Config colour-name → SwiftUI Color (mirrors the swatch set used in the editors).
private let configSwatch: [String: Color] = [
    "green": .green, "red": .red, "blue": .blue, "yellow": .yellow, "orange": .orange,
    "purple": .purple, "white": .white, "black": .black, "gray": .gray,
]

/// A live mock of a 2×2 tiled desktop so BOTH the window border and the margins are visible as you
/// change them: the top-left window is "focused" (shows the border colour/width/radius), and the
/// gaps between the four windows + the screen edge are the margin size (the review asked to "show 4
/// windows … to preview margins as well … clarify what the border does").
struct AppearancePreview: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let b = model.config.borders
        let m = model.config.zoneConfig.margins
        let marginsOn = m?.enabled ?? false
        let gap = marginsOn ? CGFloat(min(max(m?.size ?? 0, 0), 40)) * 0.45 + 3 : 3
        let edge = (marginsOn && (m?.screen_edge ?? false)) ? gap : 6
        let color = b.enabled ? (configSwatch[b.color] ?? .accentColor) : .clear
        return VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.30))   // desktop
                Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                    GridRow { tile(focused: true, color: color, b: b); tile(focused: false, color: color, b: b) }
                    GridRow { tile(focused: false, color: color, b: b); tile(focused: false, color: color, b: b) }
                }
                .padding(edge)
            }
            .frame(height: 150)
            Text(marginsOn ? "2×2 tiling, margins \(Int(m?.size ?? 0))px"
                           : "2×2 tiling, margins off")
                .font(.caption2).foregroundColor(.secondary)
        }
        .listRowInsets(EdgeInsets())
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func tile(focused: Bool, color: Color, b: ConfigLoader.Borders) -> some View {
        RoundedRectangle(cornerRadius: CGFloat(b.cornerRadius))
            .fill(Color.white.opacity(focused ? 0.10 : 0.05))
            .overlay(focused
                     ? RoundedRectangle(cornerRadius: CGFloat(b.cornerRadius)).strokeBorder(color, lineWidth: CGFloat(b.width))
                     : nil)
            .overlay(focused ? Text("focused").font(.caption2).foregroundColor(.secondary) : nil)
    }
}

/// Live mock of the Pomodoro color bar — a top-edge strip (used on the left, remaining on the
/// right) across a mock screen, reflecting the colours / opacity / height as you change them (the
/// review asked to "see a preview of how the bar will look and where, updated live").
struct PomodoroBarPreview: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let on = model.config.pomodoroEnableColorBar
        let heightRatio = model.config.pomodoroIndicatorHeight        // 0…1 of the menubar
        let alpha = model.config.pomodoroIndicatorAlpha
        let used = configSwatch[model.config.pomodoroColorUsed] ?? .red
        let remaining = configSwatch[model.config.pomodoroColorRemaining] ?? .green
        let barH = max(3.0, 26.0 * heightRatio)                       // scale onto a ~26pt mock menubar
        return VStack(spacing: 6) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.30))   // mock screen
                if on {
                    HStack(spacing: 0) {
                        Rectangle().fill(used.opacity(alpha)).frame(width: 90)       // ~35% elapsed
                        Rectangle().fill(remaining.opacity(alpha))
                    }
                    .frame(height: barH)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .padding(.horizontal, 1).padding(.top, 1)
                }
            }
            .frame(height: 120)
            Text(on ? "Strip across the top of the screen (used │ remaining)"
                    : "Color bar off")
                .font(.caption2).foregroundColor(.secondary)
        }
        .listRowInsets(EdgeInsets())
        .padding(.vertical, 4)
    }
}

struct AppearanceTab: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        Form {
            Section { AppearancePreview(model: model) }
            BordersSettings(model: model)
            Section("Margins") {
                Toggle("Enable margins", isOn: Binding(
                    get: { model.config.zoneConfig.margins?.enabled ?? false },
                    set: { model.setMarginsEnabled($0) }))
                SliderRow(label: "Size", value: Binding(
                    get: { Int(model.config.zoneConfig.margins?.size ?? 0) },
                    set: { model.setMarginsSize($0) }), range: 0...40, suffix: "px")
                    .disabled(!(model.config.zoneConfig.margins?.enabled ?? false))
                Toggle("Apply margin at screen edges", isOn: Binding(
                    get: { model.config.zoneConfig.margins?.screen_edge ?? false },
                    set: { model.setMarginsScreenEdge($0) }))
                    .disabled(!(model.config.zoneConfig.margins?.enabled ?? false))
            }

        }
        .formStyle(.grouped)
    }
}
