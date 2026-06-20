// SpacesReader.swift — READ-ONLY reader for the real macOS Spaces (virtual desktops), per display.
//
// Uses the private CGS/SkyLight call `CGSCopyManagedDisplaySpaces(_CGSDefaultConnection())` — the
// same one yabai / Spaceman / Amethyst use. It's been stable for ~10+ years and needs no SIP change
// (READING only; we never mutate). Per docs/ROADMAP.md §A this is the gated "experimental" path; the
// public SpacesProvider is the App-Store fallback. We do NOT move windows between spaces or
// switch spaces from here (that's the fragile mutate path) — switching is done by riding the user's
// Mission Control keyboard shortcut / a dock-swipe gesture elsewhere.
//
// Per-space wallpapers come from ~/Library/Application Support/com.apple.wallpaper/Store/Index.plist,
// whose "Spaces" dict is keyed by the space UUID (the default/active space uses the empty-string key).

import AppKit

#if ZT_PRIVATE_APIS
// ⚠ PRIVATE / EXPERIMENTAL — these CGS/SkyLight symbols are undocumented and NOT App-Store-safe.
// Compiled in only when ZT_PRIVATE_APIS is defined (see Package.swift). The App-Store-safe
// alternative (see docs/ROADMAP.md §A) is NSWorkspaceActiveSpaceDidChangeNotification +
// an invisible 1×1 window per Space cross-referenced via CGWindowListCopyWindowInfo's
// kCGWindowWorkspace key (the WhichSpace/AirSpace technique; needs a one-time onboarding cycle and
// can't track native full-screen spaces).
private typealias CGSConnectionID = UInt32
@_silgen_name("_CGSDefaultConnection") private func _CGSDefaultConnection() -> CGSConnectionID
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ conn: CGSConnectionID) -> CFArray
#endif

public struct RealSpace: Equatable {
    public let id: Int          // CGS ManagedSpaceID (stable for the space's lifetime)
    public let uuid: String     // space UUID ("" for the default/active space), for wallpaper lookup
    public let displayUUID: String
    public let isCurrent: Bool
    public let isFullscreen: Bool   // type 4 = a full-screen-app space
    public init(id: Int, uuid: String, displayUUID: String, isCurrent: Bool, isFullscreen: Bool) {
        self.id = id; self.uuid = uuid; self.displayUUID = displayUUID
        self.isCurrent = isCurrent; self.isFullscreen = isFullscreen
    }
}

public enum SpacesReader {

    /// Whether the experimental private-API reader is compiled in. When false, `spacesByDisplay()`
    /// is empty and callers fall back to the public-API "current Space only" model.
    public static var experimentalEnabled: Bool {
        #if ZT_PRIVATE_APIS
        return true
        #else
        return false
        #endif
    }

    /// Real Spaces grouped by display UUID, in on-screen order, with the current space flagged.
    /// EXPERIMENTAL — empty unless ZT_PRIVATE_APIS (private SkyLight) is compiled in.
    public static func spacesByDisplay() -> [String: [RealSpace]] {
        #if !ZT_PRIVATE_APIS
        return [:]
        #else
        guard let displays = CGSCopyManagedDisplaySpaces(_CGSDefaultConnection()) as? [[String: Any]] else { return [:] }
        var out: [String: [RealSpace]] = [:]
        for d in displays {
            let displayUUID = d["Display Identifier"] as? String ?? ""
            let currentID = (d["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int ?? -1
            let raw = d["Spaces"] as? [[String: Any]] ?? []
            out[displayUUID] = raw.map { s in
                let id = (s["ManagedSpaceID"] as? Int) ?? (s["id64"] as? Int) ?? -1
                let type = s["type"] as? Int ?? 0
                return RealSpace(id: id, uuid: s["uuid"] as? String ?? "",
                                 displayUUID: displayUUID, isCurrent: id == currentID, isFullscreen: type == 4)
            }
        }
        return out
        #endif
    }

    // MARK: - Per-space wallpapers

    private static func wallpaperStore() -> [String: Any]? {
        let url = URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        return NSDictionary(contentsOf: url) as? [String: Any]
    }

    /// The wallpaper image for each space UUID (incl. the empty-string default key). Reads the
    /// surprisingly-nested wallpaper Configuration plist and resolves the file URL.
    public static func wallpapersBySpaceUUID() -> [String: NSImage] {
        guard let store = wallpaperStore(), let spaces = store["Spaces"] as? [String: Any] else { return [:] }
        var out: [String: NSImage] = [:]
        for (uuid, val) in spaces {
            if let img = wallpaperImage(from: val) { out[uuid] = img }
        }
        return out
    }

    private static func wallpaperImage(from spaceVal: Any) -> NSImage? {
        guard let v = spaceVal as? [String: Any],
              let def = v["Default"] as? [String: Any],
              let desktop = def["Desktop"] as? [String: Any],
              let content = desktop["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              let first = choices.first,
              let configData = first["Configuration"] as? Data,
              let decoded = try? PropertyListSerialization.propertyList(from: configData, options: [], format: nil) as? [String: Any],
              let urlDict = decoded["url"] as? [String: Any],
              let relative = urlDict["relative"] as? String,
              let url = URL(string: relative) else { return nil }
        return NSImage(contentsOf: url)
    }
}
