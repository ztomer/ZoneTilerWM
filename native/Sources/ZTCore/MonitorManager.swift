// MonitorManager.swift — port of the stable-logical-id registry in monitor_manager.lua.
// Maps a screen's persistent UUID to a stable logical id (1, 2, …) assigned in first-seen
// order and preserved across reconnects. The actual UUID fetch / screen lookup is the
// ScreenProvider boundary; this is the pure mapping policy.
//
// Note: logical ids are what the on-disk window_positions.json stores as monitor_id (the
// real file uses numeric ids — first screen == 1), so this reproduces that numbering.

public final class MonitorManager {

    private var registry: [String: Int] = [:]   // uuid -> logical id
    private var nextLogicalId = 1

    public init() {}

    /// Stable logical id for a screen UUID, registering it on first sight.
    public func id(forUUID uuid: String) -> Int {
        if let existing = registry[uuid] { return existing }
        let id = nextLogicalId
        nextLogicalId += 1
        registry[uuid] = id
        return id
    }

    /// The UUID for a logical id, if registered.
    public func uuid(forId id: Int) -> String? {
        registry.first(where: { $0.value == id })?.key
    }

    /// Whether a UUID has been registered.
    public func isRegistered(uuid: String) -> Bool { registry[uuid] != nil }

    /// Register all currently-known UUIDs (preserving existing ids), e.g. on screen change.
    public func reregister(uuids: [String]) {
        for uuid in uuids { _ = id(forUUID: uuid) }
    }
}
