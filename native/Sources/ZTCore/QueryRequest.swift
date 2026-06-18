// QueryRequest.swift — the read-only resource verbs an MCP client (or any front-end) can ask
// for. Every query is answered from CGWindowList + the in-memory config/learned store, so a
// query costs ZERO AX calls (the SentinelOne budget). Titles are deliberately NOT exposed:
// kCGWindowName reads empty for other apps' windows without Screen Recording, and we never want
// that permission or that data leaving the device — app/bundle identity is the safe currency.

public enum QueryRequest: String, Codable, Equatable, CaseIterable {
    case arrangement      // current windows: app, frame, monitor, occupied zone
    case zones            // available zone keys per screen
    case placementStats   // the learned per-app placement preferences

    /// Stable resource URI used by the MCP `resources/*` methods.
    public var uri: String { "zonetiler://\(rawValue)" }

    public init?(uri: String) {
        guard uri.hasPrefix("zonetiler://") else { return nil }
        self.init(rawValue: String(uri.dropFirst("zonetiler://".count)))
    }

    public var displayName: String {
        switch self {
        case .arrangement:    return "Current window arrangement"
        case .zones:          return "Available zones"
        case .placementStats: return "Learned placement preferences"
        }
    }

    public var description: String {
        switch self {
        case .arrangement:
            return "All standard windows on every screen: window id, app, frame, monitor, and the zone it currently occupies (if any). Read from CGWindowList — no titles, no Accessibility."
        case .zones:
            return "The zone keys available on each connected screen, given the active layout."
        case .placementStats:
            return "The app→zone placement preferences ZoneTilerWM has learned, with usage counts."
        }
    }
}

/// A window as a resource reader sees it (no title — see file header).
public struct WindowInfo: Codable, Equatable {
    public let windowId: Int
    public let app: String
    public let frame: ZTRect
    public let monitor: String
    public let zone: String?   // best-effort occupied zone key, nil if none overlaps enough

    public init(windowId: Int, app: String, frame: ZTRect, monitor: String, zone: String?) {
        self.windowId = windowId; self.app = app; self.frame = frame
        self.monitor = monitor; self.zone = zone
    }
}

public struct ScreenZones: Codable, Equatable {
    public let monitor: String
    public let screenName: String
    public let zones: [String]

    public init(monitor: String, screenName: String, zones: [String]) {
        self.monitor = monitor; self.screenName = screenName; self.zones = zones
    }
}

public struct PlacementStat: Codable, Equatable {
    public let app: String
    public let monitor: String
    public let zone: String
    public let tile: TileIndex
    public let count: Int

    public init(app: String, monitor: String, zone: String, tile: TileIndex, count: Int) {
        self.app = app; self.monitor = monitor; self.zone = zone; self.tile = tile; self.count = count
    }
}

public enum QueryResult: Codable, Equatable {
    // Labeled associated values so the synthesized JSON is self-describing
    // (`{"zones":{"screens":[…]}}`) rather than `{"zones":{"_0":[…]}}` — this is the text an MCP
    // client / the CLI surfaces to the model.
    case arrangement(windows: [WindowInfo])
    case zones(screens: [ScreenZones])
    case placementStats(stats: [PlacementStat])
    case unavailable(reason: String)   // e.g. a query that needs a subsystem that's disabled
}
