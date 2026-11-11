import Foundation

/// Text cut to lines read at a glance, for menus and tooltips (T-429): a Slack message's first line can run for a paragraph.
public enum LineCut {
    /// The longest line a menu item or a tooltip shows, in characters.
    public static let width = 64

    /// On one line, at most `width` characters: cut at a word with "…", or in the middle for an address.
    public static func line(_ text: String, width: Int = width, middle: Bool = false) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard flat.count > width, width > 1 else { return flat }
        if middle {
            let head = (width - 1) / 2
            return flat.prefix(head) + "…" + flat.suffix(width - 1 - head)
        }
        return end(Substring(flat), width: width)
    }

    /// Wrapped at words in lines of at most `width` characters, each paragraph on at most `lines`, the last cut with "…".
    public static func wrap(_ text: String, width: Int = width, lines: Int = 8) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { paragraph in
            var out: [String] = []
            var current = ""
            var words = paragraph.split(whereSeparator: \.isWhitespace).map(String.init)
            while !words.isEmpty {
                var word = words.removeFirst()
                // A word longer than a line breaks where the line ends.
                if word.count > width {
                    words.insert(String(word.dropFirst(width)), at: 0)
                    word = String(word.prefix(width))
                }
                if current.isEmpty {
                    current = word
                } else if current.count + 1 + word.count <= width {
                    current += " " + word
                } else {
                    out.append(current)
                    current = word
                }
                if out.count == lines { break }
            }
            if !current.isEmpty, out.count < lines { out.append(current); current = "" }
            // Cut: the last line ends with "…", at a word.
            if out.count == lines, !current.isEmpty || !words.isEmpty, let last = out.popLast() {
                out.append(end(Substring(last + " " + current), width: width))
            }
            return out.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    /// The text up to `width` characters, cut at the last word that fits, then "…".
    private static func end(_ text: Substring, width: Int) -> String {
        guard text.count > width else { return String(text) }
        let room = text.prefix(width - 1)
        let atWord = room.lastIndex(of: " ").map { room[..<$0] }
        let kept = atWord.map { $0.count >= width / 2 ? $0 : room } ?? room
        return kept.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",;:-"))) + "…"
    }
}
