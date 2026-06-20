// PlistSpacesReader.swift — App-Store-safe-ish reader for the macOS Spaces LAYOUT (count, order,
// per-display grouping, UUIDs, full-screen flag) WITHOUT any private CGS/SkyLight call.
//
// macOS persists the whole Spaces arrangement in the plain preferences file
// ~/Library/Preferences/com.apple.spaces.plist, under
//   SpacesDisplayConfiguration → "Management Data" → Monitors → [ { Display Identifier, Spaces[], … } ]
// which mirrors, field-for-field, what the private `CGSCopyManagedDisplaySpaces` returns (same
// ManagedSpaceID / id64 / type / uuid keys). So we can enumerate every Space per display for free —
// the one thing the marker-window provider (PublicSpacesProvider) cannot do.
//
// HONEST LIMIT — the *current* Space: the file's "Current Space" field is only rewritten by the
// WindowServer when a Space is created/deleted, NOT on a plain switch (verified live; also kept
// `kCGWindowWorkspace`-dead on current macOS). So `isCurrent` here is best-effort and can lag a plain
// switch until the next create/delete. Exact live current needs the private reader (the "Use real
// macOS Spaces" toggle). Count/order/UUIDs/full-screen are always exact.
//
// The plist also remembers DISCONNECTED displays (stale entries with empty Spaces) — the parser drops
// those, keying only currently-connected displays. The primary display is stored as "Main"; we remap
// it to its CGDisplay UUID so it groups/keys consistently with the rest of the app.

import AppKit

public enum PlistSpacesReader {
    private static let path = "\(NSHomeDirectory())/Library/Preferences/com.apple.spaces.plist"

    /// Spaces grouped by display UUID, in Mission-Control order, current best-effort flagged. Empty if
    /// the plist can't be read (e.g. a sandboxed App-Store build with no preferences entitlement) —
    /// callers then fall back to the marker-window provider.
    public static func spacesByDisplay() -> [String: [RealSpace]] {
        guard let monitors = monitors() else { return [:] }
        return parse(monitors: monitors, mainDisplayUUID: mainDisplayUUID(), connected: connectedDisplayUUIDs())
    }

    /// Whether the plist is readable AND yields at least one Space (drives provider selection / the gate).
    public static var isAvailable: Bool { !spacesByDisplay().isEmpty }

    // MARK: - pure parsing (unit-tested)

    /// Turn the raw `Monitors` array into per-display Spaces. Pure given the environment inputs so it can
    /// be tested against captured plist fixtures. `connected` keeps only live displays; the primary's
    /// "Main" identifier is remapped to `mainDisplayUUID`.
    public static func parse(monitors: [[String: Any]], mainDisplayUUID: String,
                             connected: Set<String>) -> [String: [RealSpace]] {
        var out: [String: [RealSpace]] = [:]
        for m in monitors {
            let raw = m["Spaces"] as? [[String: Any]] ?? []
            guard !raw.isEmpty else { continue }                  // collapsed/sleeping or stale entry
            let ident = m["Display Identifier"] as? String ?? ""
            let displayUUID = (ident == "Main") ? mainDisplayUUID : ident
            guard !displayUUID.isEmpty, connected.contains(displayUUID), out[displayUUID] == nil else { continue }
            let currentID = (m["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
            out[displayUUID] = raw.map { s in
                let id = (s["ManagedSpaceID"] as? Int) ?? (s["id64"] as? Int) ?? -1
                let type = s["type"] as? Int ?? 0
                return RealSpace(id: id, uuid: s["uuid"] as? String ?? "", displayUUID: displayUUID,
                                 isCurrent: id == currentID, isFullscreen: type == 4)
            }
        }
        return out
    }

    // MARK: - environment

    private static func monitors() -> [[String: Any]]? {
        guard let d = NSDictionary(contentsOfFile: path) as? [String: Any],
              let cfg = d["SpacesDisplayConfiguration"] as? [String: Any],
              let mgmt = cfg["Management Data"] as? [String: Any],
              let mons = mgmt["Monitors"] as? [[String: Any]] else { return nil }
        return mons
    }

    private static func mainDisplayUUID() -> String { uuid(of: CGMainDisplayID()) ?? "Main" }

    private static func connectedDisplayUUIDs() -> Set<String> {
        var set: Set<String> = []
        for s in NSScreen.screens {
            if let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               let u = uuid(of: CGDirectDisplayID(num.uint32Value)) { set.insert(u) }
        }
        return set
    }

    private static func uuid(of display: CGDirectDisplayID) -> String? {
        guard let cf = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, cf) as String?
    }
}
