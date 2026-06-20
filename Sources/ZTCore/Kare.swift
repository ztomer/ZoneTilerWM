// Kare.swift — the Susan Kare status glyphs for TUI output (zonetiler-cli + the agent's stderr log).
// Mirrors ~/projects/scripts/_stylerc; these are the ONLY decorative glyphs allowed in the codebase
// (the EmojiPolicyTest enforces it). Monochrome, clear-at-a-glance — never colourful emoji.

public enum Kare {
    public static let start = "→"   // an action begins / neutral info
    public static let step  = "·"   // a sub-step within a list
    public static let ok    = "✓"   // success
    public static let err   = "✗"   // failure
    public static let warn  = "⚠"   // warning

    /// Prefix a line with a glyph + single space (e.g. `Kare.mark(.ok, "ready")` -> "✓ ready").
    public static func mark(_ glyph: String, _ s: String) -> String { "\(glyph) \(s)" }
}
