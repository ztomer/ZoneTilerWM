// WindowFocusTracker.swift — port of window_cache.lua's last_focused_time bookkeeping. The
// auto-tiler's working-set cull (auto_tiler.lua:128-136) drops windows not focused within
// `working_set.time_limit_sec`; that needs a per-window "last focused" timestamp tracked over
// time. The live agent stamps the focused window here; the cull reads it back. Pure value
// logic — the clock is always injected, never read internally (determinism).

import Foundation

public final class WindowFocusTracker {
    private var lastFocusById: [Int: Int] = [:]   // window id (CGWindowID) -> epoch seconds

    public init() {}

    /// Record (or refresh) the focus time for a window — called when it becomes focused.
    public func record(id: Int, at time: Int) {
        lastFocusById[id] = time
    }

    /// Seed a baseline time only if the window is not already tracked, so an initial sweep
    /// (window_cache.refresh equivalent) never resets a window that already has a fresher time.
    public func recordIfAbsent(id: Int, at time: Int) {
        if lastFocusById[id] == nil { lastFocusById[id] = time }
    }

    /// Last focus time, or nil if never seen (caller falls back to `now`, matching the Lua
    /// `info and info.last_focused_time or now`).
    public func lastFocused(id: Int) -> Int? {
        lastFocusById[id]
    }

    public func forget(id: Int) {
        lastFocusById[id] = nil
    }

    /// Drop any tracked id not in the live set (windows that have since closed).
    public func prune(keepingIds live: Set<Int>) {
        lastFocusById = lastFocusById.filter { live.contains($0.key) }
    }
}
