// ConfigWatcher.swift — watches config.toml for changes and fires a debounced callback so the
// agent can re-decode + re-wire in place (the native analog of hs.reload, but targeted). The
// callback runs on the main queue. Editors (and our own TOMLEditor) replace the file via
// atomic rename, which invalidates the fd, so we re-arm the source after each event.
//
// No self-write suppression: the agent applies reloads in-process and never writes the file
// during a reload, so a GUI save → one reload, with no feedback loop.

import Foundation

public final class ConfigWatcher {
    private let url: URL
    private let debounce: TimeInterval
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var pending: DispatchWorkItem?

    /// `debounce` collapses the burst of events an atomic-rename save emits into one reload.
    public init(url: URL, debounce: TimeInterval = 0.15, onChange: @escaping () -> Void) {
        self.url = url
        self.debounce = debounce
        self.onChange = onChange
    }

    public func start() { arm() }

    public func stop() {
        pending?.cancel(); pending = nil
        source?.cancel(); source = nil   // cancel handler closes the fd
    }

    private func arm() {
        source?.cancel()
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        src.setEventHandler { [weak self] in self?.handleEvent() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd); self?.fd = -1 }
        }
        source = src
        src.resume()
    }

    private func handleEvent() {
        // A rename/delete (atomic save) detaches our fd from the live file — re-arm on the new
        // inode so subsequent edits keep firing. Then debounce the user-facing callback.
        let data = source?.data ?? []
        if data.contains(.rename) || data.contains(.delete) { arm() }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
