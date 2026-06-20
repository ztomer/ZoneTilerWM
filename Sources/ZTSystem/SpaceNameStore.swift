// SpaceNameStore.swift — persists user-assigned names for real macOS Spaces to
// ~/.config/ZoneTilerWM/spaces.json. Keyed by the space UUID; the default/active space sometimes
// reports an empty UUID via CGS, so it's keyed by `default@<displayUUID>` instead (stable per
// display). Pure dictionary + a small JSON file; the file URL is injectable for tests.

import Foundation

public final class SpaceNameStore {
    private let url: URL
    private var names: [String: String]

    public init(fileURL: URL) {
        self.url = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.names = decoded
        } else {
            self.names = [:]
        }
    }

    /// Default location: ~/.config/ZoneTilerWM/spaces.json
    public convenience init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ZoneTilerWM", isDirectory: true)
        self.init(fileURL: dir.appendingPathComponent("spaces.json"))
    }

    /// Stable persistence key for a space (UUID, or `default@<display>` when the UUID is empty).
    public static func key(for space: RealSpace) -> String {
        space.uuid.isEmpty ? "default@\(space.displayUUID)" : space.uuid
    }

    public func name(for space: RealSpace) -> String? {
        let n = names[Self.key(for: space)]
        return (n?.isEmpty == false) ? n : nil
    }

    /// Set (or clear, with nil/empty) a space's name and persist. Returns false on write failure.
    @discardableResult
    public func setName(_ name: String?, for space: RealSpace) -> Bool {
        let key = Self.key(for: space)
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { names[key] = trimmed } else { names.removeValue(forKey: key) }
        return persist()
    }

    private func persist() -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(names)
            try data.write(to: url, options: .atomic)
            return true
        } catch { return false }
    }
}
