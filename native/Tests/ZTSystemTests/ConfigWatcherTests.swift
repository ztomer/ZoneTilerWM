// ConfigWatcherTests — the file-watch that drives live config reload. Timing-based, so it
// uses expectations and a temp file; the assertions are about debounce + that edits fire.

import XCTest
@testable import ZTSystem

final class ConfigWatcherTests: XCTestCase {

    private func tempFile() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ztwatch-\(UUID().uuidString).toml")
        try? "version = \"1\"\n".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testFiresOnWrite() {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let exp = expectation(description: "change fired")
        let watcher = ConfigWatcher(url: url, debounce: 0.05) { exp.fulfill() }
        watcher.start()
        defer { watcher.stop() }

        // Give the source a beat to arm, then write.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            try? "version = \"2\"\n".write(to: url, atomically: false, encoding: .utf8)
        }
        wait(for: [exp], timeout: 3.0)
    }

    func testDebounceCollapsesBurstToOne() {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        var fires = 0
        let settled = expectation(description: "settled")
        let watcher = ConfigWatcher(url: url, debounce: 0.2) {
            fires += 1
            // After the first (collapsed) fire, wait a bit to ensure no second fire arrives.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settled.fulfill() }
        }
        watcher.start()
        defer { watcher.stop() }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for i in 0..<5 {   // rapid burst within the debounce window
                try? "version = \"\(i)\"\n".write(to: url, atomically: false, encoding: .utf8)
            }
        }
        wait(for: [settled], timeout: 3.0)
        XCTAssertEqual(fires, 1, "a burst of writes should debounce to a single reload")
    }
}
