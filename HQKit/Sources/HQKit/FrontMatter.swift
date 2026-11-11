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
        // A byte order mark before the fence, or spaces after one, don't hide the front matter.
        func fence(_ line: String, _ marks: [String]) -> Bool {
            var line = Substring(line)
            if line.unicodeScalars.first == "\u{FEFF}" { line = Substring(line.unicodeScalars.dropFirst()) }
            return marks.contains { line.hasPrefix($0) && line.dropFirst($0.count).allSatisfy(\.isWhitespace) }
        }
        guard let first = all.first, fence(first, ["---"]), let end = all.dropFirst().firstIndex(where: { fence($0, ["---", "..."]) }) else {
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

    /// The note again: fences, front matter, body, its blank lines kept.
    public var text: String {
        lines.isEmpty ? body : (["---"] + lines + ["---"]).joined(separator: "\n") + "\n" + body
    }

    // MARK: Reading

    public func string(_ key: String) -> String? {
        guard let (index, rest) = find(key) else { return nil }
        let value = rest.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { return block(after: index).first }
        if value.hasPrefix("[") { return Self.inlineList(value).first }
        if let header = Self.blockHeader(value) { return blockScalar(after: index, header) }
        return Self.scalar(value)
    }

    public func list(_ key: String) -> [String] {
        guard let (index, rest) = find(key) else { return [] }
        let raw = rest.trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("[") { return Self.inlineList(raw) }
        let value = Self.stripComment(raw)
        if value.isEmpty { return block(after: index) }
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

    /// Indented lines that belong to the key on `index`: a block list or a block of text, blank lines between them included.
    private func blockLength(after index: Int) -> Int {
        var count = 0, length = 0
        for line in lines[(index + 1)...] {
            count += 1
            if line.allSatisfy(\.isWhitespace) { continue }
            guard line.hasPrefix(" ") || line.hasPrefix("\t") || line.hasPrefix("-") else { break }
            length = count
        }
        return length
    }

    private func block(after index: Int) -> [String] {
        lines[(index + 1)..<(index + 1 + blockLength(after: index))].compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("-") else { return nil }
            let item = Self.scalar(trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
            return item.isEmpty ? nil : item
        }
    }

    /// `|`, `>`, with `-` or `+` and an indent: a block of text's style and how it ends.
    static func blockHeader(_ value: String) -> (folded: Bool, chomp: Character?)? {
        let header = stripComment(value)
        guard let style = header.first, style == "|" || style == ">" else { return nil }
        let rest = header.dropFirst()
        guard rest.count <= 2, rest.allSatisfy({ $0 == "-" || $0 == "+" || $0.isNumber }) else { return nil }
        return (style == ">", rest.first { $0 == "-" || $0 == "+" })
    }

    /// A block of text after `key: |` or `key: >`, as YAML reads it.
    private func blockScalar(after index: Int, _ header: (folded: Bool, chomp: Character?)) -> String {
        let raw = lines[(index + 1)..<(index + 1 + blockLength(after: index))]
        let indent = raw.first { !$0.allSatisfy(\.isWhitespace) }.map { $0.prefix { $0 == " " }.count } ?? 0
        let text = raw.map { $0.allSatisfy(\.isWhitespace) ? "" : String($0.dropFirst(indent)) }
        // Folded: lines join with a space, a blank line is a line break.
        var joined = text.first ?? ""
        for (previous, line) in zip(text, text.dropFirst()) {
            if !header.folded { joined += "\n" + line } else if line.isEmpty { joined += "\n" } else { joined += (previous.isEmpty ? "" : " ") + line }
        }
        let content = joined.replacing(/\n+$/, with: "")
        switch header.chomp {
        case "-": return content
        case "+": return joined + "\n"
        default: return content.isEmpty ? "" : content + "\n"
        }
    }

    static func inlineList(_ value: String) -> [String] {
        var items: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        var closed = false
        for character in value.dropFirst() {
            if let open = quote {
                current.append(character)
                if escaped { escaped = false } else if open == "\"" && character == "\\" { escaped = true } else if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == "," {
                items.append(current)
                current = ""
            } else if character == "]" {
                closed = true
                break
            } else {
                current.append(character)
            }
        }
        guard closed else { return [] }
        items.append(current)
        return items.map { unquote($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
    }

    /// A value on its key's line: quoted up to its closing quote, a comment after it ignored.
    static func scalar(_ value: String) -> String {
        guard let open = value.first, open == "\"" || open == "'" else { return stripComment(value) }
        var escaped = false
        var index = value.index(after: value.startIndex)
        while index < value.endIndex {
            let character = value[index]
            if open == "\"" {
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { break }
            } else if character == "'" {
                let next = value.index(after: index)
                guard next < value.endIndex, value[next] == "'" else { break }
                index = next
            }
            index = value.index(after: index)
        }
        guard index < value.endIndex else { return value }
        let rest = value[value.index(after: index)...].trimmingCharacters(in: .whitespaces)
        guard rest.isEmpty || rest.hasPrefix("#") else { return value }
        return unquote(String(value[...index]))
    }

    static func stripComment(_ value: String) -> String {
        guard !value.hasPrefix("\""), !value.hasPrefix("'"), let hash = value.range(of: " #") else { return value }
        return String(value[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    /// A quoted value's text: `''` in single quotes, `\"`, `\\`, `\n`, `\t`, `\r` in double quotes.
    static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first else { return value }
        let inner = value.dropFirst().dropLast()
        guard first == "\"" else { return inner.replacingOccurrences(of: "''", with: "'") }
        var out = ""
        var escaped = false
        for scalar in inner.unicodeScalars {
            if escaped {
                switch scalar {
                case "n": out += "\n"
                case "t": out += "\t"
                case "r": out += "\r"
                case "\"", "\\", "/": out.unicodeScalars.append(scalar)
                default: out += "\\" + String(scalar)
                }
                escaped = false
            } else if scalar == "\\" {
                escaped = true
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return escaped ? out + "\\" : out
    }

    /// Quotes a value only when YAML would read it as something else; a line break or a tab is escaped, so the value
    /// stays on its key's line.
    static func quote(_ value: String) -> String {
        let special = CharacterSet(charactersIn: ":#[]{},&*!|>'\"%@`\n\r\t")
        let reserved = ["true", "false", "yes", "no", "null", "~", ""]
        let needs = value.rangeOfCharacter(from: special) != nil || reserved.contains(value.lowercased())
            || value.first == " " || value.last == " " || value.hasPrefix("- ") || value == "-" || value.first == "?"
        guard needs else { return value }
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
