import Foundation

/// The one-time move of task notes from the board (backlog, todo, doing, done columns) to the
/// cockpit's lists. Pure: it says which keys to write; running it again changes nothing.
public enum TaskMigration {
    /// The keys to set on a note, empty when it's already migrated.
    public static func plan(_ note: FrontMatter, modified: Date) -> [String: String] {
        var changes: [String: String] = [:]
        let raw = note.string("status")?.trimmingCharacters(in: .whitespaces).lowercased() ?? "todo"
        let isSubtask = note.string("parent").map { !$0.isEmpty } ?? false
        if !note.has("list") && !isSubtask {
            switch raw {
            case "doing", "review": changes["list"] = TaskList.overview.rawValue
            default: changes["list"] = TaskList.backlog.rawValue
            }
            if raw == "done", !note.has("done") { changes["done"] = NoteDate.minute(modified) }
        }
        // Review stays for the v9 review migration to read.
        if TaskStatus(rawValue: raw) == nil && raw != "review" { changes["status"] = TaskStatus.todo.rawValue }
        return changes
    }

    /// The note with the planned keys written.
    public static func apply(_ text: String, modified: Date) -> String? {
        var note = FrontMatter(text)
        let changes = plan(note, modified: modified)
        guard !changes.isEmpty else { return nil }
        for key in ["status", "type", "list", "done"] {
            if let value = changes[key] { note.set(key, value) }
        }
        return note.text
    }

    // MARK: One list (v16, T-471)

    /// A note as the one-list move reads it: its `list` key, nil once moved.
    public struct ListedNote: Sendable, Hashable {
        public var id: Int
        public var topLevel: Bool
        public var list: String?
        public var status: String?
        public var order: Double

        public init(id: Int, topLevel: Bool, list: String?, status: String?, order: Double) {
            self.id = id
            self.topLevel = topLevel
            self.list = list
            self.status = status
            self.order = order
        }
    }

    /// What the one-list move writes on a note: `list` goes, a todo top-level task of the Backlog becomes backlog, and
    /// the top-level tasks take one order, Tasks' first, then the Backlog's.
    public struct OneList: Sendable, Hashable {
        public var status: TaskStatus?
        public var order: Double?
    }

    /// The notes that still have a `list` key and what each gets; empty once every note is moved. Top-level tasks that
    /// moved already keep their order; the others follow them, Tasks' then the Backlog's, each in its own order.
    public static func oneList(_ notes: [ListedNote]) -> [Int: OneList] {
        let listed = notes.filter { $0.list != nil }
        guard !listed.isEmpty else { return [:] }
        var changes: [Int: OneList] = [:]
        for note in listed { changes[note.id] = OneList() }
        let base = notes.filter { $0.topLevel && $0.list == nil }.map(\.order).max() ?? 0
        let tops = listed.filter(\.topLevel)
        let overview = tops.filter { $0.list == TaskList.overview.rawValue }.sorted { ($0.order, $0.id) < ($1.order, $1.id) }
        let backlog = tops.filter { $0.list != TaskList.overview.rawValue }.sorted { ($0.order, $0.id) < ($1.order, $1.id) }
        for (offset, note) in (overview + backlog).enumerated() {
            changes[note.id]?.order = base + Double(offset + 1)
        }
        for note in backlog {
            let status = note.status.flatMap(TaskStatus.init(parsing:)) ?? .todo
            if status == .todo { changes[note.id]?.status = .backlog }
        }
        return changes
    }
}
