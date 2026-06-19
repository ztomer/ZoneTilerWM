// CLIFormat.swift — pure formatting + routing for the zonetiler-cli front-end, kept here so the
// executable stays thin I/O and the human-readable output is unit-testable. No AppKit, no I/O.

public enum CLIFormat {

    // MARK: result → human summary

    public static func summary(_ result: ActionResult) -> String {
        switch result {
        case .tiled(let id, let zone, let tile, let target, let applied):
            return "tiled window \(id) → zone \(zone) tile \(tile) [\(applied ? "applied" : "not applied")] @ \(rect(target))"
        case .autoTiled(let moves):
            let detail = moves.map { "  window \($0.windowId) → \($0.zone) \($0.tileIndex.sortKey) @ \(rect($0.rect))" }
            return (["auto-tiled \(moves.count) window(s)"] + detail).joined(separator: "\n")
        case .focusCycled(let id):
            return id.map { "focused window \($0)" } ?? "no window to focus in that zone"
        case .screenFocused(let id):
            return id.map { "focused window \($0) on adjacent screen" } ?? "no adjacent-screen window to focus"
        case .monitorMoved(let id, let zone, let tile, let target, let applied):
            return "moved window \(id) → monitor zone \(zone) tile \(tile) [\(applied ? "applied" : "not applied")] @ \(rect(target))"
        case .zenToggled:
            return "toggled zen mode"
        case .windowMoved(let id, let target, let applied):
            return "moved window \(id) [\(applied ? "applied" : "not applied")] @ \(rect(target))"
        case .swapped(let a, let b, let applied):
            return "swapped windows \(a) ↔ \(b) [\(applied ? "applied" : "not applied")]"
        case .floatToggled(let id, let floating):
            return "window \(id) \(floating ? "floated (excluded from auto-tile)" : "unfloated")"
        case .audioSwitched(let name):
            return name.map { "switched audio output → \($0)" } ?? "no audio device switched"
        case .appToggled(let app):
            return "toggled app \(app)"
        case .pomodoroUpdated(let active, let phase, let left):
            return active ? "pomodoro \(phase): \(left)s left" : "pomodoro off"
        case .modeToggled(let mode):
            return "toggled \(mode.rawValue) mode"
        case .configReloaded(let ok):
            return ok ? "config reloaded" : "config reload failed (kept running config)"
        case .layoutSaved(let name, let count):
            return "saved layout '\(name)' (\(count) window\(count == 1 ? "" : "s"))"
        case .layoutApplied(let name, let moved):
            return "applied layout '\(name)' (\(moved) window\(moved == 1 ? "" : "s") moved)"
        case .synced(let direction, let files):
            return files.isEmpty ? "sync \(direction): nothing to copy"
                                 : "sync \(direction): \(files.count) file\(files.count == 1 ? "" : "s") (\(files.joined(separator: ", ")))"
        case .suggestionsApplied(let moves):
            if moves.isEmpty { return "no suggestions to apply (every window is in its usual zone)" }
            let detail = moves.map { "  window \($0.windowId) → \($0.zone) \($0.tileIndex.sortKey)" }
            return (["applied \(moves.count) suggestion\(moves.count == 1 ? "" : "s")"] + detail).joined(separator: "\n")
        case .scratchpadToggled(let summoned, let apps):
            return "scratchpad \(summoned ? "summoned" : "dismissed"): \(apps.joined(separator: ", "))"
        case .clusterApplied(let name, let moves):
            return "cluster '\(name)': arranged \(moves.count) window\(moves.count == 1 ? "" : "s")"
        case .failed(let reason):
            return "error: \(describe(reason))"
        }
    }

    public static func summary(_ result: QueryResult) -> String {
        switch result {
        case .arrangement(let windows):
            if windows.isEmpty { return "(no windows)" }
            return windows.map { "monitor \($0.monitor)  \($0.app)#\($0.windowId)  \($0.zone ?? "—")  @ \(rect($0.frame))" }
                .joined(separator: "\n")
        case .zones(let screens):
            return screens.map { "monitor \($0.monitor) (\($0.screenName)): \($0.zones.joined(separator: " "))" }
                .joined(separator: "\n")
        case .placementStats(let stats):
            if stats.isEmpty { return "(no learned placements)" }
            return stats.map { "\($0.app.isEmpty ? "(unknown)" : $0.app)  monitor \($0.monitor)  zone \($0.zone) tile \($0.tile.sortKey)  ×\($0.count)" }
                .joined(separator: "\n")
        case .suggestions(let suggestions):
            if suggestions.isEmpty { return "(no suggestions — every window is in its usual zone)" }
            return suggestions.map { "\($0.app.isEmpty ? "(unknown)" : $0.app)#\($0.windowId)  monitor \($0.monitor)  \($0.currentZone ?? "—") → \($0.suggestedZone)  (weight \(String(format: "%.1f", $0.weight)))" }
                .joined(separator: "\n")
        case .unavailable(let why):
            return "unavailable: \(why)"
        }
    }

    /// Whether an action outcome is a failure (drives the CLI exit code).
    public static func isFailure(_ result: ActionResult) -> Bool {
        if case .failed = result { return true }
        return false
    }

    public static func describe(_ error: ActionError) -> String {
        switch error {
        case .noFocusedWindow:         return "no focused window"
        case .noScreenForWindow:       return "no screen for the focused window"
        case .noZone(let z):           return "unknown zone '\(z)'"
        case .noTile:                  return "no available tile"
        case .unsupportedAction:       return "unsupported action"
        case .invalidParameter(let p): return "invalid or missing parameter '\(p)'"
        case .agentUnavailable:        return "agent not reachable (is zt-agent running?)"
        }
    }

    // MARK: usage (self-documenting, generated from the catalog)

    public static func usage() -> String {
        var lines = ["zonetiler-cli — control a running ZoneTilerWM agent.", "",
                     "USAGE:", "  zonetiler-cli <action> [--key value …]   run an action",
                     "  zonetiler-cli get <resource>             read a resource",
                     "  zonetiler-cli list | --help              show this help",
                     "  (append --json for machine-readable output)", "", "ACTIONS:"]
        for spec in ActionParser.catalog {
            let params = spec.params.map { p -> String in
                let opt = p.allowed.map { " (\($0.joined(separator: "|")))" } ?? ""
                return p.required ? "--\(p.name)\(opt)" : "[--\(p.name)\(opt)]"
            }.joined(separator: " ")
            lines.append("  \(pad(spec.name)) \(params.isEmpty ? "" : params + "  ")\(spec.description)")
        }
        lines.append("")
        lines.append("RESOURCES (get <resource>):")
        for q in QueryRequest.allCases {
            lines.append("  \(pad(cliName(q))) \(q.description)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: resource name mapping (CLI ergonomics: kebab-case)

    /// The kebab-case CLI alias for a resource (e.g. `placement-stats` for `.placementStats`).
    public static func cliName(_ q: QueryRequest) -> String {
        switch q {
        case .arrangement:    return "arrangement"
        case .zones:          return "zones"
        case .placementStats: return "placement-stats"
        case .suggestions:    return "suggestions"
        }
    }

    /// Parse a CLI resource name (kebab-case or the raw enum name) into a QueryRequest.
    public static func resource(_ name: String) -> QueryRequest? {
        QueryRequest.allCases.first { cliName($0) == name || $0.rawValue == name }
    }

    // MARK: helpers

    /// Right-pad to a fixed column WITHOUT truncating (String.padding(toLength:) would clip
    /// names longer than the width, e.g. "placement-stats").
    private static func pad(_ s: String, _ width: Int = 16) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }

    private static func rect(_ r: ZTRect) -> String {
        func n(_ v: Double) -> String { String(Int(v.rounded())) }
        return "x=\(n(r.x)) y=\(n(r.y)) w=\(n(r.w)) h=\(n(r.h))"
    }
}
