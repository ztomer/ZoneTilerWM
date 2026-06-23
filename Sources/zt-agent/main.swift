// zt-agent — minimal LSUIElement menubar agent: binds the config's tiler modifier + each
// zone key (e.g. ⌃⌘h) to TilerCoordinator.moveFocusedToZone via global Carbon hotkeys, shows
// a status-bar item, and runs the app run loop. First real keypress -> tile.
//
//   zt-agent [config_path]   (default ~/.hammerspoon/config.toml)

import Foundation
import AppKit
import ZTCore
import ZTSystem
import ZTUI

// Kare-styled stderr log: every line carries a status glyph (→ info · ✓ ok · ⚠ warn). The bare
// `log` is the default info channel; `logOK`/`logWarn` mark success / caution.
private func emit(_ glyph: String, _ s: String) {
    FileHandle.standardError.write(Data((glyph + " " + s + "\n").utf8))
}
func log(_ s: String) { emit(Kare.start, s) }
func logOK(_ s: String) { emit(Kare.ok, s) }
func logWarn(_ s: String) { emit(Kare.warn, s) }

/// Runtime set of "floated" window ids (excluded from auto-tile). A reference type so the
/// coordinator's isFloated closure can capture it without capturing the controller.
final class FloatSet {
    private var ids = Set<Int>()
    func contains(_ id: Int) -> Bool { ids.contains(id) }
    @discardableResult func toggle(_ id: Int) -> Bool {
        if ids.contains(id) { ids.remove(id); return false }
        ids.insert(id); return true
    }
}

let home = FileManager.default.homeDirectoryForCurrentUser

/// Resolve the config path. An explicit arg (CLI / `run.sh`) wins. Otherwise — the bundled
/// `.app` case, launched with no args by Finder/Dock/login — use the standard user location
/// `~/.config/ZoneTilerWM/config.toml`, seeding it from the bundled default on first run so a
/// freshly-installed app starts with a working config instead of failing to launch.
func resolveConfigURL() -> URL {
    // The live config ALWAYS lives in the standard user location, alongside the JSON state —
    // never the project folder or the app bundle. The agent reads/writes only this file.
    let fm = FileManager.default
    let dir = home.appendingPathComponent(".config/ZoneTilerWM", isDirectory: true)
    let url = dir.appendingPathComponent("config.toml")
    guard !fm.fileExists(atPath: url.path) else { return url }

    // First run only: migrate an existing config into the canonical location, then never look
    // elsewhere again. Source priority: an explicit path arg (dev / run.sh), the legacy
    // Hammerspoon config, then the bundled default.
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let argPath = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : nil
    let legacy = home.appendingPathComponent(".hammerspoon/config.toml")
    let sources = [argPath, legacy, Bundle.main.url(forResource: "config", withExtension: "toml")]
        .compactMap { $0 }
    if let source = sources.first(where: { fm.fileExists(atPath: $0.path) }) {
        try? fm.copyItem(at: source, to: url)
        log("zt-agent: migrated config to \(url.path) (from \(source.path))")
    } else {
        log("zt-agent: no config found to migrate; expected \(url.path)")
    }
    return url
}

let configURL = resolveConfigURL()

guard let config = try? ConfigLoader.load(contentsOf: configURL) else {
    log("zt-agent: cannot load config at \(configURL.path)")
    exit(2)
}

/// A frosted-glass capsule for the Pomodoro time in the menubar: a behind-window
/// NSVisualEffectView (real vibrancy) clipped to a rounded capsule, with the time on top.
final class PomodoroPillView: NSView {
    private let effect = NSVisualEffectView()
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        effect.translatesAutoresizingMaskIntoConstraints = false
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.separatorColor.cgColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.alignment = .center
        label.textColor = .labelColor
        label.backgroundColor = .clear
        addSubview(effect)
        addSubview(label)   // on top of the effect
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            effect.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Set the text; returns the total width to use for the status-item length.
    @discardableResult func update(_ text: String) -> CGFloat {
        label.stringValue = text
        let w = (text as NSString).size(withAttributes: [.font: label.font as Any]).width
        return ceil(w) + 18
    }
}

final class AgentController: NSObject {
    let binder = CarbonHotkeyBinder()
    let screens: NSScreenProvider
    let windowSystem: AXWindowSystem
    let monitorManager: MonitorManager
    // System objects that survive a config reload (memory/storage are reloaded from disk only
    // on restart; in-session learning is persisted as it happens).
    let learnedMemory: WindowMemory?
    let storage: Storage?
    // Resize mode: grid-line offsets (persisted independently of window memory). The manager is
    // shared with the coordinator's offsetProvider; the modal UI lives in ResizeModeController.
    let resizeManager = ResizeManager()
    let resizeStorage: Storage
    let floats = FloatSet()   // per-window float state (excluded from auto-tile)
    // The two modal sub-controllers (extracted from this composition root).
    var resizeMode: ResizeModeController!
    var windowHints: WindowHintsController!
    var expose: ExposeController!                   // custom exposé replacement (bound iff [system_hotkeys] expose set)
    let chromeTabs = ChromeTabsController()         // toggle Chrome's tab strip (bound iff [system_hotkeys] chrome_tabs set)
    var commandPalette: CommandPaletteController!   // gated by [command_palette] enabled
    var zoneHUD: ZoneHUDController!                 // gated by [zone_hud] enabled
    var appLauncherHUD: AppLauncherHUDController!   // hold an app-launcher modifier → shortcut palette
    var dragSnap: DragSnapController!               // gated by [drag_snap] enabled
    var breakScreen: BreakScreenController!         // gated by [break_screen] enabled
    var scratchpad: ScratchpadController!           // gated by [scratchpad] apps
    var appGroupControllers: [String: ScratchpadController] = [:]  // one per [[app_groups]] entry, by name
    let sandbox = SandboxController()               // session sandbox (toggle action)
    var ffm: FocusFollowsMouseController!           // gated by [focus_follows_mouse] enabled
    var eventStream: EventStreamController!         // gated by [events] enabled
    var manualMoveRelearn: ManualMoveRelearnController!  // gated by [relearn_on_move] enabled (feedback 7b)
    var dockPreview: DockPreviewController!               // gated by [dock_previews] enabled (Wave 4)
    // Config-derived state — rebuilt in place by applyConfig() on a live reload.
    var coordinator: TilerCoordinator
    var autoTilerConfig: AutoTiler.Config
    var appSwitcher: AppSwitcher.Config
    // Declarative window rules (rebuilt on live reload). on-open detection diffs the CGWindowList
    // window-id set (0 AX) each focus tick; baseline-seeded so pre-existing windows don't fire.
    var rulesEngine: RulesEngine
    var lastWindowIds: Set<Int> = []
    var rulesSeeded = false
    var lastFocusedRuleWindowId: Int?   // on-focus: fire only when the focused window changes
    var focusRulesSeeded = false
    // The single source of truth for executing actions. Every hotkey (and the MCP server)
    // routes through this. Built after super.init (its hooks reference self).
    var dispatcher: ActionDispatcher!
    // Read-only resource provider (CGWindowList + config + learned store; 0 AX) and the IPC
    // socket the zt-mcp shim forwards to.
    var arrangementQuery: ArrangementQuery!
    var socketServer: AgentSocketServer?
    // Named layout snapshots (persisted to "layouts" under the cache dir).
    var layouts: LayoutLibrary
    let pomodoro: Pomodoro
    var statusItem: NSStatusItem?
    var spacesMenubar: SpacesMenubarController?
    var pomodoroTimer: Timer?
    var focusTimer: Timer?
    let flash = FlashOverlay()
    let pomodoroBar = PomodoroBar()
    let focusBorder = FocusBorderController()
    let telemetry = TelemetryRecorder()            // opt-in local usage log ([telemetry] enabled)
    var enableColorBar: Bool
    var pomodoroIndicatorHeight: Double
    var pomodoroIndicatorAlpha: Double
    var pomodoroColorRemaining: NSColor
    var pomodoroColorUsed: NSColor
    var config: ConfigLoader.LoadedConfig
    let configURL: URL
    var configWatcher: ConfigWatcher?
    var settings: SettingsWindowController?
    var analytics: AnalyticsWindowController?
    var about: AboutWindowController?
    var tutorial: TutorialWindowController?
    var wizard: FirstRunWizardController?
    let onboarding = AccessibilityOnboardingController()

    init(config: ConfigLoader.LoadedConfig, configURL: URL) {
        let screens = NSScreenProvider()
        self.screens = screens
        windowSystem = AXWindowSystem(screenProvider: screens)
        monitorManager = MonitorManager()

        // Adaptive memory: load persisted preferences; learn + persist on manual tiles.
        var memory: WindowMemory?
        var store: Storage?
        if config.windowMemory.enabled {
            let s = JSONFileStorage(directory: URL(fileURLWithPath: config.windowMemory.cacheDir, isDirectory: true))
            let mem = WindowMemory(excludedApps: config.windowMemory.excludedApps, settleEnabled: true,
                                   clock: { Int(Date().timeIntervalSince1970) })
            if let saved = s.load("window_positions", as: WindowMemory.SaveData.self) { mem.load(saved) }
            memory = mem
            store = s
        }
        self.config = config
        self.configURL = configURL
        self.learnedMemory = memory
        self.storage = store

        // Resize-mode offsets persist to grid_offsets.json under the same cache dir, whether or
        // not window memory is enabled.
        let rstore = JSONFileStorage(directory: URL(fileURLWithPath: config.windowMemory.cacheDir, isDirectory: true))
        resizeStorage = rstore
        resizeManager.load(from: rstore)
        layouts = rstore.load("layouts", as: LayoutLibrary.self) ?? LayoutLibrary()
        let resize = resizeManager

        coordinator = AgentController.makeCoordinator(config: config, windowSystem: windowSystem,
                                                      screens: screens, memory: memory,
                                                      monitorManager: monitorManager, storage: store,
                                                      resizeManager: resize, floats: floats)
        autoTilerConfig = config.autoTilerConfig()
        appSwitcher = config.appSwitcher
        rulesEngine = RulesEngine(rules: config.rules)
        pomodoro = Pomodoro(config: .init(workPeriodSec: config.pomodoroWorkSec,
                                          restPeriodSec: config.pomodoroRestSec,
                                          enableColorBar: config.pomodoroEnableColorBar))
        enableColorBar = config.pomodoroEnableColorBar
        pomodoroIndicatorHeight = config.pomodoroIndicatorHeight
        pomodoroIndicatorAlpha = config.pomodoroIndicatorAlpha
        pomodoroColorRemaining = PomodoroBar.color(named: config.pomodoroColorRemaining)
        pomodoroColorUsed = PomodoroBar.color(named: config.pomodoroColorUsed)
        super.init()
        // Modal sub-controllers; their config-derived inputs read self.config so a live reload
        // is picked up automatically.
        resizeMode = ResizeModeController(
            binder: binder, screens: screens, windowSystem: windowSystem, monitorManager: monitorManager,
            resizeManager: resizeManager, resizeStorage: resizeStorage,
            zoneConfig: { [weak self] in self?.config.zoneConfig ?? ZoneConfig(grids: [:], layouts: [:], margins: Margins(enabled: false, size: 0, screen_edge: false)) })
        windowHints = WindowHintsController(
            binder: binder, screens: screens, windowSystem: windowSystem,
            keyboardLayout: { [weak self] in self?.config.keyboardLayout ?? "auto" },
            zoneConfig: { [weak self] in self?.config.zoneConfig ?? ZoneConfig(grids: [:], layouts: [:]) })
        expose = ExposeController(
            binder: binder,
            screens: screens,
            windowSystem: windowSystem,
            layoutGrid: { [weak self] screen in
                guard let self else { return (2, 2) }
                let info = ZoneCalculator.ScreenInfo(name: screen.name, frame: screen.frame)
                let res = ZoneCalculator.computeZones(screen: info, config: self.config.zoneConfig, offsets: { _, _ in 0 })
                let layoutKey = res.layoutKey
                let grid = self.config.zoneConfig.grids[layoutKey] ?? GridConfig(cols: 2, rows: 2)
                return (grid.cols, grid.rows)
            },
            screenZones: { [weak self] screen in
                guard let self else { return [:] }
                let info = ZoneCalculator.ScreenInfo(name: screen.name, frame: screen.frame)
                return ZoneCalculator.computeZones(screen: info, config: self.config.zoneConfig, offsets: { _, _ in 0 }).zones
            },
            spacesBarPosition: { [weak self] in
                self?.config.exposeSpacesBarPosition ?? "top"
            },
            exposeNav: { [weak self] in
                self?.config.exposeNav ?? "arrows"
            },
            exposeScope: { [weak self] in
                self?.config.exposeScope ?? "active"
            },
            realSpacesEnabled: { [weak self] in
                self?.config.experimentalRealSpaces ?? false
            }
        )
        // The action dispatcher: hooks read live state via `unowned self` (the dispatcher is owned
        // by self and never outlives it). The coordinator/config getters are closures so a live
        // reload is picked up automatically. The pomodoro hook also refreshes the menubar UI, so
        // an MCP/URL-triggered pomodoro command updates the pill immediately, not on the next tick.
        dispatcher = ActionDispatcher(hooks: .init(
            coordinator: { [unowned self] in self.coordinator },
            autoTilerConfig: { [unowned self] in self.autoTilerConfig },
            appSwitcherConfig: { [unowned self] in self.appSwitcher },
            audioDevices: { [unowned self] in self.config.audioDevices },
            audioShortcut: { [unowned self] in self.config.audioRunShortcutEnabled ? self.config.audioShortcutCallback : nil },
            now: { Int(Date().timeIntervalSince1970) },
            pomodoro: { [unowned self] cmd in
                switch cmd {
                case .enable: self.pomodoro.enable()
                case .disable: _ = self.pomodoro.disable()
                case .reset: self.pomodoro.resetWork()
                }
                self.refreshPomodoro()
                return .pomodoroUpdated(active: self.pomodoro.isActive,
                                        phase: self.pomodoro.phase.rawValue,
                                        timeLeftSec: self.pomodoro.timeLeft)
            },
            toggleResizeMode: { [unowned self] in self.resizeMode.toggle() },
            toggleWindowHints: { [unowned self] in self.windowHints.toggle() },
            toggleExpose: { [unowned self] in self.expose.toggle() },
            peekZone: { [unowned self] in self.windowHints.enterZone() },
            toggleFloat: { [unowned self] in
                guard let id = self.windowSystem.focusedWindow()?.id else { return .failed(reason: .noFocusedWindow) }
                let floating = self.floats.toggle(id)
                log("zt-agent: float window \(id) → \(floating)")
                return .floatToggled(windowId: id, floating: floating)
            },
            reloadConfig: { [unowned self] in self.reloadFromDisk() },
            setBorders: { [unowned self] on in self.setBordersEnabled(on) },
            telemetry: { [unowned self] name in self.telemetry.record(action: name) },
            saveLayout: { [unowned self] name in self.saveLayout(name) },
            applyLayout: { [unowned self] name in self.applyLayout(name) },
            syncExport: { [unowned self] in self.syncEngine().run(.export) },
            syncImport: { [unowned self] in
                let r = self.syncEngine().run(.import)
                if case .synced = r { self.adoptImportedSettings() }
                return r
            },
            applySuggestions: { [unowned self] in self.applyPlacementSuggestions() },
            scratchpad: { [unowned self] in self.scratchpad.toggle() },
            applyCluster: { [unowned self] name in self.applyCluster(name) },
            sandbox: { [unowned self] in self.sandbox.toggle() }))
        commandPalette = CommandPaletteController(
            perform: { [unowned self] in self.dispatcher.perform($0) },
            nlEnabled: { [unowned self] in self.config.nlEnabled },   // on-device NL fallback (merged in)
            interpretNL: { text in
                let prompt = NLCommand.systemPrompt(catalog: ActionParser.catalog)
                if case .requests(let r) = await NLInterpreter.interpret(text, systemPrompt: prompt) { return r }
                return []
            },
            windows: { [unowned self] in self.paletteWindows() },                       // find-a-window-by-typing
            focusWindow: { [unowned self] id in self.windowSystem.focus(windowId: id) })
        zoneHUD = ZoneHUDController(
            screens: screens, monitorManager: monitorManager,
            zoneConfig: { [unowned self] in self.config.zoneConfig },
            offset: { [weak resize] m, a, i in resize?.getOffset(monitor: m, axis: a, index: i) ?? 0 },
            modifier: { [unowned self] in self.config.tilerModifier },
            holdDelayMs: { [unowned self] in self.config.zoneHUDHoldDelayMs },
            commitMode: { [unowned self] in self.config.zoneHUDCommitMode },
            commit: { [unowned self] zoneKey, tile in self.tileFocusedToZone(zoneKey, tile: tile) })
        appLauncherHUD = AppLauncherHUDController(
            screens: screens,
            groups: { [unowned self] in
                ([self.config.appCuts, self.config.hyperAppCuts] + self.config.appLayers.map { $0.group })
                    .filter { $0.enabled }   // a disabled layer doesn't appear in the hold-to-reveal HUD either
                    .map { .init(modifier: $0.modifier, apps: $0.apps) } },
            holdDelayMs: { [unowned self] in self.config.appLauncherHUDHoldDelayMs })   // own hold-delay (decoupled from the zone HUD)
        dragSnap = DragSnapController(
            screens: screens, monitorManager: monitorManager,
            zoneConfig: { [unowned self] in self.config.zoneConfig },
            offset: { [weak resize] m, a, i in resize?.getOffset(monitor: m, axis: a, index: i) ?? 0 },
            modifier: { [unowned self] in self.config.tilerModifier },
            snap: { [unowned self] zone, tileOffset in
                // No right-clicks (offset 0) → the smart occupancy-based auto-pick; each right-click
                // mid-drag steps to an explicit tile in the zone's cycle (wraps in the coordinator).
                if tileOffset > 0 { self.tileFocusedToZone(zone, tile: tileOffset) }
                else { _ = self.dispatcher.perform(.tileFocusedToZone(zone: zone)) }
            })
        breakScreen = BreakScreenController(
            screens: screens,
            enabled: { [unowned self] in self.config.breakScreenEnabled },
            durationSec: { [unowned self] in self.config.breakScreenDurationSec })
        scratchpad = ScratchpadController(
            apps: { [unowned self] in self.config.scratchpadApps },
            autoDismiss: { [unowned self] in self.config.scratchpadAutoDismiss })
        ffm = FocusFollowsMouseController(
            windowSystem: windowSystem,
            delayMs: { [unowned self] in self.config.focusFollowsMouseDelayMs })
        // Read-only resource provider for the MCP `resources/*` queries. Closures read live state
        // so a config reload / resize-offset change is reflected. All reads are CGWindowList — 0 AX.
        arrangementQuery = ArrangementQuery(
            windowSystem: windowSystem, screenProvider: screens, monitorManager: monitorManager,
            zoneConfig: { [unowned self] in self.config.zoneConfig },
            offset: { [weak resizeManager] m, a, i in resizeManager?.getOffset(monitor: m, axis: a, index: i) ?? 0 },
            memory: { [unowned self] in self.learnedMemory },
            now: { Int(Date().timeIntervalSince1970) })
        eventStream = EventStreamController(
            arrangement: { [unowned self] in
                if case .arrangement(let w) = self.arrangementQuery.answer(.arrangement) { return w }
                return []
            },
            path: { [unowned self] in
                self.config.eventsPath ?? (self.config.windowMemory.cacheDir as NSString).appendingPathComponent("events.jsonl")
            },
            intervalMs: { [unowned self] in self.config.eventsIntervalMs })
        log("zt-agent: window memory \(memory != nil ? "enabled (\(config.windowMemory.cacheDir))" : "disabled")")
        applyBorders(config)
        telemetry.setEnabled(config.telemetryEnabled)
    }
}


let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menubar agent (LSUIElement-equivalent)

let controller = AgentController(config: config, configURL: configURL)
controller.setupStatusItem()
controller.setupSpacesMenubar()
controller.setupPomodoro()
controller.seedMonitors()          // before any tile/move op, so logical ids match on-disk data
controller.setupScreenWatch()
controller.setupFocusTracking()
controller.bindAllHotkeys()
controller.setupConfigWatch()
controller.setupIPCServer()        // MCP shim talks to the agent over this socket
controller.setupURLHandler()       // zonetiler:// scheme (effective in the bundled .app)
controller.setupZoneHUD()          // modifier-held zone cheat-sheet (gated by [zone_hud] enabled)
controller.reconcileAppLauncherHUD()  // hold a layer's modifier → shortcut palette (gated by [app_launcher_hud] enabled)
controller.setupDragSnap()         // drag-to-snap mouse monitor (gated by [drag_snap] enabled)
controller.setupFocusFollowsMouse()  // focus-follows-mouse (gated by [focus_follows_mouse] enabled)
controller.setupEventStream()        // arrangement event stream (gated by [events] enabled)
controller.showFirstRunIfNeeded()
// Debug aid: open a window on launch for screenshot/QA (the status-item menu isn't AX-drivable).
switch ProcessInfo.processInfo.environment["ZT_OPEN_WINDOW"] {
case "analytics": DispatchQueue.main.async { controller.openAnalytics() }
case "settings":  DispatchQueue.main.async { controller.openSettings() }
case "about":     DispatchQueue.main.async { controller.openAbout() }
case "tutorial":  DispatchQueue.main.async { controller.openTutorial() }
case "onboarding": DispatchQueue.main.async { controller.onboarding.showIfNeeded(force: true) }
case "wizard":    DispatchQueue.main.async { controller.openWizard() }
case "dockpreview": DispatchQueue.main.async { controller.dockPreview.forceShowForQA() }
case "palette":   DispatchQueue.main.async { controller.showCommandPalette() }
case "hud":       DispatchQueue.main.async { controller.showZoneHUDForQA() }
case "applauncher": DispatchQueue.main.async { controller.appLauncherHUD.forceShowForQA() }
case "dragsnap":  DispatchQueue.main.async { controller.dragSnapForQA() }
case "break":     DispatchQueue.main.async { controller.breakScreenForQA() }
case "expose":    DispatchQueue.main.async { controller.showExposeForQA() }
default: break
}
// QA: switch to a non-current Space via SpaceSwitcher (gesture/keyboard), then exit. "next" picks the
// first non-current desktop on a display that has >1; an integer picks that ManagedSpaceID.
if let sw = ProcessInfo.processInfo.environment["ZT_SWITCH_SPACE"] {
    let byDisplay = SpacesReader.spacesByDisplay()
    let multi = byDisplay.values.first(where: { $0.filter { !$0.isFullscreen }.count > 1 })
    if let spaces = multi ?? byDisplay.values.first {
        let target = (Int(sw).flatMap { id in spaces.first { $0.id == id } })
            ?? spaces.first { !$0.isCurrent && !$0.isFullscreen }
        if let target { log("QA: switching to space \(target.id) on \(target.displayUUID.prefix(8))"); SpaceSwitcher.switchTo(space: target, allSpaces: spaces) }
    }
    Thread.sleep(forTimeInterval: 2.0)
    exit(0)
}
// QA preview of the menu-bar Spaces widget → composite on light + dark strips → PNG + exit.
if let path = ProcessInfo.processInfo.environment["ZT_RENDER_SPACESBAR"] {
    let byDisplay = SpacesReader.spacesByDisplay()
    let store = SpaceNameStore()
    var groups: [SpacesMenubar.InputGroup] = byDisplay.sorted { $0.key < $1.key }.map { (display, spaces) in
        let cells = spaces.enumerated().map { (j, sp) -> SpacesMenubar.InputSpace in
            let name = store.name(for: sp).map { String($0.prefix(6)) } ?? (sp.isFullscreen ? "⛶" : "\(j + 1)")
            return .init(label: name, isCurrent: sp.isCurrent, isFullscreen: sp.isFullscreen)
        }
        return .init(monitorLabel: display, spaces: cells)
    }
    if groups.isEmpty {   // no real spaces (MAS/no-toggle) → mock so the design is still previewable
        groups = [.init(monitorLabel: "DELL", spaces: [.init(label: "1", isCurrent: true), .init(label: "code", isCurrent: false)]),
                  .init(monitorLabel: "Mon2", spaces: [.init(label: "1", isCurrent: true)])]
    }
    // The shipping design: no glyph (layout + renderer agree → cells flush-left in each bracket).
    let layout = SpacesMenubar.layout(groups, height: 22, showGlyph: false)
    func tint(_ image: NSImage, _ fg: NSColor) -> NSImage {
        let t = NSImage(size: image.size); t.lockFocus()
        fg.set(); NSRect(origin: .zero, size: image.size).fill(using: .sourceOver)
        image.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
        t.unlockFocus(); return t
    }
    let widget = SpacesMenubarRenderer.image(layout, template: false, showGlyph: false)
    let flashed = SpacesMenubarRenderer.image(layout, template: false, showGlyph: false, flashIndex: 1)   // Kare press-flash on cell 1
    let pad = 16.0, big = 6.0
    let W = layout.width * big + pad * 2
    struct Row { let img: NSImage; let scale: Double; let dark: Bool }
    let rows = [Row(img: widget, scale: big, dark: true), Row(img: flashed, scale: big, dark: true),
                Row(img: widget, scale: 1, dark: false)]
    let rowHs = rows.map { 22.0 * $0.scale + pad }
    let out = NSImage(size: NSSize(width: W, height: rowHs.reduce(0, +)))
    out.lockFocus()
    var y = 0.0
    for (i, r) in rows.enumerated() {
        let h = rowHs[i]
        (r.dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.96, alpha: 1)).setFill()
        NSRect(x: 0, y: y, width: W, height: h).fill()
        let t = tint(r.img, r.dark ? .white : .black)
        t.draw(in: NSRect(x: pad, y: y + pad / 2, width: layout.width * r.scale, height: 22 * r.scale),
               from: .zero, operation: .sourceOver, fraction: 1)
        y += h
    }
    out.unlockFocus()
    if let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path)); log("zt-agent: rendered spacesbar → \(path)")
    }
    exit(0)
}
// Deterministic overlay render for QA / Gemini grading: "ZT_RENDER=hud:/path.png" → render + exit.
if let render = ProcessInfo.processInfo.environment["ZT_RENDER"] {
    let parts = render.split(separator: ":", maxSplits: 1).map(String.init)
    if parts.count == 2 { controller.renderOverlayPNG(parts[0], to: parts[1]) }
    exit(0)
}
// Deterministic settings-tab render for QA / Gemini grading: "ZT_RENDER_UI=features:/path.png".
if let r = ProcessInfo.processInfo.environment["ZT_RENDER_UI"] {
    let parts = r.split(separator: ":", maxSplits: 1).map(String.init)
    if parts.count == 2 { controller.renderSettingsPNG(parts[0], to: parts[1]) }
    exit(0)
}
// Headless NL probe: "ZT_NL=tile this left" → run the on-device interpreter, print the resulting
// actions + exit. Verifies the FoundationModels path end-to-end without the UI / agent lifecycle.
if let nlText = ProcessInfo.processInfo.environment["ZT_NL"] {
    let prompt = NLCommand.systemPrompt(catalog: ActionParser.catalog)
    let sem = DispatchSemaphore(value: 0)
    Task {
        switch await NLInterpreter.interpret(nlText, systemPrompt: prompt) {
        case .requests(let r): print("NL → [\(r.map { ActionParser.canonical($0).name }.joined(separator: ", "))]")
        case .error(let e):    print("NL error: \(e)")
        }
        sem.signal()
    }
    sem.wait()
    exit(0)
}

logOK("zt-agent: ready — <modifier>+<zone> tiles the focused window; HYPER+return auto-tiles the screen. Edits to config.toml live-reload. ⌘Q to quit.")
app.run()
