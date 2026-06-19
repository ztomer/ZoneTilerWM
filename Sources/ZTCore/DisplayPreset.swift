// DisplayPreset.swift — pure matching for environment/topology presets: when the connected display
// set changes (dock/undock, plug a monitor), auto-run a configured action. A preset lists the
// display names that must all be present; the first matching preset (in config order) wins, so put
// specific presets before general ones, and an empty `displays` list matches always (a fallback).
// The action is a parsed ActionRequest (same vocabulary as rules/CLI). The screen-change trigger +
// dispatch live in the agent; this is just the match, so it stays unit-testable. 0 AX.

public struct DisplayPreset: Equatable {
    public let displays: [String]      // names that must ALL be connected ([] = match any)
    public let action: ActionRequest
    public init(displays: [String], action: ActionRequest) {
        self.displays = displays; self.action = action
    }
}

public enum DisplayPresetEngine {
    /// The action of the first preset whose required displays are all present in `current`
    /// (case-insensitive), or nil if none match.
    public static func match(current: [String], presets: [DisplayPreset]) -> ActionRequest? {
        let present = Set(current.map { $0.lowercased() })
        return presets.first { p in p.displays.allSatisfy { present.contains($0.lowercased()) } }?.action
    }
}
