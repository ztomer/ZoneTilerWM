// DockPreview.swift — pure geometry for the DockDoor-style hover previews (feedback / Wave 4).
//
// Clean-room: behaviour inspired by DockDoor, but DockDoor is GPL and this app is proprietary, so
// NONE of its code is used — only the idea (hover a Dock tile → preview its windows). This file is
// the framework-free core: which tile the cursor is over, and where to anchor the preview panel for
// each Dock position. The AX read of tile frames and the live thumbnail capture live in the system
// layer; the hover/dwell/raise wiring lives in the agent. Everything here is a value transform.

/// Which screen edge the Dock sits on. (macOS allows bottom/left/right only; "hidden" is auto-hide
/// on ANY of these edges — modelled by the separate `autohidden` flag the controller tracks, not a
/// fourth edge.)
public enum DockEdge: String, Equatable {
    case bottom, left, right
}

/// One app tile in the Dock, as read from the Dock's AX tree: the app name + its on-screen frame
/// (top-left coordinates, matching ZTRect / AX / CGWindowList).
public struct DockItem: Equatable {
    public let appName: String
    public let frame: ZTRect
    public init(appName: String, frame: ZTRect) {
        self.appName = appName
        self.frame = frame
    }
}

public enum DockPreview {

    /// The tile whose frame contains `point` (cursor hit-test), or nil. A small `slop` expands each
    /// tile so a cursor resting just off the icon still counts (the gap between Dock tiles is dead
    /// space otherwise). First match wins; Dock tiles never overlap.
    public static func item(at point: (x: Double, y: Double), in items: [DockItem],
                            slop: Double = 0) -> DockItem? {
        items.first { it in
            let f = it.frame
            return point.x >= f.x - slop && point.x <= f.x + f.w + slop
                && point.y >= f.y - slop && point.y <= f.y + f.h + slop
        }
    }

    /// Top-left origin for a preview panel of `size`, anchored to `item` on the given Dock `edge`,
    /// clamped to stay on `screen`. Bottom dock → panel floats ABOVE the tile, centred on it; left
    /// dock → to the RIGHT of the tile, vertically centred; right dock → to the LEFT. `gap` is the
    /// breathing room between the panel and the tile.
    public static func panelOrigin(item: DockItem, size: (w: Double, h: Double),
                                   edge: DockEdge, screen: ZTRect, gap: Double = 12)
        -> (x: Double, y: Double) {
        let itemMidX = item.frame.x + item.frame.w / 2
        let itemMidY = item.frame.y + item.frame.h / 2
        var x: Double, y: Double
        switch edge {
        case .bottom:
            x = itemMidX - size.w / 2
            y = item.frame.y - gap - size.h
        case .left:
            x = item.frame.x + item.frame.w + gap
            y = itemMidY - size.h / 2
        case .right:
            x = item.frame.x - gap - size.w
            y = itemMidY - size.h / 2
        }
        // Clamp onto the screen so a tile near a corner doesn't push the panel off-display.
        x = min(max(x, screen.x), screen.x + screen.w - size.w)
        y = min(max(y, screen.y), screen.y + screen.h - size.h)
        return (x, y)
    }

    /// Parse the Dock's `orientation` default ("bottom" / "left" / "right") into a DockEdge,
    /// defaulting to bottom (the macOS default when the key is unset).
    public static func edge(fromOrientation raw: String?) -> DockEdge {
        DockEdge(rawValue: raw ?? "bottom") ?? .bottom
    }
}
