// ResizeModeController.swift — the resize-mode modal, extracted from AgentController.
// Picks the interior zone grid lines nearest the focused window, shows the cyan grid overlay,
// and binds bare arrows + escape: arrows nudge those lines' offsets (persisted via
// ResizeManager) and the overlay redraws live. Coherent port of the Lua resize mode (which was
// internally inconsistent — see ARCHITECTURE.md).

import Foundation
import ZTCore
import ZTSystem

final class ResizeModeController {
    private let binder: CarbonHotkeyBinder
    private let screens: NSScreenProvider
    private let windowSystem: AXWindowSystem
    private let monitorManager: MonitorManager
    private let resizeManager: ResizeManager        // shared with the coordinator's offsetProvider
    private let resizeStorage: Storage
    private let zoneConfig: () -> ZoneConfig         // live (config can reload)

    private let overlay = GridOverlay()
    private var active = false
    private var modalIDs: [UInt32] = []
    private var monitorKey = ""
    private var screenFrame = ZTRect(x: 0, y: 0, w: 0, h: 0)
    private var cols = 1
    private var rows = 1
    private var vIndex: Int?
    private var hIndex: Int?

    init(binder: CarbonHotkeyBinder, screens: NSScreenProvider, windowSystem: AXWindowSystem,
         monitorManager: MonitorManager, resizeManager: ResizeManager, resizeStorage: Storage,
         zoneConfig: @escaping () -> ZoneConfig) {
        self.binder = binder
        self.screens = screens
        self.windowSystem = windowSystem
        self.monitorManager = monitorManager
        self.resizeManager = resizeManager
        self.resizeStorage = resizeStorage
        self.zoneConfig = zoneConfig
    }

    func toggle() { active ? exit() : enter() }

    /// Enter: pick the interior grid lines nearest the focused window, show the overlay, and
    /// bind bare arrows + escape. Arrows nudge those lines' offsets; the overlay redraws live.
    func enter() {
        guard let focused = windowSystem.focusedWindow(), let uuid = focused.screenUUID,
              let screen = screens.screen(uuid: uuid) else { return }
        let cfg = zoneConfig()
        let info = ZoneCalculator.ScreenInfo(name: screen.name, frame: screen.frame)
        guard let key = ZoneCalculator.layoutKey(for: info, config: cfg),
              let grid = cfg.grids[key] else {
            log("zt-agent: resize mode — no grid for the focused screen"); return
        }
        monitorKey = String(monitorManager.id(forUUID: uuid))
        screenFrame = screen.frame
        cols = grid.cols; rows = grid.rows
        let cx = focused.frame.x + focused.frame.w / 2, cy = focused.frame.y + focused.frame.h / 2
        vIndex = GridLines.nearestInteriorIndex(to: cx, start: screen.frame.x, total: screen.frame.w, count: grid.cols)
        hIndex = GridLines.nearestInteriorIndex(to: cy, start: screen.frame.y, total: screen.frame.h, count: grid.rows)

        active = true
        redraw()
        bindModal()
        log("zt-agent: resize mode ON (grid \(grid.cols)x\(grid.rows), monitor \(monitorKey)) — arrows nudge lines, ESC exits")
    }

    func exit() {
        guard active else { return }
        active = false
        for id in modalIDs { binder.unbind(id) }
        modalIDs = []
        overlay.hide()
        resizeManager.save(to: resizeStorage)
        log("zt-agent: resize mode OFF (offsets saved)")
    }

    private func bindModal() {
        func reg(_ keyName: String, _ action: @escaping () -> Void) {
            if let code = KeyMap.keyCode(for: keyName), let id = binder.register(keyCode: code, modifiers: 0, action: action) {
                modalIDs.append(id)
            }
        }
        reg("left")  { [weak self] in self?.adjust(axis: "x", delta: -1) }
        reg("right") { [weak self] in self?.adjust(axis: "x", delta: +1) }
        reg("up")    { [weak self] in self?.adjust(axis: "y", delta: -1) }
        reg("down")  { [weak self] in self?.adjust(axis: "y", delta: +1) }
        reg("escape") { [weak self] in self?.exit() }
    }

    private func adjust(axis: String, delta: Double) {
        guard active else { return }
        let index = axis == "x" ? vIndex : hIndex
        guard let index else { return }   // no interior line on this axis (1xN / Nx1)
        resizeManager.adjust(monitor: monitorKey, axis: axis, index: index, delta: delta)
        redraw()
    }

    private func redraw() {
        let lines = GridLines.positions(frame: screenFrame, cols: cols, rows: rows) { [resizeManager, monitorKey] axis, idx in
            resizeManager.getOffset(monitor: monitorKey, axis: axis, index: idx)
        }
        overlay.show(screenCGFrame: screenFrame, verticalX: lines.vertical, horizontalY: lines.horizontal)
    }
}
