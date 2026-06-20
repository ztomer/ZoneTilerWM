// WindowSystem.swift — the window-control boundary the coordinator drives. ZTCore depends
// only on this protocol + the LiveWindow value; ZTSystem provides the AX-backed impl. Keyed
// by the real window id (CGWindowID as Int), distinct from the solver's label-based
// WindowSnapshot.

public struct LiveWindow: Equatable {
    public let id: Int            // CGWindowID
    public let appName: String
    public let frame: ZTRect      // top-left CG coords
    public let screenUUID: String?
    public let pid: Int?          // process identifier (for CGS space queries)

    public init(id: Int, appName: String, frame: ZTRect, screenUUID: String?, pid: Int? = nil) {
        self.id = id; self.appName = appName; self.frame = frame; self.screenUUID = screenUUID; self.pid = pid
    }
}

public protocol WindowSystem: AnyObject {
    /// The globally-focused window (front window of the frontmost app), if any.
    func focusedWindow() -> LiveWindow?
    /// Standard windows currently on the given screen (for occupancy/placement).
    func windows(onScreen uuid: String) -> [LiveWindow]
    /// Move the focused window to `rect` (top-left CG). Returns success.
    @discardableResult
    func moveFocusedWindow(to rect: ZTRect) -> Bool

    /// Move a specific window (by CGWindowID) to `rect`. Used by auto-tiling. Returns success.
    @discardableResult
    func move(windowId: Int, to rect: ZTRect) -> Bool

    /// Raise + focus a specific window (by CGWindowID). Returns success.
    @discardableResult
    func focus(windowId: Int) -> Bool

    /// Minimize / unminimize a specific window (by CGWindowID). Returns success.
    @discardableResult
    func setMinimized(_ minimized: Bool, windowId: Int) -> Bool
}
