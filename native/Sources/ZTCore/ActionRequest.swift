// ActionRequest.swift — the single, named, serializable vocabulary of "what the app can do".
//
// Every front-end (App Intents, URL scheme, CLI, MCP server) constructs an ActionRequest and
// hands it to the ZTSystem ActionDispatcher; the dispatcher is the single source of truth that
// executes it. This type names verbs and serializes — it executes nothing, holds no OS handle,
// imports no AppKit. Config (e.g. the AutoTiler.Config, `now`) is injected by the dispatcher,
// never smuggled in through a request, so a front-end can't override engine behavior.
//
// GUI-only openers (Settings/Analytics/About/Tutorial) are deliberately NOT part of the verb
// vocabulary — they are AppKit-bound and not meaningful headless. Add `openWindow` later if a
// front-end ever needs them.

/// Direction for screen/monitor navigation. A pure, Codable mirror of `ScreenNav.Direction`
/// (which is intentionally not Codable — serialization is this type's concern, not the
/// navigation core's).
public enum NavDirection: String, Codable, Equatable {
    case next, previous

    /// Bridge to the navigation core's direction (kept here so the conversion lives in one
    /// place; `ScreenNav.Direction` stays non-Codable — serialization is this type's job).
    public var screenNav: ScreenNav.Direction {
        switch self {
        case .next: return .next
        case .previous: return .previous
        }
    }
}

/// Audio-switch target: cycle to the next configured device, or jump to a named one.
public enum AudioTarget: Codable, Equatable {
    case next
    case named(String)
}

/// Pomodoro sub-command (one ActionRequest case namespaces all three under `pomodoro`).
public enum PomodoroCommand: String, Codable, Equatable {
    case enable, disable, reset
}

public enum ActionRequest: Codable, Equatable {
    // Pure-ish: executed by TilerCoordinator (ZTCore) alone.
    case tileFocusedToZone(zone: String)
    case autoTileScreen
    case cycleFocus(zone: String)
    case cycleZoneStack(direction: NavDirection)   // cycle focus through the windows stacked in the focused zone
    case applySuggestions   // move every window the `suggestions` resource flags into its learned-preferred zone
    case focusScreen(direction: NavDirection)
    case moveFocusedToMonitor(direction: NavDirection)
    case nudge(direction: MoveDirection)        // shift the focused window a step in a direction
    case throwWindow(direction: MoveDirection)  // snap the focused window to a screen edge
    case swap(direction: MoveDirection)         // swap the focused window with its neighbour
    case toggleZen
    case toggleFloat   // exclude/include the focused window from auto-tile

    // Needs ZTSystem adapters (AudioDevices / AppController).
    case switchAudio(device: AudioTarget)
    case appToggle(app: String)

    // Pomodoro: a ZTCore state machine owned by the agent.
    case pomodoro(PomodoroCommand)

    // Modal toggles: executed by zt-agent controllers (dispatcher routes via a hook).
    case toggleResizeMode
    case toggleWindowHints

    // Layout snapshots (capture/restore named arrangements). Agent-orchestrated (storage +
    // arrangement capture + window-targeted restore).
    case saveLayout(name: String)
    case applyLayout(name: String)

    // Lifecycle.
    case reloadConfig
    case syncExport   // copy live config + state into the user's synced folder ([sync] folder)
    case syncImport   // copy config + state back from the synced folder (backs up what it replaces)
}
