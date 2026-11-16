import Foundation
import HQKit

extension SeedData {
    /// The Archive of the sample day (T-471): stories archived this week, last week and in October, a few with tasks under
    /// them, one a backlog idea archived by hand.
    static func archive(now: Date) -> ArchiveShown {
        func days(_ count: Double) -> Date { now.addingTimeInterval(-count * 86_400) }
        typealias Entry = ArchiveIndex.Entry
        func story(_ id: Int, _ title: String, _ project: String?, done: Double?, archived: Double, status: TaskStatus = .done,
                   tags: [String] = [], under: [(Int, String)] = []) -> [Entry] {
            [Entry(id: id, root: id, title: title, status: status, project: project, tags: tags, done: done.map(days), archived: days(archived),
                   modified: days(archived))]
                + under.map { Entry(id: $0.0, root: id, parent: id, title: $0.1, status: .done, done: done.map(days), archived: days(archived),
                                    modified: days(archived)) }
        }
        let entries = story(301, "Registry v2 pull path", "Registry", done: 8, archived: 1, tags: ["perf"],
                            under: [(302, "Range requests for chunked layers"), (303, "Drag-free resume after a dropped connection"), (304, "Bench pulls against the old path")])
            + story(305, "Capture typed artifacts: dashboards, docs, decks", "HQ", done: 7, archived: 0)
            + story(306, "Flag the cdn-us autoscaler to its owners", "CDN", done: nil, archived: 0, status: .backlog)
            + story(307, "Cockpit drag and drop", "HQ", done: 12, archived: 5,
                    under: [(308, "Drag a card between two cards"), (309, "Drop a task on a task asks where it goes"), (310, "Drag a session onto another"),
                            (311, "Drag a task out to Ghostty: its line"), (312, "Cancelled drags leave nothing behind")])
            + story(313, "Write up the CDN cache key normalisation", "CDN", done: 13, archived: 6, tags: ["docs"])
            + story(314, "Image-sync v1 rollout", "Registry", done: 30, archived: 23, under: [(315, "Canary on staging, 30 minutes green")])
            + story(316, "Notification center", "HQ", done: 33, archived: 26, under: [(317, "Later puts a row away until a time"), (318, "Reminders as cards")])
            + story(319, "Unread clears when the user focuses a session's terminal", "HQ", done: 35, archived: 28)
        let index = ArchiveIndex(entries: entries)
        var shown = ArchiveShown(index: index, searcher: ArchiveIndex.Searcher(index))
        shown.notes[301] = TaskItem(id: 301, title: "Registry v2 pull path", status: .done, project: "Registry", tags: ["perf"], done: days(8),
                                    created: days(40), modified: days(1),
                                    body: "Pull a layer by ranges, so a dropped connection resumes where it stopped.\n\n## Done when\n- [x] Range requests for chunked layers\n- [x] Resume after a drop\n- [x] Bench against the old path",
                                    path: "/tmp/T-301.md")
        return shown
    }

    /// A large Archive for its speed checks: `stories` stories of five tasks each, archived over the last months.
    static func archiveIndex(stories: Int, now: Date) -> ArchiveIndex {
        var entries: [ArchiveIndex.Entry] = []
        entries.reserveCapacity(stories * 5)
        let words = ["registry", "cdn", "push", "pull", "layers", "chunks", "cache", "canary", "bench", "sessions", "faces", "outline"]
        for story in 0..<stories {
            let root = 100_000 + story * 5
            let archived = now.addingTimeInterval(-Double(story) * 3_600)
            entries.append(.init(id: root, root: root, title: "Story \(story): \(words[story % words.count]) and \(words[(story / 3) % words.count])",
                                 status: .done, project: ["Registry", "CDN", "HQ"][story % 3], archived: archived, modified: archived))
            for kid in 1...4 {
                entries.append(.init(id: root + kid, root: root, parent: root, title: "Step \(kid): \(words[(story + kid) % words.count]) for story \(story)",
                                     status: .done, archived: archived, modified: archived))
            }
        }
        return ArchiveIndex(entries: entries)
    }
}
