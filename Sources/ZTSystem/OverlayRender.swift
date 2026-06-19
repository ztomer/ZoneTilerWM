// OverlayRender.swift — deterministic, windowless rendering of the visual overlays (zone HUD,
// break screen) to PNG over a neutral backdrop, for QA + Gemini visual grading. No NSApplication,
// no live agent, no display — just draw the view into a bitmap. Keeps the grade loop fast and
// reproducible (the live `ZT_OPEN_WINDOW` path depends on agent lifecycle + screen capture, which
// is flaky for batch grading).

import AppKit

enum OverlayRender {
    /// Render `view` over a backdrop (a real screenshot if `backdropImage` is given, else a solid
    /// color) into PNG data. The view is drawn DIRECTLY into the image context (not via a cached
    /// bitmap, which flattens semi-transparent fills onto white) so the dim composites faithfully
    /// over the backdrop. The context is flipped to match the view's top-left (isFlipped) space.
    static func png(of view: NSView, size: NSSize, backdrop: NSColor, backdropImage: NSImage? = nil) -> Data? {
        // A flipped drawing context: top-left origin matches the view's isFlipped coords AND lets
        // AppKit draw text upright (a manual scaleY:-1 would mirror glyphs). Drawing the view
        // directly (not a cached bitmap) preserves the dim's alpha so it composites over the backdrop.
        let img = NSImage(size: size, flipped: true) { rect in
            if let bg = backdropImage {
                bg.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
            } else {
                backdrop.setFill(); rect.fill()
            }
            view.draw(view.bounds)
            return true
        }
        guard let tiff = img.tiffRepresentation, let bmp = NSBitmapImageRep(data: tiff) else { return nil }
        return bmp.representation(using: .png, properties: [:])
    }
}
