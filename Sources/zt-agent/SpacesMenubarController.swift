// SpacesMenubarController.swift — the live menu-bar Spaces widget (Phase 3). Renders the pure
// SpacesMenubar layout (Kare/Rams subset: per-monitor bracket, current filled / others hollow) into a
// template NSStatusItem, refreshes on Space/display changes, and switches Spaces on click.
//
// Gated: only appears when `[ui] spaces_menubar` is on AND the experimental real-Spaces reader is
// available (it needs real Spaces to show). Otherwise it's torn down.

import AppKit
import ZTCore
import ZTSystem

final class SpacesMenubarController {
    private var item: NSStatusItem?
    private let nameStore = SpaceNameStore()
    private let enabled: () -> Bool
    private let realSpaces: () -> Bool
    private let switchMethod: () -> String
    private let bracketStyle: () -> String

    private var layout: SpacesMenubar.Layout?
    private var cellSpaces: [RealSpace] = []                 // flat index → space (for click → switch)
    private var byDisplay: [String: [RealSpace]] = [:]

    init(enabled: @escaping () -> Bool, realSpaces: @escaping () -> Bool,
         switchMethod: @escaping () -> String = { "auto" }, bracketStyle: @escaping () -> String = { "bold" }) {
        self.enabled = enabled
        self.realSpaces = realSpaces
        self.switchMethod = switchMethod
        self.bracketStyle = bracketStyle
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(refresh), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// The Spaces source for the current settings: the private CGS reader when experimental real Spaces
    /// is on (and compiled in), else the App-Store-safe public marker-window provider.
    private var provider: SpacesProvider { Spaces.provider(experimentalEnabled: realSpaces()) }

    /// (Re)build the widget, or tear it down if the feature is off / unavailable.
    @objc func refresh() {
        let provider = self.provider
        provider.start()   // idempotent; lets the public provider begin learning Spaces
        guard enabled(), provider.isAvailable else {
            log("spaces-menubar: gate off (enabled=\(enabled()) available=\(provider.isAvailable))")
            teardown(); return
        }
        let spaces = provider.spacesByDisplay()
        // CGS can momentarily return nothing DURING a Space switch — do NOT tear the widget down on a
        // transient empty read (that's what made it vanish on click); keep the last render.
        guard !spaces.isEmpty else { return }
        byDisplay = spaces
        let (groups, flat) = buildGroups(from: spaces, override: nil)
        cellSpaces = flat
        if item == nil {
            let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            i.button?.target = self
            i.button?.action = #selector(clicked(_:))
            i.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            i.isVisible = true
            item = i
        }
        render(groups, flashIndex: nil)
    }

    /// Build the per-monitor input groups. `override` forces one display's current Space to a given id
    /// (for the optimistic fill-move on click, before the real switch lands).
    private func buildGroups(from spaces: [String: [RealSpace]], override: (display: String, id: Int)?)
        -> (groups: [SpacesMenubar.InputGroup], flat: [RealSpace]) {
        var groups: [SpacesMenubar.InputGroup] = []
        var flat: [RealSpace] = []
        for uuid in orderedDisplayUUIDs(spaces.keys) {
            guard let list = spaces[uuid] else { continue }
            let cells = list.enumerated().map { (j, sp) -> SpacesMenubar.InputSpace in
                flat.append(sp)
                let isCurrent = (override?.display == uuid) ? (sp.id == override!.id) : sp.isCurrent
                let label = nameStore.name(for: sp).map { String($0.prefix(6)) } ?? (sp.isFullscreen ? "⛶" : "\(j + 1)")
                return .init(label: label, isCurrent: isCurrent, isFullscreen: sp.isFullscreen)
            }
            groups.append(.init(monitorLabel: uuid, spaces: cells))
        }
        return (groups, flat)
    }

    private func render(_ groups: [SpacesMenubar.InputGroup], flashIndex: Int?) {
        let lay = SpacesMenubar.layout(groups, showGlyph: false)   // must match the renderer (no glyph)
        layout = lay
        let style = SpacesMenubarRenderer.BracketStyle(rawValue: bracketStyle()) ?? .bold
        item?.button?.image = SpacesMenubarRenderer.image(lay, template: true, showGlyph: false, flashIndex: flashIndex, bracket: style)
    }

    private func teardown() {
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil; layout = nil; cellSpaces = []
    }

    // Order display UUIDs left→right then top→bottom by their CG frame origin (physical arrangement).
    private func orderedDisplayUUIDs(_ uuids: Dictionary<String, [RealSpace]>.Keys) -> [String] {
        func originX(_ uuid: String) -> (Double, Double) {
            for s in NSScreen.screens {
                guard let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                      let cf = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(num.uint32Value))?.takeRetainedValue(),
                      (CFUUIDCreateString(nil, cf) as String?) == uuid else { continue }
                let b = CGDisplayBounds(CGDirectDisplayID(num.uint32Value))
                return (Double(b.origin.x), Double(b.origin.y))
            }
            return (.greatestFiniteMagnitude, 0)   // unknown displays sort last
        }
        return uuids.sorted { originX($0) < originX($1) }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp { showMenu(on: sender); return }
        guard let lay = layout else { return }
        // The status-button is wider than the image and CENTERS it, so subtract the centering inset
        // before hit-testing (otherwise every click lands too far right). The widget is a single row,
        // so hit-test at the vertical midline — y can't be off.
        let p = sender.convert(event.locationInWindow, from: nil)
        let xInset = max(0, (Double(sender.bounds.width) - lay.width) / 2)
        guard let idx = lay.nearestCellIndex(toX: Double(p.x) - xInset), idx < cellSpaces.count else { return }
        let clicked = cellSpaces[idx]
        // Re-read Spaces FRESH so the current-space index (→ gesture step count) is accurate; the
        // dock-swipe only affects the display under the mouse, so pass it as the active display.
        // (On the public provider, ordering is visit-order so the step count is best-effort.)
        let fresh = provider.spacesByDisplay()
        guard let target = fresh[clicked.displayUUID]?.first(where: { $0.id == clicked.id }), !target.isCurrent else { return }
        let activeUUID = displayUUIDUnderMouse()
        let confident = (activeUUID == nil || activeUUID == target.displayUUID)   // gesture path → safe to predict
        byDisplay = fresh

        // Visual feedback (Rams+Kare): a Kare press-flash on the clicked cell, plus an optimistic
        // fill-move to the clicked cell — but only on the confident gesture path; the keyboard fallback
        // just flashes (don't assert a state that might not happen). The 0.5s refresh reconciles truth.
        let (optGroups, flat) = buildGroups(from: fresh, override: confident ? (target.displayUUID, target.id) : nil)
        cellSpaces = flat
        render(optGroups, flashIndex: idx)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self] in self?.render(optGroups, flashIndex: nil) }

        SpaceSwitcher.switchTo(space: target, allSpaces: fresh[target.displayUUID] ?? [],
                               activeDisplayUUID: activeUUID, method: switchMethod())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refresh() }
    }

    /// The display UUID under the mouse (the menu bar you clicked) — the display the dock-swipe affects.
    private func displayUUIDUnderMouse() -> String? {
        let m = NSEvent.mouseLocation
        for s in NSScreen.screens where s.frame.contains(m) {
            guard let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let cf = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(num.uint32Value))?.takeRetainedValue() else { continue }
            return CFUUIDCreateString(nil, cf) as String?
        }
        return nil
    }

    private func showMenu(on button: NSStatusBarButton) {
        let menu = NSMenu()
        let rename = NSMenuItem(title: "Rename Current Space…", action: #selector(renameCurrent), keyEquivalent: "")
        rename.target = self; menu.addItem(rename)
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "")
        refreshItem.target = self; menu.addItem(refreshItem)
        item?.menu = menu
        button.performClick(nil)   // pops the menu
        item?.menu = nil           // restore click-to-switch for left clicks
    }

    @objc private func renameCurrent() {
        guard let space = cellSpaces.first(where: { $0.isCurrent }) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Rename Space"
        alert.informativeText = "Name this desktop Space (leave blank to reset)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = nameStore.name(for: space) ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            nameStore.setName(field.stringValue, for: space)
            refresh()
        }
    }
}
