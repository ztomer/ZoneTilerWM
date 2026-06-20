// ActionResult.swift — the serializable outcome of performing an ActionRequest, so a CLI / MCP
// front-end can report what happened. Built entirely from values the coordinator already
// returns (MoveOutcome, [AutoTiler.PlannedMove], focus ids, Bools) — nothing extra is queried,
// so reporting an outcome costs zero additional AX calls.

/// A serializable projection of `AutoTiler.PlannedMove` (which stays non-Codable — we project
/// rather than couple the auto-tiler's value type to the wire format).
public struct TiledMove: Codable, Equatable {
    public let windowId: Int
    public let zone: String
    public let tileIndex: TileIndex
    public let rect: ZTRect

    public init(windowId: Int, zone: String, tileIndex: TileIndex, rect: ZTRect) {
        self.windowId = windowId
        self.zone = zone
        self.tileIndex = tileIndex
        self.rect = rect
    }
}

public enum ModalMode: String, Codable, Equatable {
    case resize, windowHints, windowPeek, expose
}

/// Serializable error vocabulary. Mirrors `TilerCoordinator.MoveError` 1:1 and adds the
/// front-end-layer failures (unknown action, bad parameter).
public enum ActionError: Error, Codable, Equatable {
    case noFocusedWindow
    case noScreenForWindow
    case noZone(String)
    case noTile
    case unsupportedAction
    case invalidParameter(String)
    case agentUnavailable        // a front-end (e.g. the MCP shim) couldn't reach the agent

    /// Total mapping from the coordinator's move error.
    public init(_ moveError: TilerCoordinator.MoveError) {
        switch moveError {
        case .noFocusedWindow:  self = .noFocusedWindow
        case .noScreenForWindow: self = .noScreenForWindow
        case .noZone(let z):    self = .noZone(z)
        case .noTile:           self = .noTile
        }
    }
}

public enum ActionResult: Codable, Equatable {
    case tiled(windowId: Int, zone: String, tileIndex: Int, target: ZTRect, applied: Bool)
    case autoTiled(moves: [TiledMove])
    case focusCycled(focusedWindowId: Int?)
    case screenFocused(focusedWindowId: Int?)
    case monitorMoved(windowId: Int, zone: String, tileIndex: Int, target: ZTRect, applied: Bool)
    case zenToggled
    case windowMoved(windowId: Int, target: ZTRect, applied: Bool)   // nudge / throw
    case swapped(windowA: Int, windowB: Int, applied: Bool)
    case floatToggled(windowId: Int, floating: Bool)
    case audioSwitched(deviceName: String?)   // nil = nothing switched (e.g. <2 devices)
    case appToggled(app: String)
    case pomodoroUpdated(active: Bool, phase: String, timeLeftSec: Int)
    case modeToggled(mode: ModalMode)
    case configReloaded(ok: Bool)
    case layoutSaved(name: String, windowCount: Int)
    case layoutApplied(name: String, moved: Int)
    case synced(direction: String, files: [String])   // file-based settings sync export/import
    case suggestionsApplied(moves: [TiledMove])        // windows moved into their learned-preferred zones
    case scratchpadToggled(summoned: Bool, apps: [String])   // scratchpad drawer summoned (true) or dismissed
    case clusterApplied(name: String, moves: [TiledMove])    // an app-cluster profile was arranged
    case sandboxToggled(active: Bool, hidden: Int)           // session sandbox entered (true) / restored
    case failed(reason: ActionError)
}
