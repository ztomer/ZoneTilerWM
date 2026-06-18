// zonetiler-cli — shell front-end over the ZoneTilerWM action API. Talks to the running agent
// over the same Unix-domain socket the MCP shim uses (default ~/.config/ZoneTilerWM/agent.sock,
// ZT_AGENT_SOCKET overrides). Does NO Accessibility itself — the agent holds the TCC grant.
//
//   zonetiler-cli <action> [--key value …]   e.g. zonetiler-cli tile --zone h
//   zonetiler-cli get <resource>             e.g. zonetiler-cli get arrangement
//   zonetiler-cli list | --help              print the catalog
//   (append --json for machine-readable output)

import Foundation
import ZTCore
import ZTSystem

func out(_ s: String) { print(s) }
func err(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

func emitJSON<T: Encodable>(_ value: T) {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? enc.encode(value) { out(String(decoding: data, as: UTF8.self)) }
}

// Pull out the global --json flag wherever it appears.
var args = Array(CommandLine.arguments.dropFirst())
let jsonMode = args.contains("--json")
args.removeAll { $0 == "--json" }

guard let first = args.first, first != "list", first != "help", first != "--help", first != "-h" else {
    out(CLIFormat.usage())
    exit(0)
}

let client = AgentSocketClient(path: AgentSocket.defaultPath())

if first == "get" {
    guard args.count >= 2, let query = CLIFormat.resource(args[1]) else {
        err("usage: zonetiler-cli get <\(QueryRequest.allCases.map { CLIFormat.cliName($0) }.joined(separator: "|"))>")
        exit(2)
    }
    switch client.send(.query(query)) {
    case .query(let result):
        if jsonMode { emitJSON(result) } else { out(CLIFormat.summary(result)) }
    case .error(let message): err("error: \(message)"); exit(2)
    case .action: err("error: unexpected action response"); exit(2)
    }
    exit(0)
}

// Otherwise: an action. The argv (name + --key value pairs) maps through the shared parser.
switch ActionParser.parse(argv: args) {
case .failure(let parseError):
    err("error: \(CLIFormat.describe(parseError))")
    err("run `zonetiler-cli --help` for the action list.")
    exit(2)
case .success(let request):
    switch client.send(.action(request)) {
    case .action(let result):
        if jsonMode { emitJSON(result) } else { out(CLIFormat.summary(result)) }
        exit(CLIFormat.isFailure(result) ? 1 : 0)
    case .error(let message): err("error: \(message)"); exit(2)
    case .query: err("error: unexpected query response"); exit(2)
    }
}
