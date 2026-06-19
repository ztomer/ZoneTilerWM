// ArrangementSignature.swift — a stable signature of the window arrangement, for the state-diff
// event stream. The agent polls the arrangement (CGWindowList = 0 AX) on a timer; when this
// signature changes, it appends an event line to a file external tools can `tail -f` (subscribe to
// layout changes without polling). Signed on each window's id + occupied zone + monitor (NOT its
// raw frame), so only meaningful tiling changes — a window moving zone/monitor, appearing, or
// disappearing — emit an event; raw pixel jitter within a zone does not. Pure + order-independent.

public enum ArrangementSignature {
    public static func of(_ windows: [WindowInfo]) -> String {
        windows
            .map { "\($0.windowId):\($0.monitor):\($0.zone ?? "-")" }
            .sorted()
            .joined(separator: ",")
    }
}
