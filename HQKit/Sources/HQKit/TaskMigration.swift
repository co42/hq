import Foundation

/// The one-time move of task notes from the two lists (Tasks and the Backlog) to one list (v16, T-471). Pure: it says
/// which keys to write; running it again changes nothing.
public enum TaskMigration {
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
    public struct OneList: Sendable, Hashable, Codable {
        public var status: TaskStatus?
        public var order: Double?

        public init(status: TaskStatus? = nil, order: Double? = nil) {
            self.status = status
            self.order = order
        }
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
        let overview = tops.filter { $0.list == "overview" }.sorted { ($0.order, $0.id) < ($1.order, $1.id) }
        let backlog = tops.filter { $0.list != "overview" }.sorted { ($0.order, $0.id) < ($1.order, $1.id) }
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
