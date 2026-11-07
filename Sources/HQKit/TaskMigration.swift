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
        if raw == "backlog" || (TaskStatus(rawValue: raw) == nil && raw != "review") { changes["status"] = TaskStatus.todo.rawValue }
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
}
