// WindowSystem.swift — the window-control boundary the coordinator drives. ZTCore depends
// only on this protocol + the LiveWindow value; ZTSystem provides the AX-backed impl. Keyed
// by the real window id (CGWindowID as Int), distinct from the solver's label-based
// WindowSnapshot.

public struct LiveWindow: Equatable {
    public let id: Int            // CGWindowID
    public let appName: String
    public let frame: ZTRect      // top-left CG coords
    public let screenUUID: String?

    public init(id: Int, appName: String, frame: ZTRect, screenUUID: String?) {
        self.id = id; self.appName = appName; self.frame = frame; self.screenUUID = screenUUID
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
}
