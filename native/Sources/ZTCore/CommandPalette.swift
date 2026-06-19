// CommandPalette.swift — pure logic for the ⌘K-style action palette: fuzzy-rank the action
// catalog for the live results list, and resolve a typed command line ("tile h", "save-layout
// coding", "zen") into an ActionRequest. The overlay UI + key handling live in the agent; this
// is the testable brain (no AppKit).

public enum CommandPalette {

    /// Fuzzy-rank catalog actions for a query. The query's FIRST token is matched against each
    /// action's name (primary) and description (secondary); the rest of the query is the would-be
    /// arguments and doesn't affect filtering. Empty query → the whole catalog in catalog order.
    public static func match(_ query: String, catalog: [ActionSpec] = ActionParser.catalog) -> [ActionSpec] {
        let term = firstToken(query).lowercased()
        if term.isEmpty { return catalog }
        let scored = catalog.compactMap { spec -> (spec: ActionSpec, score: Int)? in
            guard let s = score(term, spec: spec) else { return nil }
            return (spec, s)
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.spec.name < $1.spec.name }
            .map { $0.spec }
    }

    /// Resolve a full command line into an ActionRequest. First token → action name (exact, else
    /// unique prefix, else unique subsequence match); remaining tokens → the action's params
    /// positionally in `spec.params` order. Delegates the final validation to ActionParser.
    public static func resolve(_ input: String, catalog: [ActionSpec] = ActionParser.catalog) -> Result<ActionRequest, ActionError> {
        let tokens = input.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let head = tokens.first else { return .failure(.unsupportedAction) }
        guard let spec = resolveName(head, catalog: catalog) else { return .failure(.unsupportedAction) }
        var params: [String: String] = [:]
        let args = Array(tokens.dropFirst())
        for (i, param) in spec.params.enumerated() where i < args.count {
            params[param.name] = args[i]
        }
        return ActionParser.parse(name: spec.name, params: params)
    }

    // MARK: - helpers

    private static func firstToken(_ s: String) -> String {
        String(s.drop(while: { $0 == " " }).prefix(while: { $0 != " " && $0 != "\t" }))
    }

    /// Resolve a typed action token to exactly one catalog name, or nil if none / ambiguous.
    private static func resolveName(_ token: String, catalog: [ActionSpec]) -> ActionSpec? {
        let t = token.lowercased()
        if let exact = catalog.first(where: { $0.name == t }) { return exact }
        let prefix = catalog.filter { $0.name.hasPrefix(t) }
        if prefix.count == 1 { return prefix[0] }
        let subseq = catalog.filter { isSubsequence(t, of: $0.name) }
        return subseq.count == 1 ? subseq[0] : nil
    }

    private static func score(_ term: String, spec: ActionSpec) -> Int? {
        let name = spec.name.lowercased()
        if name == term { return 1000 }
        if name.hasPrefix(term) { return 600 - name.count }          // prefer shorter names
        if name.contains(term) { return 300 }
        if isSubsequence(term, of: name) { return 150 }
        if spec.description.lowercased().contains(term) { return 60 } // description fallback
        return nil
    }

    /// Is `needle` a subsequence of `haystack` (chars in order, not necessarily contiguous)?
    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var it = haystack.makeIterator()
        for ch in needle {
            var found = false
            while let h = it.next() { if h == ch { found = true; break } }
            if !found { return false }
        }
        return true
    }
}
