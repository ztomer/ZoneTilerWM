// SettingsPreviews+Expose.swift — the Exposé / Window-grid live preview (split out of
// SettingsPreviews.swift to keep both files under the 500-LOC ceiling). Uses the shared `miniBadge`.

import SwiftUI
import ZTSystem

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
