// MCPServerTests — the pure JSON-RPC handler is exercised with stub perform/query closures;
// the wire contract (tools/resources) is asserted against the catalog.

import XCTest
import Foundation
@testable import ZTCore

final class MCPServerTests: XCTestCase {

    /// Records what the handler dispatched, and returns canned outcomes.
    final class Recorder {
        var performed: [ActionRequest] = []
        var queried: [QueryRequest] = []
        func context() -> MCPServer.Context {
            MCPServer.Context(serverName: "zonetiler", serverVersion: "2.0.0",
                perform: { req in self.performed.append(req); return .zenToggled },
                query: { q in self.queried.append(q); return .zones(screens: []) })
        }
    }

    private let server = MCPServer()

    private func send(_ message: [String: Any], _ rec: Recorder) -> [String: Any]? {
        let data = try! JSONSerialization.data(withJSONObject: message)
        guard let out = server.handle(data, context: rec.context()) else { return nil }
        return (try! JSONSerialization.jsonObject(with: out)) as? [String: Any]
    }

    func testInitializeHandshake() {
        let rec = Recorder()
        let resp = send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                         "params": ["protocolVersion": "2024-11-05"]], rec)
        let result = resp?["result"] as? [String: Any]
        XCTAssertEqual(result?["protocolVersion"] as? String, "2024-11-05")
        let info = result?["serverInfo"] as? [String: Any]
        XCTAssertEqual(info?["name"] as? String, "zonetiler")
        XCTAssertNotNil(result?["capabilities"])
        XCTAssertEqual(resp?["id"] as? Int, 1)
    }

    func testInitializeDefaultsProtocolVersion() {
        let rec = Recorder()
        let resp = send(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [:]], rec)
        let result = resp?["result"] as? [String: Any]
        XCTAssertEqual(result?["protocolVersion"] as? String, MCPServer.defaultProtocolVersion)
    }

    func testInitializedNotificationGetsNoResponse() {
        let rec = Recorder()
        let data = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        XCTAssertNil(server.handle(data, context: rec.context()))
    }

    func testPing() {
        let rec = Recorder()
        let resp = send(["jsonrpc": "2.0", "id": 2, "method": "ping"], rec)
        XCTAssertNotNil(resp?["result"])
    }

    func testToolsListMatchesCatalog() {
        let rec = Recorder()
        let resp = send(["jsonrpc": "2.0", "id": 3, "method": "tools/list"], rec)
        let tools = (resp?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.count, ActionParser.catalog.count)
        let names = Set(tools?.compactMap { $0["name"] as? String } ?? [])
        XCTAssertEqual(names, Set(ActionParser.catalog.map { $0.name }))
        // The `tile` tool requires `zone`.
        let tile = tools?.first { $0["name"] as? String == "tile" }
        let schema = tile?["inputSchema"] as? [String: Any]
        XCTAssertEqual(schema?["required"] as? [String], ["zone"])
        let props = schema?["properties"] as? [String: Any]
        XCTAssertNotNil(props?["zone"])
    }

    func testToolsCallValid() {
        let rec = Recorder()
        let resp = send(["jsonrpc": "2.0", "id": 4, "method": "tools/call",
                         "params": ["name": "tile", "arguments": ["zone": "h"]]], rec)
        XCTAssertEqual(rec.performed, [.tileFocusedToZone(zone: "h")])
        let result = resp?["result"] as? [String: Any]
        XCTAssertEqual(result?["isError"] as? Bool, false)
        let content = result?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["type"] as? String, "text")
        // The text is the JSON-encoded ActionResult.
        let text = content?.first?["text"] as? String ?? ""
        XCTAssertTrue(text.contains("zenToggled"), "expected the stubbed result, got \(text)")
    }

    func testToolsCallMissingRequiredParamIsToolError() {
        let rec = Recorder()
        let resp = send(["jsonrpc": "2.0", "id": 5, "method": "tools/call",
                         "params": ["name": "tile", "arguments": [:]]], rec)
        XCTAssertTrue(rec.performed.isEmpty)
        let result = resp?["result"] as? [String: Any]
        XCTAssertEqual(result?["isError"] as? Bool, true)
    }

    func testToolsCallUnknownToolIsToolError() {
        let rec = Recorder()
        let resp = send(["jsonrpc": "2.0", "id": 6, "method": "tools/call",
                         "params": ["name": "frobnicate", "arguments": [:]]], rec)
        XCTAssertTrue(rec.performed.isEmpty)
        XCTAssertEqual((resp?["result"] as? [String: Any])?["isError"] as? Bool, true)
    }

    func testResourcesList() {
        let rec = Recorder()
        let resp = send(["jsonrpc": "2.0", "id": 7, "method": "resources/list"], rec)
        let resources = (resp?["result"] as? [String: Any])?["resources"] as? [[String: Any]]
        XCTAssertEqual(resources?.count, QueryRequest.allCases.count)
        let uris = Set(resources?.compactMap { $0["uri"] as? String } ?? [])
        XCTAssertEqual(uris, Set(QueryRequest.allCases.map { $0.uri }))
    }

    func testResourcesRead() {
        let rec = Recorder()
        let resp = send(["jsonrpc": "2.0", "id": 8, "method": "resources/read",
                         "params": ["uri": "zonetiler://zones"]], rec)
        XCTAssertEqual(rec.queried, [.zones])
        let contents = (resp?["result"] as? [String: Any])?["contents"] as? [[String: Any]]
        XCTAssertEqual(contents?.first?["uri"] as? String, "zonetiler://zones")
        XCTAssertEqual(contents?.first?["mimeType"] as? String, "application/json")
    }

    func testResourcesReadUnknownURIErrors() {
        let rec = Recorder()
        let resp = send(["jsonrpc": "2.0", "id": 9, "method": "resources/read",
                         "params": ["uri": "zonetiler://nope"]], rec)
        XCTAssertNotNil(resp?["error"])
        XCTAssertTrue(rec.queried.isEmpty)
    }

    func testUnknownMethodErrors() {
        let rec = Recorder()
        let resp = send(["jsonrpc": "2.0", "id": 10, "method": "no/such"], rec)
        let error = resp?["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? Int, -32601)
    }

    func testMalformedJSONIsParseError() {
        let rec = Recorder()
        let out = server.handle(Data("{not json".utf8), context: rec.context())
        let resp = out.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        XCTAssertEqual((resp?["error"] as? [String: Any])?["code"] as? Int, -32700)
    }
}
