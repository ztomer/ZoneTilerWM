// JSONFileStorage.swift — Storage backed by JSON files under a directory, byte-compatible
// with modules/storage.lua (one file per key: <dir>/<key>.json). Default dir mirrors the
// Lua default (~/.config/ZoneTilerWM).
//
// Compatibility notes:
//  - Lua's storage.save adds a wall-clock `_timestamp`; we save clean (deterministic) and
//    load tolerantly. Decoding ignores unknown keys, so files written by either side load
//    in the other (the Lua reader only needs its own keys; Swift ignores `_timestamp`).

import Foundation
import ZTCore

public final class JSONFileStorage: Storage {
    private let directory: URL

    public static var defaultDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/ZoneTilerWM", isDirectory: true)
    }

    public init(directory: URL = JSONFileStorage.defaultDirectory) {
        self.directory = directory
    }

    private func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent(key + ".json")
    }

    public func load<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: fileURL(key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    @discardableResult
    public func save<T: Encodable>(_ key: String, _ value: T) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(value).write(to: fileURL(key), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
