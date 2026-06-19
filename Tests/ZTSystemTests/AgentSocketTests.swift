// AgentSocketTests — exercises the real Unix-domain-socket IPC (server + client) headlessly:
// no agent, no AX, no GUI. The server's accept source runs on the main queue, so the client
// runs on a background queue while wait(for:) spins the main run loop.

import XCTest
import Foundation
@testable import ZTCore
@testable import ZTSystem

final class AgentSocketTests: XCTestCase {

    private func tempPath() -> String { "/tmp/ztmcp-test-\(getpid())-\(abs(UUID().hashValue % 100000)).sock" }

    private func roundTrip(_ request: IPCRequest,
                           handler: @escaping (IPCRequest) -> IPCResponse) -> IPCResponse? {
        let path = tempPath()
        let server = AgentSocketServer(path: path, handler: handler)
        server.start()
        defer { server.stop() }

        let exp = expectation(description: "ipc response")
        var received: IPCResponse?
        DispatchQueue.global().async {
            let result = AgentSocketClient(path: path).send(request)
            DispatchQueue.main.async { received = result; exp.fulfill() }
        }
        wait(for: [exp], timeout: 5)
        return received
    }

    func testActionRoundTrip() {
        let response = roundTrip(.action(.tileFocusedToZone(zone: "h"))) { req in
            guard case .action(.tileFocusedToZone(let zone)) = req else { return .error("unexpected") }
            return .action(.tiled(windowId: 1, zone: zone, tileIndex: 1,
                                  target: ZTRect(x: 0, y: 0, w: 10, h: 10), applied: true))
        }
        XCTAssertEqual(response, .action(.tiled(windowId: 1, zone: "h", tileIndex: 1,
                                                target: ZTRect(x: 0, y: 0, w: 10, h: 10), applied: true)))
    }

    func testQueryRoundTrip() {
        let zones = [ScreenZones(monitor: "1", screenName: "Main", zones: ["h", "j", "k", "l"])]
        let response = roundTrip(.query(.zones)) { req in
            guard case .query(.zones) = req else { return .error("unexpected") }
            return .query(.zones(screens: zones))
        }
        XCTAssertEqual(response, .query(.zones(screens: zones)))
    }

    func testClientUnreachableReturnsError() {
        // No server bound at this path.
        let response = AgentSocketClient(path: "/tmp/ztmcp-nonexistent-\(getpid()).sock")
            .send(.action(.toggleZen))
        if case .error = response { /* expected */ } else {
            XCTFail("expected .error for unreachable agent, got \(response)")
        }
    }
}
