// ModifierFlags+Aliases.swift — one place to turn config modifier aliases (cmd/ctrl/alt/shift,
// as stored in config.toml) into AppKit NSEvent.ModifierFlags. Shared by the controllers that
// match a live modifier state (zone HUD, drag-to-snap) so the mapping isn't duplicated.

import AppKit

extension NSEvent.ModifierFlags {
    init(aliases names: [String]) {
        self = []
        for n in names {
            switch n.lowercased() {
            case "cmd", "command": insert(.command)
            case "ctrl", "control": insert(.control)
            case "alt", "option", "opt": insert(.option)
            case "shift": insert(.shift)
            default: break
            }
        }
    }

    /// The subset of flags this app's hotkeys care about (ignores caps-lock, fn, numeric pad, …).
    static let tilingRelevant: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
}
