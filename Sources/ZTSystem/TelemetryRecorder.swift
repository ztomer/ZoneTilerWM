// TelemetryRecorder.swift — opt-in LOCAL usage telemetry (feedback 11). When `[telemetry] enabled`,
// appends one JSON line per dispatched action — the action NAME + a unix timestamp, nothing else (no
// window titles, no app names) so it stays anonymous — to a file in /tmp. There is NO network sink yet
// (no collection backend), so this is purely a local usage log the user can inspect. Off by default;
// the toggle lives in the Advanced settings pane + the first-run wizard.

import Foundation

public final class TelemetryRecorder {
    private let path: String
    private let now: () -> Int
    private var enabled: Bool

    public init(path: String = "/tmp/zonetilerwm-telemetry.jsonl",
                enabled: Bool = false,
                now: @escaping () -> Int = { Int(Date().timeIntervalSince1970) }) {
        self.path = path
        self.enabled = enabled
        self.now = now
    }

    public var isEnabled: Bool { enabled }
    public var filePath: String { path }
    public func setEnabled(_ on: Bool) { enabled = on }

    /// Append one usage event (the action name only — anonymous). No-op when disabled.
    public func record(action: String) {
        guard enabled, !action.isEmpty else { return }
        let line = "{\"action\":\"\(action)\",\"ts\":\(now())}\n"
        guard let data = line.data(using: .utf8) else { return }
        if let fh = FileHandle(forWritingAtPath: path) {
            defer { try? fh.close() }
            fh.seekToEndOfFile()
            fh.write(data)
        } else {
            try? data.write(to: URL(fileURLWithPath: path))   // first event creates the file
        }
    }
}
