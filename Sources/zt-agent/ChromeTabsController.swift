// ChromeTabsController.swift — toggle Google Chrome's vertical tab strip (collapse/expand) when
// Chrome is frontmost (#26, the "Chrome ⌘S" review item). Chrome exposes the control as a button
// but no shortcut; this AX-presses it. Bound to a configurable hotkey for now — proving the AX path
// works before deciding to wrap it in a keyboard event tap for literal ⌘S (an event tap intercepts
// every keystroke and a bug can break all input, so we don't add it until the toggle is confirmed
// live — see docs/V6_FEATURE_PLAN.md). AX traversal runs only on the explicit keypress (not the hot
// path), bounded depth.

import AppKit
import ApplicationServices

final class ChromeTabsController {
    private let bundleId = "com.google.Chrome"
    // Substrings (lowercased) that likely identify the tab-strip collapse/expand control. Best-effort
    // until confirmed against the live AX tree; when nothing matches we log the candidates so the
    // real identity can be read off a live run and pinned.
    private let needles = ["collapse", "expand", "tab list", "tab strip", "show tab", "hide tab", "side panel"]

    func toggle() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == bundleId else {
            log("zt-agent: chrome-tabs — Chrome not frontmost; ignoring")
            return
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let winVal = winRef, CFGetTypeID(winVal) == AXUIElementGetTypeID() else { return }
        var buttons: [(el: AXUIElement, desc: String)] = []
        collectButtons(winVal as! AXUIElement, depth: 0, into: &buttons)
        if let match = buttons.first(where: { b in needles.contains { b.desc.contains($0) } }) {
            AXUIElementPerformAction(match.el, kAXPressAction as CFString)
            log("zt-agent: chrome-tabs — pressed '\(match.desc)'")
        } else {
            let names = buttons.map { $0.desc }.filter { !$0.isEmpty }.prefix(24)
            log("zt-agent: chrome-tabs — no tab-strip button matched; \(buttons.count) buttons, candidates: \(Array(names))")
        }
    }

    /// DFS the AX tree (bounded) collecting buttons + a lowercased description (title/desc/help).
    private func collectButtons(_ el: AXUIElement, depth: Int, into out: inout [(el: AXUIElement, desc: String)]) {
        guard depth < 14 else { return }
        if role(el) == (kAXButtonRole as String) {
            let desc = [attr(el, kAXDescriptionAttribute), attr(el, kAXTitleAttribute), attr(el, kAXHelpAttribute)]
                .joined(separator: " ").trimmingCharacters(in: .whitespaces).lowercased()
            out.append((el, desc))
        }
        var kidsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kidsRef) == .success,
              let kids = kidsRef as? [AXUIElement] else { return }
        for k in kids { collectButtons(k, depth: depth + 1, into: &out) }
    }

    private func role(_ el: AXUIElement) -> String? {
        var r: CFTypeRef?; AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &r); return r as? String
    }
    private func attr(_ el: AXUIElement, _ a: String) -> String {
        var r: CFTypeRef?; AXUIElementCopyAttributeValue(el, a as CFString, &r); return (r as? String) ?? ""
    }
}
