// ZoneHUDSession.swift — the pure interaction state machine for the zone HUD, redesigned from a
// passive cheat-sheet into an interactive "preview-then-commit" picker (v2.8 field-feedback pass).
//
// Flow (tile-on-release, the default): hold the tiling modifier → after a short delay the overlay
// shows → press a zone key HIGHLIGHTS that zone (a live preview, no move yet) → the highlight
// persists until you release the modifier or press another zone key → releasing the modifier COMMITS
// the highlighted zone. `tileImmediately` keeps the old fire-on-keypress behaviour as a toggle.
//
// Two guards make the short show-delay safe: the overlay only arms when the modifier is held ALONE
// (no other non-modifier key down — you're summoning the grid, not mid-chord), and a missed
// modifier-up is recoverable by the host (feed `.modifier(matchesTarget: false, ...)`).
//
// Pure: no AppKit, no timers, no AX. The host owns the arm timer (driven by the `.arm`/`.disarm`
// effects) and performs the `.show`/`.hide`/`.highlight`/`.commit` effects. Fully unit-tested.

public struct ZoneHUDSession {

    public enum Mode: Equatable {
        /// Press a zone key to preview (highlight); releasing the modifier commits it. The default.
        case tileOnRelease
        /// Press a zone key to commit immediately (the legacy behaviour); the overlay stays up.
        case tileImmediately
    }

    /// What the host should do in response to an event. The host owns the actual timer/AppKit/AX.
    public enum Effect: Equatable {
        case arm(delayMs: Int)   // start (or restart) the show timer; fire `armElapsed()` when it elapses
        case disarm              // cancel a pending show timer
        case show                // present the overlay now
        case hide                // dismiss the overlay
        case highlight(String?)  // set the previewed zone (nil clears it)
        case commit(String)      // perform the tile for this zone key
    }

    private enum Phase: Equatable { case idle, arming, shown }

    private let mode: Mode
    private let holdDelayMs: Int
    private var phase: Phase = .idle
    private var highlighted: String?

    public init(mode: Mode = .tileOnRelease, holdDelayMs: Int = 200) {
        self.mode = mode
        self.holdDelayMs = holdDelayMs
    }

    public var isShown: Bool { phase == .shown }
    public var previewedKey: String? { highlighted }

    /// The tiling modifier's held-state changed.
    /// - matchesTarget: the currently-held modifiers exactly equal the configured tiling modifier.
    /// - otherKeysDown: any non-modifier key is currently held (suppresses arming — feedback #10).
    public mutating func modifier(matchesTarget: Bool, otherKeysDown: Bool) -> [Effect] {
        guard matchesTarget, !otherKeysDown else { return release() }
        switch phase {
        case .idle:
            phase = .arming
            return [.arm(delayMs: holdDelayMs)]
        case .arming, .shown:
            return []   // already arming/shown; nothing changes
        }
    }

    /// The host's show timer elapsed — present the overlay (unless we were disarmed meanwhile).
    public mutating func armElapsed() -> [Effect] {
        guard phase == .arming else { return [] }
        phase = .shown
        return [.show]
    }

    /// A zone key was pressed while the overlay is up.
    public mutating func zoneKey(_ key: String) -> [Effect] {
        guard phase == .shown else { return [] }
        switch mode {
        case .tileImmediately:
            return [.commit(key)]   // legacy: commit now, leave the overlay up to place more
        case .tileOnRelease:
            highlighted = key
            return [.highlight(key)]
        }
    }

    /// The modifier was released (or no longer matches, or another key joined it) — commit & tear down.
    private mutating func release() -> [Effect] {
        let wasShown = phase == .shown
        let pending = highlighted
        phase = .idle
        highlighted = nil
        var effects: [Effect] = [.disarm]
        if wasShown {
            if mode == .tileOnRelease, let key = pending { effects.append(.commit(key)) }
            effects.append(.hide)
        }
        return effects
    }
}
