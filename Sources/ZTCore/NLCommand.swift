// NLCommand.swift — pure seam for the on-device natural-language layout box. The system prompt is
// built from the action catalog (single source of truth) so the on-device model knows the exact
// vocabulary; the model's structured output ({action, params}) is mapped back to ActionRequests via
// the shared ActionParser. Both halves are pure + unit-testable; the FoundationModels call lives in
// ZTSystem.NLInterpreter and the input box in the agent. No SDK dependency here.

public enum NLCommand {
    /// Instructions for the on-device model: enumerate the allowed actions + params from the catalog
    /// so it only emits commands that map to real ActionRequests.
    public static func systemPrompt(catalog: [ActionSpec]) -> String {
        var lines = [
            "You convert a natural-language window-management request into an ordered list of commands.",
            "Use ONLY these actions. Emit each as an action name plus any params it needs:",
        ]
        for s in catalog {
            let params = s.params.map { p -> String in
                let allowed = p.allowed.map { " one of: " + $0.joined(separator: "/") } ?? ""
                return "\(p.name)\(p.required ? "" : "?")\(allowed)"
            }.joined(separator: ", ")
            lines.append("- \(s.name)\(params.isEmpty ? "" : " [\(params)]") — \(s.description)")
        }
        lines.append("Map the request to these actions only. If nothing applies, return an empty list.")
        return lines.joined(separator: "\n")
    }

    /// Map the model's structured commands to ActionRequests via the shared parser; drop any that
    /// don't validate (unknown action, missing/invalid param) so a sloppy generation can't misfire.
    public static func requests(from commands: [(action: String, params: [String: String])]) -> [ActionRequest] {
        commands.compactMap { c in
            if case .success(let r) = ActionParser.parse(name: c.action, params: c.params) { return r }
            return nil
        }
    }
}
