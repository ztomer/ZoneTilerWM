// Rule.swift — the declarative window-rules vocabulary (roadmap theme A). A rule is a MATCH
// (by app/owner name — never window title, which would need Screen Recording) + a TRIGGER (when
// to evaluate) + an ACTION (an ActionRequest, the same vocabulary every front-end speaks). The
// engine is pure: it maps an (app, trigger) event to the matching rules' actions. The agent
// supplies the events (0 AX: new windows via CGWindowList diffs, focus via the existing poll,
// display changes via the screen observer) and executes the actions.

public struct Rule: Equatable {

    /// When a rule is evaluated.
    public enum Trigger: String, Codable, Equatable, CaseIterable {
        case onOpen = "on-open"                    // a new window of the app appears
        case onFocus = "on-focus"                  // the app's window gains focus
        case onDisplayChange = "on-display-change" // the display arrangement changed
    }

    public let app: String          // matched against the window owner's app name (case-insensitive)
    public let trigger: Trigger
    public let action: ActionRequest

    public init(app: String, trigger: Trigger, action: ActionRequest) {
        self.app = app; self.trigger = trigger; self.action = action
    }

    public func matches(app other: String) -> Bool {
        app.caseInsensitiveCompare(other) == .orderedSame
    }
}

public struct RulesEngine: Equatable {
    public let rules: [Rule]
    public init(rules: [Rule]) { self.rules = rules }

    public var isEmpty: Bool { rules.isEmpty }

    /// Whether any rule uses a given trigger (lets the agent skip work when none do).
    public func hasRules(for trigger: Rule.Trigger) -> Bool {
        rules.contains { $0.trigger == trigger }
    }

    /// The rules (in declaration order) that fire for an app on a given trigger.
    public func matching(app: String, trigger: Rule.Trigger) -> [Rule] {
        rules.filter { $0.trigger == trigger && $0.matches(app: app) }
    }
}
