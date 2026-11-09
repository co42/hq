import Foundation
import HQKit

/// Everything an agent can do in hq. Add a command here and the CLI and `help` get it.
/// Each `run` is on the main actor with the app's model, like a button in the window.
enum AgentCommands {
    static let all: [AgentCommand] = [
        AgentCommand(name: "status", summary: "Show whether HQ runs and what needs the user.",
                     example: "hq status --json", readOnly: true) { _, model in
            ["running": true, "needsYou": model.importantCount, "updates": model.updateCount, "sessions": model.gridSessions.count,
             "tasks": model.tasks.count, "files": model.files.count, "artifacts": model.artifacts.count]
        },
        AgentCommand(name: "ctx", summary: "Show this session's tasks, the overview's tasks in Doing, recent files, and the other open sessions.",
                     params: [.init(name: "session", help: "a session id (default: the Claude session running the command)")],
                     example: "hq ctx --json", readOnly: true) { args, model in
            let id = args.string("session") ?? args.string(sessionArg)
            guard let session = model.session(id) ?? (id.flatMap { model.session(prefix: $0) }) else {
                throw AgentError.notFound("no session \(id ?? "here"). Run it inside a Claude session, or pass --session <id>")
            }
            let mine = model.tasks(of: session.id)
            let overview = model.taskTree.outline(.overview).compactMap { model.task($0) }
                .filter { $0.status == .doing && !mine.contains($0) }
            let mineIDs = Set(mine.map(\.id))
            let files = model.files.filter { file in file.sessions.contains(session.id) || file.tasks.contains(where: mineIDs.contains) }
                .sorted { $0.modified > $1.modified }
            let artifacts = model.artifacts.filter { $0.session == session.id }.sorted { $0.published > $1.published }
            let others = model.sessions.filter { $0.id != session.id && $0.closedAt == nil }
            var text = ["This session: \(session.name)"]
            text.append(mine.isEmpty ? "Works on: no task yet (hq task link T-n, or the user drops one on its card)" : "Works on:")
            // Open tasks in full; done ones only counted, the latest few named, so a long session's list stays short.
            let open = mine.filter { $0.status != .done }
            let done = mine.filter { $0.status == .done }.sorted { $0.modified > $1.modified }
            text += open.map { "  \($0.key) [\($0.status.rawValue)] \($0.title) (\(model.list(of: $0.id) == .backlog ? "Backlog" : "Tasks"))" }
            if !done.isEmpty {
                text.append("  \(done.count) done" + (done.count > 3 ? ", latest " : ": ") + done.prefix(3).map(\.key).joined(separator: ", "))
            }
            if !overview.isEmpty {
                text.append("On the overview:")
                text += overview.prefix(15).map { "  \($0.key) [\($0.status.rawValue)] \($0.title)" }
            }
            if !files.isEmpty {
                text.append("Recent files:")
                text += files.prefix(10).map { "  \($0.title) (\($0.path ?? $0.id))" }
            }
            if !artifacts.isEmpty {
                text.append("Artifacts:")
                text += artifacts.prefix(10).map { "  \($0.title) \($0.id.absoluteString)" }
            }
            if !others.isEmpty {
                text.append("Other open sessions:")
                text += others.prefix(12).map { "  \($0.name) (\($0.status.title.lowercased()))" }
            }
            return ["text": text.joined(separator: "\n"), "session": session.agentJSON(model),
                    "tasks": mine.map { $0.agentJSON(model) }, "overview": overview.prefix(15).map { $0.agentJSON(model) },
                    "files": files.prefix(10).map(\.agentJSON), "artifacts": artifacts.prefix(10).map(\.agentJSON),
                    "sessions": others.map { $0.agentJSON(model) }]
        },
        AgentCommand(name: "ls", summary: "List sessions, tasks, prs, files, artifacts, projects or notifications.",
                     params: [.init(name: "kind", positional: true, help: "sessions (default), tasks, prs (Reviews, then Yours, as on the page), files, artifacts, projects or notifications (--all: with what was read today)"),
                              .init(name: "overview", kind: .boolean, help: "tasks: only the overview's Tasks"),
                              .init(name: "backlog", kind: .boolean, help: "tasks: only the Backlog"),
                              .init(name: "all", kind: .boolean, help: "include closed sessions and done tasks"),
                              .init(name: "project", help: "tasks: only this project"),
                              .init(name: "tag", help: "tasks: only with this tag"),
                              .init(name: "limit", kind: .integer, help: "at most this many (default 50)"),
                              .init(name: "offset", kind: .integer, help: "skip this many, for the next page")],
                     example: "hq ls tasks --overview --json", readOnly: true) { args, model in
            let kind = args.string("kind") ?? "sessions"
            let all = try args.bool("all") ?? false
            let items: [JSONObject]
            switch kind {
            case "sessions":
                items = (all ? model.sessions.sorted { $0.order < $1.order } : model.gridSessions).map { $0.agentJSON(model) }
            case "tasks":
                let tree = model.taskTree
                let overview = try args.bool("overview") ?? false
                let backlog = try args.bool("backlog") ?? false
                var ids: [Int] = []
                if !backlog { ids += tree.outline(.overview) }
                if !overview { ids += tree.outline(.backlog) }
                items = ids.compactMap { model.task($0) }.filter { task in
                    (all || task.status != .done)
                        && (args.string("project").map { $0.caseInsensitiveCompare(task.project ?? "") == .orderedSame } ?? true)
                        && (args.string("tag").map { tag in task.tags.contains(tag.replacingOccurrences(of: "#", with: "")) } ?? true)
                }.map { $0.agentJSON(model) }
            case "prs":
                // As on the page: Reviews (every one, whatever its filter), then Yours, then the other linked ones.
                let reviews = model.allReviewRequests, yours = model.ownPullRequests
                let shown = Set((reviews + yours).map(\.url))
                let others = (model.github?.items ?? []).filter { !shown.contains($0.url) && (all || $0.state == .open || $0.state == .draft) }
                @MainActor func json(_ item: GitHubItem, card: String?) -> JSONObject {
                    var json = item.agentJSON
                    json["card"] = card
                    if card != nil { json["status"] = PRRow.reviewText(item, waits: model.waitsForReview(item)) }
                    return json
                }
                items = reviews.map { json($0, card: "reviews") } + yours.map { json($0, card: "yours") } + others.map { json($0, card: nil) }
            case "files":
                items = model.files.sorted { $0.modified > $1.modified }.map(\.agentJSON)
            case "artifacts":
                items = model.artifacts.sorted { $0.published > $1.published }.map(\.agentJSON)
            case "projects":
                items = model.allProjects.map { model.projectJSON($0) }
            case "notifications":
                let sections: [NoticeSection] = all ? [.needsYou, .updates, .later, .earlier] : [.needsYou, .updates, .later]
                items = model.blockedSessions.map { ["section": "needsYou", "session": $0.id, "text": $0.reason ?? $0.status.title] }
                    + sections.flatMap { section in model.notices(in: section).map { model.noticeJSON($0, section: section) } }
            default:
                throw AgentError.usage("no kind \"\(kind)\". Kinds: sessions, tasks, prs, files, artifacts, projects, notifications")
            }
            let limit = try args.int("limit", default: 50)
            let offset = try args.int("offset", default: 0)
            let page = items.dropFirst(offset).prefix(limit)
            var result: JSONObject = [kind: Array(page), "total": items.count]
            if offset + page.count < items.count { result["nextOffset"] = offset + page.count }
            return result
        },
        AgentCommand(name: "task show", summary: "Show a task with the tasks it's part of, its description, subtasks and what's linked to it.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12")],
                     example: "hq task show T-12 --json", readOnly: true) { args, model in
            let task = try findTask(args, model)
            let tree = model.taskTree
            var json = task.agentJSON(model)
            json["body"] = task.body
            json["parents"] = tree.ancestors(of: task.id).compactMap { model.task($0) }.map(\.briefJSON)
            json["subtasks"] = tree.children(of: task.id).compactMap { model.task($0) }.map(\.briefJSON)
            json["linked"] = model.outputs(ofTask: task.id).map { model.linkJSON($0) }
            return json
        },
        AgentCommand(name: "task add", summary: "Create a task, at the end of Tasks; at the top of the Backlog with --backlog, only when the user asks for the Backlog; under a task with --parent.",
                     params: [.init(name: "title", required: true, positional: true, help: "what to do, short; #words set a status or a project they name, else become tags"),
                              .init(name: "project", help: "the project it belongs to"),
                              .init(name: "tag", help: "tags, comma separated"),
                              .init(name: "parent", help: "T-12: a subtask of that task"),
                              .init(name: "backlog", kind: .boolean, help: "at the top of the Backlog: only when the user says Backlog"),
                              .init(name: "now", kind: .boolean, help: "at the end of Tasks: the default"),
                              .init(name: "status", help: "todo (default), doing (also puts it on Tasks) or done"),
                              .init(name: "body", help: "the description in markdown; - reads stdin"), notMine],
                     example: "hq task add \"Dedup layers on push\" --project Registry --body -") { args, model in
            let titled = TitleTags.split((try? args.required("title")) ?? "").tags.compactMap { word -> TaskStatus? in
                if case .status(let status) = model.titleWord(word) { status } else { nil }
            }.last
            let status = try args.string("status").map { raw in
                guard let status = TaskStatus(parsing: raw) else { throw AgentError.usage("no status \"\(raw)\". Statuses: todo, doing, done") }
                return status
            } ?? titled ?? .todo
            let session = model.session(args.string(sessionArg))
            let tree = model.taskTree
            let placed: (TaskTree.Placement, changes: [Int: TaskTree.Placement])?
            if let ref = args.string("parent") {
                guard let parent = model.task(TaskItem.key(ref)) else { throw AgentError.notFound("no task \(ref). Run `hq ls tasks`") }
                try own(parent, args, model)
                placed = tree.placeNew(in: .task(parent.id))
            } else if try args.bool("backlog") == true, status != .doing {
                placed = tree.placeNew(in: .list(.backlog), at: 0)
            } else {
                placed = tree.placeNew(in: .list(.overview))
            }
            guard let (placement, renumber) = placed,
                  let task = model.addTask(title: try args.required("title"), placement: placement, status: status,
                                           project: args.string("project"),
                                           tags: tags(args.string("tag")), body: args.string("body") ?? "", session: session?.id, renumber: renumber) else {
                throw AgentError.invalid("could not create the task. Check that the vault is reachable")
            }
            return task.agentJSON(model)
        },
        AgentCommand(name: "task move", summary: "Set a task's status: todo, doing or done. When the user must check something, keep it doing and tell them with hq notify.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12"),
                              .init(name: "status", required: true, positional: true, help: "todo, doing (also brings it to Tasks) or done (backlog: todo, in the Backlog)"),
                              notMine],
                     example: "hq task move T-12 doing") { args, model in
            let raw = try args.required("status").lowercased()
            if raw == "review" {
                throw AgentError.usage("there is no review status. Keep the task doing and tell the user what to check: "
                                       + "hq notify \"PR #418 is ready to merge\" --link \(args.string("task") ?? "T-12")")
            }
            let task = try ownTask(args, model)
            if raw == "backlog" {
                model.setStatus(task.id, .todo)
                model.move(task.id, to: .backlog)
            } else {
                guard let status = TaskStatus(rawValue: raw) else {
                    throw AgentError.usage("no status \"\(raw)\". Statuses: todo, doing, done")
                }
                model.setStatus(task.id, status)
                // Work started: a top-level task in the Backlog comes to Tasks.
                if status == .doing, task.parent == nil, model.list(of: task.id) == .backlog { model.move(task.id, to: .overview) }
                // The session works on it.
                if status == .doing { link(task.id, args, model) }
            }
            var result = model.task(task.id)?.agentJSON(model) ?? [:]
            // The parent in doing doesn't move its subtasks: say which still read todo.
            let todo = model.taskTree.subtree(of: task.id).dropFirst().compactMap { model.task($0) }.filter { $0.status == .todo }
            if raw == "doing", let first = todo.first {
                result["next"] = "Still todo under \(task.key): " + todo.prefix(8).map { "\($0.key) \($0.title)" }.joined(separator: "; ")
                    + (todo.count > 8 ? "; and \(todo.count - 8) more" : "")
                    + ". Move each to doing as you start it: hq task move \(first.key) doing"
            }
            return result
        },
        AgentCommand(name: "task edit", summary: "Change a task's title, description, project, tags or parent. Everything else stays.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12"),
                              .init(name: "title", help: "the new title"),
                              .init(name: "body", help: "the new description in markdown; - reads stdin"),
                              .init(name: "project", help: "the project; empty clears it"),
                              .init(name: "add-tag", help: "tags to add, comma separated"),
                              .init(name: "remove-tag", help: "tags to remove, comma separated"),
                              .init(name: "parent", help: "T-34: its last subtask, in its list; none: top level, in the list it's in"),
                              notMine],
                     example: "hq task edit T-12 --body - --add-tag perf") { args, model in
            let task = try ownTask(args, model)
            if let ref = args.string("parent")?.trimmingCharacters(in: .whitespaces) {
                try moveUnder(task.id, ref, model)
            }
            let added = tags(args.string("add-tag"))
            let removed = Set(tags(args.string("remove-tag")))
            model.changeTask(task.id, "Edit Task") { task in
                if let body = args.string("body") { task.body = body.trimmingCharacters(in: .newlines) }
                if let project = args.string("project") { task.project = project.isEmpty ? nil : project }
                task.tags = task.tags.filter { !removed.contains($0) } + added.filter { !task.tags.contains($0) }
            }
            if let title = args.string("title"), !title.isEmpty { model.setTitle(task.id, title) }
            return model.task(task.id)?.agentJSON(model) ?? [:]
        },
        AgentCommand(name: "task delete", summary: "Delete a task and its subtasks, as Delete does in HQ: their notes go to the Trash.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12"), notMine],
                     example: "hq task delete T-12 --yes", destructive: true) { args, model in
            let task = try ownTask(args, model)
            let keys = model.taskTree.subtree(of: task.id).compactMap { model.task($0)?.key }
            let named = keys.joined(separator: ", ")
            guard args.confirmed else { return ["wouldDelete": keys, "text": "Would delete \(named). Again with --yes to delete."] }
            model.deleteTasks([task.id])
            return ["deleted": keys, "text": "Deleted \(named): \(keys.count == 1 ? "its note is" : "their notes are") in the Trash."]
        },
        AgentCommand(name: "task history", summary: "What sessions changed in a task through hq in the last 30 days, the latest first. task undo reverts the latest.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12")],
                     example: "hq task history T-12", readOnly: true) { args, model in
            let ref = try args.required("task")
            guard let id = TaskItem.key(ref) else { throw AgentError.usage("\(ref) isn't a task key: T-12") }
            let edits = TaskEditLog.shared.edits(of: id).reversed()
            let items: [JSONObject] = edits.map { edit in
                let change = edit.changes.first { $0.id == id }
                var item: JSONObject = ["at": JSON.date(edit.at), "command": edit.command, "by": model.editor(edit),
                                        "changes": TaskEdit.fields(change?.before, change?.after), "tasks": edit.changes.map { "T-\($0.id)" }]
                if let session = edit.session { item["session"] = session }
                return item
            }
            let lines = edits.map { edit in
                let change = edit.changes.first { $0.id == id }
                let others = edit.changes.count - 1
                return "\(edit.at.formatted(date: .abbreviated, time: .shortened)) · \(model.editor(edit)) · \(edit.command): "
                    + TaskEdit.fields(change?.before, change?.after).joined(separator: ", ")
                    + (others > 0 ? " (and \(others) other task\(others == 1 ? "" : "s"))" : "")
            }
            return ["edits": items, "text": lines.isEmpty ? "No change to T-\(id) through hq in the last 30 days." : lines.joined(separator: "\n")]
        },
        AgentCommand(name: "task undo", summary: "Undo the latest change hq made to a task: every task that command changed goes back as it was. Tasks it created or deleted stay so.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12")],
                     example: "hq task undo T-12 --yes", destructive: true) { args, model in
            let ref = try args.required("task")
            guard let id = TaskItem.key(ref) else { throw AgentError.usage("\(ref) isn't a task key: T-12") }
            guard let edit = TaskEditLog.shared.edits(of: id).last else {
                throw AgentError.notFound("no change to T-\(id) through hq in the last 30 days")
            }
            let reverted = edit.changes.filter { $0.before != nil && $0.after != nil }
            let moved = reverted.filter { change in model.task(change.id).map { !$0.sameNote(as: change.after!) } ?? true }
            guard moved.isEmpty else {
                let keys = moved.map { "T-\($0.id)" }.joined(separator: ", ")
                throw AgentError.invalid("\(keys) changed again since \(edit.command) by \(model.editor(edit)): put \(moved.count == 1 ? "it" : "them") back by hand (`hq task history`)")
            }
            var lines = reverted.map { "T-\($0.id): " + TaskEdit.fields($0.after, $0.before).joined(separator: ", ") }
            let created = edit.changes.filter { $0.before == nil }.map { "T-\($0.id)" }
            let deleted = edit.changes.filter { $0.after == nil }.map { "T-\($0.id)" }
            if !created.isEmpty { lines.append("Kept: \(created.joined(separator: ", ")), created by it (`hq task delete` removes a task)") }
            if !deleted.isEmpty { lines.append("Still deleted: \(deleted.joined(separator: ", ")), their notes are in the Trash") }
            let what = "\(edit.command) by \(model.editor(edit)), \(edit.at.formatted(date: .abbreviated, time: .shortened))"
            let keys = reverted.map { "T-\($0.id)" }
            guard args.confirmed else {
                return ["wouldRevert": keys, "text": "Would undo \(what):\n" + lines.joined(separator: "\n") + "\nAgain with --yes to undo."]
            }
            model.revert(edit)
            return ["reverted": keys, "text": "Undid \(what):\n" + lines.joined(separator: "\n")]
        },
        AgentCommand(name: "task link", summary: "Link a task to a PR or issue URL, any web page, another task, a session, a file or an artifact. It shows under the task's row.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12"),
                              .init(name: "item", required: true, positional: true, help: "a URL, T-34, a session id, or a file path"), notMine],
                     example: "hq task link T-12 https://github.com/acme/registry/pull/418") { args, model in
            let task = try ownTask(args, model)
            try linkItem(try args.required("item"), to: task.id, model)
            return model.task(task.id)?.agentJSON(model) ?? [:]
        },
        AgentCommand(name: "task unlink", summary: "Unlink what task link linked: a PR or issue URL, a task, a session, a file or an artifact.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12"),
                              .init(name: "item", required: true, positional: true, help: "a URL, T-34, a session id, or a file path"), notMine],
                     example: "hq task unlink T-12 T-34") { args, model in
            let task = try ownTask(args, model)
            let ref = try args.required("item")
            let route = try item(ref, model)
            guard model.isLinked(route, to: task.id) else { throw AgentError.notFound("\(task.key) doesn't link \(ref). `hq task show \(task.key)` lists its links") }
            model.unlink(route, from: task.id)
            return model.task(task.id)?.agentJSON(model) ?? [:]
        },
        AgentCommand(name: "link", summary: "Link a URL or a file to a task (the same as task link, the other way round).",
                     params: [.init(name: "item", required: true, positional: true, help: "a URL or a file path"),
                              .init(name: "task", required: true, positional: true, help: "T-12"), notMine],
                     example: "hq link \"2026-11-04 - Push plan.md\" T-12") { args, model in
            let task = try ownTask(args, model)
            try linkItem(try args.required("item"), to: task.id, model)
            return model.task(task.id)?.agentJSON(model) ?? [:]
        },
        AgentCommand(name: "project edit", summary: "Set a project's folder (where its sessions start) and GitHub repositories. Names a new project too.",
                     params: [.init(name: "project", required: true, positional: true, help: "its name, as on tasks"),
                              .init(name: "folder", help: "the folder its sessions start in; empty clears it"),
                              .init(name: "repo", help: "its GitHub repositories, owner/name, comma separated; empty clears them")],
                     example: "hq project edit Registry --folder ~/code/registry --repo acme/registry,acme/image-sync") { args, model in
            let name = try args.required("project").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw AgentError.usage("a project needs a name") }
            let folder = args.string("folder").map { ($0 as NSString).expandingTildeInPath }
            if let folder, !folder.isEmpty {
                var directory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: folder, isDirectory: &directory), directory.boolValue else {
                    throw AgentError.usage("no folder at \(folder)")
                }
            }
            let repos = args.string("repo").map { $0.split(separator: ",").map(String.init) }
            if let repos, let bad = repos.first(where: { AppModel.repoName($0).isEmpty && !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                throw AgentError.usage("\(bad) isn't owner/name")
            }
            model.setLinks(name, folder: folder.map { $0.isEmpty ? nil : $0 }, repos: repos)
            return model.projectJSON(name)
        },
        AgentCommand(name: "file new", summary: "Create a note in HQ's files, linked to this session (and --task), and print its path.",
                     params: [.init(name: "title", required: true, positional: true, help: "the note's title"),
                              .init(name: "task", help: "T-12: the task it belongs to (default: this session's, when it has one)"),
                              .init(name: "body", help: "the note in markdown; - reads stdin")],
                     example: "hq file new \"Push path plan\" --task T-12 --body -") { args, model in
            let session = model.session(args.string(sessionArg))
            let task = try args.string("task").map { ref in
                guard let task = model.task(TaskItem.key(ref)) else { throw AgentError.notFound("no task \(ref)") }
                return task.id
            } ?? session.flatMap { model.tasks(of: $0.id).count == 1 ? model.tasks(of: $0.id)[0].id : nil }
            guard let file = model.addFile(title: try args.required("title"), body: args.string("body") ?? "", session: session?.id, task: task) else {
                throw AgentError.invalid("could not create the note. Check that the vault is reachable")
            }
            return file.agentJSON
        },
        AgentCommand(name: "file show", summary: "Show a note's text, without its front matter.",
                     params: [.init(name: "file", required: true, positional: true, help: "the note's path, or its name (with or without .md)")],
                     example: "hq file show \"2026-11-03 - Push plan\"", readOnly: true) { args, model in
            let ref = try args.required("file")
            guard let file = model.file(ref: ref) else { throw AgentError.notFound("no note \(ref). Run `hq ls files`") }
            var json = file.agentJSON
            json["body"] = model.fileBody(file.id)
            return json
        },
        AgentCommand(name: "file write", summary: "Replace a note's text, or add to its end, keeping its front matter.",
                     params: [.init(name: "file", required: true, positional: true, help: "the note's path, or its name (with or without .md)"),
                              .init(name: "body", required: true, help: "the markdown; - reads stdin"),
                              .init(name: "append", kind: .boolean, help: "add to the end instead of replacing")],
                     example: "hq file write \"2026-11-03 - Push plan\" --append --body -") { args, model in
            let ref = try args.required("file")
            guard let file = model.file(ref: ref) else { throw AgentError.notFound("no note \(ref). Run `hq ls files`") }
            let body = try args.required("body")
            let current = model.fileBody(file.id)
            let text = try args.bool("append") == true
                ? current.trimmingCharacters(in: .newlines) + "\n\n" + body.trimmingCharacters(in: .newlines) + "\n"
                : body
            model.saveFileBody(file.id, text)
            if let session = args.string(sessionArg), model.session(session) != nil, !file.sessions.contains(session) {
                model.changeFile(file.id, "Link Session") { $0.sessions.append(session) }
            }
            return file.agentJSON
        },
        AgentCommand(name: "file delete", summary: "Delete a note, as Delete does in HQ: it goes to the Trash.",
                     params: [.init(name: "file", required: true, positional: true, help: "the note's path, or its name (with or without .md)")],
                     example: "hq file delete \"2026-11-03 - Push plan\" --yes", destructive: true) { args, model in
            let ref = try args.required("file")
            guard let file = model.file(ref: ref) else { throw AgentError.notFound("no note \(ref). Run `hq ls files`") }
            guard args.confirmed else { return ["wouldDelete": file.id, "text": "Would delete “\(file.title)” (\(file.id)). Again with --yes to delete."] }
            model.deleteFile(file.id)
            return ["deleted": file.id, "text": "Deleted “\(file.title)”: its note is in the Trash."]
        },
        AgentCommand(name: "artifact add", summary: "Add a claude.ai artifact HQ didn't capture, by its URL. Again with the same URL updates it.",
                     params: [.init(name: "url", required: true, positional: true, help: "https://claude.ai/artifact/…; a ?sk= share key is dropped"),
                              .init(name: "title", required: true, help: "its title"),
                              .init(name: "date", help: "when it was published, 2026-11-03 (default: now)"),
                              .init(name: "task", help: "T-12: the task it belongs to")],
                     example: "hq artifact add https://claude.ai/artifact/abc --title \"Bench speed\" --date 2026-11-03") { args, model in
            let raw = try args.required("url")
            guard let url = AppModel.artifactURL(raw) else { throw AgentError.usage("not a claude.ai artifact URL: \(raw)") }
            let title = try args.required("title").trimmingCharacters(in: .whitespaces)
            let date = try args.string("date").map { text in
                guard let date = NoteDate.parse(text) else { throw AgentError.usage("--date takes 2026-11-03") }
                return date
            }
            let task = try args.string("task").map { ref in
                guard let task = model.task(TaskItem.key(ref)) else { throw AgentError.notFound("no task \(ref). Run `hq ls tasks`") }
                return task.id
            }
            return model.importArtifact(url, title: title, published: date, task: task).agentJSON
        },
        AgentCommand(name: "notify", summary: "Tell the user something in HQ's notification center: work ready to check, a write-up done. --important for a ping they asked for, or when you can't go on without them.",
                     params: [.init(name: "text", required: true, positional: true, help: "what they should know, in a sentence or two: what is ready and what to check"),
                              .init(name: "important", kind: .boolean, help: "Needs You, with a banner: they asked to be pinged, or you are blocked on them"),
                              .init(name: "link", help: "what to open, comma-separated: T-12, a URL, a file, an artifact (default: this session's open tasks and what it made since its last notification)")],
                     example: "hq notify \"Retry budget ready to check: the canary is green\" --link T-12") { args, model in
            let text = try args.required("text").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw AgentError.usage("say what the user should know") }
            let session = model.session(args.string(sessionArg))?.id
            let links = try args.string("link").map { try noticeLinks($0, model) } ?? session.map { model.defaultLinks(forSession: $0) } ?? []
            let level: Notice.Level = try args.bool("important") == true ? .important : .update
            let row = model.notify(text, level: level, source: session, links: links)
            return model.noticeJSON(row, section: model.section(of: row))
        },
        AgentCommand(name: "remind", summary: "Set a reminder in HQ's notification center: it shows in Later, then comes back at its time.",
                     params: [.init(name: "text", required: true, positional: true, help: "what to remember, one line"),
                              .init(name: "at", required: true, help: "when: 16:00, in 2h, tomorrow 9:00, monday, 2026-11-09T09:00"),
                              .init(name: "important", kind: .boolean, help: "Needs You, with a banner, when it's due: the user asked to be reminded"),
                              .init(name: "link", help: "what to open, comma-separated: T-12, a URL, a file, an artifact")],
                     example: "hq remind \"Check the canary\" --at \"in 2h\" --important --link T-12") { args, model in
            let text = try args.required("text").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw AgentError.usage("say what to remember") }
            let raw = try args.required("at")
            guard let due = ReminderTime.parse(raw), due > .now else {
                throw AgentError.usage("--at \"\(raw)\" isn't a time to come: 16:00, in 2h, tomorrow 9:00, monday, 2026-11-09T09:00")
            }
            let links = try args.string("link").map { try noticeLinks($0, model) } ?? []
            let level: Notice.Level = try args.bool("important") == true ? .important : .update
            let row = model.remind(text, at: due, level: level, source: model.session(args.string(sessionArg))?.id, links: links)
            return model.noticeJSON(row, section: .later)
        },
        AgentCommand(name: "notification done", summary: "Mark a notification this session sent read, or a reminder it set done: it no longer needs the user.",
                     params: [.init(name: "id", required: true, positional: true, help: "its id from hq notify, hq remind or hq ls notifications; its first 8 characters do"),
                              .init(name: "not-mine", kind: .boolean, help: "one this session didn't send, that the user named")],
                     example: "hq notification done 3F2A9C1B") { args, model in
            let row = try ownNotice(args, model)
            model.setDone(row.id, true)
            let done = model.notices.first { $0.id == row.id } ?? row
            return model.noticeJSON(done, section: model.section(of: done))
        },
        AgentCommand(name: "notification delete", summary: "Delete a notification this session sent or a reminder it set: a ping that no longer holds, a follow-up done early.",
                     params: [.init(name: "id", required: true, positional: true, help: "its id from hq notify, hq remind or hq ls notifications; its first 8 characters do"),
                              .init(name: "not-mine", kind: .boolean, help: "one this session didn't send, that the user named")],
                     example: "hq notification delete 3F2A9C1B") { args, model in
            let row = try ownNotice(args, model)
            model.removeNotice(row.id)
            return ["deleted": row.id.uuidString, "text": row.text]
        },
        AgentCommand(name: "session new", summary: "Start a fresh, named Claude session in a new Ghostty tab. With --task it works on that task and is linked to it.",
                     params: [.init(name: "name", required: true, positional: true, help: "the session's name, short: \"T-12 Dedup layers\""),
                              .init(name: "task", help: "T-12: the task the new session works on"),
                              .init(name: "cwd", help: "its directory (default: this session's, else the current one)"),
                              .init(name: "message", help: "its first message, markdown; - reads stdin (default: one that sends it to the task)")],
                     example: "hq session new \"T-12 Dedup layers\" --task T-12") { args, model in
            var task: TaskItem?
            if let ref = args.string("task") {
                guard let found = model.task(TaskItem.key(ref)) else { throw AgentError.notFound("no task \(ref). Run `hq ls tasks`") }
                task = found
            }
            let caller = model.session(args.string(sessionArg))
            guard let directory = args.string("cwd").map({ ($0 as NSString).expandingTildeInPath }) ?? (caller?.cwd).flatMap({ $0.isEmpty ? nil : $0 }) ?? args.string(cwdArg) else {
                throw AgentError.usage("name a directory with --cwd")
            }
            guard FileManager.default.fileExists(atPath: (directory as NSString).expandingTildeInPath) else { throw AgentError.notFound("no directory \(directory)") }
            let name = try args.required("name").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw AgentError.usage("give the session a name") }
            let message = args.string("message") ?? task.map { AppModel.taskPrompt($0) } ?? ""
            let id = model.startSession(named: name, in: directory, task: task?.id, message: message)
            var json = model.session(id)?.agentJSON(model) ?? ["id": id]
            json["started"] = "a new Ghostty tab in \(directory)"
            return json
        },
        AgentCommand(name: "hook", summary: "Report a Claude Code hook event (used by the hq plugin). Always exits 0; while HQ is off, the event waits for its next launch.",
                     params: [.init(name: "event", help: "the hook's JSON, read from stdin by the CLI"),
                              .init(name: "pid", kind: .integer, help: "Claude's process, added by the CLI"),
                              .init(name: "tty", help: "Claude's terminal, added by the CLI"),
                              .init(name: "ghostty", kind: .boolean, help: "true when Claude runs in Ghostty, added by the CLI"),
                              .init(name: "at", help: "when it happened (ISO 8601), for an event HQ replays after being off")],
                     example: "echo '{\"hook_event_name\":\"Stop\",\"session_id\":\"…\"}' | hq hook") { args, model in
            model.lastHookEvent = .now
            guard let json = args.string("event"),
                  var event = HookEvent(json: Data(json.utf8), pid: args.string("pid").flatMap(Int32.init),
                                        tty: args.string("tty"), inGhostty: try args.bool("ghostty")) else {
                return ["received": false]
            }
            event.at = args.string("at").flatMap { try? Date($0, strategy: .iso8601) }
            model.receive(event)
            // SessionStart's stdout reaches Claude: a short note on what it works on.
            if event.name == "SessionStart" { return ["received": true, "context": model.startContext(event.sessionID)] }
            return ["received": true]
        },
    ]

    /// The Claude session that runs a command: the CLI adds it from CLAUDE_CODE_SESSION_ID.
    static let sessionArg = "_session"
    /// The directory the CLI runs in.
    static let cwdArg = "_cwd"

    /// `--parent`: under another task, as its last subtask, or out to the top of the list it's in.
    private static func moveUnder(_ id: Int, _ ref: String, _ model: AppModel) throws {
        let tree = model.taskTree
        if ref.isEmpty || ref.lowercased() == "none" {
            guard tree.parent(of: id) != nil else { return }
            let list = model.list(of: id)
            model.drop([id], into: .list(list), at: tree.top(list).count)
            return
        }
        guard let parent = model.task(TaskItem.key(ref)) else { throw AgentError.notFound("no task \(ref). Run `hq ls tasks`") }
        guard tree.parent(of: id) != parent.id else { return }
        guard model.drop([id], into: .task(parent.id), at: tree.children(of: parent.id).count) else {
            throw AgentError.usage("\(parent.key) is \(model.task(id)?.key ?? "the task") itself or one of its subtasks")
        }
    }

    private static func tags(_ text: String?) -> [String] {
        (text ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "") }.filter { !$0.isEmpty }
    }

    private static func findTask(_ args: Args, _ model: AppModel) throws -> TaskItem {
        let ref = try args.required("task")
        guard let task = model.task(TaskItem.key(ref)) else {
            throw AgentError.notFound("no task \(ref). Run `hq ls tasks`")
        }
        return task
    }

    static let notMine = AgentCommand.Param(name: "not-mine", kind: .boolean, help: "a task this session isn't on, that the user named")

    /// The task, when this session may change it: it's on it or on a task above it, or the user named it (--not-mine).
    /// A wrong key then fails, naming the task it hit. From a terminal, or a session HQ doesn't know, anything goes.
    private static func ownTask(_ args: Args, _ model: AppModel) throws -> TaskItem {
        let task = try findTask(args, model)
        try own(task, args, model)
        return task
    }

    /// The check every command that changes a task goes through, a parent for a new subtask included.
    private static func own(_ task: TaskItem, _ args: Args, _ model: AppModel) throws {
        guard let session = args.string(sessionArg), model.session(session) != nil, try args.bool("not-mine") != true else { return }
        let mine = ([task.id] + model.taskTree.ancestors(of: task.id)).contains { model.task($0)?.sessions.contains(session) == true }
        guard mine else {
            throw AgentError.notMine("\(task.key) is “\(task.title)”, a task this session isn't on. Check the key (`hq ls tasks`); "
                + "if it's the one the user means, run again with --not-mine")
        }
    }

    /// A notification by its id or the id's first characters, when this session sent or set it, or the user named it
    /// (--not-mine). From a terminal, or a session HQ doesn't know, anything goes.
    private static func ownNotice(_ args: Args, _ model: AppModel) throws -> Notice {
        let ref = try args.required("id").trimmingCharacters(in: .whitespaces).uppercased()
        let found = model.notices.filter { $0.id.uuidString.hasPrefix(ref) }
        guard ref.count >= 4, found.count == 1, let row = found.first else {
            throw AgentError.notFound(found.count > 1 ? "\(ref) starts several notifications: give more of its id"
                                                      : "no notification \(ref). Run `hq ls notifications --all`")
        }
        guard let session = args.string(sessionArg), model.session(session) != nil, try args.bool("not-mine") != true else { return row }
        guard row.source == session else {
            throw AgentError.notMine("“\(row.text)” isn't from this session. Check the id (`hq ls notifications --all`); "
                + "if it's the one the user means, run again with --not-mine")
        }
        return row
    }

    /// A URL, a session id or a file, linked to a task.
    private static func linkItem(_ ref: String, to id: Int, _ model: AppModel) throws {
        let route = try item(ref, model)
        guard route != .task(id) else { throw AgentError.usage("a task can't link to itself") }
        model.link(route, to: id)
    }

    /// What `task link` and `task unlink` name: a task, an artifact, any other URL, a session, a file.
    /// `T-12,https://…,Push plan`: each one's selection key.
    /// Comma-separated; a piece that names nothing joins the next one, so a file name with a comma still works.
    private static func noticeLinks(_ list: String, _ model: AppModel) throws -> [String] {
        var pieces = list.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        var keys: [String] = []
        while let first = pieces.first {
            var ref = first
            var taken = 1
            var route = try? item(ref.trimmingCharacters(in: .whitespaces), model)
            while route == nil, taken < pieces.count {
                ref += "," + pieces[taken]
                taken += 1
                route = try? item(ref.trimmingCharacters(in: .whitespaces), model)
            }
            let piece = first.trimmingCharacters(in: .whitespaces)
            if let route {
                keys.append(route.selectionKey)
                pieces.removeFirst(taken)
            } else if piece.isEmpty {
                pieces.removeFirst()
            } else {
                _ = try item(piece, model)
            }
        }
        return keys
    }

    private static func item(_ ref: String, _ model: AppModel) throws -> ModalRoute {
        if ref.uppercased().hasPrefix("T-"), let other = TaskItem.key(ref) {
            guard model.task(other) != nil else { throw AgentError.notFound("no task \(ref). Run `hq ls tasks`") }
            return .task(other)
        }
        if let artifact = model.artifacts.first(where: { $0.id.absoluteString == ref }) ?? AppModel.artifactURL(ref).flatMap({ url in
            model.artifacts.first { $0.id == url }
        }) {
            return .artifact(artifact.id)
        }
        if let url = URL(string: ref), url.scheme == "https" || url.scheme == "http" {
            return GitHubLinks.isItem(ref) ? .github(ref) : SlackLink.isLink(ref) ? .slack(ref) : .web(ref)
        }
        if let session = model.session(ref) ?? model.session(prefix: ref) { return .session(session.id) }
        if let file = model.file(ref: ref) { return .file(file.id) }
        throw AgentError.notFound("nothing called \(ref). Use a URL, a session id, a file under hq/files, or an artifact URL")
    }

    /// A session that adds a task, starts it or ships it through hq shows on it; edits alone don't link it.
    private static func link(_ id: Int, _ args: Args, _ model: AppModel) {
        guard let session = args.string(sessionArg), model.session(session) != nil,
              let task = model.task(id), !task.sessions.contains(session) else { return }
        model.link(task: id, session: session)
    }
}

extension SessionItem {
    func agentJSON(_ model: AppModel) -> JSONObject {
        var json: JSONObject = ["id": id, "name": name, "state": status.title, "since": JSON.date(status.since),
                                "cwd": cwd, "branch": branch, "tasks": model.tasks(of: id).map(\.key)]
        if let reason { json["reason"] = reason }
        if closedAt != nil { json["closed"] = true }
        return json
    }
}

extension TaskItem {
    func agentJSON(_ model: AppModel) -> JSONObject {
        var json: JSONObject = ["id": key, "title": title, "status": status.rawValue,
                                "list": model.list(of: id).rawValue, "tags": tags, "sessions": sessions,
                                "modified": JSON.date(modified)]
        if let project { json["project"] = project }
        if let parent { json["parent"] = "T-\(parent)" }
        if !links.isEmpty { json["links"] = links.map(\.absoluteString) }
        if !related.isEmpty { json["related"] = related.map { "T-\($0)" } }
        if let path { json["path"] = path }
        return json
    }
}

extension FileItem {
    var agentJSON: JSONObject {
        var json: JSONObject = ["path": path ?? "hq/files/\(id)", "title": title, "modified": JSON.date(modified)]
        if !tasks.isEmpty { json["tasks"] = tasks.map { "T-\($0)" } }
        return json
    }
}

extension ArtifactItem {
    var agentJSON: JSONObject {
        var json: JSONObject = ["url": id.absoluteString, "title": title, "published": JSON.date(published)]
        if !tasks.isEmpty { json["tasks"] = tasks.map { "T-\($0)" } }
        return json
    }
}

extension TaskItem {
    /// A parent or a subtask in `task show`: its key, status and title.
    var briefJSON: JSONObject { ["id": key, "status": status.rawValue, "title": title] }
}

extension AppModel {
    /// What `task show` lists as linked: the files, artifacts, PRs, issues and tasks under the task's row.
    func linkJSON(_ route: ModalRoute) -> JSONObject {
        switch route {
        case .file(let id): ["kind": "file", "title": title(of: route), "path": file(id)?.path ?? "hq/files/\(id)"]
        case .artifact(let url): ["kind": "artifact", "title": title(of: route), "url": url.absoluteString]
        case .github(let url):
            if let item = githubItem(url) {
                ["kind": item.kind == .issue ? "issue" : "pr", "title": title(of: route), "state": item.state.rawValue, "url": url]
            } else {
                ["kind": "github", "title": title(of: route), "url": url]
            }
        case .task(let id): ["kind": "task", "id": "T-\(id)", "status": task(id)?.status.rawValue ?? "", "title": title(of: route)]
        case .session(let id): ["kind": "session", "id": id, "title": title(of: route)]
        case .web(let url): ["kind": "web", "title": title(of: route), "url": url]
        case .slack(let url): ["kind": "slack", "title": title(of: route), "url": url]
        case .start, .closedSessions, .notifications, .newTask, .newReminder: ["kind": "other", "title": title(of: route)]
        }
    }

    func noticeJSON(_ row: Notice, section: NoticeSection) -> JSONObject {
        var json: JSONObject = ["id": row.id.uuidString, "section": "\(section)", "level": row.level.rawValue, "kind": row.kind.rawValue,
                                "text": row.text, "at": JSON.date(row.at),
                                "links": row.links.compactMap { ModalRoute(noticeKey: $0).map(linkJSON) }]
        if let source = row.source { json["source"] = source }
        if row.count > 1 { json["count"] = row.count }
        if let due = row.dueAt { json["due"] = JSON.date(due) }
        if let read = row.readAt { json["read"] = JSON.date(read) }
        return json
    }
}

extension GitHubItem {
    var agentJSON: JSONObject {
        ["url": url, "title": title, "kind": kind.rawValue, "state": state.rawValue, "repo": repo, "number": number,
         "author": author, "review": review.rawValue, "checks": checks.rawValue, "reviewRequested": reviewRequested,
         "approved": approved, "updated": updatedAt.formatted(.iso8601)]
    }
}
