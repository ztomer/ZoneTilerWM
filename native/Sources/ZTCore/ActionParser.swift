// ActionParser.swift — the single source of the URL / CLI / MCP contract.
//
// Canonical form: an action NAME plus a flat [String:String] of PARAMS. The same shape drives
//   URL   zonetiler://<name>?<params>
//   CLI   zt <name> [--key value]
//   MCP   { "name": <name>, "arguments": <params> }
// `parse` maps that form to an ActionRequest; `canonical` is its inverse, so tests assert
// parse(canonical(x)) == x and the MCP tool list can be generated from one source of truth.
//
// Contract table:
//   tile          zone=<key>
//   autotile      —
//   focus-cycle   zone=<key>
//   focus-screen  direction=next|previous
//   move-monitor  direction=next|previous
//   zen           —
//   audio         device=next|<name>   (default: next)
//   app           name=<app>
//   pomodoro      command=enable|disable|reset
//   resize-mode   —
//   window-hints  —
//   reload        —

public enum ActionParser {

    // MARK: parse

    public static func parse(name: String, params: [String: String]) -> Result<ActionRequest, ActionError> {
        switch name {
        case "tile":
            return requireNonEmpty(params, "zone").map { .tileFocusedToZone(zone: $0) }
        case "autotile":
            return .success(.autoTileScreen)
        case "focus-cycle":
            return requireNonEmpty(params, "zone").map { .cycleFocus(zone: $0) }
        case "focus-screen":
            return direction(params).map { .focusScreen(direction: $0) }
        case "move-monitor":
            return direction(params).map { .moveFocusedToMonitor(direction: $0) }
        case "zen":
            return .success(.toggleZen)
        case "float":
            return .success(.toggleFloat)
        case "audio":
            let device = params["device"]
            if device == nil || device == "next" { return .success(.switchAudio(device: .next)) }
            return .success(.switchAudio(device: .named(device!)))
        case "app":
            return requireNonEmpty(params, "name").map { .appToggle(app: $0) }
        case "pomodoro":
            guard let raw = params["command"], let cmd = PomodoroCommand(rawValue: raw) else {
                return .failure(.invalidParameter("command"))
            }
            return .success(.pomodoro(cmd))
        case "resize-mode":
            return .success(.toggleResizeMode)
        case "window-hints":
            return .success(.toggleWindowHints)
        case "save-layout":
            return requireNonEmpty(params, "name").map { .saveLayout(name: $0) }
        case "apply-layout":
            return requireNonEmpty(params, "name").map { .applyLayout(name: $0) }
        case "reload":
            return .success(.reloadConfig)
        default:
            return .failure(.unsupportedAction)
        }
    }

    /// CLI argv: the first element is the action name, the rest are `--key value` pairs.
    public static func parse(argv: [String]) -> Result<ActionRequest, ActionError> {
        guard let name = argv.first else { return .failure(.unsupportedAction) }
        var params: [String: String] = [:]
        var i = 1
        while i < argv.count {
            let token = argv[i]
            guard token.hasPrefix("--") else { return .failure(.invalidParameter(token)) }
            let key = String(token.dropFirst(2))
            guard i + 1 < argv.count else { return .failure(.invalidParameter(key)) }
            params[key] = argv[i + 1]
            i += 2
        }
        return parse(name: name, params: params)
    }

    /// URL form: the host/path is the action name, the query is the params.
    public static func parse(urlPath: String, query: [String: String]) -> Result<ActionRequest, ActionError> {
        parse(name: urlPath, params: query)
    }

    // MARK: canonical (inverse)

    public static func canonical(_ request: ActionRequest) -> (name: String, params: [String: String]) {
        switch request {
        case .tileFocusedToZone(let zone):       return ("tile", ["zone": zone])
        case .autoTileScreen:                    return ("autotile", [:])
        case .cycleFocus(let zone):              return ("focus-cycle", ["zone": zone])
        case .focusScreen(let dir):              return ("focus-screen", ["direction": dir.rawValue])
        case .moveFocusedToMonitor(let dir):     return ("move-monitor", ["direction": dir.rawValue])
        case .toggleZen:                         return ("zen", [:])
        case .toggleFloat:                       return ("float", [:])
        case .switchAudio(let target):
            switch target {
            case .next:            return ("audio", ["device": "next"])
            case .named(let name): return ("audio", ["device": name])
            }
        case .appToggle(let app):                return ("app", ["name": app])
        case .pomodoro(let cmd):                 return ("pomodoro", ["command": cmd.rawValue])
        case .toggleResizeMode:                  return ("resize-mode", [:])
        case .toggleWindowHints:                 return ("window-hints", [:])
        case .saveLayout(let name):              return ("save-layout", ["name": name])
        case .applyLayout(let name):             return ("apply-layout", ["name": name])
        case .reloadConfig:                      return ("reload", [:])
        }
    }

    // MARK: helpers

    private static func requireNonEmpty(_ params: [String: String], _ key: String) -> Result<String, ActionError> {
        guard let v = params[key], !v.isEmpty else { return .failure(.invalidParameter(key)) }
        return .success(v)
    }

    private static func direction(_ params: [String: String]) -> Result<NavDirection, ActionError> {
        guard let raw = params["direction"], let dir = NavDirection(rawValue: raw) else {
            return .failure(.invalidParameter("direction"))
        }
        return .success(dir)
    }
}

// MARK: - Action catalog (the contract, enumerated)

/// One parameter of an action — drives the MCP tool inputSchema and CLI/URL `--help`.
public struct ActionParam: Equatable {
    public let name: String
    public let required: Bool
    public let description: String
    /// If non-nil, the allowed values (an `enum` in JSON Schema terms).
    public let allowed: [String]?
    public init(name: String, required: Bool, description: String, allowed: [String]? = nil) {
        self.name = name; self.required = required; self.description = description; self.allowed = allowed
    }
}

/// One action — its canonical name, a human description, and its parameters.
public struct ActionSpec: Equatable {
    public let name: String
    public let description: String
    public let params: [ActionParam]
    public init(name: String, description: String, params: [ActionParam] = []) {
        self.name = name; self.description = description; self.params = params
    }
}

public extension ActionParser {
    /// The full, ordered catalog of actions. The single source for the MCP tool list — every
    /// entry's `name`/`params` must round-trip through `parse`/`canonical`.
    static let catalog: [ActionSpec] = [
        ActionSpec(name: "tile", description: "Tile the focused window into a zone on its current screen.",
                   params: [ActionParam(name: "zone", required: true, description: "Zone key (e.g. h, j, k, l).")]),
        ActionSpec(name: "autotile", description: "Auto-tile every window on the focused screen."),
        ActionSpec(name: "focus-cycle", description: "Cycle focus among the windows in a zone.",
                   params: [ActionParam(name: "zone", required: true, description: "Zone key to cycle within.")]),
        ActionSpec(name: "focus-screen", description: "Focus the same app's window on the next/previous screen.",
                   params: [ActionParam(name: "direction", required: true, description: "Navigation direction.", allowed: ["next", "previous"])]),
        ActionSpec(name: "move-monitor", description: "Move the focused window to the next/previous monitor.",
                   params: [ActionParam(name: "direction", required: true, description: "Navigation direction.", allowed: ["next", "previous"])]),
        ActionSpec(name: "zen", description: "Toggle zen mode: minimize every other window on the focused screen."),
        ActionSpec(name: "float", description: "Float the focused window — exclude it from auto-tile (toggle)."),
        ActionSpec(name: "audio", description: "Switch the system audio output device.",
                   params: [ActionParam(name: "device", required: false, description: "Device name, or 'next' to cycle (default).")]),
        ActionSpec(name: "app", description: "Launch, focus, or hide an application (toggle).",
                   params: [ActionParam(name: "name", required: true, description: "Application name, e.g. Finder.")]),
        ActionSpec(name: "pomodoro", description: "Control the Pomodoro timer.",
                   params: [ActionParam(name: "command", required: true, description: "Timer command.", allowed: ["enable", "disable", "reset"])]),
        ActionSpec(name: "resize-mode", description: "Toggle the grid-line resize mode."),
        ActionSpec(name: "window-hints", description: "Toggle window hints (label each window, type to focus)."),
        ActionSpec(name: "save-layout", description: "Save the current window arrangement as a named layout.",
                   params: [ActionParam(name: "name", required: true, description: "Layout name, e.g. coding.")]),
        ActionSpec(name: "apply-layout", description: "Restore a previously saved named layout.",
                   params: [ActionParam(name: "name", required: true, description: "Layout name to restore.")]),
        ActionSpec(name: "reload", description: "Reload config.toml from disk."),
    ]
}
