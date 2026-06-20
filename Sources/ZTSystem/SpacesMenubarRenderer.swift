// SpacesMenubarRenderer.swift — draws the pure `SpacesMenubar.Layout` into an NSImage for the
// NSStatusItem. Rams/Kare language: a thin rounded BRACKET per monitor (clear grouping) with a small
// MONITOR GLYPH at its leading edge; the CURRENT space is a filled cell with its number punched out
// (knockout), other spaces are hollow outlines; a fullscreen space uses a distinct (oval) shape.
//
// Rendered as a single-tone TEMPLATE image (isTemplate=true) so macOS tints it for the light/dark
// menu bar automatically — the knockout keeps the current-space number legible against the fill.

import AppKit
import ZTCore

public enum SpacesMenubarRenderer {

    /// How each monitor group's enclosure is drawn. `bold` is the default (the thin one disappears on
    /// some wallpapers); `paren`/`square` use literal `( )` / `[ ]`; `none` relies on the group gap.
    public enum BracketStyle: String, CaseIterable { case thin, bold, paren, square, none }

    /// `flashIndex` pops one cell (a brief emphasis ring) — Kare's tactile click acknowledgment.
    public static func image(_ layout: SpacesMenubar.Layout, template: Bool = true, showGlyph: Bool = true,
                             flashIndex: Int? = nil, bracket: BracketStyle = .bold) -> NSImage {
        let size = NSSize(width: max(1, layout.width), height: layout.height)
        let img = NSImage(size: size)
        img.lockFocus()
        // Layout is top-left (ZTRect); lockFocus is bottom-left → flip Y.
        func ns(_ r: ZTRect) -> NSRect { NSRect(x: r.x, y: size.height - r.y - r.h, width: r.w, height: r.h) }
        let ink = NSColor.black   // template → system tints it

        for g in layout.groups {
            drawBracket(bracket, around: ns(g.bracket), ink: ink)
            if showGlyph { drawMonitorGlyph(in: ns(g.glyph), ink: ink) }

            for c in g.cells {
                let cr = ns(c.rect).insetBy(dx: 1, dy: 1)
                let shape: NSBezierPath = c.isFullscreen
                    ? NSBezierPath(ovalIn: cr)                                  // fullscreen = distinct shape
                    : NSBezierPath(roundedRect: cr, xRadius: 3, yRadius: 3)
                if c.isCurrent {
                    ink.setFill(); shape.fill()
                    drawLabel(c.label, in: ns(c.rect), color: .black, knockout: true)   // punch the number out
                } else {
                    ink.withAlphaComponent(0.8).setStroke(); shape.lineWidth = 1; shape.stroke()
                    drawLabel(c.label, in: ns(c.rect), color: ink, knockout: false)
                }
                // Kare press-flash: a brief bold ring popping out around the clicked cell.
                if c.index == flashIndex {
                    let ring = NSBezierPath(roundedRect: cr.insetBy(dx: -2.5, dy: -2.5), xRadius: 5, yRadius: 5)
                    ink.setStroke(); ring.lineWidth = 2; ring.stroke()
                }
            }
        }
        img.unlockFocus()
        img.isTemplate = template
        return img
    }

    private static func drawBracket(_ style: BracketStyle, around rect: NSRect, ink: NSColor) {
        switch style {
        case .none:
            break
        case .thin:
            let p = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            p.lineWidth = 0.75; ink.withAlphaComponent(0.32).setStroke(); p.stroke()
        case .bold:
            let p = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            p.lineWidth = 1.5; ink.withAlphaComponent(0.85).setStroke(); p.stroke()
        case .paren, .square:
            let (l, r) = style == .paren ? ("(", ")") : ("[", "]")
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: rect.height * 1.05, weight: .medium),
                .foregroundColor: ink.withAlphaComponent(0.9),
            ]
            let ls = l as NSString, rs = r as NSString
            let lsz = ls.size(withAttributes: attrs), rsz = rs.size(withAttributes: attrs)
            ls.draw(at: NSPoint(x: rect.minX - lsz.width * 0.25, y: rect.midY - lsz.height / 2), withAttributes: attrs)
            rs.draw(at: NSPoint(x: rect.maxX - rsz.width * 0.75, y: rect.midY - rsz.height / 2), withAttributes: attrs)
        }
    }

    /// A single bold screen mark — Kare: don't draw a picture of a monitor at 22px; one clean rounded
    /// rectangle, single weight, no fussy stand (it dies at 1×). A filled centred dot reads as "a
    /// display" without representation.
    private static func drawMonitorGlyph(in rect: NSRect, ink: NSColor) {
        let h = rect.height * 0.62
        let screen = NSRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h)
        let p = NSBezierPath(roundedRect: screen.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
        p.lineWidth = 1.2; ink.withAlphaComponent(0.7).setStroke(); p.stroke()
    }

    private static func drawLabel(_ label: String, in rect: NSRect, color: NSColor, knockout: Bool) {
        guard !label.isEmpty else { return }
        let s = String(label.prefix(10)) as NSString   // caller pre-truncates; cap as a safety net
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: min(11, rect.height * 0.62), weight: .semibold),
            .foregroundColor: color,
        ]
        let sz = s.size(withAttributes: attrs)
        let at = NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2)
        if knockout {
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            s.draw(at: at, withAttributes: attrs)
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        } else {
            s.draw(at: at, withAttributes: attrs)
        }
    }
}
