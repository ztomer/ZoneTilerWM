// Keybinding.swift — pure helpers for the keybind editor: match a captured set of modifier
// tokens back to a config alias (mash / HYPER / …) so edits are written in the same aliased
// form the rest of config.toml uses. The NSEvent capture itself lives in ZTUI (AppKit).

public enum Keybinding {

    /// The config alias whose modifier set exactly equals `tokens`, or nil if none matches.
    /// Deterministic: alias names are checked in sorted order, first exact match wins.
    public static func alias(forModifiers tokens: [String], aliases: [String: [String]]) -> String? {
        let want = Set(tokens)
        for name in aliases.keys.sorted() where Set(aliases[name] ?? []) == want { return name }
        return nil
    }
}
