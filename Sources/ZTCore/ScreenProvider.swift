// ScreenProvider.swift — the screen-enumeration boundary. ZTCore depends only on this
// protocol + the ScreenSnapshot value; ZTSystem provides an NSScreen/CGDisplay-backed impl.
// Coordinates are top-left CG space (matching ZTRect / AX / CGWindowList).

public struct ScreenSnapshot: Equatable {
    public let uuid: String        // stable display UUID (survives reconnects)
    public let name: String
    public let frame: ZTRect       // visible frame (excludes menu bar / dock)
    public let fullFrame: ZTRect   // full display bounds

    public init(uuid: String, name: String, frame: ZTRect, fullFrame: ZTRect) {
        self.uuid = uuid; self.name = name; self.frame = frame; self.fullFrame = fullFrame
    }
}

public protocol ScreenProvider: AnyObject {
    func allScreens() -> [ScreenSnapshot]
    func mainScreen() -> ScreenSnapshot?
    func screen(uuid: String) -> ScreenSnapshot?
}

public extension ScreenProvider {
    /// The screen whose full frame contains the given point (top-left CG coords), if any.
    func screen(containing point: (x: Double, y: Double)) -> ScreenSnapshot? {
        allScreens().first { s in
            point.x >= s.fullFrame.x && point.x < s.fullFrame.x + s.fullFrame.w &&
            point.y >= s.fullFrame.y && point.y < s.fullFrame.y + s.fullFrame.h
        }
    }
}
