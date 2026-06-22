// ZoneTilePrimer.swift — the visual explainer that conveys the zone-vs-tile mental model (feedback
// 6: "a zone is a named region; tiles are its slots"). A filmstrip of mini-screens shows one key's
// zone and how repeated presses cycle through its tiles. Sits at the top of the Layouts editor.

import SwiftUI
import ZTSystem

struct ZoneTilePrimer: View {
    // An illustrative "J" zone cycle, as screen-fraction rects (mirrors a real centre-zone cycle:
    // centre column → left half → a single top cell). Purely for the diagram.
    private let steps: [(caption: String, rect: CGRect)] = [
        ("tap  J  →  zone",   CGRect(x: 0.28, y: 0.0,  width: 0.44, height: 1.0)),
        ("press again → tile 2", CGRect(x: 0.0,  y: 0.0,  width: 0.5,  height: 1.0)),
        ("again → tile 3",    CGRect(x: 0.52, y: 0.0,  width: 0.48, height: 0.5)),
    ]

    var body: some View {
        SectionCard(title: "How zones & tiles work") {
            Text("A zone is a named region of the screen mapped to a key. Hold your modifier and tap "
                 + "the key to send the focused window there. Each zone has one or more tiles — the "
                 + "exact slots it can take; press the key again to cycle through them.")
                .font(.callout).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                ForEach(steps.indices, id: \.self) { i in
                    if i > 0 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                            .padding(.bottom, 18)
                    }
                    VStack(spacing: 7) {
                        MiniScreen(tile: steps[i].rect, key: "J")
                            .frame(width: 150, height: 94)
                        Text(steps[i].caption).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
        }
    }
}

/// A tiny screen with one tile (a screen-fraction rect) highlighted in amber + the zone key glyph.
private struct MiniScreen: View {
    let tile: CGRect
    let key: String
    // The demonstrated tile IS the "selected" state → the binary accent is correct here.
    private let amber = ZTPalette.accentColor

    var body: some View {
        Canvas { ctx, size in
            // Gray fill + a `.primary`-tinted border so the screen reads on BOTH a light and a dark
            // settings card (the validate-light-and-dark rule); the amber tile pops on either.
            let screen = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8)
            ctx.fill(screen, with: .color(.gray.opacity(0.22)))
            ctx.stroke(screen, with: .color(.primary.opacity(0.30)), lineWidth: 1)

            let t = CGRect(x: tile.minX * size.width + 3, y: tile.minY * size.height + 3,
                           width: tile.width * size.width - 6, height: tile.height * size.height - 6)
            let tp = Path(roundedRect: t, cornerRadius: 5)
            ctx.fill(tp, with: .color(amber.opacity(0.26)))
            ctx.stroke(tp, with: .color(amber), lineWidth: 1.5)
            ctx.draw(Text(key).font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundColor(amber),
                     at: CGPoint(x: t.midX, y: t.midY))
        }
    }
}
