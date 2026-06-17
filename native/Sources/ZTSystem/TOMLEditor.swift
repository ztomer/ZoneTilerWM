// TOMLEditor.swift — surgical, comment-preserving config.toml edits for the settings GUI.
//
// TOMLKit/toml++ does not preserve comments or layout on re-serialization, so a
// decode→encode round-trip would destroy the user's heavily-commented config. Instead this
// edits the raw text in place: it finds the target key's line within its [section] and
// replaces ONLY the value, keeping indentation, the key, the spacing, and any trailing inline
// comment byte-identical. Everything else in the file is untouched.
//
// Scope: single-line scalar / inline-array values (the common settings). Multi-line arrays
// and values containing a literal '#' are out of scope (the visual layout editor handles
// those later). Returns nil if the key isn't found in the given section.

import Foundation

public enum TOMLEditor {

    private static let headerRegex = try! NSRegularExpression(pattern: #"^\s*\[([^\]]+)\]\s*$"#)

    /// Replace the value of `key` within `section` (dotted path, e.g. "tiler.margins";
    /// nil/"" = top-level keys before any header). `rawValue` is the TOML-formatted value
    /// the caller produces (e.g. "true", "6", "\"rotate\"", "[\"a\", \"b\"]").
    public static func setValue(_ toml: String, section: String?, key: String, rawValue: String) -> String? {
        let wantSection = (section ?? "").trimmingCharacters(in: .whitespaces)
        var lines = toml.components(separatedBy: "\n")

        let keyEscaped = NSRegularExpression.escapedPattern(for: key)
        // indent, optional open-quote, key, optional close-quote, "=" spacing, value, optional inline comment
        let keyRegex = try! NSRegularExpression(
            pattern: #"^(\s*)("?'?)"# + "(\(keyEscaped))" + #"("?'?)(\s*=\s*)(.*?)(\s*#.*)?$"#)

        var current = ""
        for (i, line) in lines.enumerated() {
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            if let h = headerRegex.firstMatch(in: line, range: full) {
                current = ns.substring(with: h.range(at: 1)).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard current == wantSection,
                  let m = keyRegex.firstMatch(in: line, range: full) else { continue }
            func group(_ idx: Int) -> String {
                let r = m.range(at: idx)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            // indent + openQuote + key + closeQuote + "= " spacing + newValue + trailing comment
            lines[i] = group(1) + group(2) + group(3) + group(4) + group(5) + rawValue + group(7)
            return lines.joined(separator: "\n")
        }
        return nil
    }
}
