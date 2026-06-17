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

    /// Set `key` in `section` if it exists; otherwise append it (creating the `[section]` header
    /// if needed) at the end of the file. Used by the settings GUI for monitor overrides and
    /// other keys the user's config may not have yet. Existing content stays byte-identical.
    public static func setOrAppend(_ toml: String, section: String, key: String, rawValue: String) -> String {
        if let edited = setValue(toml, section: section, key: key, rawValue: rawValue) { return edited }
        var out = toml
        if !out.hasSuffix("\n") { out += "\n" }
        // Reuse the header if the section already exists (key was just missing); else add it.
        let hasSection = toml.components(separatedBy: "\n").contains {
            if let m = headerRegex.firstMatch(in: $0, range: NSRange(location: 0, length: ($0 as NSString).length)) {
                return ($0 as NSString).substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces) == section
            }
            return false
        }
        if hasSection {
            // Append the key right after the existing header.
            var lines = toml.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                let ns = line as NSString
                if let m = headerRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                   ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces) == section {
                    lines.insert("\(key) = \(rawValue)", at: i + 1)
                    return lines.joined(separator: "\n")
                }
            }
        }
        out += "\n[\(section)]\n\(key) = \(rawValue)\n"
        return out
    }

    /// Remove a single `key` line within `section`. Returns nil if not found. Used to clear an
    /// app-shortcut binding (delete the key rather than leaving an empty value).
    public static func removeKey(_ toml: String, section: String, key: String) -> String? {
        let wantSection = section.trimmingCharacters(in: .whitespaces)
        var lines = toml.components(separatedBy: "\n")
        let keyEscaped = NSRegularExpression.escapedPattern(for: key)
        let keyRegex = try! NSRegularExpression(pattern: #"^\s*"?'?"# + "(\(keyEscaped))" + #""?'?\s*=\s*"#)
        var current = ""
        for (i, line) in lines.enumerated() {
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            if let h = headerRegex.firstMatch(in: line, range: full) {
                current = ns.substring(with: h.range(at: 1)).trimmingCharacters(in: .whitespaces); continue
            }
            if current == wantSection, keyRegex.firstMatch(in: line, range: full) != nil {
                lines.remove(at: i)
                return lines.joined(separator: "\n")
            }
        }
        return nil
    }

    /// Remove a `[section]` header and its body (lines up to the next header / EOF). Returns nil
    /// if the section isn't present. Used to clear a GUI-managed override back to default.
    public static func removeSection(_ toml: String, section: String) -> String? {
        let lines = toml.components(separatedBy: "\n")
        var start = -1
        for (i, line) in lines.enumerated() {
            let ns = line as NSString
            if let m = headerRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces) == section {
                start = i; break
            }
        }
        guard start >= 0 else { return nil }
        var end = lines.count
        for i in (start + 1)..<lines.count {
            let ns = lines[i] as NSString
            if headerRegex.firstMatch(in: lines[i], range: NSRange(location: 0, length: ns.length)) != nil { end = i; break }
        }
        var kept = Array(lines[0..<start]) + Array(lines[end...])
        // Collapse a doubled blank line left by the removal.
        if start > 0, start < kept.count, kept[start - 1].trimmingCharacters(in: .whitespaces).isEmpty,
           kept[start].trimmingCharacters(in: .whitespaces).isEmpty {
            kept.remove(at: start)
        }
        return kept.joined(separator: "\n")
    }
}
