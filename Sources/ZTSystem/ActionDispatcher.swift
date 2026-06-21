// ActionDispatcher.swift — the single source of truth that EXECUTES an ActionRequest.
//
// Every front-end (hotkeys, URL, CLI, MCP) builds an ActionRequest and calls perform(_:); the
// dispatcher maps each verb to the existing coordinator / AppController / AudioDevices methods
// and projects the outcome into a serializable ActionResult. The audio-switch sequence that
// used to live inline in AgentController.bindAudioHotkey now lives here, so there is exactly one
// implementation of every action.
//
// It introduces ZERO new AX calls: it calls the same mutate-on-action methods the hotkeys
// already called, and reports outcomes from values those methods already return.
//
// Layering: this is the one piece that needs both ZTCore (TilerCoordinator) and ZTSystem
// (AppController/AudioDevices), so it lives in ZTSystem. The cases whose executors live in the
// agent (the Pomodoro instance, the modal controllers, config reload) are reached through the
// dependency-inverted `Hooks` closures, so the dispatcher stays free of any GUI/agent type.

import Foundation
import ZTCore

public final class ActionDispatcher {

    /// Dependency-inverted seams. Closures (not stored values) because the agent rebuilds the
    /// coordinator and re-reads config on every live reload — the dispatcher must always see the
    /// current instance, never a stale snapshot.
    public struct Hooks {
        public var coordinator: () -> TilerCoordinator
        public var autoTilerConfig: () -> AutoTiler.Config
        public var appSwitcherConfig: () -> AppSwitcher.Config
        public var audioDevices: () -> [String]
        public var audioShortcut: () -> String?
        public var now: () -> Int
        /// The agent owns the Pomodoro instance + its menubar UI, so it supplies this hook
        /// (mutate the state machine, refresh the UI, return the resulting state).
        public var pomodoro: (PomodoroCommand) -> ActionResult
        public var toggleResizeMode: () -> Void
        public var toggleWindowHints: () -> Void
        public var toggleExpose: () -> Void
        public var peekZone: () -> Void
        public var toggleFloat: () -> ActionResult
        /// Returns whether the reload was applied (false = parse/validation failed, config kept).
        public var reloadConfig: () -> Bool
        /// Toggle the focus border at runtime (no config edit).
        public var setBorders: (Bool) -> Void
        /// Record a dispatched action name for opt-in usage telemetry (no-op when telemetry is off).
        public var telemetry: (String) -> Void
        /// Layout snapshots — agent-orchestrated (storage + arrangement capture + window-targeted
        /// restore). Each returns the resulting ActionResult.
        public var saveLayout: (String) -> ActionResult
        public var applyLayout: (String) -> ActionResult
        /// File-based settings sync — export/import the config + state to/from the synced folder.
        public var syncExport: () -> ActionResult
        public var syncImport: () -> ActionResult
        /// Apply the context-aware placement suggestions (move flagged windows to their zones).
        public var applySuggestions: () -> ActionResult
        /// Summon/dismiss the scratchpad app set (the controller owns state + auto-dismiss).
        public var scratchpad: () -> ActionResult
        /// Arrange a named app-cluster profile (launch missing apps + tile matching windows).
        public var applyCluster: (String) -> ActionResult
        /// Toggle the session sandbox (hide everything but the focused app / restore).
        public var sandbox: () -> ActionResult

        public init(coordinator: @escaping () -> TilerCoordinator,
                    autoTilerConfig: @escaping () -> AutoTiler.Config,
                    appSwitcherConfig: @escaping () -> AppSwitcher.Config,
                    audioDevices: @escaping () -> [String],
                    audioShortcut: @escaping () -> String?,
                    now: @escaping () -> Int,
                    pomodoro: @escaping (PomodoroCommand) -> ActionResult,
                    toggleResizeMode: @escaping () -> Void,
                    toggleWindowHints: @escaping () -> Void,
                    toggleExpose: @escaping () -> Void = {},
                    peekZone: @escaping () -> Void = {},
                    toggleFloat: @escaping () -> ActionResult,
                    reloadConfig: @escaping () -> Bool,
                    setBorders: @escaping (Bool) -> Void = { _ in },
                    telemetry: @escaping (String) -> Void = { _ in },
                    saveLayout: @escaping (String) -> ActionResult,
                    applyLayout: @escaping (String) -> ActionResult,
                    syncExport: @escaping () -> ActionResult = { .failed(reason: .unsupportedAction) },
                    syncImport: @escaping () -> ActionResult = { .failed(reason: .unsupportedAction) },
                    applySuggestions: @escaping () -> ActionResult = { .failed(reason: .unsupportedAction) },
                    scratchpad: @escaping () -> ActionResult = { .failed(reason: .unsupportedAction) },
                    applyCluster: @escaping (String) -> ActionResult = { _ in .failed(reason: .unsupportedAction) },
                    sandbox: @escaping () -> ActionResult = { .failed(reason: .unsupportedAction) }) {
            self.coordinator = coordinator
            self.autoTilerConfig = autoTilerConfig
            self.appSwitcherConfig = appSwitcherConfig
            self.audioDevices = audioDevices
            self.audioShortcut = audioShortcut
            self.now = now
            self.pomodoro = pomodoro
            self.toggleResizeMode = toggleResizeMode
            self.toggleWindowHints = toggleWindowHints
            self.toggleExpose = toggleExpose
            self.peekZone = peekZone
            self.toggleFloat = toggleFloat
            self.reloadConfig = reloadConfig
            self.setBorders = setBorders
            self.telemetry = telemetry
            self.saveLayout = saveLayout
            self.applyLayout = applyLayout
            self.syncExport = syncExport
            self.syncImport = syncImport
            self.applySuggestions = applySuggestions
            self.scratchpad = scratchpad
            self.applyCluster = applyCluster
            self.sandbox = sandbox
        }
    }

    private let hooks: Hooks
    public init(hooks: Hooks) { self.hooks = hooks }

    @discardableResult
    public func perform(_ request: ActionRequest) -> ActionResult {
        hooks.telemetry(ActionParser.canonical(request).name)   // opt-in usage log (no-op when off)
        switch request {
        case .tileFocusedToZone(let zone):
            switch hooks.coordinator().moveFocusedToZone(zone) {
            case .success(let o):
                return .tiled(windowId: o.windowId, zone: o.zoneKey, tileIndex: o.tileIndex,
                              target: o.target, applied: o.applied)
            case .failure(let e):
                return .failed(reason: ActionError(e))
            }

        case .autoTileScreen:
            // Matches the hotkey path exactly: an explicit empty memory override (auto-tile via
            // this entry point does not apply learned per-app memory).
            let moves = hooks.coordinator().autoTileScreen(
                autoTilerConfig: hooks.autoTilerConfig(), memory: [:], now: hooks.now())
            return .autoTiled(moves: moves.map {
                TiledMove(windowId: $0.windowId, zone: $0.zoneKey, tileIndex: $0.tileIndex, rect: $0.rect)
            })

        case .cycleFocus(let zone):
            return .focusCycled(focusedWindowId: hooks.coordinator().cycleFocus(zone))

        case .cycleZoneStack(let dir):
            return .focusCycled(focusedWindowId: hooks.coordinator().cycleZoneStack(dir))

        case .focusScreen(let dir):
            return .screenFocused(focusedWindowId: hooks.coordinator().focusScreen(dir.screenNav))

        case .moveFocusedToMonitor(let dir):
            guard let o = hooks.coordinator().moveFocusedToMonitor(dir.screenNav) else {
                return .failed(reason: .noScreenForWindow)
            }
            return .monitorMoved(windowId: o.windowId, zone: o.zoneKey, tileIndex: o.tileIndex,
                                 target: o.target, applied: o.applied)

        case .nudge(let dir):
            guard let o = hooks.coordinator().nudgeFocused(dir) else { return .failed(reason: .noFocusedWindow) }
            return .windowMoved(windowId: o.windowId, target: o.target, applied: o.applied)

        case .throwWindow(let dir):
            guard let o = hooks.coordinator().throwFocused(dir) else { return .failed(reason: .noFocusedWindow) }
            return .windowMoved(windowId: o.windowId, target: o.target, applied: o.applied)

        case .swap(let dir):
            guard let r = hooks.coordinator().swapFocused(dir) else { return .failed(reason: .noTile) }
            return .swapped(windowA: r.a, windowB: r.b, applied: r.applied)

        case .toggleZen:
            hooks.coordinator().toggleZen()
            return .zenToggled

        case .toggleFloat:
            return hooks.toggleFloat()

        case .switchAudio(let target):
            return performAudio(target)

        case .appToggle(let app):
            AppController.toggle(app: app, config: hooks.appSwitcherConfig())
            return .appToggled(app: app)

        case .pomodoro(let cmd):
            return hooks.pomodoro(cmd)

        case .toggleResizeMode:
            hooks.toggleResizeMode()
            return .modeToggled(mode: .resize)

        case .toggleWindowHints:
            hooks.toggleWindowHints()
            return .modeToggled(mode: .windowHints)

        case .toggleExpose:
            hooks.toggleExpose()
            return .modeToggled(mode: .expose)

        case .peekZone:
            hooks.peekZone()
            return .modeToggled(mode: .windowPeek)

        case .applySuggestions:
            return hooks.applySuggestions()

        case .scratchpad:
            return hooks.scratchpad()

        case .applyCluster(let name):
            return hooks.applyCluster(name)

        case .sandboxToggle:
            return hooks.sandbox()

        case .syncExport:
            return hooks.syncExport()

        case .syncImport:
            return hooks.syncImport()

        case .reloadConfig:
            return .configReloaded(ok: hooks.reloadConfig())

        case .setBorders(let on):
            hooks.setBorders(on)
            return .bordersSet(enabled: on)

        case .saveLayout(let name):
            return hooks.saveLayout(name)

        case .applyLayout(let name):
            return hooks.applyLayout(name)
        }
    }

    /// The audio-switch sequence, migrated verbatim from AgentController.bindAudioHotkey:
    /// pick next (or the named device) → set default → optionally run the configured Shortcut.
    private func performAudio(_ target: AudioTarget) -> ActionResult {
        let devices = hooks.audioDevices()
        let pick: String?
        switch target {
        case .next:
            pick = AudioSwitcher.nextDevice(configured: devices, currentName: AudioDevices.defaultOutputName())
        case .named(let name):
            pick = devices.contains(name) ? name : nil
        }
        guard let next = pick, AudioDevices.setDefaultOutput(named: next) else {
            return .audioSwitched(deviceName: nil)
        }
        if let shortcut = hooks.audioShortcut(), !shortcut.isEmpty { AudioDevices.runShortcut(shortcut) }
        return .audioSwitched(deviceName: next)
    }
}
