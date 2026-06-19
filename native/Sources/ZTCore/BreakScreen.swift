// BreakScreen.swift — pure decision + copy for the retro Pomodoro break overlay. When a work
// period completes the agent shows a full-screen "step away" overlay; this owns the trigger
// predicate and the displayed text so they're unit-testable. The overlay rendering + the auto-
// dismiss timer live in ZTSystem/zt-agent.

public enum BreakScreen {
    /// A work→break transition raises the overlay; nothing else does (a completed *rest* doesn't).
    public static func shouldPresent(_ event: Pomodoro.TickEvent?, enabled: Bool) -> Bool {
        enabled && event == .workCompleted
    }

    /// Headline + subline for the overlay, given the upcoming rest length and sessions done so far.
    public static func message(restSec: Int, workCount: Int) -> (title: String, subtitle: String) {
        let span = restSec >= 60 ? "\(restSec / 60) MIN" : "\(max(0, restSec)) SEC"
        let session = "SESSION #\(workCount)"
        return ("BREAK TIME", "STEP AWAY · \(span) · \(session)")
    }
}
