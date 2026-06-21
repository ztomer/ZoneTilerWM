// ManualMoveRelearnController.swift — feedback 7b runtime trigger.
//
// When the user drags a window to a new spot by hand, re-teach window memory that placement. This
// is the thin, AX-budget-free wiring on top of the pure pieces: it drives a WindowSettleTracker
// from the existing 1 s focus-timer poll (which already enumerates windows via CGWindowList — zero
// new Accessibility calls), and for each window that comes to rest at a new frame it asks the
// coordinator to relearn its zone. Windows the agent itself just tiled are skipped via the
// coordinator's self-move suppression, so an explicit tile isn't double-counted as a manual move.
//
// Opt-in: gated on [relearn_on_move] enabled (default off). Disabled is a near-total no-op — it only
// drains the suppression map so it can't accumulate stale entries while the feature is off.

import Foundation
import ZTCore

final class ManualMoveRelearnController {
    private let coordinator: TilerCoordinator
    /// All live windows this tick (id, app, frame, screenUUID), read AX-free from CGWindowList.
    private let enumerate: () -> [LiveWindow]
    private var tracker = WindowSettleTracker()
    var enabled = false

    init(coordinator: TilerCoordinator, enumerate: @escaping () -> [LiveWindow]) {
        self.coordinator = coordinator
        self.enumerate = enumerate
    }

    /// Called once per focus-timer poll. Decays self-move suppression always (so the map drains even
    /// when off), then — only when enabled — settles the tracker and relearns windows that just came
    /// to rest at a new position.
    func tick() {
        coordinator.decaySelfMoveSuppression()
        guard enabled else { return }
        let live = enumerate()
        let settled = tracker.observe(live.map { .init(id: $0.id, frame: $0.frame) })
        for id in settled {
            guard !coordinator.isSelfMoveSettling(windowId: id),
                  let w = live.first(where: { $0.id == id }),
                  let uuid = w.screenUUID else { continue }
            coordinator.relearnPlacement(window: w, screenUUID: uuid)
        }
    }
}
