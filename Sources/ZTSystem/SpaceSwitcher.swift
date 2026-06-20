// SpaceSwitcher.swift — switch the current macOS Space WITHOUT the fragile private mutate API.
//
// Two SIP-free mechanisms (the Spaceman / InstantSpaceSwitcher technique), chosen by `switchTo`:
//   • SAME display  → synthetic dock-swipe CGEvents (no keyboard shortcut needed). Uses PUBLIC
//     CGEvent API with undocumented field numbers — not a private @_silgen_name symbol, so it passes
//     App-Store static analysis (still undocumented/fragile; behaviour can change across macOS).
//   • CROSS display → ride the user's "Switch to Desktop N" Mission Control keyboard shortcut via
//     System Events (gestures only affect the focused display). Needs those shortcuts enabled
//     (System Settings → Keyboard → Shortcuts → Mission Control) — best-effort, no-op if unbound.
//
// The step/direction math is pure + unit-tested (`plan`).

import AppKit
import Carbon.HIToolbox

public enum SpaceSwitcher {

    // MARK: - Pure planning (testable)

    /// Steps + direction to go from `current` to `target` among `spaces` on the SAME display. nil if
    /// they're on different displays, either isn't found, or they're the same.
    public static func plan(from current: RealSpace, to target: RealSpace, in spaces: [RealSpace]) -> (steps: Int, goRight: Bool)? {
        guard current.displayUUID == target.displayUUID else { return nil }
        let onDisplay = spaces.filter { $0.displayUUID == target.displayUUID && !$0.isFullscreen }
        guard let ci = onDisplay.firstIndex(where: { $0.id == current.id }),
              let ti = onDisplay.firstIndex(where: { $0.id == target.id }), ci != ti else { return nil }
        return (abs(ti - ci), ti > ci)
    }

    // MARK: - Execution

    /// Switch to `target`. The dock-swipe gesture only affects the ACTIVE display, so it's used only
    /// when the target is on it (`activeDisplayUUID`); otherwise (or if unknown and the plan fails) we
    /// ride the keyboard shortcut. Async; posting is paced so swipes aren't dropped. Callers should pass
    /// freshly-read `allSpaces` so the current-space index (→ step count) is accurate.
    public static func switchTo(space target: RealSpace, allSpaces: [RealSpace], activeDisplayUUID: String? = nil,
                                method: String = "auto") {
        guard !target.isCurrent else { return }
        // "keyboard" forces the shortcut; "gesture"/"auto" use the swipe when the target is on the
        // active display (gestures only affect it), else fall back to the keyboard shortcut.
        let canGesture = method.lowercased() != "keyboard"
            && (activeDisplayUUID == nil || activeDisplayUUID == target.displayUUID)
        if canGesture, let current = allSpaces.first(where: { $0.isCurrent }),
           let p = plan(from: current, to: target, in: allSpaces) {
            let velocity = speedFast * Double(p.steps)
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0..<p.steps {
                    postDockSwipe(phaseBegan, goRight: p.goRight, velocity: velocity)
                    postDockSwipe(phaseChanged, goRight: p.goRight, velocity: velocity)
                    postDockSwipe(phaseEnded, goRight: p.goRight, velocity: velocity)
                    if i < p.steps - 1 { Thread.sleep(forTimeInterval: 0.05) }   // let each swipe land
                }
            }
        } else {
            keyboardSwitch(to: target, allSpaces: allSpaces)
        }
    }

    // MARK: - Dock-swipe gesture (public CGEvent API, undocumented fields)

    private static let fType     = CGEventField(rawValue: 55)!
    private static let fHID      = CGEventField(rawValue: 110)!
    private static let fMotion   = CGEventField(rawValue: 123)!
    private static let fProgress = CGEventField(rawValue: 124)!
    private static let fVelX     = CGEventField(rawValue: 129)!
    private static let fVelY     = CGEventField(rawValue: 130)!
    private static let fPhase    = CGEventField(rawValue: 132)!
    private static let dockControl: Int64 = 30
    private static let hidDockSwipe: Int64 = 23
    private static let motionHorizontal: Int64 = 1
    private static let phaseBegan: Int64 = 1, phaseChanged: Int64 = 2, phaseEnded: Int64 = 4
    private static let speedFast: Double = 10

    private static func postDockSwipe(_ phase: Int64, goRight: Bool, velocity: Double) {
        let progress = goRight ? Double(Float.leastNonzeroMagnitude) : -Double(Float.leastNonzeroMagnitude)
        let vel = goRight ? velocity : -velocity
        guard let e = CGEvent(source: nil) else { return }
        e.setIntegerValueField(fType, value: dockControl)
        e.setIntegerValueField(fHID, value: hidDockSwipe)
        e.setIntegerValueField(fPhase, value: phase)
        e.setDoubleValueField(fProgress, value: progress)
        e.setIntegerValueField(fMotion, value: motionHorizontal)
        e.setDoubleValueField(fVelX, value: vel)
        e.setDoubleValueField(fVelY, value: vel)
        e.post(tap: .cgSessionEventTap)
    }

    // MARK: - Keyboard-shortcut fallback (cross-display)

    private static func keyboardSwitch(to target: RealSpace, allSpaces: [RealSpace]) {
        let desktops = allSpaces.filter { $0.displayUUID == target.displayUUID && !$0.isFullscreen }
        guard let idx = desktops.firstIndex(where: { $0.id == target.id }), idx < 9 else { return }
        let keyCodes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        let source = "tell application \"System Events\" to key code \(keyCodes[idx]) using control down"
        DispatchQueue.global(qos: .userInitiated).async {
            NSAppleScript(source: source)?.executeAndReturnError(nil)
        }
    }
}
