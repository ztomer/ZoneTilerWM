// TelemetryRecorderTests — opt-in local usage log writes only when enabled, anonymous lines.

import XCTest
@testable import ZTSystem

final class TelemetryRecorderTests: XCTestCase {

    private func tmp(_ tag: String) -> String { "/tmp/zt-telemetry-\(tag)-\(getpid()).jsonl" }

    func testRecordsAnonymousLinesWhenEnabled() {
        let path = tmp("on"); try? FileManager.default.removeItem(atPath: path)
        let r = TelemetryRecorder(path: path, enabled: true, now: { 1000 })
        r.record(action: "tile"); r.record(action: "zen")
        let content = (try? String(contentsOfFile: path)) ?? ""
        XCTAssertTrue(content.contains("{\"action\":\"tile\",\"ts\":1000}"))
        XCTAssertTrue(content.contains("{\"action\":\"zen\",\"ts\":1000}"))
        XCTAssertEqual(content.split(separator: "\n").count, 2)
        try? FileManager.default.removeItem(atPath: path)
    }

    func testNoOpWhenDisabled() {
        let path = tmp("off"); try? FileManager.default.removeItem(atPath: path)
        TelemetryRecorder(path: path, enabled: false, now: { 1 }).record(action: "tile")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testSetEnabledTogglesLive() {
        let path = tmp("toggle"); try? FileManager.default.removeItem(atPath: path)
        let r = TelemetryRecorder(path: path, enabled: false, now: { 5 })
        r.record(action: "a")              // off → dropped
        r.setEnabled(true); r.record(action: "b")
        r.setEnabled(false); r.record(action: "c")   // off again → dropped
        let content = (try? String(contentsOfFile: path)) ?? ""
        XCTAssertTrue(content.contains("\"action\":\"b\""))
        XCTAssertFalse(content.contains("\"action\":\"a\""))
        XCTAssertFalse(content.contains("\"action\":\"c\""))
        try? FileManager.default.removeItem(atPath: path)
    }
}
