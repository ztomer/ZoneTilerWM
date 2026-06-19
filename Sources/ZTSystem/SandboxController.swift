// SandboxController.swift — session sandbox: enter hides every regular, visible, non-frontmost app
// (a clean-slate focus mode), remembering exactly which it hid; exit un-hides that set. Distinct
// from zen (which minimizes others to the Dock). 0 AX — pure NSWorkspace hide/unhide. The "which
// apps to hide" decision is ZTCore.Sandbox (unit-tested); this owns the I/O + toggle state.

import AppKit
import ZTCore

public final class SandboxController {
    private var hiddenNames: [String] = []
    private var active = false
    public init() {}

    public func toggle() -> ActionResult { active ? exit() : enter() }

    private func enter() -> ActionResult {
        let running = NSWorkspace.shared.runningApplications
        let apps = running.map {
            Sandbox.App(name: $0.localizedName ?? "",
                        regular: $0.activationPolicy == .regular,
                        hidden: $0.isHidden,
                        frontmost: $0.isActive)
        }
        hiddenNames = Sandbox.appsToHide(apps, selfName: "ZoneTilerWM")
        let toHide = Set(hiddenNames.map { $0.lowercased() })
        for r in running where toHide.contains((r.localizedName ?? "").lowercased()) { r.hide() }
        active = true
        return .sandboxToggled(active: true, hidden: hiddenNames.count)
    }

    private func exit() -> ActionResult {
        let restore = Set(hiddenNames.map { $0.lowercased() })
        for r in NSWorkspace.shared.runningApplications
        where restore.contains((r.localizedName ?? "").lowercased()) { r.unhide() }
        let n = hiddenNames.count
        hiddenNames = []; active = false
        return .sandboxToggled(active: false, hidden: n)
    }
}
