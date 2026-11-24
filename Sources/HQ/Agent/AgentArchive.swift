import Foundation
import HQKit

/// `hq` and the Archive (T-471): the index and the archived notes a call needs are read on the socket's thread before the
/// call runs on the main actor, which then reads them from memory only.
nonisolated enum AgentArchive {
    /// Reads what a request needs of the Archive, after the queued note writes (a story just archived is in its folder).
    /// Returns what lets it go once the reply is sent.
    static func prepare(_ request: Data) -> (@Sendable () -> Void)? {
        guard let object = try? JSONSerialization.jsonObject(with: request) as? [String: Any],
              let name = object["command"] as? String else { return nil }
        let args = object["args"] as? [String: String] ?? [:]
        let store = ArchiveStore.shared
        let keys = (args["task"] ?? "").split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { TaskItem.key(String($0)) }
        var notes: [Int] = []
        switch name {
        case "ls" where args["kind"] == "tasks" && args["archived"] != nil:
            break
        case "task unarchive", "task show":
            NoteWriter.queue.sync {}
            notes = keys.filter(store.isArchived)
            guard !notes.isEmpty else { return nil }
        default:
            // A change to an archived task is refused by name: only its file is looked at, on the main actor.
            return nil
        }
        NoteWriter.queue.sync {}
        store.hold()
        let index = store.index()
        let stories = Set(notes.compactMap { index.entry($0)?.root })
        store.prepare(notes: notes + stories.flatMap { [$0] + index.tasks(under: $0).map(\.id) })
        return { store.release() }
    }
}

extension AgentCommands {
    /// No live task by that key: an archived one says so, with the way back.
    static func missing(_ ref: String) -> AgentError {
        if let id = TaskItem.key(ref), ArchiveStore.shared.isArchived(id) {
            return AgentError.invalid("T-\(id) is archived: hq task unarchive T-\(id) first")
        }
        return AgentError.notFound("no task \(ref). Run `hq ls tasks`")
    }

    static func archiveCommand(_ args: Args, _ model: AppModel) throws -> Any {
        let ref = try args.required("task")
        guard let task = model.task(TaskItem.key(ref)) else { throw missing(ref) }
        try own(task, args, model)
        if let parent = model.taskTree.ancestors(of: task.id).last {
            throw AgentError.usage("\(task.key) is a subtask: a story goes to the Archive whole, hq task archive T-\(parent)")
        }
        let count = model.taskTree.subtree(of: task.id).count - 1
        var result = task.agentJSON(model)
        model.archive([task.id])
        result["archived"] = JSON.date(.now)
        result["note"] = "Archived\(count > 0 ? " with its \(count) task\(count == 1 ? "" : "s")" : ""): out of the list. hq task unarchive \(task.key) brings it back"
        return result
    }

    static func unarchiveCommand(_ args: Args, _ model: AppModel) throws -> Any {
        let ref = try args.required("task")
        guard let id = TaskItem.key(ref) else { throw AgentError.usage("\(ref) isn't a task key: T-12") }
        if model.task(id) != nil { throw AgentError.invalid("T-\(id) isn't archived: it's in the list") }
        guard let entry = ArchiveStore.shared.current?.entry(id), let note = ArchiveStore.shared.note(id) else {
            throw AgentError.notFound("no archived task T-\(id). Run `hq ls tasks --archived`")
        }
        guard entry.root == id else {
            throw AgentError.usage("T-\(id) is under T-\(entry.root): a story comes back whole, hq task unarchive T-\(entry.root)")
        }
        if let session = args.string(sessionArg), model.session(session) != nil, try args.bool("not-mine") != true, !note.sessions.contains(session) {
            throw AgentError.notMine("T-\(id) is “\(note.title)”, a task this session isn't on. Check the key (`hq ls tasks --archived`); "
                + "if it's the one the user means, run again with --not-mine")
        }
        model.unarchive(id)
        var result: JSONObject = ["id": "T-\(id)", "title": note.title, "status": note.status.rawValue, "tags": note.tags]
        if let project = note.project { result["project"] = project }
        result["note"] = "Back first in the list, with its tasks"
        return result
    }

    /// `ls tasks --archived`: the archived stories, the newest archived first; with --search, those with every word in
    /// them or in a task under them.
    static func archivedList(_ args: Args, _ model: AppModel) -> [JSONObject] {
        guard let index = ArchiveStore.shared.current else { return [] }
        let matches = ArchiveIndex.Searcher(index).search(args.string("search") ?? "")
        return matches.map { match in
            var json = archivedJSON(match.story)
            json["tasks"] = match.count
            if !match.under.isEmpty {
                json["found"] = match.under.map { ["id": $0.key, "status": $0.status.rawValue, "title": $0.title] as JSONObject }
                json["flow"] = "\(json["flow"] ?? "") · found in " + match.under.prefix(3).map { "\($0.key) \($0.title)" }.joined(separator: "; ")
            }
            return json
        }
    }

    private static func archivedJSON(_ entry: ArchiveIndex.Entry) -> JSONObject {
        var json: JSONObject = ["id": entry.key, "title": entry.title, "status": entry.status.rawValue, "tags": entry.tags,
                                "archived": JSON.date(entry.archived), "flow": "archived \(NoteDate.day(entry.archived))"]
        if let project = entry.project { json["project"] = project }
        if let parent = entry.parent { json["parent"] = "T-\(parent)" }
        if let done = entry.done { json["done"] = JSON.date(done) }
        return json
    }

    /// `task show` of an archived task: read only, its description from its note, the tasks under it from the index.
    static func archivedShow(_ id: Int, view: String?) -> JSONObject? {
        guard let index = ArchiveStore.shared.current, let entry = index.entry(id) else { return nil }
        var json = archivedJSON(entry)
        json["flow"] = "archived \(NoteDate.day(entry.archived)), read only: hq task unarchive T-\(entry.root) to change it"
        let note = ArchiveStore.shared.note(id)
        if view != "brief", let body = note?.body { json["body"] = body }
        if let links = note?.links, !links.isEmpty { json["links"] = links.map(\.absoluteString) }
        guard view != "body" else { return json }
        var subtasks: [JSONObject] = []
        func walk(_ parent: Int, depth: Int) {
            for kid in index.entries.filter({ $0.parent == parent && $0.root == entry.root }).sorted(by: { $0.id < $1.id }) {
                subtasks.append(["id": kid.key, "status": kid.status.rawValue, "title": kid.title, "depth": depth, "parent": "T-\(parent)"])
                walk(kid.id, depth: depth + 1)
            }
        }
        walk(id, depth: 0)
        json["subtasks"] = subtasks
        return json
    }
}
