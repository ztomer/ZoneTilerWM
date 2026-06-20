// SettingsPreviews.swift — live preview components for the settings panes (window hints, Exposé,
// zone HUD, drag-to-snap, break screen, command palette, Spaces bracket, appearance/Pomodoro mocks).
import SwiftUI
import AppKit
import ZTCore
import ZTSystem

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
