// LiquidGlass.swift — the shared macOS 26 Liquid Glass primitives for every overlay (the template
// proven on the app-launcher and cleared by Gemini). Two factories: a `container` whose chip subviews
// MERGE fluidly when close (the liquid bridge), and a `chip`/`panel` of clear glass that LENSES the
// desktop behind it. Pre-26 falls back to NSVisualEffectView frost. The headless render harness can't
// composite glass, so overlays keep an opaque-draw fallback for renderPNG.

import AppKit

public enum LiquidGlass {

    /// True on macOS 26+, where real Liquid Glass (NSGlassEffectView) is available.
    public static var isAvailable: Bool { if #available(macOS 26.0, *) { return true } else { return false } }

    /// A glass container that merges nearby chip subviews. Add chips to the returned `content` (a
    /// top-left-origin view so chip frames match overlay layout math). `spacing` is the merge radius —
    /// set it above the inter-chip gap so neighbours bridge fluidly.
    public static func container(frame: NSRect, spacing: CGFloat) -> (view: NSView, content: NSView) {
        let content = FlippedView(frame: frame)
        content.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let c = NSGlassEffectContainerView(frame: frame)
            c.spacing = spacing
            c.contentView = content
            return (c, content)
        } else {
            let c = NSView(frame: frame)
            c.addSubview(content)
            return (c, content)
        }
    }

    /// A single clear-glass element holding `content` (sized to fill it). Use for keycap chips and for
    /// panel backdrops alike. `tint` is a faint depth/legibility wash (keep it light so it still lenses).
    public static func chip(frame: NSRect, cornerRadius: CGFloat,
                            tint: NSColor? = NSColor.black.withAlphaComponent(0.10),
                            clear: Bool = true, content: NSView? = nil) -> NSView {
        if #available(macOS 26.0, *) {
            let g = NSGlassEffectView(frame: frame)
            g.cornerRadius = cornerRadius
            g.style = clear ? .clear : .regular
            g.tintColor = tint
            if let content { content.frame = g.bounds; content.autoresizingMask = [.width, .height]; g.contentView = content }
            return g
        } else {
            let g = NSVisualEffectView(frame: frame)
            g.material = .hudWindow; g.blendingMode = .behindWindow; g.state = .active
            g.wantsLayer = true; g.layer?.cornerRadius = cornerRadius; g.layer?.masksToBounds = true
            if let content { content.frame = g.bounds; content.autoresizingMask = [.width, .height]; g.addSubview(content) }
            return g
        }
    }

    /// Top-left-origin view so subview frames match overlay (CG-style) layout math.
    public final class FlippedView: NSView { override public var isFlipped: Bool { true } }
}
