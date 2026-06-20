// zt-axspike — Phase 0 manual spike for the AX adapter. De-risks: accessibility trust,
// window enumeration / z-order (no permission), and moving another app's window via AX
// (with the AXEnhancedUserInterface toggle for Firefox/Zen) or the AppleScript fallback.
//
// Usage:
//   zt-axspike check                         -> is Accessibility granted for this process?
//   zt-axspike list [n]                      -> top-n on-screen windows in z-order
//   zt-axspike move <appNeedle> <left|right|full>          -> move via AX, with EnhancedUI toggle
//   zt-axspike move-noToggle <appNeedle> <left|right|full>  -> move via AX, WITHOUT the toggle
//   zt-axspike move-applescript <appNeedle> <left|right|full> -> move via System Events
//
// Defaults: appNeedle "Zen", side "left".

import Foundation
import CoreGraphics
import ZTSystem

let args = CommandLine.arguments
let cmd = args.count > 1 ? args[1] : "check"

func targetRect(_ side: String) -> CGRect {
    let full = CGDisplayBounds(CGMainDisplayID())   // top-left CG coords for the main display
    switch side {
    case "right": return CGRect(x: full.midX, y: full.minY, width: full.width / 2, height: full.height)
    case "full":  return full
    default:      return CGRect(x: full.minX, y: full.minY, width: full.width / 2, height: full.height)
    }
}

func describe(_ r: CGRect) -> String {
    String(format: "x=%.0f y=%.0f w=%.0f h=%.0f", r.origin.x, r.origin.y, r.size.width, r.size.height)
}

func printMove(_ result: Result<AXWindowSystem.MoveResult, AXMoveError>, side: String) {
    switch result {
    case .success(let m):
        print("Moved '\(m.appName)' to \(side) half (target \(describe(targetRect(side))))")
        print("  before: \(describe(m.before))")
        print("  after:  \(describe(m.after))")
        print("  enhancedUI toggle used: \(m.usedEnhancedUIToggle) (was enabled: \(m.wasEnhancedUI))")
        let moved = abs(m.after.origin.x - m.before.origin.x) > 1 || abs(m.after.size.width - m.before.size.width) > 1
        print(moved ? "  RESULT: window moved ✓" : "  RESULT: window did NOT move ✗")
    case .failure(let e):
        print("FAILED: \(e)")
    }
}

switch cmd {
case "check":
    print("Accessibility trusted: \(AXWindowSystem.isTrusted(prompt: true))")

case "list":
    let n = (args.count > 2 ? Int(args[2]) : nil) ?? 15
    let windows = AXWindowSystem.onScreenWindows().filter { $0.layer == 0 }
    print("On-screen windows (z-order, layer 0), showing \(min(n, windows.count)) of \(windows.count):")
    for w in windows.prefix(n) {
        print("  [\(w.zOrder)] id=\(w.windowID) pid=\(w.pid) \(describe(w.bounds))  \(w.ownerName)")
    }

case "move", "move-noToggle":
    let needle = args.count > 2 ? args[2] : "Zen"
    let side = args.count > 3 ? args[3] : "left"
    printMove(AXWindowSystem.moveFrontWindow(ofAppMatching: needle, to: targetRect(side),
                                             toggleEnhancedUI: cmd == "move"), side: side)

case "move-applescript":
    let needle = args.count > 2 ? args[2] : "Zen"
    let side = args.count > 3 ? args[3] : "left"
    printMove(AXWindowSystem.moveFrontWindowViaAppleScript(ofAppMatching: needle, to: targetRect(side)),
              side: side)

default:
    print("unknown command '\(cmd)' — try: check | list | move | move-noToggle | move-applescript")
    exit(2)
}
