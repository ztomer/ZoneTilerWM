// Models.swift — value snapshots the solver/auto-tiler/placement operate on.
// These are plain data (built once by the system layer per operation), so the hot
// algorithms never touch protocol existentials or live OS objects.

/// A tile index. Usually an integer zone-tile index, but the auto-tiler's BSP splitter
/// produces string ids like "4a"/"4b". Mirrors Lua, where `tonumber(tile_index)` yields
/// a number for the former and nil for the latter. Equality is type-strict (matching
/// Lua's `==`): `.int(1)` does not equal `.string("1")`.
public enum TileIndex: Codable, Equatable, Hashable {
    case int(Int)
    case string(String)

    /// Canonical string form, matching Lua's `tostring(tile_index)`. Used as the
    /// deterministic tie-break key (lexicographic) in window-memory ranking.
    public var sortKey: String {
        switch self {
        case .int(let i): return String(i)
        case .string(let s): return s
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "TileIndex must be an Int or String")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let i): try c.encode(i)
        case .string(let s): try c.encode(s)
        }
    }

    /// Numeric value, or nil for non-numeric string ids — equivalent to Lua `tonumber()`.
    public var numericValue: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .string(let s): return Double(s)
        }
    }
}

/// A learned placement preference for an app, ranked (index 0 = strongest).
public struct MemoryPref: Codable, Equatable {
    public var zone_key: String
    public var tile_index: TileIndex
    public var count: Int?

    public init(zone_key: String, tile_index: TileIndex, count: Int? = nil) {
        self.zone_key = zone_key; self.tile_index = tile_index; self.count = count
    }
}

/// A window as the **solver** sees it. `id` is an opaque label used only to map results
/// back to the caller's windows — it is NOT a live window id. (The solver corpus uses
/// app-name-ish labels like "WideApp"; the live layer stringifies its CGWindowID into this
/// field when invoking the solver.) Only `w`/`h` + `memory` feed the cost function.
///
/// Window-value-type model (intentionally two types, do not merge):
///   - `WindowSnapshot` — solver input, label-keyed (this type).
///   - `AutoTiler.Window` / live enumeration — keyed by the real Int CGWindowID.
public struct WindowSnapshot: Codable, Equatable {
    public var id: String
    public var w: Double
    public var h: Double
    /// Ranked memory preferences for this window's app, most-preferred first.
    public var memory: [MemoryPref]?

    public init(id: String, w: Double, h: Double, memory: [MemoryPref]? = nil) {
        self.id = id; self.w = w; self.h = h; self.memory = memory
    }
}

/// A candidate tile: a zone key, a tile index within that zone, and its pixel rect.
public struct TileSpec: Codable, Equatable {
    public var zone: String
    public var idx: TileIndex
    public var rect: ZTRect

    public init(zone: String, idx: TileIndex, rect: ZTRect) {
        self.zone = zone; self.idx = idx; self.rect = rect
    }
}
