// zt-mcp — the stdio MCP shim. An MCP client (Claude Desktop / Claude Code) spawns this; it
// speaks MCP/JSON-RPC over stdin/stdout and forwards every action/query to the already-running
// zt-agent over a Unix-domain socket. It does NO Accessibility and holds NO window-manager
// state — the AX/TCC grant and all logic stay in the agent. This keeps the shim a thin,
// permission-free bridge.
//
//   stdin  : newline-delimited JSON-RPC requests from the client
//   stdout : newline-delimited JSON-RPC responses
//   socket : zt-agent (default ~/.config/ZoneTilerWM/agent.sock; ZT_AGENT_SOCKET overrides)

import Foundation
import ZTCore
import ZTSystem

let client = AgentSocketClient(path: AgentSocket.defaultPath())
let server = MCPServer()

let context = MCPServer.Context(
    serverName: "zonetiler",
    serverVersion: "1.4.3",
    perform: { request in
        switch client.send(.action(request)) {
        case .action(let result): return result
        case .error:              return .failed(reason: .agentUnavailable)
        case .query:              return .failed(reason: .unsupportedAction)
        }
    },
    query: { query in
        switch client.send(.query(query)) {
        case .query(let result): return result
        case .error(let message): return .unavailable(reason: message)
        case .action:            return .unavailable(reason: "unexpected action response")
        }
    })

// stdout must carry ONLY protocol messages — write diagnostics to stderr.
func emit(_ data: Data) {
    var line = data
    line.append(0x0A)
    FileHandle.standardOutput.write(line)
}

// Read newline-delimited messages from stdin. readLine() handles the framing for us.
while let line = readLine(strippingNewline: true) {
    if line.isEmpty { continue }
    if let response = server.handle(Data(line.utf8), context: context) {
        emit(response)
    }
}
