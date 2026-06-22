// BorderStyleRow.swift — the focus-border line-style picker. Each option is a DRAWN preview of the
// stroke (solid / dashed / dotted / wavy / hazard) — a glyph, not a text label (per feedback) — so
// the user picks by sight. The selected swatch is marked with the accent (binary-accent rule).

import SwiftUI
import ZTSystem

struct BorderStyleRow: View {
    let selected: String
    let onSelect: (String) -> Void
    private let styles = ["solid", "dashed", "dotted", "wavy", "hazard"]

    var body: some View {
        LabeledContent("Style") {
            HStack(spacing: 8) {
                ForEach(styles, id: \.self) { s in
                    Button { onSelect(s) } label: {
                        BorderStyleGlyph(style: s)
                            .frame(width: 48, height: 26)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(selected == s ? ZTPalette.accentColor.opacity(0.18) : Color.gray.opacity(0.12)))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(selected == s ? ZTPalette.accentColor : Color.gray.opacity(0.25),
                                        lineWidth: selected == s ? 1.6 : 1))
                    }
                    .buttonStyle(.plain)
                    .help(s.capitalized)
                }
            }
        }
    }
}

/// Draws one border style as a short horizontal stroke (the visual the option represents).
struct BorderStyleGlyph: View {
    let style: String
    var body: some View {
        Canvas { ctx, size in
            let accent = ZTPalette.accentColor
            let y = size.height / 2, x0: CGFloat = 7, x1 = size.width - 7
            var line = Path(); line.move(to: CGPoint(x: x0, y: y)); line.addLine(to: CGPoint(x: x1, y: y))
            switch style {
            case "solid":
                ctx.stroke(line, with: .color(accent), lineWidth: 2.5)
            case "dashed":
                ctx.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
            case "dotted":
                ctx.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, dash: [0.1, 5]))
            case "wavy":
                var w = Path(); w.move(to: CGPoint(x: x0, y: y))
                var x = x0
                while x <= x1 { w.addLine(to: CGPoint(x: x, y: y + 3 * sin((x - x0) / 4))); x += 1 }
                ctx.stroke(w, with: .color(accent), lineWidth: 2)
            case "hazard":
                ctx.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: 3.2, dash: [5, 5]))
                ctx.stroke(line, with: .color(.black), style: StrokeStyle(lineWidth: 3.2, dash: [5, 5], dashPhase: 5))
            default:
                ctx.stroke(line, with: .color(accent), lineWidth: 2.5)
            }
        }
    }
}
