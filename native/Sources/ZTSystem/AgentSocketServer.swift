// AgentSocketServer.swift — a tiny Unix-domain-socket listener so the (AX-granted) running
// agent can answer IPC from the zt-mcp shim. A socket FILE under the user dir, never a listening
// TCP port (less EDR attention). One request per connection: the shim connects, writes one JSON
// `IPCRequest` line, reads one `IPCResponse` line, and closes.
//
// Single-threaded-on-main: the accept source runs on `.main`, and each tiny local message is
// handled inline there. A 2s recv timeout bounds any single read so a stuck client can't wedge
// the main thread.

import Foundation
import ZTCore

private func logErr(_ s: String) { FileHandle.standardError.write(Data(("zt-agent[ipc]: " + s + "\n").utf8)) }

public final class AgentSocketServer {
    private let path: String
    private let handler: (IPCRequest) -> IPCResponse
    private var listenFd: Int32 = -1
    private var source: DispatchSourceRead?

    public init(path: String, handler: @escaping (IPCRequest) -> IPCResponse) {
        self.path = path
        self.handler = handler
    }

    public func start() {
        unlink(path)   // clear a stale socket from a previous run / crash
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { logErr("socket() failed errno=\(errno)"); return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8CString)
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            logErr("socket path too long: \(path)"); close(fd); return
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
                pathBytes.withUnsafeBufferPointer { src in dst.update(from: src.baseAddress!, count: pathBytes.count) }
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
        }
        guard bound == 0 else { logErr("bind() failed errno=\(errno)"); close(fd); return }
        chmod(path, 0o700)   // owner-only
        guard listen(fd, 8) == 0 else { logErr("listen() failed errno=\(errno)"); close(fd); return }

        listenFd = fd
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        src.setEventHandler { [weak self] in self?.acceptOne() }
        src.resume()
        source = src
        logErr("listening on \(path)")
    }

    public func stop() {
        source?.cancel(); source = nil
        if listenFd >= 0 { close(listenFd); listenFd = -1 }
        unlink(path)
    }

    private func acceptOne() {
        let client = accept(listenFd, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        guard let line = readLine(client) else { return }
        let response: IPCResponse
        if let req = try? JSONDecoder().decode(IPCRequest.self, from: line) {
            response = handler(req)
        } else {
            response = .error("malformed IPC request")
        }
        if var data = try? JSONEncoder().encode(response) {
            data.append(0x0A)
            data.withUnsafeBytes { _ = write(client, $0.baseAddress, data.count) }
        }
    }

    /// Read up to the first newline (the message delimiter). Returns the bytes before it.
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
            if acc.count > 1_000_000 { return nil }   // sanity cap
        }
    }
}
