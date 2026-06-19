// ScratchpadController.swift — the scratchpad drawer. A hotkey (or the `scratchpad` action) summons
// a configured set of utility apps together and dismisses them together; with auto-dismiss on, the
// set hides as soon as focus moves to a non-scratchpad app. Pure decision is ZTCore.Scratchpad; the
// activate/hide is NSWorkspace (0 AX). Gated: does nothing unless [scratchpad] apps is non-empty.

import AppKit
import ZTCore
import ZTSystem

final class ScratchpadController {
    private let apps: () -> [String]
    private let autoDismiss: () -> Bool
    private var summoned = false
    private var focusObserver: NSObjectProtocol?

    init(apps: @escaping () -> [String], autoDismiss: @escaping () -> Bool) {
        self.apps = apps; self.autoDismiss = autoDismiss
    }

    /// Toggle the scratchpad set. Returns the ActionResult the dispatcher surfaces.
    func toggle() -> ActionResult {
        let set = apps()
        guard !set.isEmpty else { return .failed(reason: .invalidParameter("scratchpad apps not set ([scratchpad] apps)")) }
        switch Scratchpad.decide(frontmost: AppController.frontmostAppName(), apps: set) {
        case .summon:
            AppController.summon(set)
            summoned = true
            if autoDismiss() { armAutoDismiss(set) }
            return .scratchpadToggled(summoned: true, apps: set)
        case .dismiss:
            AppController.hideApps(set)
            summoned = false
            disarmAutoDismiss()
            return .scratchpadToggled(summoned: false, apps: set)
        }
    }

    // Hide the set the moment focus lands on an app outside it.
    private func armAutoDismiss(_ set: [String]) {
        disarmAutoDismiss()
        focusObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, self.summoned else { return }
            let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName
            if !Scratchpad.contains(app, in: set) {
                AppController.hideApps(set)
                self.summoned = false
                self.disarmAutoDismiss()
            }
        }
    }

    private func disarmAutoDismiss() {
        if let o = focusObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        focusObserver = nil
    }
}
