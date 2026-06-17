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

    /// Spatially assign a hint key to each window so the key's physical keyboard position roughly
    /// matches the window's on-screen position (left windows → left keys, top → top row): easier
    /// to pick than arbitrary order. `centers` are window centers normalized to [0,1]×[0,1] over
    /// the desktop (input order preserved in the result). `keys` is the physical key grid (rows
    /// of keys). Greedy: windows in reading order each claim the nearest unused key. Windows
    /// beyond the available keys get "" (caller skips them).
    public static func spatialLabels(centers: [(x: Double, y: Double)], keys: [[String]]) -> [String] {
        guard !centers.isEmpty else { return [] }
        let rows = keys.count
        var keyPts: [(key: String, x: Double, y: Double)] = []
        for (r, row) in keys.enumerated() {
            let cols = row.count
            for (c, k) in row.enumerated() {
                keyPts.append((k,
                               cols <= 1 ? 0.5 : Double(c) / Double(cols - 1),
                               rows <= 1 ? 0.5 : Double(r) / Double(rows - 1)))
            }
        }
        var used = Set<Int>()
        var result = [String](repeating: "", count: centers.count)
        // Assign in reading order (top-to-bottom, left-to-right) for a stable, sensible result.
        let order = centers.indices.sorted {
            centers[$0].y != centers[$1].y ? centers[$0].y < centers[$1].y : centers[$0].x < centers[$1].x
        }
        for i in order {
            var best = -1, bestD = Double.infinity
            for (j, kp) in keyPts.enumerated() where !used.contains(j) {
                let dx = kp.x - centers[i].x, dy = kp.y - centers[i].y
                let d = dx * dx + dy * dy
                if d < bestD { bestD = d; best = j }
            }
            if best >= 0 { used.insert(best); result[i] = keyPts[best].key }
        }
        return result
    }
}
