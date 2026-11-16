import Foundation
import HQKit

/// What one `hq` command changed in tasks, so a wrong change can be seen (`hq task history`) and undone (`hq task undo`).
nonisolated struct TaskEdit: Codable, Sendable {
    var at: Date
    /// The session that ran it; nil from a terminal.
    var session: String?
    var command: String
    var changes: [Change]

    /// A task as it was and as it became: `before` nil when the command created it, `after` nil when it deleted it.
    struct Change: Codable, Sendable {
        var id: Int
        var before: TaskItem?
        var after: TaskItem?
    }

    /// "parent T-273 → T-264", "status todo → doing": what changed in one task, in words.
    static func fields(_ before: TaskItem?, _ after: TaskItem?) -> [String] {
        guard let before else { return ["created"] }
        guard let after else { return ["deleted"] }
        func text<T>(_ value: T?) -> String { value.map { "\($0)" } ?? "none" }
        func keys(_ ids: [Int]) -> String { ids.isEmpty ? "none" : ids.map { "T-\($0)" }.joined(separator: ",") }
        var lines: [String] = []
        func add(_ name: String, _ old: String, _ new: String) { if old != new { lines.append("\(name) \(old) → \(new)") } }
        add("title", "“\(before.title)”", "“\(after.title)”")
        add("status", before.status.rawValue, after.status.rawValue)
        add("type", text(before.type?.rawValue), text(after.type?.rawValue))
        add("project", text(before.project), text(after.project))
        add("tags", before.tags.joined(separator: ","), after.tags.joined(separator: ","))
        add("parent", before.parent.map { "T-\($0)" } ?? "none", after.parent.map { "T-\($0)" } ?? "none")
        add("order", text(before.order), text(after.order))
        add("review", text(before.review), text(after.review))
        if before.body != after.body { lines.append("description") }
        if before.links != after.links || before.related != after.related { lines.append("links") }
        add("blocked", before.blocked ? before.blockedReason ?? "yes" : "no", after.blocked ? after.blockedReason ?? "yes" : "no")
        add("blocked by", keys(before.blockedBy), keys(after.blockedBy))
        add("after", keys(before.after), keys(after.after))
        if before.sessions != after.sessions { lines.append("sessions") }
        return lines
    }
}

extension AppModel {
    /// Who made an edit: its session's name, else "a terminal".
    func editor(_ edit: TaskEdit) -> String {
        guard let id = edit.session else { return "a terminal" }
        return session(id)?.name ?? "session \(id.prefix(8))"
    }

    /// Each task an edit changed, still there, as it was before it.
    func revert(_ edit: TaskEdit) {
        var next = tasks
        for change in edit.changes {
            guard var task = change.before, change.after != nil, let index = next.firstIndex(where: { $0.id == change.id }) else { continue }
            task.path = next[index].path
            task.created = next[index].created
            task.modified = .now
            next[index] = task
        }
        tasks = next
    }
}

/// Every task change a session made through `hq` in the last 7 days, in task-edits.jsonl beside the store. The file is read,
/// trimmed and written on one background queue, in order.
@MainActor
final class TaskEditLog {
    static let shared = TaskEditLog()
    nonisolated private static let kept: TimeInterval = 7 * 86_400
    nonisolated private static let queue = DispatchQueue(label: "hq.task-edits", qos: .utility)
    private let url = Store.directory.appending(path: "task-edits.jsonl")
    /// The last 7 days' edits: those recorded this run until `load` has read the file.
    private(set) var edits: [TaskEdit] = []

    /// Reads the file in the background at launch, dropping what's older than 7 days.
    func load() {
        let url = url
        Self.queue.async {
            let recent = Self.read(url)
            Task { @MainActor in self.edits = recent + self.edits }
        }
    }

    /// The tasks a command changed, from the list before it ran and after.
    func record(command: String, session: String?, before: [TaskItem], after: [TaskItem]) {
        let old = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let new = Dictionary(after.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let changes = Set(old.keys).union(new.keys).sorted().compactMap { id -> TaskEdit.Change? in
            let was = old[id], now = new[id]
            if let was, let now, was.sameNote(as: now) { return nil }
            return TaskEdit.Change(id: id, before: was, after: now)
        }
        guard !changes.isEmpty else { return }
        let edit = TaskEdit(at: .now, session: session, command: command, changes: changes)
        edits.append(edit)
        let url = url
        Self.queue.async { Self.append(edit, to: url) }
    }

    /// The edits that changed a task, oldest first.
    func edits(of id: Int) -> [TaskEdit] {
        edits.filter { edit in edit.changes.contains { $0.id == id } }
    }

    nonisolated private static func read(_ url: URL) -> [TaskEdit] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let all = data.split(separator: UInt8(ascii: "\n")).compactMap { try? decoder.decode(TaskEdit.self, from: Data($0)) }
        let recent = all.filter { $0.at > Date.now.addingTimeInterval(-kept) }
        if recent.count < all.count {
            let lines = recent.compactMap { try? encoder().encode($0) }
            try? Data(lines.joined(separator: Data("\n".utf8)) + Data("\n".utf8)).write(to: url)
        }
        return recent
    }

    nonisolated private static func append(_ edit: TaskEdit, to url: URL) {
        guard let line = try? encoder().encode(edit) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line + Data("\n".utf8))
            try? handle.close()
        } else {
            try? (line + Data("\n".utf8)).write(to: url)
        }
    }

    nonisolated private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
