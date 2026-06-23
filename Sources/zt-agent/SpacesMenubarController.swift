// SpacesMenubarController.swift — adaptation for unified segmented statusbar widget.
// Renders the Spaces list and forwards clicks from AgentController's click handler.

import AppKit
import ZTCore
import ZTSystem

final class SpacesMenubarController {
    var onRefresh: (() -> Void)?
    private let nameStore = SpaceNameStore()
    private let enabled: () -> Bool
    private let realSpaces: () -> Bool
    private let switchMethod: () -> String
    private let bracketStyle: () -> String

    private(set) var layout: SpacesMenubar.Layout?
    private var cellSpaces: [RealSpace] = []                 // flat index → space (for click → switch)
    private var byDisplay: [String: [RealSpace]] = [:]
    private var clickGen = 0                                 // invalidates a stale click's delayed un-flash

    var isAvailable: Bool { provider.isAvailable }
    var layoutWidth: Double { layout?.width ?? 0.0 }

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

    private var provider: SpacesProvider { Spaces.provider(experimentalEnabled: realSpaces()) }

    @objc func refresh() {
        let provider = self.provider
        provider.start()
        guard enabled(), provider.isAvailable else {
            teardown(); return
        }
        let spaces = provider.spacesByDisplay()
        guard !spaces.isEmpty else { return }
        byDisplay = spaces
        let (groups, flat) = buildGroups(from: spaces, override: nil)
        cellSpaces = flat
        layout = SpacesMenubar.layout(groups, showGlyph: false)
        onRefresh?()
    }

    func spacesImage(flashIndex: Int? = nil) -> NSImage? {
        guard let layout = layout else { return nil }
        let style = SpacesMenubarRenderer.BracketStyle(rawValue: bracketStyle()) ?? .bold
        return SpacesMenubarRenderer.image(layout, template: true, showGlyph: false, flashIndex: flashIndex, bracket: style)
    }

    func handleSpacesClick(atX x: Double, event: NSEvent) {
        guard let lay = layout else { return }
        guard let idx = lay.nearestCellIndex(toX: x), idx < cellSpaces.count else { return }
        let clicked = cellSpaces[idx]
        let fresh = provider.spacesByDisplay()
        guard let target = fresh[clicked.displayUUID]?.first(where: { $0.id == clicked.id }), !target.isCurrent else { return }
        let activeUUID = displayUUIDUnderMouse()
        let confident = (activeUUID == nil || activeUUID == target.displayUUID)
        byDisplay = fresh

        let (optGroups, flat) = buildGroups(from: fresh, override: confident ? (target.displayUUID, target.id) : nil)
        cellSpaces = flat
        clickGen += 1
        let gen = clickGen

        layout = SpacesMenubar.layout(optGroups, showGlyph: false)
        onRefresh?()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self] in
            guard let self, self.clickGen == gen else { return }
            self.layout = SpacesMenubar.layout(optGroups, showGlyph: false)
            self.onRefresh?()
        }

        SpaceSwitcher.switchTo(space: target, allSpaces: fresh[target.displayUUID] ?? [],
                               activeDisplayUUID: activeUUID, method: switchMethod())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refresh() }
    }

    @objc func renameCurrent() {
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

    private func teardown() {
        layout = nil; cellSpaces = []
        onRefresh?()
    }

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

    private func orderedDisplayUUIDs(_ uuids: Dictionary<String, [RealSpace]>.Keys) -> [String] {
        func originX(_ uuid: String) -> (Double, Double) {
            for s in NSScreen.screens {
                guard let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                      let cf = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(num.uint32Value))?.takeRetainedValue(),
                      (CFUUIDCreateString(nil, cf) as String?) == uuid else { continue }
                let b = CGDisplayBounds(CGDirectDisplayID(num.uint32Value))
                return (Double(b.origin.x), Double(b.origin.y))
            }
            return (.greatestFiniteMagnitude, 0)
        }
        return uuids.sorted { originX($0) < originX($1) }
    }

    private func displayUUIDUnderMouse() -> String? {
        let m = NSEvent.mouseLocation
        for s in NSScreen.screens where s.frame.contains(m) {
            guard let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let cf = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(num.uint32Value))?.takeRetainedValue() else { continue }
            return CFUUIDCreateString(nil, cf) as String?
        }
        return nil
    }
}
