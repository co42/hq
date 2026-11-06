import Foundation
import HQKit

/// Everything an agent can do in hq. Add a command here and the CLI and `help` get it.
/// Each `run` is on the main actor with the app's model, like a button in the window.
enum AgentCommands {
    static let all: [AgentCommand] = [
        AgentCommand(name: "status", summary: "Show whether HQ runs and what needs the user.",
                     example: "hq status --json", readOnly: true) { _, model in
            ["running": true, "needsYou": model.needsYouCount, "new": model.newCount, "sessions": model.gridSessions.count,
             "tasks": model.tasks.count, "files": model.files.count, "artifacts": model.artifacts.count]
        },
        AgentCommand(name: "ctx", summary: "Show this session's tasks, the overview's tasks in Review and Doing, recent files, and the other open sessions.",
                     params: [.init(name: "session", help: "a session id (default: the Claude session running the command)")],
                     example: "hq ctx --json", readOnly: true) { args, model in
            let id = args.string("session") ?? args.string(sessionArg)
            guard let session = model.session(id) ?? (id.flatMap { model.session(prefix: $0) }) else {
                throw AgentError.notFound("no session \(id ?? "here"). Run it inside a Claude session, or pass --session <id>")
            }
            let mine = model.tasks(of: session.id)
            let overview = model.taskTree.outline(.overview).compactMap { model.task($0) }
                .filter { ($0.status == .review || $0.status == .doing) && !mine.contains($0) }
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
        AgentCommand(name: "ls", summary: "List sessions, tasks, prs, files, artifacts or projects.",
                     params: [.init(name: "kind", positional: true, help: "sessions (default), tasks, prs, files, artifacts or projects"),
                              .init(name: "overview", kind: .boolean, help: "tasks: only the overview's Tasks"),
                              .init(name: "backlog", kind: .boolean, help: "tasks: only the Backlog"),
                              .init(name: "all", kind: .boolean, help: "include closed sessions and done tasks"),
                              .init(name: "type", help: "tasks: story, bug, feature, chore, research or docs"),
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
                items = (all ? model.sessions.sorted { $0.order < $1.order } : model.gridSessions + model.hiddenSessions).map { $0.agentJSON(model) }
            case "tasks":
                let tree = model.taskTree
                let overview = try args.bool("overview") ?? false
                let backlog = try args.bool("backlog") ?? false
                let type = try args.string("type").map { try taskType($0) }
                var ids: [Int] = []
                if !backlog { ids += tree.outline(.overview) }
                if !overview { ids += tree.outline(.backlog) }
                items = ids.compactMap { model.task($0) }.filter { task in
                    (all || task.status != .done) && (type == nil || task.type == type)
                        && (args.string("project").map { $0.caseInsensitiveCompare(task.project ?? "") == .orderedSame } ?? true)
                        && (args.string("tag").map { tag in task.tags.contains(tag.replacingOccurrences(of: "#", with: "")) } ?? true)
                }.map { $0.agentJSON(model) }
            case "prs":
                items = ((model.github?.items ?? []).filter { all || $0.state == .open || $0.state == .draft }).map(\.agentJSON)
            case "files":
                items = model.files.sorted { $0.modified > $1.modified }.map(\.agentJSON)
            case "artifacts":
                items = model.artifacts.sorted { $0.published > $1.published }.map(\.agentJSON)
            case "projects":
                items = model.allProjects.map { model.projectJSON($0) }
            default:
                throw AgentError.usage("no kind \"\(kind)\". Kinds: sessions, tasks, prs, files, artifacts, projects")
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
        AgentCommand(name: "task add", summary: "Create a task, in the Backlog unless --now (Claude works on it now, with the user) or --parent.",
                     params: [.init(name: "title", required: true, positional: true, help: "what to do, short; #words set a status, a type or a project they name, else become tags"),
                              .init(name: "type", help: "story, bug, feature, chore, research or docs: set it"),
                              .init(name: "project", help: "the project it belongs to"),
                              .init(name: "tag", help: "tags, comma separated"),
                              .init(name: "parent", help: "T-12: a subtask of that task"),
                              .init(name: "now", kind: .boolean, help: "at the end of Tasks, on the overview"),
                              .init(name: "status", help: "todo (default), doing (also puts it on Tasks), review or done"),
                              .init(name: "body", help: "the description in markdown; - reads stdin")],
                     example: "hq task add \"Dedup layers on push\" --type feature --now --body -") { args, model in
            let titled = TitleTags.split((try? args.required("title")) ?? "").tags.compactMap { word -> TaskStatus? in
                if case .status(let status) = model.titleWord(word) { status } else { nil }
            }.last
            let status = try args.string("status").map { raw in
                guard let status = TaskStatus(parsing: raw) else { throw AgentError.usage(raw.lowercased() == "story" ? "story is a type: --type story" : "no status \"\(raw)\". Statuses: todo, doing, review, done") }
                return status
            } ?? titled ?? .todo
            let session = model.session(args.string(sessionArg))
            let tree = model.taskTree
            let placed: (TaskTree.Placement, changes: [Int: TaskTree.Placement])?
            if let ref = args.string("parent") {
                guard let parent = model.task(TaskItem.key(ref)) else { throw AgentError.notFound("no task \(ref). Run `hq ls tasks`") }
                placed = tree.placeNew(in: .task(parent.id))
            } else if try args.bool("now") == true || status == .doing {
                placed = tree.placeNew(in: .list(.overview))
            } else {
                placed = tree.placeNew(in: .list(.backlog), at: 0)
            }
            guard let (placement, renumber) = placed,
                  let task = model.addTask(title: try args.required("title"), placement: placement, status: status,
                                           type: try args.string("type").map { try taskType($0) }, project: args.string("project"),
                                           tags: tags(args.string("tag")), body: args.string("body") ?? "", session: session?.id, renumber: renumber) else {
                throw AgentError.invalid("could not create the task. Check that the vault is reachable")
            }
            return task.agentJSON(model)
        },
        AgentCommand(name: "task move", summary: "Set a task's status. Review needs --reason: what the user must check, with its link in the description.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12"),
                              .init(name: "status", required: true, positional: true, help: "todo, doing (also brings it to Tasks), review or done (backlog: todo, in the Backlog)"),
                              .init(name: "reason", help: "with review: one line, what the user must check")],
                     example: "hq task move T-12 review --reason \"PR #418 is ready to merge\"") { args, model in
            let task = try findTask(args, model)
            let raw = try args.required("status").lowercased()
            if raw == "backlog" {
                model.setStatus(task.id, .todo)
                model.move(task.id, to: .backlog)
            } else {
                guard let status = TaskStatus(rawValue: raw) else {
                    throw AgentError.usage(raw.lowercased() == "story" ? "story is a type: --type story" : "no status \"\(raw)\". Statuses: todo, doing, review, done")
                }
                if status == .review, (args.string("reason") ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                    throw AgentError.usage("review needs --reason \"…\": one line saying what the user must check")
                }
                model.setStatus(task.id, status, reason: status == .review ? args.string("reason") : nil)
                // Work started: a top-level task in the Backlog comes to Tasks.
                if status == .doing, task.parent == nil, model.list(of: task.id) == .backlog { model.move(task.id, to: .overview) }
                // The session works on it, or shipped it.
                if status == .doing || status == .review { link(task.id, args, model) }
            }
            return model.task(task.id)?.agentJSON(model) ?? [:]
        },
        AgentCommand(name: "task edit", summary: "Change a task's title, description, type, project, tags or parent. Everything else stays.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12"),
                              .init(name: "title", help: "the new title"),
                              .init(name: "body", help: "the new description in markdown; - reads stdin"),
                              .init(name: "type", help: "story, bug, feature, chore, research or docs"),
                              .init(name: "project", help: "the project; empty clears it"),
                              .init(name: "add-tag", help: "tags to add, comma separated"),
                              .init(name: "remove-tag", help: "tags to remove, comma separated"),
                              .init(name: "parent", help: "T-34: its last subtask, in its list; none: top level, in the list it's in")],
                     example: "hq task edit T-12 --body - --add-tag perf") { args, model in
            let task = try findTask(args, model)
            if let ref = args.string("parent")?.trimmingCharacters(in: .whitespaces) {
                try moveUnder(task.id, ref, model)
            }
            let type = try args.string("type").map { try taskType($0) }
            let added = tags(args.string("add-tag"))
            let removed = Set(tags(args.string("remove-tag")))
            model.changeTask(task.id, "Edit Task") { task in
                if let body = args.string("body") { task.body = body.trimmingCharacters(in: .newlines) }
                if let type { task.type = type }
                if let project = args.string("project") { task.project = project.isEmpty ? nil : project }
                task.tags = task.tags.filter { !removed.contains($0) } + added.filter { !task.tags.contains($0) }
            }
            if let title = args.string("title"), !title.isEmpty { model.setTitle(task.id, title) }
            return model.task(task.id)?.agentJSON(model) ?? [:]
        },
        AgentCommand(name: "task link", summary: "Link a task to a PR or issue URL, another task, a session, a file or an artifact. It shows under the task's row.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12"),
                              .init(name: "item", required: true, positional: true, help: "a URL, T-34, a session id, or a file path")],
                     example: "hq task link T-12 https://github.com/acme/registry/pull/418") { args, model in
            let task = try findTask(args, model)
            try linkItem(try args.required("item"), to: task.id, model)
            return model.task(task.id)?.agentJSON(model) ?? [:]
        },
        AgentCommand(name: "task unlink", summary: "Unlink what task link linked: a PR or issue URL, a task, a session, a file or an artifact.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12"),
                              .init(name: "item", required: true, positional: true, help: "a URL, T-34, a session id, or a file path")],
                     example: "hq task unlink T-12 T-34") { args, model in
            let task = try findTask(args, model)
            let ref = try args.required("item")
            let route = try item(ref, model)
            guard model.isLinked(route, to: task.id) else { throw AgentError.notFound("\(task.key) doesn't link \(ref). `hq task show \(task.key)` lists its links") }
            model.unlink(route, from: task.id)
            return model.task(task.id)?.agentJSON(model) ?? [:]
        },
        AgentCommand(name: "link", summary: "Link a URL or a file to a task (the same as task link, the other way round).",
                     params: [.init(name: "item", required: true, positional: true, help: "a URL or a file path"),
                              .init(name: "task", required: true, positional: true, help: "T-12")],
                     example: "hq link \"2026-11-04 - Push plan.md\" T-12") { args, model in
            let task = try findTask(args, model)
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
        AgentCommand(name: "hook", summary: "Report a Claude Code hook event (used by the hq plugin). Always exits 0.",
                     params: [.init(name: "event", help: "the hook's JSON, read from stdin by the CLI"),
                              .init(name: "pid", kind: .integer, help: "Claude's process, added by the CLI"),
                              .init(name: "tty", help: "Claude's terminal, added by the CLI"),
                              .init(name: "ghostty", kind: .boolean, help: "true when Claude runs in Ghostty, added by the CLI")],
                     example: "echo '{\"hook_event_name\":\"Stop\",\"session_id\":\"…\"}' | hq hook") { args, model in
            model.lastHookEvent = .now
            guard let json = args.string("event"),
                  let event = HookEvent(json: Data(json.utf8), pid: args.string("pid").flatMap(Int32.init),
                                        tty: args.string("tty"), inGhostty: try args.bool("ghostty")) else {
                return ["received": false]
            }
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

    private static func taskType(_ text: String) throws -> TaskType {
        guard let type = TaskType(parsing: text) else {
            throw AgentError.usage("no type \"\(text)\". Types: story, bug, feature, chore, research, docs")
        }
        return type
    }

    private static func findTask(_ args: Args, _ model: AppModel) throws -> TaskItem {
        let ref = try args.required("task")
        guard let task = model.task(TaskItem.key(ref)) else {
            throw AgentError.notFound("no task \(ref). Run `hq ls tasks`")
        }
        return task
    }

    /// A URL, a session id or a file, linked to a task.
    private static func linkItem(_ ref: String, to id: Int, _ model: AppModel) throws {
        let route = try item(ref, model)
        guard route != .task(id) else { throw AgentError.usage("a task can't link to itself") }
        model.link(route, to: id)
    }

    /// What `task link` and `task unlink` name: a task, an artifact, any other URL, a session, a file.
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
        if let url = URL(string: ref), url.scheme == "https" || url.scheme == "http" { return .github(ref) }
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
        if hidden { json["hidden"] = true }
        if closedAt != nil { json["closed"] = true }
        return json
    }
}

extension TaskItem {
    func agentJSON(_ model: AppModel) -> JSONObject {
        var json: JSONObject = ["id": key, "title": title, "status": status.rawValue,
                                "list": model.list(of: id).rawValue, "tags": tags, "sessions": sessions,
                                "modified": JSON.date(modified)]
        if let type { json["type"] = type.rawValue }
        if let project { json["project"] = project }
        if let parent { json["parent"] = "T-\(parent)" }
        if let review, status == .review { json["review"] = review }
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
        case .start, .hiddenAndClosed: ["kind": "other", "title": title(of: route)]
        }
    }
}

extension GitHubItem {
    var agentJSON: JSONObject {
        ["url": url, "title": title, "kind": kind.rawValue, "state": state.rawValue, "repo": repo, "number": number,
         "author": author, "review": review.rawValue, "checks": checks.rawValue, "reviewRequested": reviewRequested]
    }
}
