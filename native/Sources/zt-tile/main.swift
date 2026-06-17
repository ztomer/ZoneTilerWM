// zt-tile — first live end-to-end tiling: move the focused window into a zone, using the
// full ported pipeline (config -> screens -> zones -> placement) and the live AX mover
// (with the Firefox/Zen EnhancedUI toggle). Drives the UI.
//
//   zt-tile <zone_key> [config_path]
//
// config_path defaults to ~/.hammerspoon/config.toml (the live Hammerspoon config).

import Foundation
import ZTCore
import ZTSystem

let args = CommandLine.arguments
guard args.count > 1 else {
    print("usage: zt-tile <zone_key> [config_path]")
    exit(2)
}
let zoneKey = args[1]
let home = FileManager.default.homeDirectoryForCurrentUser
let configURL = args.count > 2
    ? URL(fileURLWithPath: args[2])
    : home.appendingPathComponent(".hammerspoon/config.toml")

guard let config = try? ConfigLoader.load(contentsOf: configURL) else {
    print("could not load config at \(configURL.path) (pass a path as the 2nd arg)")
    exit(2)
}

guard AXWindowSystem.isTrusted(prompt: true) else {
    print("Accessibility not granted — enable this binary in System Settings > Privacy & Security > Accessibility")
    exit(3)
}

let screens = NSScreenProvider()
let windowSystem = AXWindowSystem(screenProvider: screens)
let coordinator = TilerCoordinator(
    windowSystem: windowSystem,
    screenProvider: screens,
    zoneConfig: config.zoneConfig,
    placementStrategy: config.placementStrategy)

func fmt(_ r: ZTRect) -> String { String(format: "x=%.0f y=%.0f w=%.0f h=%.0f", r.x, r.y, r.w, r.h) }

switch coordinator.moveFocusedToZone(zoneKey) {
case .success(let o):
    print("Tiled window \(o.windowId) -> zone '\(o.zoneKey)' tile \(o.tileIndex)")
    print("  target: \(fmt(o.target))  applied=\(o.applied)")
    if let after = windowSystem.focusedWindow() {
        print("  after:  \(fmt(after.frame))")
    }
case .failure(let e):
    print("FAILED: \(e)")
    exit(1)
}
