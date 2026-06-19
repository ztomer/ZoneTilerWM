// FocusFollowsMouse.swift — pure "which window is under the cursor" for the focus-follows-mouse
// feature. Given the windows on the cursor's screen front-to-back (CGWindowList z-order) and the
// cursor point, return the topmost window containing it. The passive mouse monitor, the dwell
// timer, and the focus call (the ONLY Accessibility call — issued once per settle on a new window)
// live in the agent; this is just the hit-test, so it stays unit-testable. 0 AX.

public enum FocusFollowsMouse {
    /// The id of the topmost (front-most) window whose frame contains (x, y), or nil if none.
    /// `windows` must be front-to-back (CGWindowList order). Half-open on far edges so adjacent
    /// windows don't both claim a shared boundary pixel.
    public static func topWindow(at x: Double, y: Double, windows: [(id: Int, frame: ZTRect)]) -> Int? {
        windows.first { w in
            x >= w.frame.x && x < w.frame.x + w.frame.w && y >= w.frame.y && y < w.frame.y + w.frame.h
        }?.id
    }
}
