// SidebarIcons.swift — custom monochrome sidebar glyphs (Kare/Rams line language: a 20-unit grid,
// ~1.7 stroke, rounded caps, geometric, one visual language across the set). Drawn as SwiftUI
// Paths so they inherit the row's foreground colour and tint on selection exactly like SF Symbols
// (no raster assets, fully reproducible). One case per settings-group id. The IconMontage at the
// bottom renders the whole set on a neutral backdrop for the Gemini asset-grade loop.

import SwiftUI

struct SidebarGlyph: View {
    let id: String
    var size: CGFloat = 18
    private let u: CGFloat = 20          // design grid
    private let lw: CGFloat = 1.7

    var body: some View {
        Canvas { ctx, sz in draw(&ctx, scale: sz.width / u) }
            .frame(width: size, height: size)
    }

    private var stroke: StrokeStyle { StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round) }

    /// Draw in the 20-unit space, scaled to the frame. Uses the resolved foreground colour so the
    /// glyph tints with the row (primary/white-on-selection), matching SF Symbol behaviour.
    private func draw(_ ctx: inout GraphicsContext, scale: CGFloat) {
        ctx.scaleBy(x: scale, y: scale)
        let fg = GraphicsContext.Shading.color(.primary)
        func line(_ p: Path) { ctx.stroke(p, with: fg, style: stroke) }
        func fill(_ p: Path) { ctx.fill(p, with: fg) }
        func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
            Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
        }
        func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }

        switch id {
        case "tiling":            // 2×2 outlined squares (stroked to match the set's line language)
            for (x, y) in [(2.5, 2.5), (10.5, 2.5), (2.5, 10.5), (10.5, 10.5)] {
                line(rrect(x, y, 7, 7, 1.6))
            }
        case "layouts":           // main + sidebar split (a layout)
            line(rrect(3, 3, 4.5, 14, 1.2))
            line(rrect(9, 3, 8, 14, 1.2))
        case "previews":          // Exposé & Hints: two mini screen frames side-by-side with small filled badges inside
            line(rrect(2.5, 3.5, 6.5, 13, 1.2))
            line(rrect(11.0, 3.5, 6.5, 13, 1.2))
            fill(dot(5.75, 7.75, 1.2))
            fill(dot(14.25, 11.75, 1.2))
        case "keys":              // miniature computer keyboard (Kare clean metaphor)
            line(rrect(2, 5, 16, 10, 2))
            var keys = Path()
            // Horizontal row divider
            keys.move(to: .init(x: 2, y: 10))
            keys.addLine(to: .init(x: 18, y: 10))
            // Row 1 key dividers
            keys.move(to: .init(x: 6, y: 5)); keys.addLine(to: .init(x: 6, y: 10))
            keys.move(to: .init(x: 10, y: 5)); keys.addLine(to: .init(x: 10, y: 10))
            keys.move(to: .init(x: 14, y: 5)); keys.addLine(to: .init(x: 14, y: 10))
            // Row 2 key dividers (modifiers + spacebar)
            keys.move(to: .init(x: 5, y: 10)); keys.addLine(to: .init(x: 5, y: 15))
            keys.move(to: .init(x: 15, y: 10)); keys.addLine(to: .init(x: 15, y: 15))
            line(keys)
        case "io":                // up / down arrows (input + output)
            var up = Path(); up.move(to: .init(x: 6, y: 15)); up.addLine(to: .init(x: 6, y: 5))
            up.move(to: .init(x: 3.5, y: 7.5)); up.addLine(to: .init(x: 6, y: 5)); up.addLine(to: .init(x: 8.5, y: 7.5))
            var dn = Path(); dn.move(to: .init(x: 14, y: 5)); dn.addLine(to: .init(x: 14, y: 15))
            dn.move(to: .init(x: 11.5, y: 12.5)); dn.addLine(to: .init(x: 14, y: 15)); dn.addLine(to: .init(x: 16.5, y: 12.5))
            line(up); line(dn)
        case "apps":              // 3×3 dot grid (launchpad)
            for gy in [4.5, 10.0, 15.5] { for gx in [4.5, 10.0, 15.5] { fill(dot(gx, gy, 1.5)) } }
        case "pomodoro":          // clock: circle + two hands
            line(Path(ellipseIn: CGRect(x: 3, y: 3, width: 14, height: 14)))
            var hands = Path(); hands.move(to: .init(x: 10, y: 10)); hands.addLine(to: .init(x: 10, y: 5.5))
            hands.move(to: .init(x: 10, y: 10)); hands.addLine(to: .init(x: 13.5, y: 10))
            line(hands)
        case "appearance":        // bold window-border frame
            ctx.stroke(rrect(3.5, 3.5, 13, 13, 3), with: fg, style: StrokeStyle(lineWidth: 2.6, lineJoin: .round))
        case "automation":        // terminal  >_
            var chev = Path(); chev.move(to: .init(x: 5, y: 6)); chev.addLine(to: .init(x: 9.5, y: 10)); chev.addLine(to: .init(x: 5, y: 14))
            var bar = Path(); bar.move(to: .init(x: 11, y: 14.5)); bar.addLine(to: .init(x: 16, y: 14.5))
            line(chev); line(bar)
        case "advanced":          // sliders (tuning)
            for (y, kx) in [(5.5, 13.0), (10.0, 7.0), (14.5, 14.0)] {
                var l = Path(); l.move(to: .init(x: 3, y: y)); l.addLine(to: .init(x: 17, y: y)); line(l)
                fill(dot(kx, y, 2.0))
                ctx.stroke(dot(kx, y, 2.0), with: GraphicsContext.Shading.color(.primary), style: StrokeStyle(lineWidth: lw))
            }
        default:                  // general: rotary dial knob
            line(Path(ellipseIn: CGRect(x: 4, y: 4, width: 12, height: 12)))
            var ticks = Path()
            ticks.move(to: .init(x: 10, y: 1.5)); ticks.addLine(to: .init(x: 10, y: 3.5))
            ticks.move(to: .init(x: 1.5, y: 10)); ticks.addLine(to: .init(x: 3.5, y: 10))
            ticks.move(to: .init(x: 16.5, y: 10)); ticks.addLine(to: .init(x: 18.5, y: 10))
            ticks.move(to: .init(x: 10, y: 10)); ticks.addLine(to: .init(x: 14, y: 6))
            line(ticks)
        }
    }
}

/// Renders the full glyph set in a labeled grid on a neutral backdrop — the asset for the Gemini
/// grade loop (render via ZT_RENDER_UI=icons:/path.png).
struct IconMontage: View {
    private let items: [(String, String)] = [
        ("general", "General"), ("tiling", "Tiling"), ("layouts", "Layouts"),
        ("previews", "Exposé & Hints"), ("keys", "Keys"),
        ("io", "Input & Output"), ("apps", "App Launcher"), ("pomodoro", "Pomodoro"),
        ("appearance", "Appearance"), ("automation", "Automation"), ("advanced", "Advanced"),
    ]
    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 150), spacing: 18)]
        LazyVGrid(columns: cols, spacing: 18) {
            ForEach(items, id: \.0) { id, title in
                HStack(spacing: 12) {
                    SidebarGlyph(id: id, size: 26).frame(width: 30, height: 30)
                    Text(title).font(.body)
                    Spacer()
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                .foregroundStyle(.white)
            }
        }
        .padding(24)
        .frame(width: 720)
        .background(Color(white: 0.13))   // match the app's dark sidebar so contrast is judged fairly
    }
}
