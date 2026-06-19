// KeyboardLayout.swift — physical key arrangements for the settings keyboard renders (app
// shortcuts + zone map). Each preset lists the characters at the standard physical key
// positions, so a Dvorak/Colemak user sees their actual key faces. The live layout is
// auto-detected (ZTSystem) and can be overridden; this just supplies the preset character rows.

public enum KeyboardLayout {

    public static let fRow = ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10"]
    public static let numberRow = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    public static let presets = ["qwerty", "dvorak", "colemak"]

    // Letter/symbol body rows (top, home, bottom) at QWERTY physical positions.
    private static let bodies: [String: [[String]]] = [
        "qwerty": [
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";"],
            ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/"],
        ],
        "dvorak": [
            ["'", ",", ".", "p", "y", "f", "g", "c", "r", "l"],
            ["a", "o", "e", "u", "i", "d", "h", "t", "n", "s"],
            [";", "q", "j", "k", "x", "b", "m", "w", "v", "z"],
        ],
        "colemak": [
            ["q", "w", "f", "p", "g", "j", "l", "u", "y", ";"],
            ["a", "r", "s", "t", "d", "h", "n", "e", "i", "o"],
            ["z", "x", "c", "v", "b", "k", "m", ",", ".", "/"],
        ],
    ]

    /// Full rows (F-keys, numbers, three letter rows) for a layout name; falls back to QWERTY.
    public static func rows(for name: String) -> [[String]] {
        [fRow, numberRow] + (bodies[name.lowercased()] ?? bodies["qwerty"]!)
    }
}
