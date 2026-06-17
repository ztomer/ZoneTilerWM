// zt-autotile — auto-tile every window on the focused window's screen via the ported
// AutoTiler, applying each move with the live AX mover. Drives the UI.
//
//   zt-autotile [config_path]   (default ~/.hammerspoon/config.toml)

import Foundation
import ZTCore
import ZTSystem

let home = FileManager.default.homeDirectoryForCurrentUser
let configURL = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : home.appendingPathComponent(".hammerspoon/config.toml")

guard let config = try? ConfigLoader.load(contentsOf: configURL) else {
    print("could not load config at \(configURL.path)"); exit(2)
}
guard AXWindowSystem.isTrusted(prompt: true) else {
    print("Accessibility not granted"); exit(3)
}

let screens = NSScreenProvider()
let windowSystem = AXWindowSystem(screenProvider: screens)
let coordinator = TilerCoordinator(windowSystem: windowSystem, screenProvider: screens,
                                   zoneConfig: config.zoneConfig, placementStrategy: config.placementStrategy)

let now = Int(Date().timeIntervalSince1970)
let moves = coordinator.autoTileScreen(autoTilerConfig: config.autoTilerConfig(), memory: [:], now: now)

func fmt(_ r: ZTRect) -> String { String(format: "x=%.0f y=%.0f w=%.0f h=%.0f", r.x, r.y, r.w, r.h) }
print("auto-tiled \(moves.count) windows:")
for m in moves {
    print("  window \(m.windowId) -> \(m.zoneKey):\(m.tileIndex.sortKey)  \(fmt(m.rect))")
}
