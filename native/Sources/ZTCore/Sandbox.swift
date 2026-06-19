// Sandbox.swift — pure selection for the session sandbox: a toggle that hides everything except
// the window you're focused on (a clean-slate focus mode) and restores it all on toggle-off.
// Distinct from zen (which minimizes others to the Dock) — sandbox HIDES apps and un-hides exactly
// the set it hid, so one chord blanks the desktop and one brings it all back. 0 AX (NSWorkspace
// hide/unhide). This owns the "which apps to hide" decision; the controller does the I/O + state.

public enum Sandbox {
    public struct App: Equatable {
        public let name: String
        public let regular: Bool      // activationPolicy == .regular (a normal windowed app)
        public let hidden: Bool       // already hidden (don't touch — the user hid it)
        public let frontmost: Bool    // the app being focused on (keep it visible)
        public init(name: String, regular: Bool, hidden: Bool, frontmost: Bool) {
            self.name = name; self.regular = regular; self.hidden = hidden; self.frontmost = frontmost
        }
    }

    /// Apps to hide on enter: regular, currently visible, not the frontmost one, not `selfName`
    /// (the agent). Skips already-hidden apps so exit only un-hides what sandbox itself hid.
    public static func appsToHide(_ apps: [App], selfName: String) -> [String] {
        apps.filter { $0.regular && !$0.hidden && !$0.frontmost
            && $0.name.lowercased() != selfName.lowercased() && !$0.name.isEmpty }
            .map { $0.name }
    }
}
