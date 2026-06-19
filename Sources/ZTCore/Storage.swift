// Storage.swift — persistence boundary (mirrors modules/storage.lua). ZTCore depends only
// on this protocol; ZTSystem provides a JSON-file implementation. Algorithms that persist
// (window memory, resize offsets, layouts) take a Storage and never touch the filesystem.

public protocol Storage: AnyObject {
    /// Load and decode the value stored under `key`, or nil if absent/undecodable.
    func load<T: Decodable>(_ key: String, as type: T.Type) -> T?
    /// Encode and persist `value` under `key`. Returns whether it succeeded.
    @discardableResult
    func save<T: Encodable>(_ key: String, _ value: T) -> Bool
}
