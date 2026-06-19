// BreakScreenController.swift — drives the retro break overlay off the Pomodoro tick stream. When
// a work period completes (and [break_screen] is enabled) it shows the full-screen overlay over the
// screen under the cursor, auto-dismissing after the configured duration (or on click). 0 AX:
// screen pick is screenUnderMouse (pure AppKit); the overlay is purely visual. Gated, default off.

import AppKit
import ZTCore
import ZTSystem

final class BreakScreenController {
    private let overlay = BreakScreenOverlay()
    private let screens: NSScreenProvider
    private let enabled: () -> Bool
    private let durationSec: () -> Int
    private var dismissTimer: Timer?

    init(screens: NSScreenProvider, enabled: @escaping () -> Bool, durationSec: @escaping () -> Int) {
        self.screens = screens; self.enabled = enabled; self.durationSec = durationSec
    }

    /// Feed each Pomodoro tick event; shows the overlay on work→break when enabled.
    func handle(_ event: Pomodoro.TickEvent?, restSec: Int, workCount: Int) {
        guard BreakScreen.shouldPresent(event, enabled: enabled()) else { return }
        present(restSec: restSec, workCount: workCount)
    }

    /// QA/debug: show a representative break overlay now.
    func forceShow() { present(restSec: 300, workCount: 1) }

    private func present(restSec: Int, workCount: Int) {
        guard let screen = screens.screenUnderMouse() else { return }   // 0 AX
        let msg = BreakScreen.message(restSec: restSec, workCount: workCount)
        overlay.show(title: msg.title, subtitle: msg.subtitle,
                     screenCGFrame: screen.fullFrame, onDismiss: { [weak self] in self?.dismiss() })
        dismissTimer?.invalidate()
        let secs = Double(max(2, min(60, durationSec())))   // clamp: never flicker, never trap the screen
        dismissTimer = Timer.scheduledTimer(withTimeInterval: secs, repeats: false) { [weak self] _ in self?.dismiss() }
    }

    func dismiss() {
        dismissTimer?.invalidate(); dismissTimer = nil
        overlay.hide()
    }
}
