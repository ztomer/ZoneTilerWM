// IPCEnvelopeTests + QueryRequest round-trips — the agent↔shim wire format is Codable.

import XCTest
import Foundation
@testable import ZTCore

final class IPCEnvelopeTests: XCTestCase {

    func testRequestRoundTrip() throws {
        let cases: [IPCRequest] = [
            .action(.tileFocusedToZone(zone: "h")),
            .action(.switchAudio(device: .named("BlackHole"))),
            .query(.arrangement),
            .query(.placementStats),
            .query(.suggestions),
        ]
        for c in cases {
            let data = try JSONEncoder().encode(c)
            XCTAssertEqual(try JSONDecoder().decode(IPCRequest.self, from: data), c)
        }
    }

    func testResponseRoundTrip() throws {
        let rect = ZTRect(x: 0, y: 0, w: 10, h: 20)
        let cases: [IPCResponse] = [
            .action(.tiled(windowId: 1, zone: "h", tileIndex: 1, target: rect, applied: true)),
            .query(.arrangement(windows: [WindowInfo(windowId: 1, app: "Finder", frame: rect, monitor: "1", zone: "h")])),
            .query(.zones(screens: [ScreenZones(monitor: "1", screenName: "Main", zones: ["h", "j"])])),
            .query(.placementStats(stats: [PlacementStat(app: "Finder", monitor: "1", zone: "h", tile: .int(1), count: 3)])),
            .error("boom"),
        ]
        for c in cases {
            let data = try JSONEncoder().encode(c)
            XCTAssertEqual(try JSONDecoder().decode(IPCResponse.self, from: data), c)
        }
    }
}

final class QueryRequestTests: XCTestCase {

    func testURIRoundTrip() {
        for q in QueryRequest.allCases {
            XCTAssertEqual(QueryRequest(uri: q.uri), q)
        }
    }

    func testUnknownURIRejected() {
        XCTAssertNil(QueryRequest(uri: "zonetiler://nope"))
        XCTAssertNil(QueryRequest(uri: "http://arrangement"))
    }

    func testResultRoundTrip() throws {
        let rect = ZTRect(x: 1, y: 2, w: 3, h: 4)
        let cases: [QueryResult] = [
            .arrangement(windows: [WindowInfo(windowId: 9, app: "Zen", frame: rect, monitor: "2", zone: nil)]),
            .zones(screens: [ScreenZones(monitor: "1", screenName: "Main", zones: ["h"])]),
            .placementStats(stats: [PlacementStat(app: "Zen", monitor: "2", zone: "k", tile: .string("4a"), count: 1)]),
            .suggestions(suggestions: [PlacementSuggestion(windowId: 9, app: "Zen", monitor: "2", currentZone: "h", suggestedZone: "k", weight: 4.5)]),
            .unavailable(reason: "memory disabled"),
        ]
        for c in cases {
            let data = try JSONEncoder().encode(c)
            XCTAssertEqual(try JSONDecoder().decode(QueryResult.self, from: data), c)
        }
    }
}
