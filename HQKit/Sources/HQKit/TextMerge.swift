import Foundation

/// What an editor writes when it ends, from the text it started from (`base`), what the user made of it (`mine`) and
/// what the note holds now (`theirs`: a session or Obsidian may have written it meanwhile). An untouched editor never
/// writes; changes on different lines join; a change on the same lines keeps the user's.
public enum TextMerge {
    public enum Commit: Equatable, Sendable {
        /// The user changed nothing: write nothing, whatever the note became.
        case unchanged
        /// Write this: the user's text over an unchanged note, or both changes joined by lines.
        case write(String)
        /// Both changed the same lines: the user's text is written, the other is what Undo brings back.
        case conflict(String)
    }

    public static func commit(base: String, mine: String, theirs: String) -> Commit {
        let base = trimmed(base), mine = trimmed(mine), theirs = trimmed(theirs)
        if mine == base { return .unchanged }
        if theirs == base || theirs == mine { return .write(mine) }
        if let merged = merge(base: base, mine: mine, theirs: theirs) { return .write(merged) }
        return .conflict(mine)
    }

    /// Both sides' changes to `base`, joined line by line; nil when they touch the same lines.
    public static func merge(base: String, mine: String, theirs: String) -> String? {
        let old = lines(base)
        let ours = hunks(old, lines(mine)), others = hunks(old, lines(theirs))
        var all = ours.map { ($0, true) } + others.map { ($0, false) }
        all.sort { $0.0.start != $1.0.start ? $0.0.start < $1.0.start : $0.0.end < $1.0.end }
        // Two changes from different sides that overlap, or insert at the same place, conflict unless they're the same.
        for (i, a) in all.enumerated() {
            for b in all[(i + 1)...] where a.1 != b.1 {
                guard b.0.start <= a.0.end else { break }
                let touching = b.0.start < a.0.end || (a.0.start == b.0.start) || (b.0.start == a.0.end && (a.0.isInsert || b.0.isInsert))
                if touching && a.0 != b.0 { return nil }
            }
        }
        var out: [Substring] = []
        var at = 0
        var applied: [Hunk] = []
        for (hunk, _) in all where !applied.contains(hunk) {
            out += old[at..<hunk.start]
            out += hunk.lines
            at = hunk.end
            applied.append(hunk)
        }
        out += old[at...]
        return out.joined(separator: "\n")
    }

    /// Lines `start..<end` of the base replaced by `lines`.
    struct Hunk: Equatable {
        var start: Int
        var end: Int
        var lines: [Substring]
        var isInsert: Bool { start == end }
    }

    /// The changes from `a` to `b`, from their longest common subsequence of lines.
    static func hunks(_ a: [Substring], _ b: [Substring]) -> [Hunk] {
        let n = a.count, m = b.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var hunks: [Hunk] = []
        var i = 0, j = 0
        var open: Hunk?
        func close() { if let hunk = open { hunks.append(hunk) }; open = nil }
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                close()
                i += 1; j += 1
            } else if j < m, i == n || lcs[i][j + 1] >= lcs[i + 1][j] {
                if open == nil { open = Hunk(start: i, end: i, lines: []) }
                open?.lines.append(b[j])
                j += 1
            } else {
                if open == nil { open = Hunk(start: i, end: i, lines: []) }
                open?.end = i + 1
                i += 1
            }
        }
        close()
        return hunks
    }

    private static func lines(_ text: String) -> [Substring] { text.split(separator: "\n", omittingEmptySubsequences: false) }
    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .newlines) }
}
