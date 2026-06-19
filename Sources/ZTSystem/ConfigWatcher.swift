// ConfigWatcher.swift — watches config.toml for changes and fires a debounced callback so the
// agent can re-decode + re-wire in place (the native analog of hs.reload, but targeted). The
// callback runs on the main queue.
//
// Atomic-rename saves are the hazard: editors (and our TOMLEditor / SwiftUI's
// String.write(atomically:true)) replace the file by renaming a temp over it, which unlinks the
// inode our fd watches. Re-arming on .rename/.delete catches the *next* edit but the fd can miss
// the event that unlinks it, so a burst of atomic saves drops reloads (a GUI toggle then "does
// nothing"). So we pair the DispatchSource (instant response) with a 1s modification-time poll
// (safety net): whichever notices the new mtime first fires; mtime de-dupes the other. The poll
// stats only the config file, so sibling JSON state writes in the same dir don't trigger reloads.
//
// No self-write suppression: the agent applies reloads in-process and never writes the file
// during a reload, so a save → one reload, with no feedback loop.

import Foundation

public final class ConfigWatcher {
    private let url: URL
    private let debounce: TimeInterval
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var pending: DispatchWorkItem?
    private var pollTimer: Timer?
    private var lastMtime: TimeInterval = 0

    /// `debounce` collapses the burst of events an atomic-rename save emits into one reload.
    public init(url: URL, debounce: TimeInterval = 0.15, onChange: @escaping () -> Void) {
        self.url = url
        self.debounce = debounce
        self.onChange = onChange
    }

    public func start() {
        lastMtime = currentMtime()
        arm()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.checkMtime() }
        RunLoop.main.add(t, forMode: .common)   // keep polling during event tracking
        pollTimer = t
    }

    public func stop() {
        pending?.cancel(); pending = nil
        pollTimer?.invalidate(); pollTimer = nil
        source?.cancel(); source = nil   // cancel handler closes the fd
    }

    private func currentMtime() -> TimeInterval {
        (try? FileManager.default.attributesOfItem(atPath: url.path))
            .flatMap { ($0[.modificationDate] as? Date)?.timeIntervalSince1970 } ?? 0
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
        // A rename/delete (atomic save) detached our fd from the live file — re-arm on the new
        // inode so subsequent edits keep firing the fast path. mtime de-dupes against the poll.
        let data = source?.data ?? []
        if data.contains(.rename) || data.contains(.delete) { arm() }
        checkMtime()
    }

    /// Fire (debounced) only when the file's mtime has advanced — shared by the event source and
    /// the poll, so a save reloads exactly once regardless of which path noticed it.
    private func checkMtime() {
        let m = currentMtime()
        guard m > lastMtime else { return }
        lastMtime = m
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
