// MCPServer.swift — a pure, transport-free MCP (Model Context Protocol) message handler.
//
// MCP over stdio is JSON-RPC 2.0 with newline-delimited messages. This type takes one message
// (a line of bytes) and returns the response bytes to write back (or nil for a notification,
// which gets no response). It executes nothing itself: the Context injects `perform` (run an
// action) and `query` (read a resource), so the handler is fully unit-testable with stubs, and
// the zt-mcp shim wires those closures to "send the IPCEnvelope over the socket to the agent."
//
// Implemented methods: initialize, notifications/initialized, ping, tools/list, tools/call,
// resources/list, resources/read. Tools and resources are generated from ActionParser.catalog
// and QueryRequest.allCases — one source of truth, so the wire contract can't drift from the
// vocabulary.

import Foundation

public struct MCPServer {

    public struct Context {
        public var perform: (ActionRequest) -> ActionResult
        public var query: (QueryRequest) -> QueryResult
        public var serverName: String
        public var serverVersion: String
        public init(serverName: String, serverVersion: String,
                    perform: @escaping (ActionRequest) -> ActionResult,
                    query: @escaping (QueryRequest) -> QueryResult) {
            self.serverName = serverName; self.serverVersion = serverVersion
            self.perform = perform; self.query = query
        }
    }

    /// The newest protocol version we advertise when the client doesn't pin one.
    public static let defaultProtocolVersion = "2024-11-05"

    public init() {}

    /// Handle one JSON-RPC message. Returns response bytes (a single line, no trailing newline)
    /// or nil for a notification.
    public func handle(_ line: Data, context: Context) -> Data? {
        guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            return encode(errorObject(id: nil, code: -32700, message: "Parse error"))
        }
        guard let method = obj["method"] as? String else {
            return encode(errorObject(id: obj["id"], code: -32600, message: "Invalid Request"))
        }
        let id = obj["id"]
        let isNotification = !obj.keys.contains("id")
        let params = obj["params"] as? [String: Any] ?? [:]

        // Notifications get no response regardless of method.
        if isNotification { return nil }

        switch method {
        case "initialize":
            return encode(resultObject(id: id, result: initializeResult(params, context)))
        case "ping":
            return encode(resultObject(id: id, result: [:]))
        case "tools/list":
            return encode(resultObject(id: id, result: ["tools": toolsList()]))
        case "tools/call":
            return encode(resultObject(id: id, result: toolsCall(params, context)))
        case "resources/list":
            return encode(resultObject(id: id, result: ["resources": resourcesList()]))
        case "resources/read":
            switch resourcesRead(params, context) {
            case .success(let result): return encode(resultObject(id: id, result: result))
            case .failure(let err):    return encode(errorObject(id: id, code: err.code, message: err.message))
            }
        default:
            return encode(errorObject(id: id, code: -32601, message: "Method not found: \(method)"))
        }
    }

    // MARK: - method results

    private func initializeResult(_ params: [String: Any], _ ctx: Context) -> [String: Any] {
        let version = (params["protocolVersion"] as? String) ?? Self.defaultProtocolVersion
        return [
            "protocolVersion": version,
            "capabilities": ["tools": [:] as [String: Any], "resources": [:] as [String: Any]],
            "serverInfo": ["name": ctx.serverName, "version": ctx.serverVersion],
        ]
    }

    private func toolsList() -> [[String: Any]] {
        ActionParser.catalog.map { spec in
            ["name": spec.name, "description": spec.description, "inputSchema": inputSchema(spec)]
        }
    }

    private func inputSchema(_ spec: ActionSpec) -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []
        for p in spec.params {
            var prop: [String: Any] = ["type": "string", "description": p.description]
            if let allowed = p.allowed { prop["enum"] = allowed }
            properties[p.name] = prop
            if p.required { required.append(p.name) }
        }
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        return schema
    }

    private func toolsCall(_ params: [String: Any], _ ctx: Context) -> [String: Any] {
        guard let name = params["name"] as? String else {
            return toolError("missing tool name")
        }
        // Arguments arrive as a JSON object of strings; coerce values to String defensively.
        var args: [String: String] = [:]
        if let raw = params["arguments"] as? [String: Any] {
            for (k, v) in raw { args[k] = stringify(v) }
        }
        switch ActionParser.parse(name: name, params: args) {
        case .failure(let e):
            return toolError("invalid request: \(describe(e))")
        case .success(let request):
            let result = ctx.perform(request)
            return ["content": [["type": "text", "text": jsonText(result)]], "isError": false]
        }
    }

    private func resourcesList() -> [[String: Any]] {
        QueryRequest.allCases.map { q in
            ["uri": q.uri, "name": q.displayName, "description": q.description, "mimeType": "application/json"]
        }
    }

    private struct RPCError: Error { let code: Int; let message: String }

    private func resourcesRead(_ params: [String: Any], _ ctx: Context) -> Result<[String: Any], RPCError> {
        guard let uri = params["uri"] as? String else {
            return .failure(RPCError(code: -32602, message: "missing uri"))
        }
        guard let q = QueryRequest(uri: uri) else {
            return .failure(RPCError(code: -32602, message: "unknown resource: \(uri)"))
        }
        let result = ctx.query(q)
        return .success(["contents": [["uri": uri, "mimeType": "application/json", "text": jsonText(result)]]])
    }

    // MARK: - helpers

    private func toolError(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    private func resultObject(id: Any?, result: Any) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }

    private func errorObject(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private func encode(_ obj: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
    }

    /// Encode a Codable outcome to a compact JSON string for embedding as MCP text content.
    private func jsonText<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private func stringify(_ v: Any) -> String {
        switch v {
        case let s as String: return s
        case let b as Bool:   return b ? "true" : "false"
        case let n as NSNumber: return n.stringValue
        default: return "\(v)"
        }
    }

    private func describe(_ e: ActionError) -> String {
        switch e {
        case .noFocusedWindow:        return "no focused window"
        case .noScreenForWindow:      return "no screen for window"
        case .noZone(let z):          return "unknown zone '\(z)'"
        case .noTile:                 return "no available tile"
        case .unsupportedAction:      return "unsupported action"
        case .invalidParameter(let p): return "invalid or missing parameter '\(p)'"
        case .agentUnavailable:       return "agent unavailable"
        }
    }
}
