import Foundation

/// Fuzzy matching for Quick Open: the query's characters in order, anywhere
/// in the text. Scores favor word starts and runs.
public enum Fuzzy {
    public struct Match: Sendable, Hashable {
        public var score: Int
        /// Offsets of the matched characters in the text.
        public var offsets: [Int]
    }

    public static func match(_ query: String, in text: String) -> Match? {
        let needle = Array(fold(query).filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return Match(score: 0, offsets: []) }
        let hay = Array(fold(text))
        // The query whole, as typed, first: "retry" is the word retry, not r-e from "registry" and t-r-y after (2026-11-11).
        if let whole = contiguous(Array(fold(query).trimmingCharacters(in: .whitespaces)), in: hay) {
            let wordStart = whole.first == 0 || isBoundary(hay[whole.first! - 1])
            return Match(score: 50 + whole.count * 5 + (wordStart ? 20 : 0) - whole.first! / 4 - hay.count / 32, offsets: whole)
        }
        // Word starts make better highlights; plain left-to-right always finds a match if one exists.
        guard let offsets = scan(needle, in: hay, preferWordStarts: true) ?? scan(needle, in: hay, preferWordStarts: false) else {
            return nil
        }
        var score = 0
        for (position, found) in offsets.enumerated() {
            score += 1
            if position > 0, found == offsets[position - 1] + 1 { score += 4 }
            if found == 0 || isBoundary(hay[found - 1]) { score += 6 }
        }
        // Shorter texts and earlier matches rank higher.
        score -= offsets[0] / 4 + hay.count / 32
        return Match(score: score, offsets: offsets)
    }

    /// Where the query sits whole in the text, at a word start if it does anywhere.
    private static func contiguous(_ needle: [Character], in hay: [Character]) -> [Int]? {
        guard !needle.isEmpty, needle.count <= hay.count else { return nil }
        var first: Int?
        for start in 0...(hay.count - needle.count) where Array(hay[start..<(start + needle.count)]) == needle {
            if start == 0 || isBoundary(hay[start - 1]) { return Array(start..<(start + needle.count)) }
            if first == nil { first = start }
        }
        return first.map { Array($0..<($0 + needle.count)) }
    }

    /// Each query character in order: the next character first, then (optionally) a word start, then any.
    private static func scan(_ needle: [Character], in hay: [Character], preferWordStarts: Bool) -> [Int]? {
        var offsets: [Int] = []
        var index = 0
        for char in needle {
            let next = !offsets.isEmpty && index < hay.count && hay[index] == char ? index : nil
            let wordStart = preferWordStarts
                ? hay.indices[index...].first { hay[$0] == char && ($0 == 0 || isBoundary(hay[$0 - 1])) }
                : nil
            guard let found = next ?? wordStart ?? hay[index...].firstIndex(of: char) else { return nil }
            offsets.append(found)
            index = found + 1
        }
        return offsets
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func isBoundary(_ char: Character) -> Bool {
        char == " " || char == "-" || char == "_" || char == "/" || char == ":" || char == "."
    }
}
