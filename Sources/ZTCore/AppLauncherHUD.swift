// AppLauncherHUD.swift — pure layout for the app-launcher cheat-sheet overlay: hold the app-launcher
// modifier and (after a short delay) a keyboard palette appears showing which key launches which app.
// Same hold-to-reveal idea as the zone HUD, but app shortcuts are arbitrary keyboard keys (not a
// spatial zone grid), so each cap sits at its real position on a QWERTY keyboard. Pure; the overlay
// and the modifier trigger live in the agent.

public enum AppLauncherHUD {

    /// One app shortcut, placed at its physical key on the keyboard. `col` carries the per-row stagger.
    public struct Cap: Equatable {
        public let key: String      // the shortcut key (e.g. "c")
        public let label: String    // the app it launches (e.g. "Chrome")
        public let row: Int         // 0 = number row … 3 = bottom row
        public let col: Double      // staggered column position within the row
        public init(key: String, label: String, row: Int, col: Double) {
            self.key = key; self.label = label; self.row = row; self.col = col
        }
    }

    /// QWERTY rows with the usual physical stagger (each lower row shifted right a fraction of a key).
    static let rows: [(keys: [String], offset: Double)] = [
        (["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="], 0.0),
        (["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]"], 0.5),
        (["a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'"], 0.75),
        (["z", "x", "c", "v", "b", "n", "m", ",", ".", "/"], 1.25),
    ]

    private static let position: [String: (row: Int, col: Double)] = {
        var p: [String: (row: Int, col: Double)] = [:]
        for (r, row) in rows.enumerated() {
            for (i, k) in row.keys.enumerated() { p[k] = (r, Double(i) + row.offset) }
        }
        return p
    }()

    /// One cap per assigned shortcut whose key is on the keyboard, ordered top-left → bottom-right.
    /// Keys not on the keyboard (or empty app names) are skipped. Deterministic.
    public static func caps(apps: [String: String]) -> [Cap] {
        apps.compactMap { key, app -> Cap? in
            guard !app.isEmpty, let pos = position[key.lowercased()] else { return nil }
            return Cap(key: key, label: app, row: pos.row, col: pos.col)
        }
        .sorted { a, b in a.row != b.row ? a.row < b.row : a.col < b.col }
    }

    /// The keyboard's column extent (max col across all rows), so the overlay can size the panel.
    public static var columnSpan: Double {
        rows.map { Double($0.keys.count - 1) + $0.offset }.max() ?? 0
    }
}
