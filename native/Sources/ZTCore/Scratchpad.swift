// Scratchpad.swift — pure decision for the scratchpad drawer: a configured set of utility apps
// (Terminal, Notes, …) that a hotkey summons together and dismisses together. If a scratchpad app
// is already frontmost, the chord dismisses (hides) the set; otherwise it summons them. The actual
// activate/hide (NSWorkspace) and the auto-dismiss-on-focus-loss observer live in the agent; this
// is just the toggle decision, so it stays unit-testable. 0 AX (app activation, not Accessibility).

public enum Scratchpad {
    public enum Decision: Equatable { case summon, dismiss }

    /// Dismiss when the frontmost app is part of the scratchpad set; otherwise summon the set.
    public static func decide(frontmost: String?, apps: [String]) -> Decision {
        guard let f = frontmost?.lowercased() else { return .summon }
        return apps.contains { $0.lowercased() == f } ? .dismiss : .summon
    }

    /// Whether `app` belongs to the scratchpad set (used by the auto-dismiss focus observer).
    public static func contains(_ app: String?, in apps: [String]) -> Bool {
        guard let a = app?.lowercased() else { return false }
        return apps.contains { $0.lowercased() == a }
    }
}
