// WindowHints.swift — label assignment for the window-hints overlay (port of
// hs.hints.windowHints): show a short key label on each window, type it to focus that window.
// Pure label generation here; the overlay + key capture are the system/agent boundary.

public enum WindowHints {

    /// Single-character labels (home-row-first, like vimium) for up to `alphabet.count`
    /// windows. Returns one label per window in order; windows beyond the alphabet get no
    /// label (caller logs the cap). Single-char keeps the key-capture modal a flat keymap.
    public static let alphabet = Array("asdfghjklqwertyuiopzxcvbnm")

    public static func labels(count: Int) -> [String] {
        guard count > 0 else { return [] }
        return (0..<min(count, alphabet.count)).map { String(alphabet[$0]) }
    }
}
