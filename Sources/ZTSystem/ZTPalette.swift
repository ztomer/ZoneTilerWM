// ZTPalette.swift — the single source of truth for the app's colors.
//
// Adopted from a Rams + Kare design consult (2026-06-22): a neutral charcoal base with ONE functional
// accent (Braun tool-orange) used STRICTLY for the element with current focus / active / selected
// state — never decoratively. Everything else stays neutral grey / black / white. Replaces the two
// ad-hoc ambers and the purple focus border that competed as signal colors.
//
// Exposes both NSColor (overlays, Core Graphics draw) and SwiftUI Color (settings) tokens so every
// surface pulls from the same values.

import AppKit
import SwiftUI

public enum ZTPalette {
    // Raw components (0–1), one place to tune.
    public static let backgroundRGB:    (CGFloat, CGFloat, CGFloat) = (0.102, 0.102, 0.102)  // #1A1A1A
    public static let surfaceRGB:       (CGFloat, CGFloat, CGFloat) = (0.157, 0.157, 0.157)  // #282828
    public static let primaryTextRGB:   (CGFloat, CGFloat, CGFloat) = (0.961, 0.961, 0.969)  // #F5F5F7
    public static let secondaryTextRGB: (CGFloat, CGFloat, CGFloat) = (0.557, 0.557, 0.576)  // #8E8E93
    public static let accentRGB:        (CGFloat, CGFloat, CGFloat) = (1.000, 0.420, 0.000)  // #FF6B00

    // MARK: NSColor (overlays / CG)
    public static let background    = ns(backgroundRGB)
    public static let surface       = ns(surfaceRGB)
    public static let primaryText   = ns(primaryTextRGB)
    public static let secondaryText = ns(secondaryTextRGB)
    /// The ONE functional accent — apply only to the active/selected/focused element.
    public static let accent        = ns(accentRGB)

    /// Default focus-border color name (the border is an active-state indicator → the accent).
    public static let accentHex = "#FF6B00"

    // Traffic-light dots (close / minimize / fullscreen) — one definition shared by the live Dock
    // preview panel (NSColor) and its settings mock (Color), so they can't drift.
    public static let trafficClose      = NSColor(srgbRed: 1.0, green: 0.37, blue: 0.34, alpha: 1)
    public static let trafficMinimize   = NSColor(srgbRed: 1.0, green: 0.74, blue: 0.18, alpha: 1)
    public static let trafficFullscreen = NSColor(srgbRed: 0.31, green: 0.79, blue: 0.31, alpha: 1)
    public static var trafficCloseColor:      Color { Color(.sRGB, red: 1.0, green: 0.37, blue: 0.34) }
    public static var trafficMinimizeColor:   Color { Color(.sRGB, red: 1.0, green: 0.74, blue: 0.18) }
    public static var trafficFullscreenColor: Color { Color(.sRGB, red: 0.31, green: 0.79, blue: 0.31) }

    private static func ns(_ c: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
    }

    // MARK: SwiftUI Color (settings)
    public static var backgroundColor:    Color { color(backgroundRGB) }
    public static var surfaceColor:       Color { color(surfaceRGB) }
    public static var primaryTextColor:   Color { color(primaryTextRGB) }
    public static var secondaryTextColor: Color { color(secondaryTextRGB) }
    public static var accentColor:        Color { color(accentRGB) }

    private static func color(_ c: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(.sRGB, red: c.0, green: c.1, blue: c.2, opacity: 1)
    }
}
