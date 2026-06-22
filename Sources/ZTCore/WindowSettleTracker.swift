// WindowSettleTracker.swift — detects when a window has come to REST at a new frame, the signal
// that the user finished dragging it somewhere (feedback 7b: a manual move re-teaches its zone).
//
// Pure + AX-free by construction: it is fed the (id, frame) snapshots the caller already read from
// the CGWindowList poll each tick, and returns the ids that just settled. No timers, no Accessibility
// — the runtime controller owns the polling cadence and calls `observe` once per tick.
//
// Semantics: a window fires ONCE when its frame has held stable for `settleTicks` consecutive
// observations AND that resting frame differs from the one it last fired at. So a drag in progress
// (frame changing each tick) keeps resetting and never fires; a window sitting still doesn't re-fire;
// and a window that is moved, rests, moved again, rests again fires once per rest. Windows seen for
// the first time are seeded as already-at-rest, so the initial enumeration never fires a flood.

import Foundation

public struct WindowSettleTracker {

    public struct Observation {
        public let id: Int
        public let frame: ZTRect
        public init(id: Int, frame: ZTRect) { self.id = id; self.frame = frame }
    }

    private struct Track {
        var frame: ZTRect       // the frame at the last observation
        var stableTicks: Int    // consecutive ticks the frame has been unchanged
        var firedFrame: ZTRect? // the resting frame we last reported settled (dedup guard)
    }

    private var tracks: [Int: Track] = [:]
    private let settleTicks: Int
    private let moveEpsilon: Double

    /// - settleTicks: how many consecutive unchanged observations count as "at rest" (>=1).
    /// - moveEpsilon: per-edge pixel slack below which a difference isn't a real move (AX/animation
    ///   rounding). Frames within epsilon on all four edges are treated as identical.
    public init(settleTicks: Int = 2, moveEpsilon: Double = 2.0) {
        self.settleTicks = max(1, settleTicks)
        self.moveEpsilon = moveEpsilon
    }

    /// Feed one tick's window snapshots. Returns the ids that just came to rest at a NEW position
    /// (i.e. should be re-learned). Order follows `windows`.
    public mutating func observe(_ windows: [Observation]) -> [Int] {
        var settled: [Int] = []
        let present = Set(windows.map { $0.id })
        tracks = tracks.filter { present.contains($0.key) }   // forget vanished windows

        for w in windows {
            guard var t = tracks[w.id] else {
                // First sighting: seed as already-at-rest (firedFrame == current) so we never fire
                // on the baseline enumeration — only on a *subsequent* move-then-rest.
                tracks[w.id] = Track(frame: w.frame, stableTicks: settleTicks, firedFrame: w.frame)
                continue
            }
            if Self.moved(t.frame, w.frame, eps: moveEpsilon) {
                t.frame = w.frame           // at a new frame: this observation is its 1st tick at rest
                t.stableTicks = 1
            } else {
                t.stableTicks += 1
                let isNewRest = t.firedFrame == nil || Self.moved(t.firedFrame!, w.frame, eps: moveEpsilon)
                if t.stableTicks >= settleTicks && isNewRest {
                    settled.append(w.id)
                    t.firedFrame = w.frame   // dedup: don't fire again until it moves to a new rest
                }
            }
            tracks[w.id] = t
        }
        return settled
    }

    /// True if two frames differ by more than `eps` on any edge.
    static func moved(_ a: ZTRect, _ b: ZTRect, eps: Double) -> Bool {
        abs(a.x - b.x) > eps || abs(a.y - b.y) > eps || abs(a.w - b.w) > eps || abs(a.h - b.h) > eps
    }
}
