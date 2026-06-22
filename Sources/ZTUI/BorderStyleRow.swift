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
                // 45° angled stripes (trapezoids) alternating accent/black — distinct from dashed.
                let band = CGRect(x: x0, y: y - 5, width: x1 - x0, height: 10)
                ctx.clip(to: Path(roundedRect: band, cornerRadius: 2))
                let stripeW: CGFloat = 5
                var sx = band.minX - band.height; var i = 0
                while sx < band.maxX + band.height {
                    var p = Path()
                    p.move(to: CGPoint(x: sx, y: band.maxY))
                    p.addLine(to: CGPoint(x: sx + band.height, y: band.minY))
                    p.addLine(to: CGPoint(x: sx + band.height + stripeW, y: band.minY))
                    p.addLine(to: CGPoint(x: sx + stripeW, y: band.maxY))
                    p.closeSubpath()
                    ctx.fill(p, with: .color(i % 2 == 0 ? accent : .black))
                    sx += stripeW; i += 1
                }
            default:
                ctx.stroke(line, with: .color(accent), lineWidth: 2.5)
            }
        }
    }
}

/// Draws a rounded-rect border around its bounds in the chosen color + line style — so the live
/// border preview shows BOTH the selected color and type (solid/dashed/dotted/wavy/hazard). Mirrors
/// the renderer (BorderShapeView) so the preview matches what you'll see on a window.
struct StyledBorderOverlay: View {
    let style: String
    let color: Color
    let width: CGFloat
    let radius: CGFloat
    var body: some View {
        Canvas { ctx, size in
            guard width > 0 else { return }
            let inset = width / 2
            let rect = CGRect(x: inset, y: inset, width: size.width - width, height: size.height - width)
            guard rect.width > 1, rect.height > 1 else { return }
            let rr = Path(roundedRect: rect, cornerRadius: max(0, radius))
            switch style {
            case "dashed":
                ctx.stroke(rr, with: .color(color), style: StrokeStyle(lineWidth: width, dash: [width * 2.6, width * 1.8]))
            case "dotted":
                ctx.stroke(rr, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: [0.1, width * 1.9]))
            case "wavy":
                ctx.stroke(wavy(in: rect, amplitude: width * 0.7, wavelength: max(width * 5, 12)),
                           with: .color(color), style: StrokeStyle(lineWidth: width, lineJoin: .round))
            case "hazard":
                let half = width / 2
                var band = Path(roundedRect: rect.insetBy(dx: -half, dy: -half), cornerRadius: radius + half)
                band.addPath(Path(roundedRect: rect.insetBy(dx: half, dy: half), cornerRadius: max(1, radius - half)))
                ctx.clip(to: band, style: FillStyle(eoFill: true))
                let stripeW = max(5, width * 1.3)
                var sx = -size.height; var i = 0
                while sx < size.width + size.height {
                    var p = Path()
                    p.move(to: CGPoint(x: sx, y: size.height))
                    p.addLine(to: CGPoint(x: sx + size.height, y: 0))
                    p.addLine(to: CGPoint(x: sx + size.height + stripeW, y: 0))
                    p.addLine(to: CGPoint(x: sx + stripeW, y: size.height))
                    p.closeSubpath()
                    ctx.fill(p, with: .color(i % 2 == 0 ? color : .black))
                    sx += stripeW; i += 1
                }
            default:
                ctx.stroke(rr, with: .color(color), lineWidth: width)
            }
        }
    }

    /// A wavy rounded-rect outline — continuous sine around the perimeter (sharp corners; matches the
    /// renderer closely enough for a small preview).
    private func wavy(in r: CGRect, amplitude a: CGFloat, wavelength wl: CGFloat) -> Path {
        var path = Path()
        let edges: [(start: CGPoint, dir: CGVector, normal: CGVector, len: CGFloat)] = [
            (CGPoint(x: r.minX, y: r.minY), CGVector(dx: 1, dy: 0),  CGVector(dx: 0, dy: -1), r.width),
            (CGPoint(x: r.maxX, y: r.minY), CGVector(dx: 0, dy: 1),  CGVector(dx: 1, dy: 0),  r.height),
            (CGPoint(x: r.maxX, y: r.maxY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: 1),  r.width),
            (CGPoint(x: r.minX, y: r.maxY), CGVector(dx: 0, dy: -1), CGVector(dx: -1, dy: 0), r.height),
        ]
        let perimeter = 2 * (r.width + r.height)
        let waveLen = perimeter / max(1, (perimeter / wl).rounded())
        var s: CGFloat = 0; var first = true
        for e in edges {
            let steps = max(2, Int((e.len / waveLen) * 8))
            for i in 0...steps {
                let along = (CGFloat(i) / CGFloat(steps)) * e.len
                let off = a * sin(((s + along) / waveLen) * 2 * .pi)
                let pt = CGPoint(x: e.start.x + e.dir.dx * along + e.normal.dx * off,
                                 y: e.start.y + e.dir.dy * along + e.normal.dy * off)
                if first { path.move(to: pt); first = false } else { path.addLine(to: pt) }
            }
            s += e.len
        }
        path.closeSubpath()
        return path
    }
}
