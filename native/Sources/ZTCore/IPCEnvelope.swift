// IPCEnvelope.swift — the wire format between the zt-mcp stdio shim and the running agent.
//
// The shim does no AX and holds no window-manager state; it forwards an IPCRequest to the
// agent over a Unix-domain socket (one JSON line per message) and relays the IPCResponse back
// out as MCP. Keeping this a plain Codable value type means both ends share one definition and
// the round-trip is unit-testable without any socket.

public enum IPCRequest: Codable, Equatable {
    case action(ActionRequest)
    case query(QueryRequest)
}

public enum IPCResponse: Codable, Equatable {
    case action(ActionResult)
    case query(QueryResult)
    case error(String)
}
