// ResizeManager.swift — port of modules/resize_manager.lua. Holds per-monitor grid-line
// offsets (percentage of screen size, one per axis/index), adjustable in ±2% steps and
// clamped to ±40%. Supplies ZoneCalculator's OffsetProvider and persists via Storage.
//
// The Lua module's debounced save (hs.timer.delayed) is system glue; here saving is
// explicit (the system layer debounces). Pure logic + serialization only.

public final class ResizeManager {

    public static let stepSize = 0.02
    public static let clampLimit = 0.4
    public static let storageKey = "grid_offsets"

    /// On-disk shape: per monitor, an offsets-by-index map per axis (index keys are strings
    /// for JSON). Matches what grid_offsets.json holds.
    public struct MonitorOffsets: Codable, Equatable {
        public var x: [String: Double]
        public var y: [String: Double]
        public init(x: [String: Double] = [:], y: [String: Double] = [:]) { self.x = x; self.y = y }
    }

    // monitor -> axis ("x"/"y") -> grid-line index -> offset
    private var offsets: [String: [String: [Int: Double]]] = [:]

    public init() {}

    public func getOffset(monitor: String, axis: String, index: Int) -> Double {
        offsets[monitor]?[axis]?[index] ?? 0
    }

    public func adjust(monitor: String, axis: String, index: Int, delta: Double) {
        let current = offsets[monitor]?[axis]?[index] ?? 0
        var newVal = current + delta * Self.stepSize
        newVal = min(Self.clampLimit, max(-Self.clampLimit, newVal))
        offsets[monitor, default: [:]][axis, default: [:]][index] = newVal
    }

    public func reset(monitor: String) {
        offsets[monitor] = nil
    }

    /// A ZoneCalculator OffsetProvider bound to a specific monitor.
    public func offsetProvider(monitor: String) -> ZoneCalculator.OffsetProvider {
        { [weak self] axis, index in self?.getOffset(monitor: monitor, axis: axis, index: index) ?? 0 }
    }

    // MARK: - Serialization

    public func snapshot() -> [String: MonitorOffsets] {
        var out: [String: MonitorOffsets] = [:]
        for (monitor, axes) in offsets {
            var mo = MonitorOffsets()
            for (index, value) in axes["x"] ?? [:] { mo.x[String(index)] = value }
            for (index, value) in axes["y"] ?? [:] { mo.y[String(index)] = value }
            out[monitor] = mo
        }
        return out
    }

    public func restore(_ data: [String: MonitorOffsets]) {
        var loaded: [String: [String: [Int: Double]]] = [:]
        for (monitor, mo) in data {
            var x: [Int: Double] = [:], y: [Int: Double] = [:]
            for (k, v) in mo.x { if let i = Int(k) { x[i] = v } }
            for (k, v) in mo.y { if let i = Int(k) { y[i] = v } }
            loaded[monitor] = ["x": x, "y": y]
        }
        offsets = loaded
    }

    public func load(from storage: Storage) {
        if let data = storage.load(Self.storageKey, as: [String: MonitorOffsets].self) {
            restore(data)
        }
    }

    @discardableResult
    public func save(to storage: Storage) -> Bool {
        storage.save(Self.storageKey, snapshot())
    }
}
