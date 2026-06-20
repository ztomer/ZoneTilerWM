import XCTest

/// Emoji are a failure state — the UI/log aesthetic is Susan Kare monochrome glyphs, not colourful
/// pictographs. This test scans every Swift source file and fails on any emoji character. The only
/// allowed "glyphs" are the kare list (→ · ✓ ✗ ⚠, mirrored from ~/projects/scripts/_stylerc) plus
/// ordinary typographic symbols (arrows, keyboard glyphs like ⇧/↵) — none of which are emoji.
final class EmojiPolicyTest: XCTestCase {
    /// The kare status glyphs — explicitly allowed (they aren't emoji, but pin the intent).
    static let kareAllow: Set<Unicode.Scalar> = ["→", "·", "✓", "✗", "⚠"]

    /// A scalar counts as a forbidden EMOJI if it has default emoji presentation, lives in the
    /// pictographic planes, or is an emoji variation/keycap/flag selector — and isn't kare-allowlisted.
    static func isForbiddenEmoji(_ s: Unicode.Scalar) -> Bool {
        if kareAllow.contains(s) { return false }
        let v = s.value
        if v == 0xFE0F || v == 0x20E3 { return true }                 // emoji variation selector / keycap
        if (0x1F000...0x1FAFF).contains(v) { return true }            // pictographic planes
        if (0x1F1E6...0x1F1FF).contains(v) { return true }            // regional indicators (flags)
        if (0x1FB00...0x1FBFF).contains(v) { return false }           // legacy computing — not emoji
        return s.properties.isEmojiPresentation                        // default-emoji glyphs (check, dots)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ZTCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    func testNoEmojiInSwiftSources() throws {
        let root = repoRoot()
        var violations: [String] = []
        for sub in ["Sources", "Tests"] {
            let dir = root.appendingPathComponent(sub)
            guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                for (lineNo, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    for scalar in line.unicodeScalars where Self.isForbiddenEmoji(scalar) {
                        let name = scalar.properties.name ?? "U+\(String(scalar.value, radix: 16))"
                        violations.append("\(url.lastPathComponent):\(lineNo + 1)  '\(scalar)' (\(name))")
                    }
                }
            }
        }
        XCTAssertTrue(violations.isEmpty,
                      "Emoji are a failure state — use the kare glyphs (→ · ✓ ✗ ⚠) instead:\n" +
                      violations.joined(separator: "\n"))
    }
}
