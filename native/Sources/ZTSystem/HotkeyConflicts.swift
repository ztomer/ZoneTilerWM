// HotkeyConflicts.swift — detect when two different actions are bound to the same modifier+key
// (e.g. Pomodoro reset and Focus-zone-0 both on ⇧⌃⌘0). Pure logic over a flat binding list;
// ConfigLoader.LoadedConfig.hotkeyConflicts() assembles the list from the config.

import Foundation

public enum HotkeyConflicts {

    public struct Binding {
        public let modifier: [String]   // resolved tokens, e.g. ["ctrl","cmd"]
        public let key: String
        public let label: String        // human action name
        public init(modifier: [String], key: String, label: String) {
            self.modifier = modifier; self.key = key; self.label = label
        }
    }

    public struct Conflict: Equatable {
        public let combo: String        // glyph form, e.g. "⇧⌃⌘0"
        public let actions: [String]    // the clashing action names (sorted, deduped)
        public var description: String { "\(combo) — " + actions.joined(separator: "  ·  ") }
    }

    private static let glyphOrder = ["shift", "ctrl", "alt", "cmd"]
    private static let glyph = ["shift": "⇧", "ctrl": "⌃", "alt": "⌥", "cmd": "⌘"]

    static func comboGlyph(modifier: [String], key: String) -> String {
        let mods = Set(modifier)
        let g = glyphOrder.filter(mods.contains).compactMap { glyph[$0] }.joined()
        return g + key.uppercased()
    }

    /// Conflicts = combos (same modifier set + key) bound to more than one distinct action.
    public static func find(_ bindings: [Binding]) -> [Conflict] {
        var byCombo: [String: (mods: [String], key: String, labels: Set<String>)] = [:]
        for b in bindings where !b.key.isEmpty {
            let id = b.modifier.map { $0.lowercased() }.sorted().joined(separator: "+") + "\u{1}" + b.key.lowercased()
            byCombo[id, default: (b.modifier, b.key, [])].labels.insert(b.label)
        }
        return byCombo.values
            .filter { $0.labels.count > 1 }
            .map { Conflict(combo: comboGlyph(modifier: $0.mods, key: $0.key), actions: $0.labels.sorted()) }
            .sorted { $0.combo < $1.combo }
    }
}
