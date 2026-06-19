// AgentSocket.swift — the one place the agent (server) and the zt-mcp shim (client) agree on
// the IPC socket location. A file under the user config dir, alongside the JSON state.

import Foundation

public enum AgentSocket {
    /// `~/.config/ZoneTilerWM/agent.sock`, overridable via ZT_AGENT_SOCKET (tests / dev).
    public static func defaultPath() -> String {
        if let override = ProcessInfo.processInfo.environment["ZT_AGENT_SOCKET"], !override.isEmpty {
            return override
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/ZoneTilerWM/agent.sock").path
    }
}
