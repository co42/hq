import Foundation

/// A note's YAML front matter, read and written line by line, so keys hq doesn't own keep
/// their exact text. Handles what Obsidian writes: `key: value`, `key: [a, b]`, and block
/// lists (`key:` then `  - a`).
public struct FrontMatter: Sendable, Equatable {
    /// The lines between the `---` fences.
    public private(set) var lines: [String]
    public var body: String

    public init(_ text: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var all = normalized.components(separatedBy: "\n")
        guard all.first == "---", let end = all.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }) else {
            lines = []
            body = normalized
            return
        }
        lines = Array(all[1..<end])
        all.removeSubrange(0...end)
        body = all.joined(separator: "\n")
    }

    public init(lines: [String] = [], body: String = "") {
        self.lines = lines
        self.body = body
    }

    /// The note again: fences, front matter, body.
    public var text: String {
        lines.isEmpty ? body : (["---"] + lines + ["---"]).joined(separator: "\n") + "\n" + body.drop { $0 == "\n" }
    }

    // MARK: Reading

    public func string(_ key: String) -> String? {
        guard let (index, rest) = find(key) else { return nil }
        let value = rest.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { return block(after: index).first }
        if value.hasPrefix("[") { return Self.inlineList(value).first }
        return Self.unquote(Self.stripComment(value))
    }

    public func list(_ key: String) -> [String] {
        guard let (index, rest) = find(key) else { return [] }
        let value = Self.stripComment(rest.trimmingCharacters(in: .whitespaces))
        if value.isEmpty { return block(after: index) }
        if value.hasPrefix("[") { return Self.inlineList(value) }
        // A single scalar, or Obsidian's old comma form: "tags: a, b".
        return value.split(separator: ",").map { Self.unquote($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
    }

    public func has(_ key: String) -> Bool { find(key) != nil }

    // MARK: Writing

    /// Sets or removes (nil) a scalar.
    public mutating func set(_ key: String, _ value: String?) {
        replace(key, with: value.map { ["\(key): \(Self.quote($0))"] } ?? [])
    }

    /// Sets or removes (false) a flag, as a YAML boolean Obsidian shows as a checkbox.
    public mutating func set(_ key: String, flag: Bool) {
        replace(key, with: flag ? ["\(key): true"] : [])
    }

    /// Sets a list, inline: `tags: [registry, chunks]`.
    public mutating func set(_ key: String, list: [String]) {
        replace(key, with: ["\(key): [" + list.map(Self.quote).joined(separator: ", ") + "]"])
    }

    private mutating func replace(_ key: String, with new: [String]) {
        if let (index, _) = find(key) {
            let end = index + 1 + blockLength(after: index)
            lines.replaceSubrange(index..<end, with: new)
        } else {
            lines += new
        }
    }

    // MARK: Lines

    private func find(_ key: String) -> (Int, Substring)? {
        let prefix = key + ":"
        guard let index = lines.firstIndex(where: { $0.hasPrefix(prefix) }) else { return nil }
        return (index, lines[index].dropFirst(prefix.count))
    }

    /// Indented lines that belong to the key on `index`: a block list or a folded value.
    private func blockLength(after index: Int) -> Int {
        lines[(index + 1)...].prefix { $0.hasPrefix(" ") || $0.hasPrefix("\t") || $0.hasPrefix("-") }.count
    }

    private func block(after index: Int) -> [String] {
        lines[(index + 1)..<(index + 1 + blockLength(after: index))].compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("-") else { return nil }
            let item = Self.unquote(Self.stripComment(trimmed.dropFirst().trimmingCharacters(in: .whitespaces)))
            return item.isEmpty ? nil : item
        }
    }

    static func inlineList(_ value: String) -> [String] {
        guard let close = value.lastIndex(of: "]") else { return [] }
        let inside = value[value.index(after: value.startIndex)..<close]
        var items: [String] = []
        var current = ""
        var quote: Character?
        for character in inside {
            if let open = quote {
                if character == open { quote = nil }
                current.append(character)
            } else if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == "," {
                items.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        items.append(current)
        return items.map { unquote($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
    }

    static func stripComment(_ value: String) -> String {
        guard !value.hasPrefix("\""), !value.hasPrefix("'"), let hash = value.range(of: " #") else { return value }
        return String(value[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first else { return value }
        let inner = String(value.dropFirst().dropLast())
        return first == "\"" ? inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
                             : inner.replacingOccurrences(of: "''", with: "'")
    }

    /// Quotes a value only when YAML would read it as something else.
    static func quote(_ value: String) -> String {
        let special = CharacterSet(charactersIn: ":#[]{},&*!|>'\"%@`")
        let reserved = ["true", "false", "yes", "no", "null", "~", ""]
        let needs = value.rangeOfCharacter(from: special) != nil || reserved.contains(value.lowercased())
            || value.first == " " || value.last == " " || value.hasPrefix("- ") || value == "-" || value.first == "?"
        guard needs else { return value }
        return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
