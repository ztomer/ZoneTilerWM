// FocusFollowsMouseController.swift — focus-follows-mouse. A PASSIVE NSEvent global mouse monitor
// (0 AX) restarts a short dwell timer on every move; only when the cursor SETTLES does it hit-test
// the window under it (CGWindowList enumeration = 0 AX) and, if that's a DIFFERENT window, focus it.
// The move/settle/enumerate path is 0 AX; the focus is NOT free — `windowSystem.focus` resolves the
// AX element by reading the target app's window list (~3 + N AX calls, N = that app's window count)
// then raises it. The dwell bounds the FREQUENCY (one focus per deliberate rest on a new window,
// never per move or on the same window), but each focus is several AX calls, not one. This is the
// only V3 feature that adds per-interaction AX, so it's gated HARD (default off). Validate the AX
// budget on a real SentinelOne trace before enabling widely (see V2_TEST_DEBT.md).

import AppKit
import ZTCore
import ZTSystem

final class FocusFollowsMouseController {
    private let windowSystem: AXWindowSystem
    private let delayMs: () -> Int

    private var monitor: Any?
    private var dwell: Timer?
    private var lastFocused: Int?

    init(windowSystem: AXWindowSystem, delayMs: @escaping () -> Int) {
        self.windowSystem = windowSystem; self.delayMs = delayMs
    }

    var isRunning: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.onMove() }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        dwell?.invalidate(); dwell = nil
        lastFocused = nil
    }

    // Every move just (re)arms the dwell — no enumeration, no AX here.
    private func onMove() {
        dwell?.invalidate()
        let ms = max(50, min(2000, delayMs()))
        dwell = Timer.scheduledTimer(withTimeInterval: Double(ms) / 1000.0, repeats: false) { [weak self] _ in
            self?.settle()
        }
    }

    // Cursor settled: hit-test (0 AX) and focus the window under it if it changed.
    private func settle() {
        // One mouse reading, one coordinate space: CGEvent.location is top-left CG, matching the
        // window frames AND screen(containing:) (avoids the bottom-left NSEvent.mouseLocation mismatch).
        guard let loc = CGEvent(source: nil)?.location else { return }
        let point = (x: Double(loc.x), y: Double(loc.y))
        let mine = NSRunningApplication.current.localizedName
        // Hit-test ALL on-screen windows in global front-to-back order — NOT the per-display set.
        // windows(onScreen:) filters by which display the window's CENTER sits on, which wrongly
        // drops a window under the cursor whose centre is on another display (or one that straddles
        // two displays), so FFM would then focus the window *beneath* it. allWindows() keeps the raw
        // CGWindowList z-order so topWindow() picks the genuinely frontmost window at the point. 0 AX.
        let wins = windowSystem.allWindows()
            .filter { $0.appName != mine }                       // never steal focus to our own windows
            .map { (id: $0.id, frame: $0.frame) }                // 0 AX (CGWindowList)
        // The `wid != lastFocused` guard is load-bearing: focus() raises the window (changes z-order),
        // so the next settle would re-pick it as topmost — the guard stops that oscillation.
        guard let wid = FocusFollowsMouse.topWindow(at: point.x, y: point.y, windows: wins),
              wid != lastFocused else { return }
        lastFocused = wid
        windowSystem.focus(windowId: wid)   // AX (several calls — see header); only on settle-on-a-new-window
    }
}
