import Foundation
import HQKit

/// One part of a markdown text changed, every other byte kept: a `##` section, an exact text, a checkbox.
enum PartialEdit {
    /// A checklist item: its line in the text, its box, its words.
    struct Box {
        var line: Int
        var checked: Bool
        var text: String
    }

    /// What `tick` did: the new text, the item, whether its box changed, and the tally after.
    struct Tick {
        var source: String
        var item: String
        var changed: Bool
        var done: Int
        var total: Int
    }

    // MARK: Sections

    /// The section under the heading called `name` (any level, up to the next heading as high) replaced by `text`, its
    /// heading kept; added at the end as a `##` section when there's none.
    static func section(_ name: String, in source: String, with text: String) -> String {
        let wanted = key(name)
        var body = text.trimmingCharacters(in: .newlines)
        // A text that starts with the section's own heading doesn't get it twice.
        if let first = body.components(separatedBy: "\n").first, let heading = heading(first), key(heading.title) == wanted {
            body = String(body.dropFirst(first.count)).trimmingCharacters(in: .newlines)
        }
        var lines = source.components(separatedBy: "\n")
        let headings = headings(lines)
        guard let start = headings.first(where: { key($0.title) == wanted }) else {
            let kept = source.trimmingCharacters(in: .newlines)
            let title = name.trimmingCharacters(in: .whitespaces)
            return kept + (kept.isEmpty ? "" : "\n\n") + "## \(title)\n" + body + (source.hasSuffix("\n") ? "\n" : "")
        }
        let end = headings.first { $0.line > start.line && $0.level <= start.level }?.line
        var replacement = body.isEmpty ? [] : body.components(separatedBy: "\n")
        if end != nil { replacement.append("") }
        lines.replaceSubrange(start.line + 1 ..< (end ?? lines.count), with: replacement)
        var result = lines.joined(separator: "\n")
        if end == nil, source.hasSuffix("\n") { result += "\n" }
        return result
    }

    /// The headings outside code blocks: line, level, title.
    static func headings(_ lines: [String]) -> [(line: Int, level: Int, title: String)] {
        var found: [(line: Int, level: Int, title: String)] = []
        var fence: String?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for mark in ["```", "~~~"] where trimmed.hasPrefix(mark) {
                fence = fence == nil ? mark : (fence == mark ? nil : fence)
            }
            guard fence == nil, !trimmed.hasPrefix("```"), !trimmed.hasPrefix("~~~"), let heading = heading(line) else { continue }
            found.append((index, heading.level, heading.title))
        }
        return found
    }

    private static func heading(_ line: String) -> (level: Int, title: String)? {
        guard let match = line.firstMatch(of: /^(#{1,6})[ \t]+(.+?)[ \t#]*$/) else { return nil }
        return (match.output.1.count, String(match.output.2))
    }

    /// `Done when`, `done when:` and `DONE WHEN` are one section.
    private static func key(_ title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasSuffix(":") { text.removeLast() }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: Exact text

    /// `old` replaced by `new`, when `old` is in the text exactly once.
    static func replace(_ old: String, with new: String, in source: String, what: String) throws -> String {
        guard !old.isEmpty else { throw AgentError.usage("--replace is empty: give the exact text to change") }
        let count = source.components(separatedBy: old).count - 1
        if count == 0 {
            throw AgentError.notFound("\(what) has no “\(short(old))”: --replace takes the text exactly as it is, marks and spaces included")
        }
        guard count == 1 else {
            throw AgentError.usage("“\(short(old))” is in \(what) \(count) times: give more of the text around it, so it matches once")
        }
        return source.replacingOccurrences(of: old, with: new)
    }

    private static func short(_ text: String) -> String {
        let line = text.replacingOccurrences(of: "\n", with: "⏎")
        return line.count > 60 ? line.prefix(60) + "…" : line
    }

    // MARK: Checkboxes

    /// The text's checklist items outside code, in order.
    static func boxes(_ source: String) -> [Box] {
        let lines = source.components(separatedBy: "\n")
        return Markdown.taskLines(source).compactMap { index in
            guard let match = lines[index].firstMatch(of: /^(?:\s*>)*\s*(?:[-*+]|\d+[.)])[ \t]+\[([ xX])\][ \t]+(.*)$/) else { return nil }
            return Box(line: index, checked: match.output.1 != " ", text: String(match.output.2).trimmingCharacters(in: .whitespaces))
        }
    }

    /// The one item whose words start with `start` ticked, or cleared.
    static func tick(_ start: String, in source: String, checked: Bool, what: String) throws -> Tick {
        let wanted = fold(start.replacing(/^\s*(?:[-*+]|\d+[.)])\s+\[[ xX]\]\s+/, with: ""))
        guard !wanted.isEmpty else { throw AgentError.usage("give the start of the item's text: hq task tick T-12 \"At most 3 attempts\"") }
        let all = boxes(source)
        guard !all.isEmpty else { throw AgentError.notFound("\(what) has no checklist: no `- [ ]` line in its description") }
        var found = all.filter { fold($0.text) == wanted }
        if found.isEmpty { found = all.filter { fold($0.text).hasPrefix(wanted) || fold(Markdown.firstLine($0.text)).hasPrefix(wanted) } }
        let listed = all.map { "[\($0.checked ? "x" : " ")] \($0.text)" }.joined(separator: "; ")
        guard found.count == 1, let box = found.first else {
            if found.isEmpty { throw AgentError.notFound("no item of \(what) starts with “\(start)”. Its items: \(listed)") }
            throw AgentError.usage("“\(start)” starts \(found.count) items of \(what): give more of its text. Its items: \(listed)")
        }
        var lines = source.components(separatedBy: "\n")
        let changed = box.checked != checked
        if changed, let match = lines[box.line].firstMatch(of: /\[[ xX]\]/) {
            lines[box.line].replaceSubrange(match.range, with: checked ? "[x]" : "[ ]")
        }
        let done = all.filter(\.checked).count + (changed ? (checked ? 1 : -1) : 0)
        return Tick(source: lines.joined(separator: "\n"), item: box.text, changed: changed, done: done, total: all.count)
    }

    /// Lowercased, spaces folded: what two item texts are compared on.
    private static func fold(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
