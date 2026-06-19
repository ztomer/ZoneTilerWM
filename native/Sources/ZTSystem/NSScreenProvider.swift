// NSScreenProvider.swift — ScreenProvider backed by NSScreen + CGDisplay. Read-only; needs
// no permissions. Stable UUIDs via CGDisplayCreateUUIDFromDisplayID (same identity
// Hammerspoon's screen:getUUID uses). Full frames come from CGDisplayBounds (already
// top-left CG); the visible frame is derived by applying NSScreen's visibleFrame insets
// (which are origin-independent) to the full frame.

import Foundation
import AppKit
import ZTCore

public final class NSScreenProvider: ScreenProvider {

    public init() {}

    public func allScreens() -> [ScreenSnapshot] {
        NSScreen.screens.compactMap(snapshot(for:))
    }

    public func mainScreen() -> ScreenSnapshot? {
        let mainID = CGMainDisplayID()
        return NSScreen.screens.first { displayID(of: $0) == mainID }.flatMap(snapshot(for:))
    }

    public func screen(uuid: String) -> ScreenSnapshot? {
        allScreens().first { $0.uuid == uuid }
    }

    /// The screen under the mouse cursor (0 AX — pure AppKit), else the main screen. Lets callers
    /// pick the active screen without an AX `focusedWindow()` round trip.
    public func screenUnderMouse() -> ScreenSnapshot? {
        let mouse = NSEvent.mouseLocation
        let target = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        return target.flatMap(snapshot(for:))
    }

    // MARK: - Internals

    private func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private func uuidString(for displayID: CGDirectDisplayID) -> String? {
        guard let cfuuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let cfStr = CFUUIDCreateString(nil, cfuuid) else { return nil }
        return cfStr as String
    }

    private func snapshot(for screen: NSScreen) -> ScreenSnapshot? {
        let id = displayID(of: screen)
        guard id != 0, let uuid = uuidString(for: id) else { return nil }

        // Full frame: top-left CG coords directly from CoreGraphics.
        let cg = CGDisplayBounds(id)
        let full = ZTRect(x: cg.origin.x, y: cg.origin.y, w: cg.size.width, h: cg.size.height)

        // Visible frame: apply NSScreen visibleFrame insets (origin-independent magnitudes).
        let f = screen.frame
        let v = screen.visibleFrame
        let topInset = f.maxY - v.maxY        // menu bar
        let bottomInset = v.minY - f.minY     // dock
        let leftInset = v.minX - f.minX
        let rightInset = f.maxX - v.maxX
        let visible = ZTRect(
            x: full.x + leftInset,
            y: full.y + topInset,
            w: full.w - leftInset - rightInset,
            h: full.h - topInset - bottomInset)

        let name = screen.localizedName
        return ScreenSnapshot(uuid: uuid, name: name, frame: visible, fullFrame: full)
    }
}
