// SkyLightBorderRenderer.swift — the intended second border backend: drawing the outline as a
// window created directly on the window server via private SkyLight APIs (the JankyBorders
// technique, reimplemented clean-room — no GPL code).
//
// DISABLED. A window-server window has no reliable public equivalent of
// NSWindow.ignoresMouseEvents, so the filled window captured mouse input — clicking a window's
// body did nothing and focus churned (the border appeared to "toggle"). Making it click-through
// needs a correct rounded *input-shape* region (a thin hollow ring that follows the rounded
// corners); a rectangular ring also blocks the title-bar buttons, and the rounded-region path
// couldn't be validated without risking the always-running agent. So `init?()` returns nil and
// FocusBorderController falls back to the public, reliably click-through OverlayBorderRenderer.
//
// The full window-server drawing implementation is preserved in git history (commit e750328)
// for a future, properly input-shaped attempt.

import ZTCore

final class SkyLightBorderRenderer: BorderRenderer {
    init?() { return nil }                         // always fall back to the overlay renderer
    func render(frame: ZTRect?, style: BorderStyle) {}
}
