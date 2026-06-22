// DockPreviewController.swift — DockDoor-style hover previews (Wave 4, clean-room).
//
// Ties the pieces together: a PASSIVE global mouse monitor (0 AX) hit-tests the cursor against the
// cached Dock-tile frames; dwelling on a tile shows the DockPreviewOverlay (window thumbnails);
// clicking a thumbnail raises that app. AX is touched only to (1) read tile frames — once, then
// refreshed at most every 2 s and only while the cursor is in the Dock band — and (2) activate the
// app on click. Gated [dock_previews] enabled (default off), like focus-follows-mouse.

import AppKit
import ApplicationServices
import ZTCore
import ZTSystem

final class DockPreviewController {
    private let observer = DockObserver()
    private let overlay = DockPreviewOverlay()
    var enabled = false { didSet { if enabled != oldValue { enabled ? start() : stop() } } }
    var thumbWidth: CGFloat = 240

    private var monitor: Any?
    private var edge: DockEdge = .bottom
    private var items: [DockItem] = []
    private var lastRefresh: Date = .distantPast
    private var dwell: Timer?
    private var hideTimer: Timer?
    private var hovered: DockItem?
    private var shown: DockItem?
    private var qaPinned = false   // forceShowForQA pins the panel so the hover hide-logic can't drop it

    private func start() {
        refreshDock(force: true)
        // Passive: a global monitor observes but never consumes events (0 AX).
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in self?.onMove() }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        dwell?.invalidate(); hideTimer?.invalidate()
        hovered = nil; shown = nil
        overlay.hide()
    }

    /// Re-read the Dock edge + tile frames (the only steady-state AX). Throttled to 2 s.
    private func refreshDock(force: Bool) {
        if !force && Date().timeIntervalSince(lastRefresh) < 2 { return }
        lastRefresh = Date()
        edge = observer.dockEdge()
        items = observer.dockItems()
    }

    /// CG/AX top-left point for the current cursor (NSEvent gives bottom-left, primary-relative).
    private func cursorTopLeft() -> (x: Double, y: Double) {
        let p = NSEvent.mouseLocation
        let primaryH = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height ?? 0
        return (Double(p.x), Double(primaryH - p.y))
    }

    /// Whether the cursor is in the ~120pt band along the Dock's edge (so we only refresh/hit-test
    /// near the Dock, never across the whole screen).
    private func inDockBand(_ pt: (x: Double, y: Double)) -> Bool {
        guard let f = items.first?.frame else {
            // No cached tiles yet — use the screen edge so a first approach can trigger a refresh.
            let scr = NSScreen.main?.frame ?? .zero
            switch edge {
            case .bottom: return pt.y >= Double(scr.height) - 120
            case .left:   return pt.x <= 120
            case .right:  return pt.x >= Double(scr.width) - 120
            }
        }
        switch edge {
        case .bottom: return pt.y >= f.y - 60
        case .left:   return pt.x <= f.x + f.w + 60
        case .right:  return pt.x >= f.x - 60
        }
    }

    private func onMove() {
        if qaPinned { return }
        let pt = cursorTopLeft()
        guard inDockBand(pt) else {                 // cursor left the Dock area → schedule hide
            if shown != nil, !cursorOverPanel() { scheduleHide() }
            hovered = nil
            return
        }
        refreshDock(force: false)
        let hit = DockPreview.item(at: pt, in: items, slop: 6)
        if hit?.appName == hovered?.appName { return }   // same tile (or same empty) → nothing new
        hovered = hit
        dwell?.invalidate()
        if let hit {
            hideTimer?.invalidate()
            if hit.appName == shown?.appName { return }  // already showing this app
            dwell = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: false) { [weak self] _ in
                self?.present(hit)
            }
        } else if shown != nil, !cursorOverPanel() {
            scheduleHide()
        }
    }

    /// QA: force the preview for the first Dock app that has capturable windows (deterministic panel
    /// render for screenshots / Gemini grading, no real hover needed).
    func forceShowForQA() {
        qaPinned = true
        refreshDock(force: true)
        log("dock-preview QA: \(items.count) tiles, edge=\(edge)")
        for item in items {
            let wins = DockPreviewOverlay.windows(forApp: item.appName)
            if let first = wins.first {
                log("dock-preview QA: showing '\(item.appName)' (\(wins.count) windows) at tile \(item.frame); highlight frame=\(first.frame)")
                present(item)
                overlay.forceHoverForQA(0)   // M1: also render the hover highlight + ring for the shot
                return
            }
        }
        log("dock-preview QA: no Dock app had capturable on-screen windows")
    }

    private func present(_ item: DockItem) {
        // Clamp the panel to the display the tile is ON (top-left CG), not a hardcoded primary — so a
        // multi-monitor / non-primary dock anchors on the right screen.
        let mid = CGPoint(x: item.frame.x + item.frame.w / 2, y: item.frame.y + item.frame.h / 2)
        overlay.show(appName: item.appName, item: item, edge: edge, thumbWidth: thumbWidth,
                     screen: screenCGFrame(containing: mid)) { pid, frame, action in
            DockWindowActions.perform(pid: pid, frame: frame, action)   // raise / close / minimize / fullscreen
        }
        shown = item
    }

    /// The CG (top-left) frame of the display containing `point`, defaulting to the primary.
    private func screenCGFrame(containing point: CGPoint) -> ZTRect {
        let primaryH = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height ?? 0
        for s in NSScreen.screens {
            let cg = ZTRect(x: s.frame.minX, y: primaryH - s.frame.maxY, w: s.frame.width, h: s.frame.height)
            if point.x >= cg.x && point.x < cg.x + cg.w && point.y >= cg.y && point.y < cg.y + cg.h { return cg }
        }
        return ZTRect(x: 0, y: 0, w: Double(NSScreen.main?.frame.width ?? 0), h: Double(primaryH))
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let self else { return }
            if !self.cursorOverPanel() { self.overlay.hide(); self.shown = nil }
        }
    }

    /// True when the cursor is over the shown preview panel — so a move onto the panel (e.g. to click a
    /// traffic light) doesn't trigger the hide timer and yank it away. Hit-tests against the panel's
    /// known frame (bottom-left global, matching NSEvent.mouseLocation).
    private func cursorOverPanel() -> Bool {
        guard let f = overlay.panelFrame else { return false }
        return NSMouseInRect(NSEvent.mouseLocation, f, false)
    }
}
