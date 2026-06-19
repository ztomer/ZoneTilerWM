// AgentSocketClient.swift — the shim side of the agent IPC. Connects to the agent's Unix-domain
// socket, writes one JSON `IPCRequest` line, reads one `IPCResponse` line, closes. Returns
// `.error` if the agent isn't reachable (e.g. zt-agent isn't running).

import Foundation
import ZTCore

public struct AgentSocketClient {
    private let path: String
    public init(path: String) { self.path = path }

    public func send(_ request: IPCRequest) -> IPCResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .error("socket() failed") }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8CString)
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            return .error("socket path too long")
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
                pathBytes.withUnsafeBufferPointer { src in dst.update(from: src.baseAddress!, count: pathBytes.count) }
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        guard connected == 0 else { return .error("agent not reachable at \(path)") }

        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        guard var payload = try? JSONEncoder().encode(request) else { return .error("encode failed") }
        payload.append(0x0A)
        let wrote = payload.withUnsafeBytes { write(fd, $0.baseAddress, payload.count) }
        guard wrote == payload.count else { return .error("write failed") }

        guard let line = readLine(fd) else { return .error("no response from agent") }
        guard let response = try? JSONDecoder().decode(IPCResponse.self, from: line) else {
            return .error("malformed response from agent")
        }
        return response
    }

    private func readLine(_ fd: Int32) -> Data? {
        var acc = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return acc.isEmpty ? nil : acc }
            if let nl = chunk[0..<n].firstIndex(of: 0x0A) {
                acc.append(contentsOf: chunk[0..<nl]); return acc
            }
            acc.append(contentsOf: chunk[0..<n])
            if acc.count > 1_000_000 { return nil }
        }
    }
}
