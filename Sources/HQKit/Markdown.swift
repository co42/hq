import Foundation

/// A markdown block, from Foundation's parser (CommonMark with GitHub tables). Inline styles,
/// links and code spans stay in each block's AttributedString, which SwiftUI's Text draws.
public indirect enum MarkdownBlock: Sendable, Equatable {
    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case list(ordered: Bool, start: Int, items: [MarkdownListItem])
    case quote([MarkdownBlock])
    /// A fenced or indented block; `mermaid` is a diagram.
    case code(language: String?, text: String)
    /// The first row is the header.
    case table(alignments: [MarkdownAlignment], rows: [[AttributedString]])
    case rule
}

public struct MarkdownListItem: Sendable, Equatable {
    /// A task list item: `- [ ]` is false, `- [x]` true.
    public var checked: Bool?
    public var blocks: [MarkdownBlock]
    /// Which checkbox it is, in document order: `Markdown.toggleTask(_:at:)` takes it.
    public var taskIndex: Int?
}

public enum MarkdownAlignment: Sendable, Equatable {
    case leading, center, trailing
}

public enum Markdown {
    /// The scheme of an Obsidian `[[link]]`; the rest of the URL is the note's name.
    public static let noteScheme = "hq-note"

    public static func blocks(_ text: String) -> [MarkdownBlock] {
        let source = linkNotes(text)
        guard let parsed = try? AttributedString(markdown: source, options: .init(
            allowsExtendedAttributes: false, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)) else {
            return [.paragraph(AttributedString(text))]
        }
        let root = Node(kind: nil, identity: -1)
        for run in parsed.runs {
            var slice = AttributedString(parsed[run.range])
            // Obsidian shows a single line break as one, as the user writes it.
            if let inline = run.inlinePresentationIntent, inline.contains(.softBreak) || inline.contains(.lineBreak) {
                slice = AttributedString("\n")
            }
            slice.presentationIntent = nil
            var node = root
            for component in (run.presentationIntent?.components ?? []).reversed() {
                node = node.child(component)
            }
            node.text.append(slice)
        }
        var counter = 0
        return number(root.blocks, &counter)
    }

    /// Numbers the checkboxes in document order.
    private static func number(_ blocks: [MarkdownBlock], _ counter: inout Int) -> [MarkdownBlock] {
        blocks.map { block in
            switch block {
            case .list(let ordered, let start, let items):
                return .list(ordered: ordered, start: start, items: items.map { item in
                    var item = item
                    if item.checked != nil {
                        item.taskIndex = counter
                        counter += 1
                    }
                    item.blocks = number(item.blocks, &counter)
                    return item
                })
            case .quote(let inner): return .quote(number(inner, &counter))
            default: return block
            }
        }
    }

    /// The name of the note a `hq-note:` URL points to.
    /// A renamed note's body: its opening `# heading` takes the new title when it was the old one, else nil.
    public static func retitled(_ body: String, from old: String, to new: String) -> String? {
        var lines = body.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              lines[index].hasPrefix("# "),
              lines[index].dropFirst(2).trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(old.trimmingCharacters(in: .whitespaces)) == .orderedSame
        else { return nil }
        lines[index] = "# \(new)"
        return lines.joined(separator: "\n")
    }

    public static func noteName(_ url: URL) -> String? {
        guard url.scheme == noteScheme else { return nil }
        return String(url.absoluteString.dropFirst(noteScheme.count + 1)).removingPercentEncoding
    }

    /// `[[Note]]` and `[[Note|label]]` become links, outside code.
    static func linkNotes(_ text: String) -> String {
        guard text.contains("[[") else { return text }
        var openFence: String?
        return text.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = openFence {
                if trimmed.hasPrefix(open) { openFence = nil }
                return line
            }
            if let marker = fence(trimmed) {
                openFence = marker
                return line
            }
            // Between backticks is code: only the even parts are text.
            return line.components(separatedBy: "`").enumerated().map { index, part in
                index.isMultiple(of: 2) ? part.replacing(notePattern) { match in
                    let name = String(match.1)
                    let label = match.2.map(String.init) ?? name
                    let encoded = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? name
                    return "[\(label)](\(noteScheme):\(encoded))"
                } : part
            }.joined(separator: "`")
        }.joined(separator: "\n")
    }

    nonisolated(unsafe) private static let notePattern = /\[\[([^\[\]|\n]+)(?:\|([^\[\]\n]+))?\]\]/

    /// The fence a line opens or closes (```` ``` ```` or `~~~`), else nil.
    static func fence(_ trimmed: String) -> String? {
        for mark in ["```", "~~~"] where trimmed.hasPrefix(mark) {
            return String(trimmed.prefix { $0 == mark.first })
        }
        return nil
    }

    // MARK: Task lists

    /// Lines of the source that are task list items, outside code, in document order: the n-th is
    /// the n-th checkbox the viewer draws.
    /// The first line with words, without its markdown marks: a heading's `#`, a list's marker, a checkbox, emphasis.
    public static func firstLine(_ source: String) -> String {
        for raw in source.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") || line.hasPrefix("---") { continue }
            line = line.replacing(/^(#{1,6}\s+|>\s*|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+(\[[ xX]\]\s+)?)/, with: "")
            line = line.replacing(/\*\*|__|`/, with: "")
            line = line.replacing(/\[([^\]]+)\]\([^)]*\)/) { String($0.1) }
            line = line.replacing(/\[\[([^\]|]+)(\|[^\]]+)?\]\]/) { String($0.1) }
            if !line.isEmpty { return line.trimmingCharacters(in: .whitespaces) }
        }
        return ""
    }

    public static func taskLines(_ source: String) -> [Int] {
        var result: [Int] = []
        var open: String?
        for (index, line) in source.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = open {
                if trimmed.hasPrefix(marker) { open = nil }
                continue
            }
            if let marker = fence(trimmed) {
                open = marker
                continue
            }
            if line.firstMatch(of: taskPattern) != nil { result.append(index) }
        }
        return result
    }

    /// The source with the n-th checkbox ticked or cleared; every other byte stays. Nil when there's no such box.
    public static func toggleTask(_ source: String, at index: Int) -> String? {
        let tasks = taskLines(source)
        guard tasks.indices.contains(index) else { return nil }
        var lines = source.components(separatedBy: "\n")
        let line = lines[tasks[index]]
        guard let match = line.firstMatch(of: taskPattern) else { return nil }
        let box = match.output.2
        let mark = box == " " ? "x" : " "
        lines[tasks[index]] = line.replacingCharacters(in: box.startIndex..<box.endIndex, with: mark)
        return lines.joined(separator: "\n")
    }

    /// `- [ ] text`, `1. [x] text`, also inside quotes; group 2 is the box's one character.
    nonisolated(unsafe) private static let taskPattern = /^((?:\s*>)*\s*(?:[-*+]|\d+[.)])[ \t]+)\[([ xX])\][ \t]+\S/
}

/// One block while the runs are gathered: its kind, identity and children, or its text.
private final class Node {
    let kind: PresentationIntent.Kind?
    let identity: Int
    var children: [Node] = []
    var text = AttributedString()

    init(kind: PresentationIntent.Kind?, identity: Int) {
        self.kind = kind
        self.identity = identity
    }

    /// Runs come in document order: a block already met is the last child.
    func child(_ intent: PresentationIntent.IntentType) -> Node {
        if let last = children.last, last.identity == intent.identity { return last }
        let node = Node(kind: intent.kind, identity: intent.identity)
        children.append(node)
        return node
    }

    var blocks: [MarkdownBlock] { children.compactMap(\.block) }

    var block: MarkdownBlock? {
        switch kind {
        case .header(let level): return .heading(level: level, text: text)
        case .orderedList, .unorderedList:
            var start = 1
            if case .listItem(let ordinal) = children.first?.kind { start = ordinal }
            return .list(ordered: kind == .orderedList, start: start, items: children.map(\.item))
        case .blockQuote: return .quote(blocks)
        case .codeBlock(let language):
            var code = String(text.characters)
            if code.hasSuffix("\n") { code.removeLast() }
            return .code(language: language?.lowercased(), text: code)
        case .thematicBreak: return .rule
        case .table(let columns):
            let alignments: [MarkdownAlignment] = columns.map {
                switch $0.alignment {
                case .center: .center
                case .right: .trailing
                default: .leading
                }
            }
            let rows = children.map { row in
                var cells = Array(repeating: AttributedString(), count: alignments.count)
                for cell in row.children {
                    if case .tableCell(let column) = cell.kind, cells.indices.contains(column) { cells[column] = cell.text }
                }
                return cells
            }
            return .table(alignments: alignments, rows: rows)
        case .listItem: return item.blocks.first
        default:
            // A paragraph, or a block Foundation adds later: its text, or its children.
            return children.isEmpty ? .paragraph(text) : blocks.first
        }
    }

    /// A list item; a leading `[ ]` or `[x]` makes it a task.
    var item: MarkdownListItem {
        var blocks = blocks
        var checked: Bool?
        if case .paragraph(var first) = blocks.first {
            let head = String(first.characters.prefix(4))
            if head == "[ ] " || head.lowercased() == "[x] " {
                checked = head != "[ ] "
                first.removeSubrange(first.startIndex..<first.index(first.startIndex, offsetByCharacters: 4))
                blocks[0] = .paragraph(first)
            }
        }
        return MarkdownListItem(checked: checked, blocks: blocks)
    }
}
