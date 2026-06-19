// ZoneConfig.swift — the subset of config.toml's [tiler] section that ZoneCalculator
// needs. Mirrors the Lua tables read by zone_calculator.lua. Decoded from the same JSON
// the Lua oracle emits, so both sides see identical input.

public struct GridConfig: Codable, Equatable {
    public var cols: Int
    public var rows: Int
    public init(cols: Int, rows: Int) { self.cols = cols; self.rows = rows }
}

public struct Margins: Codable, Equatable {
    public var enabled: Bool
    public var size: Double
    public var screen_edge: Bool
    public init(enabled: Bool, size: Double, screen_edge: Bool) {
        self.enabled = enabled; self.size = size; self.screen_edge = screen_edge
    }
    enum CodingKeys: String, CodingKey { case enabled, size, screen_edge }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        size = try c.decodeFlexDouble(.size)   // TOML stores `size = 5` as an integer
        screen_edge = try c.decode(Bool.self, forKey: .screen_edge)
    }
}

public struct CustomScreen: Codable, Equatable {
    public var layout: String
}

/// Portrait detection thresholds (config.tiler.screen_detection.portrait.{large,small}).
public struct PortraitDetection: Codable, Equatable {
    public struct Entry: Codable, Equatable {
        public var layout: String
        /// Optional min screen height to choose the "large" portrait layout (Lua defaults 2000).
        public var min_height_for_layout_check: Double?
    }
    public var large: Entry?
    public var small: Entry?
}

public struct ScreenDetection: Codable, Equatable {
    /// name-pattern (Lua string.match pattern) -> layout key.
    public var patterns: [String: String]?
    public var portrait: PortraitDetection?
}

/// Everything ZoneCalculator reads. `layouts` maps a layout key (e.g. "4x3") to a map of
/// zone key (e.g. "j") -> list of tile-coordinate strings (e.g. ["b1:c3", "b2"]).
public struct ZoneConfig: Codable, Equatable {
    public var grids: [String: GridConfig]
    public var layouts: [String: [String: [String]]]
    public var margins: Margins?
    public var screen_detection: ScreenDetection?
    public var custom_screens: [String: CustomScreen]?

    public init(grids: [String: GridConfig],
                layouts: [String: [String: [String]]],
                margins: Margins? = nil,
                screen_detection: ScreenDetection? = nil,
                custom_screens: [String: CustomScreen]? = nil) {
        self.grids = grids
        self.layouts = layouts
        self.margins = margins
        self.screen_detection = screen_detection
        self.custom_screens = custom_screens
    }
}
