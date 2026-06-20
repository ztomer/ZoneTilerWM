// MarkerSpaceResolver.swift — the JOIN that gives the public Spaces path an EXACT live current Space.
//
// Two public techniques each know half the picture:
//   • the plist (PlistSpacesReader) knows the full per-display Space LIST + order, but its "current"
//     only updates on Space create/delete — it lags a plain switch.
//   • a 1×1 marker window pinned per Space (the WhichSpace trick) knows the LIVE current Space, but by
//     an opaque per-session marker id — it can't say WHICH plist cell that is.
//
// This resolver builds the marker-id → ManagedSpaceID map incrementally, with no private API:
//   1. SEED — when the plist read is "fresh" (launch, or the file was just rewritten by a create/delete,
//      so its "current" is trustworthy), bind the on-screen marker to the plist's current Space.
//   2. ELIMINATE — otherwise, if every Space on a display but one is already mapped, the unknown current
//      marker must be that last Space.
//   3. FALL BACK — until a marker resolves, report the plist's (possibly stale) current for that display.
//
// Consequence (documented honestly): a 1- or 2-Space display resolves to EXACT live current after the
// first visit to each Space; a display with ≥3 Spaces resolves the launch Space + any the user
// add/removes near, and is otherwise best-effort. Exact-always remains the private reader's edge.
//
// Pure (no AppKit) so it's unit-tested against hand-built fixtures (MarkerSpaceResolverTests).

public enum MarkerSpaceResolver {
    public struct Result: Equatable {
        public var map: [Int: Int]                 // markerID → ManagedSpaceID (accumulates across calls)
        public var currentByDisplay: [String: Int] // displayUUID → best-available current ManagedSpaceID
        public init(map: [Int: Int], currentByDisplay: [String: Int]) {
            self.map = map; self.currentByDisplay = currentByDisplay
        }
    }

    /// - layout: displayUUID → ordered ManagedSpaceIDs (Mission-Control order, from the plist).
    /// - currentMarkerByDisplay: displayUUID → the marker id currently on-screen on that display (live).
    /// - markerDisplay: markerID → the displayUUID it was created on.
    /// - plistCurrent: displayUUID → the plist's current ManagedSpaceID (may be stale).
    /// - plistFresh: whether the plist read is trustworthy this tick (launch / file just rewritten).
    /// - prior: the map accumulated so far.
    public static func resolve(layout: [String: [Int]],
                               currentMarkerByDisplay: [String: Int],
                               markerDisplay: [Int: String],
                               plistCurrent: [String: Int],
                               plistFresh: Bool,
                               prior: [Int: Int]) -> Result {
        var map = prior
        var current: [String: Int] = [:]
        for (display, ids) in layout {
            // Spaces on THIS display already bound to some marker — never double-claim them.
            let claimed = Set(map.compactMap { markerDisplay[$0.key] == display ? $0.value : nil })
            guard let cm = currentMarkerByDisplay[display] else {
                // No marker on-screen for this display yet → take the plist's word.
                if let pc = plistCurrent[display] { current[display] = pc }
                continue
            }
            if map[cm] == nil {
                let candidates = ids.filter { !claimed.contains($0) }
                if plistFresh, let pc = plistCurrent[display], candidates.contains(pc) {
                    map[cm] = pc                       // seed: fresh plist current is trustworthy
                } else if candidates.count == 1 {
                    map[cm] = candidates[0]            // eliminate: only one Space left unbound
                }
            }
            current[display] = map[cm] ?? plistCurrent[display]   // resolved, else best-effort plist value
        }
        return Result(map: map, currentByDisplay: current)
    }
}
