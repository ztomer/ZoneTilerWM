// EventStreamController.swift — the state-diff event stream. On a timer it polls the current
// arrangement (CGWindowList via the query provider = 0 AX); when the arrangement SIGNATURE changes
// (a window moves zone/monitor, appears, or disappears — see ZTCore.ArrangementSignature) it
// appends one JSON line to an events file. External tools `tail -f` that file to react to layout
// changes without polling. Gated: [events] enabled (default off). 0 AX. The baseline (first poll)
// is recorded but not emitted — only changes produce lines.

import Foundation
import ZTCore

final class EventStreamController {
    private let arrangement: () -> [WindowInfo]
    private let path: () -> String
    private let intervalMs: () -> Int
    private let now: () -> Int

    private var timer: Timer?
    private var lastSig: String?

    private struct Event: Codable { let ts: Int; let windows: [WindowInfo] }

    init(arrangement: @escaping () -> [WindowInfo], path: @escaping () -> String,
         intervalMs: @escaping () -> Int, now: @escaping () -> Int = { Int(Date().timeIntervalSince1970) }) {
        self.arrangement = arrangement; self.path = path; self.intervalMs = intervalMs; self.now = now
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        let secs = Double(max(250, min(10_000, intervalMs()))) / 1000.0   // clamp 0.25–10s
        let t = Timer.scheduledTimer(withTimeInterval: secs, repeats: true) { [weak self] _ in self?.tick() }
        timer = t
        tick()   // record the baseline immediately (not emitted)
    }

    func stop() { timer?.invalidate(); timer = nil; lastSig = nil }

    private func tick() {
        let wins = arrangement()                        // 0 AX (CGWindowList)
        let sig = ArrangementSignature.of(wins)
        guard sig != lastSig else { return }
        let isBaseline = lastSig == nil
        lastSig = sig
        guard !isBaseline else { return }               // emit changes, not the first snapshot
        append(wins)
    }

    private func append(_ wins: [WindowInfo]) {
        guard var data = try? JSONEncoder().encode(Event(ts: now(), windows: wins)) else { return }
        data.append(0x0A)   // newline-delimited JSON (jsonl)
        let url = URL(fileURLWithPath: path())
        if let fh = try? FileHandle(forWritingTo: url) {
            defer { try? fh.close() }
            _ = try? fh.seekToEnd()
            try? fh.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)   // create on first event
        }
    }
}
