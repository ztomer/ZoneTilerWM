// SkyLightBorderRenderer.swift — ZTSystem: the second border backend, drawing the outline as a
// window created directly on the window server via private SkyLight APIs. This is the technique
// JankyBorders uses (lower latency, draws across spaces and above every layer); it is
// reimplemented here from scratch — no GPL code is involved (see the license discussion).
//
// The private symbols are resolved at runtime with dlsym from SkyLight.framework, so a missing
// symbol fails the initializer gracefully and FocusBorderController falls back to the public
// OverlayBorderRenderer rather than crashing.
//
// Status: scaffolded with a graceful fallback. The window-server drawing path is implemented and
// live-tested in a dedicated step; until then `init?` returns nil and the overlay backend is used.

import AppKit
import ZTCore

final class SkyLightBorderRenderer: BorderRenderer {
    /// Returns nil until the private window-server path is implemented + live-verified, so the
    /// controller transparently uses the overlay renderer. (Avoids shipping an unvalidated
    /// private-API path that could destabilize the agent.)
    init?() {
        return nil
    }

    func render(frame: ZTRect?, style: BorderStyle) {
        // Implemented alongside the live-tested SkyLight path.
    }
}
