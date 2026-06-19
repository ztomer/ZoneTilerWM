// DragSnapController.swift — drag-to-snap. While [drag_snap] is enabled, watch global left-mouse
// drags with a PASSIVE NSEvent global monitor (deliberately NOT an active CGEventTap: it observes
// only, makes zero AX calls for detection, and is far less EDR-alarming — the AX-call budget and
// SentinelOne are the gates here). When a drag ends with the tiling modifier held, snap the
// dragged (frontmost) window into the zone under the cursor by dispatching the SAME
// tileFocusedToZone action the keyboard hotkey uses. Gated, default off; requiring the modifier at
// drop means an ordinary window drag is never hijacked.

import AppKit
import ZTCore
import ZTSystem

final class DragSnapController {
    private let screens: NSScreenProvider
    private let monitorManager: MonitorManager
    private let zoneConfig: () -> ZoneConfig
    private let offset: (_ monitor: String, _ axis: String, _ index: Int) -> Double
    private let modifier: () -> [String]
    private let snap: (_ zone: String) -> Void

    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var dragging = false

    init(screens: NSScreenProvider, monitorManager: MonitorManager,
         zoneConfig: @escaping () -> ZoneConfig,
         offset: @escaping (_ monitor: String, _ axis: String, _ index: Int) -> Double,
         modifier: @escaping () -> [String],
         snap: @escaping (_ zone: String) -> Void) {
        self.screens = screens; self.monitorManager = monitorManager
        self.zoneConfig = zoneConfig; self.offset = offset; self.modifier = modifier; self.snap = snap
    }

    var isRunning: Bool { dragMonitor != nil }

    private var downMonitor: Any?

    func start() {
        guard dragMonitor == nil else { return }
        // A fresh press clears any stale drag state — closes the "missed mouse-up" window so a
        // later unrelated up (with the modifier coincidentally held) can't trigger a phantom snap.
        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.dragging = false
        }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            self?.dragging = true
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.mouseUp()
        }
    }

    func stop() {
        if let m = downMonitor { NSEvent.removeMonitor(m) }
        if let m = dragMonitor { NSEvent.removeMonitor(m) }
        if let m = upMonitor { NSEvent.removeMonitor(m) }
        downMonitor = nil; dragMonitor = nil; upMonitor = nil; dragging = false
    }

    /// QA/debug: snap as if a modifier-held drag just ended under the cursor (no real drag needed).
    func forceSnap() { performSnap() }

    private func mouseUp() {
        defer { dragging = false }   // always reset, even on the early-returns below
        guard dragging else { return }
        // Only snap when the tiling modifier is held at drop — never hijack a plain drag.
        let held = NSEvent.modifierFlags.intersection(.tilingRelevant)
        let target = NSEvent.ModifierFlags(aliases: modifier())
        guard !target.isEmpty, held == target else { return }
        performSnap()
    }

    private func performSnap() {
        guard let screen = screens.screenUnderMouse() else { log("drag-snap: no screen under cursor"); return }  // 0 AX
        guard let loc = CGEvent(source: nil)?.location else { log("drag-snap: no cursor location"); return }      // 0 AX
        let info = ZoneCalculator.ScreenInfo(name: screen.name, frame: screen.frame)
        let key = String(monitorManager.id(forUUID: screen.uuid))
        let zones = ZoneCalculator.computeZones(screen: info, config: zoneConfig(),
                                                offsets: { [offset] axis, index in offset(key, axis, index) }).zones
        guard let zone = DragSnap.target(atX: Double(loc.x), y: Double(loc.y), zones: zones) else {
            log("drag-snap: drop at (\(Int(loc.x)),\(Int(loc.y))) matched no zone on \(screen.name)"); return
        }
        log("drag-snap: → zone \(zone) on \(screen.name)")
        snap(zone)
    }
}
