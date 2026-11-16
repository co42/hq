import Foundation

/// Archived stories (PLAN.md §5, T-471): which top-level tasks go to the Archive on their own, and the index the Archive
/// window and `hq` search, kept beside the store so nothing reads the archived notes to find one.
public enum TaskArchive {
    /// Settings › General's choices for how long a done story waits, in days.
    public static let delayChoices = [1, 3, 7, 14, 30]
    public static let defaultDelay = 7

    /// The top-level tasks done for `delayDays` or more, with every task under them done: the Archive's on its own.
    /// `done` is when a task was done; a done task with none never goes on its own.
    public static func due(roots: [Int], subtree: (Int) -> [Int], status: (Int) -> TaskStatus?, done: (Int) -> Date?,
                           now: Date, delayDays: Int) -> [Int] {
        let limit = now.addingTimeInterval(-Double(delayDays) * 86_400)
        return roots.filter { root in
            guard status(root) == .done, let when = done(root), when <= limit else { return false }
            return subtree(root).allSatisfy { status($0) == .done }
        }
    }
}

/// One line per archived task: what the Archive shows and searches without reading a note.
public struct ArchiveIndex: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Hashable {
        public var id: Int
        /// Its archived top-level task: itself for a story.
        public var root: Int
        public var parent: Int?
        public var title: String
        public var status: TaskStatus
        public var project: String?
        public var tags: [String]
        public var done: Date?
        public var archived: Date
        /// The note's date when the index read it: a later one was edited since.
        public var modified: Date

        public init(id: Int, root: Int, parent: Int? = nil, title: String, status: TaskStatus, project: String? = nil,
                    tags: [String] = [], done: Date? = nil, archived: Date, modified: Date) {
            self.id = id
            self.root = root
            self.parent = parent
            self.title = title
            self.status = status
            self.project = project
            self.tags = tags
            self.done = done
            self.archived = archived
            self.modified = modified
        }

        public var key: String { "T-\(id)" }
    }

    public var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// The highest key archived: a new task's key is above it.
    public var highestKey: Int { entries.map(\.id).max() ?? 0 }

    /// The archived stories, the newest archived first.
    public var stories: [Entry] {
        entries.filter { $0.id == $0.root }.sorted { ($0.archived, $0.id) > ($1.archived, $1.id) }
    }

    public mutating func add(_ new: [Entry]) {
        let ids = Set(new.map(\.id))
        entries.removeAll { ids.contains($0.id) }
        entries.append(contentsOf: new)
    }

    /// The index read back from the archived notes themselves, when it's missing or a note changed: each entry's story is
    /// the top of its parents among the archived notes (a parent that isn't archived, or a loop, makes it a story).
    public static func rebuilt(_ notes: [Entry]) -> [Entry] {
        let byID = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return notes.map { note in
            var entry = note
            var seen: Set<Int> = [note.id]
            var top = note.id
            while let parent = byID[top]?.parent, byID[parent] != nil, seen.insert(parent).inserted { top = parent }
            entry.root = top
            if top == note.id { entry.parent = nil }
            return entry
        }
    }

    /// Takes a story and everything under it out: it was unarchived or deleted.
    public mutating func remove(story root: Int) {
        entries.removeAll { $0.root == root }
    }

    public func entry(_ id: Int) -> Entry? { entries.first { $0.id == id } }

    /// The tasks under an archived story, in key order.
    public func tasks(under root: Int) -> [Entry] {
        entries.filter { $0.root == root && $0.id != root }.sorted { $0.id < $1.id }
    }

    // MARK: Search

    /// A story the search found: itself, or tasks under it.
    public struct Match: Sendable, Hashable {
        public var story: Entry
        /// The tasks under it that have every word; empty when only the story does, or there are no words.
        public var under: [Entry]
        /// How many tasks are under it.
        public var count: Int
    }

    /// The query's words, folded.
    public static func words(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }.filter { !$0.isEmpty }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// What the search reads of the index, folded once: build it when the Archive opens, ask it on each keystroke.
    public struct Searcher: Sendable {
        struct Item: Sendable {
            var entry: Entry
            var text: String
        }

        let stories: [Item]
        let under: [Int: [Item]]

        public init(_ index: ArchiveIndex) {
            let projects = Dictionary(index.entries.filter { $0.id == $0.root }.map { ($0.id, $0.project) }, uniquingKeysWith: { a, _ in a })
            func item(_ entry: Entry) -> Item {
                let project = entry.project ?? projects[entry.root] ?? nil
                let text = "t-\(entry.id) \(entry.title) \(project ?? "") \(entry.tags.map { "#\($0)" }.joined(separator: " "))"
                return Item(entry: entry, text: ArchiveIndex.fold(text))
            }
            stories = index.stories.map(item)
            var under: [Int: [Item]] = [:]
            for entry in index.entries where entry.id != entry.root { under[entry.root, default: []].append(item(entry)) }
            for key in under.keys { under[key]?.sort { $0.entry.id < $1.entry.id } }
            self.under = under
        }

        public var count: Int { stories.count }

        /// The stories with every word in their title, key, project or tags, or in one of their tasks'; the newest
        /// archived first. No words: every story.
        public func search(_ query: String) -> [Match] {
            let words = ArchiveIndex.words(query)
            return stories.compactMap { story in
                let kids = under[story.entry.id] ?? []
                guard !words.isEmpty else { return Match(story: story.entry, under: [], count: kids.count) }
                let own = words.allSatisfy(story.text.contains)
                let found = kids.filter { kid in words.allSatisfy(kid.text.contains) }
                guard own || !found.isEmpty else { return nil }
                return Match(story: story.entry, under: found.map(\.entry), count: kids.count)
            }
        }
    }

    // MARK: Groups

    /// Where a story sits in the Archive: by when it was archived.
    public enum Group: Sendable, Hashable {
        case thisWeek, lastWeek
        case month(year: Int, month: Int)
    }

    public static func group(_ date: Date, now: Date, calendar: Calendar = .current) -> Group {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return .thisWeek }
        if date >= week.start { return .thisWeek }
        if let last = calendar.date(byAdding: .weekOfYear, value: -1, to: week.start), date >= last { return .lastWeek }
        let parts = calendar.dateComponents([.year, .month], from: date)
        return .month(year: parts.year ?? 0, month: parts.month ?? 0)
    }
}
