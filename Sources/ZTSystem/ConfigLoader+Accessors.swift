// ConfigLoader+Accessors.swift — convenience accessors on LoadedConfig (assembling ZTCore configs
// from the loaded values). Split out of ConfigLoader.swift to keep that file focused on parsing.

import Foundation
import ZTCore

extension ConfigLoader.LoadedConfig {
    /// Convenience: assemble the AutoTiler config from the loaded values.
    public func autoTilerConfig() -> AutoTiler.Config {
        AutoTiler.Config(
            centerZones: autoTileCenterZones,
            workingSetTimeLimit: workingSetTimeLimit,
            workingSetMaxCapacity: workingSetMaxCapacity,
            mode: autoTilingMode,
            weights: solverWeights,
            zoneConfig: zoneConfig)
    }

    /// Zone keys across all layouts (excluding the "default" marker) — what the tiler binds.
    public var zoneKeys: [String] {
        var keys = Set<String>()
        for (_, zones) in zoneConfig.layouts { for k in zones.keys where k != "default" { keys.insert(k) } }
        return keys.sorted()
    }

    /// Every global hotkey the agent binds, resolved to (modifier tokens, key, action name).
    public func allBindings() -> [HotkeyConflicts.Binding] {
        var b: [HotkeyConflicts.Binding] = []
        for k in zoneKeys { b.append(.init(modifier: tilerModifier, key: k, label: "Tile zone \(k)")) }
        for k in zoneKeys { b.append(.init(modifier: focusModifier, key: k, label: "Focus zone \(k)")) }
        for (k, app) in appCuts.apps { b.append(.init(modifier: appCuts.modifier, key: k, label: "Launch \(app)")) }
        for (k, app) in hyperAppCuts.apps { b.append(.init(modifier: hyperAppCuts.modifier, key: k, label: "Launch \(app)")) }
        func add(_ group: [String: [String]], _ name: (String) -> String) {
            for (action, _) in group {
                if let r = resolvedHotkey(action, in: group), !r.key.isEmpty {
                    b.append(.init(modifier: r.modifier, key: r.key, label: name(action)))
                }
            }
        }
        add(tilerHotkeys) { "Tiler: \($0)" }
        add(pomodoroHotkeys) { "Pomodoro: \($0)" }
        add(systemHotkeys) { "System: \($0)" }
        if let key = audioHotkeyKey, !key.isEmpty {
            b.append(.init(modifier: audioHotkeyModifier, key: key, label: "Audio switch"))
        }
        return b
    }

    /// Hotkey conflicts (same modifier+key bound to multiple actions), for warnings.
    public func hotkeyConflicts() -> [HotkeyConflicts.Conflict] {
        HotkeyConflicts.find(allBindings())
    }
}
