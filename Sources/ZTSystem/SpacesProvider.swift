// SpacesProvider.swift — the abstraction over "how do we know the Spaces?", with a private and a
// public implementation selected at runtime. Lets the Spaces feature work in an App-Store-safe build
// (no private CGS) instead of degrading to "current Space only".
//
//   • PrivateSpacesProvider — the experimental CGS reader (SpacesReader). Compiled in only under
//     ZT_PRIVATE_APIS; sees every Space + wallpapers immediately, no onboarding.
//   • HybridSpacesProvider  — the best public path (NO private API): the plist's exact LAYOUT joined to
//     the 1×1-marker trick's LIVE current Space (see HybridSpacesProvider / MarkerSpaceResolver). Exact
//     counts always; live current after a display's Spaces are each visited once (else best-effort).
//   • PublicSpacesProvider  — the bare marker-window technique. Deepest fallback for when the plist
//     can't be read (e.g. a sandboxed App-Store build); discovers Spaces as the user visits them (a
//     one-time "cycle your Spaces" onboarding); no wallpapers, no native-full-screen tracking.
//
// `Spaces.provider(experimentalEnabled:)` picks, in order: private (iff compiled in AND the user opted
// into experimental real Spaces) → hybrid (if the plist is readable) → marker. Callers depend only on
// this protocol.

import AppKit

public protocol SpacesProvider: AnyObject {
    /// Real Spaces grouped by display UUID, in on-screen order, current flagged. Empty when nothing
    /// is known yet (public provider before onboarding, or private provider not compiled in).
    func spacesByDisplay() -> [String: [RealSpace]]

    /// Per-space wallpaper by space UUID. Only the private provider can read these; public → empty.
    func wallpapersBySpaceUUID() -> [String: NSImage]

    /// Whether this provider currently has usable Space data (drives the menubar-widget gate).
    var isAvailable: Bool { get }

    /// Begin any background work the provider needs (observers, marker windows). Idempotent.
    func start()
}

/// Private CGS reader wrapped as a provider. Stateless; forwards to the `SpacesReader` enum.
public final class PrivateSpacesProvider: SpacesProvider {
    public init() {}
    public func spacesByDisplay() -> [String: [RealSpace]] { SpacesReader.spacesByDisplay() }
    public func wallpapersBySpaceUUID() -> [String: NSImage] { SpacesReader.wallpapersBySpaceUUID() }
    public var isAvailable: Bool { SpacesReader.experimentalEnabled }
    public func start() {}   // nothing to set up; CGS is read on demand
}

public enum Spaces {
    /// The provider to use right now. Private CGS reader iff it's compiled in (`ZT_PRIVATE_APIS`) AND
    /// the user enabled experimental real Spaces; else the hybrid plist+marker provider (exact counts,
    /// no private API); else the bare marker provider (when even the plist is unreadable, e.g. a
    /// sandboxed build).
    public static func provider(experimentalEnabled: Bool) -> SpacesProvider {
        if SpacesReader.experimentalEnabled && experimentalEnabled {
            return sharedPrivate
        }
        if HybridSpacesProvider.shared.isAvailable {
            return HybridSpacesProvider.shared
        }
        return PublicSpacesProvider.shared
    }

    private static let sharedPrivate = PrivateSpacesProvider()
}
