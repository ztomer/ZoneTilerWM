// zt-probe — read-only inspection of the live system: screens (with stable UUIDs + frames),
// on-screen windows (z-order, mapped to their display), and audio output devices. Observes
// only; moves/changes nothing. Useful for sanity-checking the adapter layer against the real
// machine without driving the UI.

import Foundation
import ZTCore
import ZTSystem

func r(_ rect: ZTRect) -> String {
    String(format: "x=%.0f y=%.0f w=%.0f h=%.0f", rect.x, rect.y, rect.w, rect.h)
}

let screens = NSScreenProvider()

print("=== screens ===")
for s in screens.allScreens() {
    print("  \(s.name)  uuid=\(s.uuid)")
    print("    full:    \(r(s.fullFrame))")
    print("    visible: \(r(s.frame))")
}
print("  main: \(screens.mainScreen()?.name ?? "nil")")

print("\n=== windows (z-order, layer 0) ===")
for w in AXWindowSystem.onScreenWindows().filter({ $0.layer == 0 }).prefix(20) {
    let monitor = screens.screen(containing: (x: Double(w.bounds.midX), y: Double(w.bounds.midY)))?.uuid ?? "?"
    let rect = ZTRect(x: w.bounds.origin.x, y: w.bounds.origin.y, w: w.bounds.size.width, h: w.bounds.size.height)
    print("  [\(w.zOrder)] \(w.ownerName)  id=\(w.windowID)  \(r(rect))  monitor=\(monitor)")
}

print("\n=== audio output devices ===")
for d in AudioDevices.outputDevices() {
    print("  \(d.name)  [\(d.uid)]")
}
print("  default: \(AudioDevices.defaultOutputName() ?? "nil")")
