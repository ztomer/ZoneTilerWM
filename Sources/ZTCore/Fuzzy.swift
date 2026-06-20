// Fuzzy.swift — the shared subsequence matcher behind "find a window by typing" (command palette,
// window hints, Exposé). Pure + case-insensitive; the controllers all route through this one place.

public enum Fuzzy {
    /// True if `needle` is a subsequence of `hay`, case-insensitively, with a substring fast-path.
    /// An empty needle always matches. Order matters: "sf" matches "Safari" (s…f), "fs" does not.
    public static func matches(_ needle: String, in hay: String) -> Bool {
        let n = needle.lowercased(), h = hay.lowercased()
        if n.isEmpty || h.contains(n) { return true }
        var idx = h.startIndex
        for ch in n {
            guard let found = h[idx...].firstIndex(of: ch) else { return false }
            idx = h.index(after: found)
        }
        return true
    }
}
