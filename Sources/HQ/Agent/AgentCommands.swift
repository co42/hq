import Foundation
import HQKit

/// Everything an agent can do in hq. Add a command here and the CLI and `help` get it.
/// Each `run` is on the main actor with the app's model, like a button in the window.
enum AgentCommands {
    static let all: [AgentCommand] = [
        AgentCommand(name: "status", summary: "Show whether HQ runs, which build, and what needs the user.",
                     example: "hq status --json",
                     output: "{running, version, startedAt, needsYou, updates, sessions, tasks, files, artifacts}", readOnly: true) { _, model in
            ["running": true, "version": AgentVersion.atLaunch, "startedAt": JSON.date(AgentVersion.launchedAt),
             "needsYou": model.importantCount, "updates": model.updateCount, "sessions": model.gridSessions.count,
             "tasks": model.tasks.count, "files": model.files.count, "artifacts": model.artifacts.count]
        },
        AgentCommand(name: "ctx", summary: "Show this session's role, the session that started it, its tasks, the sessions it started with their role, state and task, "
                        + "what is doing in its project, recent files and artifacts, and the other open sessions.",
                     params: [.init(name: "session", help: "a session id (default: the Claude session running the command)"),
                              .init(name: "all", kind: .boolean, help: "the tasks doing in every project, not only this session's")],
                     example: "hq ctx",
                     output: "{text, session, startedBy: session, team: [session with depth], tasks: [task], overview: [task], elsewhere, files: [file], artifacts: [artifact], sessions: [session]}",
                     readOnly: true) { args, model in try contextCommand(args, model) },
        AgentCommand(name: "ls", summary: "List sessions, tasks, prs, files, artifacts, projects, notifications, reminders or roles. A list that is cut says so on its last line.",
                     params: [.init(name: "kind", positional: true, help: "sessions (default), tasks, prs (Reviews, then Yours, as on the page), files, artifacts, projects, notifications (--all: with what was read today), reminders or roles"),
                              .init(name: "here", kind: .boolean, help: "sessions: only the ones in this repository (or this folder)"),
                              .init(name: "tree", kind: .boolean, help: "sessions: the top-level ones, each with the sessions it started under it, indented"),
                              .init(name: "overview", kind: .boolean, help: "tasks: only the overview's Tasks"),
                              .init(name: "backlog", kind: .boolean, help: "tasks: only the Backlog"),
                              .init(name: "parent", help: "tasks: T-12's subtasks, the whole tree under it"),
                              .init(name: "project", help: "tasks: only this project"),
                              .init(name: "tag", help: "tasks: only with this tag"),
                              .init(name: "all", kind: .boolean, help: "sessions: closed ones too; tasks: done ones too; prs: merged and closed too; notifications: read today too"),
                              .init(name: "limit", kind: .integer, help: "at most this many (default 50; tasks with --overview, --project or --parent: all)"),
                              .init(name: "offset", kind: .integer, help: "skip this many, for the next page")],
                     example: "hq ls tasks --parent T-12",
                     output: "{<kind>: [item], total, nextOffset (when cut)}; a task {id, title, status, list, project, parent, tags, links, sessions, state, flow, blocked, blockedBy, after}, a session {id, name, state, since, cwd, branch, tasks, role, parent, thisSession, depth (--tree)}, a file {name, title, path, modified, tasks}, a notification {id, section, level, kind, text, at, due, when, links}, a role {name, color, line, builtin, changed, sessions}",
                     readOnly: true) { args, model in try listCommand(args, model) },
        AgentCommand(name: "task show", summary: "Show tasks: the tasks each is part of, its reminders, its description, the tree under it and what's linked to it.",
                     params: [.init(name: "task", required: true, positional: true, list: true, help: "T-12, or several: T-12 T-13"),
                              .init(name: "deep", kind: .boolean, help: "each open subtask's description under its line"),
                              .init(name: "brief", kind: .boolean, help: "no description: its line, the tree and the links"),
                              .init(name: "body", kind: .boolean, help: "the description only")],
                     example: "hq task show T-12 --deep",
                     output: "{id, title, status, list, project, parent, tags, links, state, flow, body, parents: [{id, status, title}], reminders: [notification], subtasks: [{id, status, title, depth, parent, flow, progress, body (--deep)}], progress, ready, blockedTasks: [{id, why}], linked: [{kind, title, id | name | url, state}]}; several tasks: {shown: [that]}",
                     readOnly: true) { args, model in try showCommand(args, model) },
        AgentCommand(name: "task block", summary: "Mark a task Blocked: you or the user can't do it now. The reason is optional; it holds until task unblock.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12"),
                              .init(name: "reason", positional: true, help: "why, in a few words: who or what it waits for (optional)"), notMine],
                     example: "hq task block T-12 \"Waiting on the CPU / RAM / disk decision\"", output: taskOutput) { args, model in
            let task = try ownTask(args, model)
            guard task.status != .done else { throw AgentError.invalid("\(task.key) is done: a done task can't be blocked") }
            model.block(task.id, reason: args.string("reason"))
            return model.task(task.id)?.agentJSON(model) ?? [:]
        },
        AgentCommand(name: "task unblock", summary: "Clear a task's Blocked. Links to the tasks it's blocked by stay: task unlink --blocked-by removes one.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12"), notMine],
                     example: "hq task unblock T-12", output: taskOutput) { args, model in
            let task = try ownTask(args, model)
            model.unblock(task.id)
            return model.task(task.id)?.agentJSON(model) ?? [:]
        },
        AgentCommand(name: "task add", summary: "Create a task, at the end of Tasks; at the top of the Backlog with --backlog, only when the user asks for the Backlog; "
                        + "under a task with --parent, in its project. Its line starts with its key; -q prints the key alone.",
                     params: [.init(name: "title", required: true, positional: true, help: "what to do, short; #words set a status or a project they name, else become tags; a title starting with -- goes after a bare --"),
                              .init(name: "project", help: "the project it belongs to (default: the parent's, for a subtask)"),
                              .init(name: "tag", list: true, help: "tags, comma separated"),
                              .init(name: "parent", help: "T-12: a subtask of that task"),
                              .init(name: "backlog", kind: .boolean, help: "at the top of the Backlog: only when the user says Backlog"),
                              .init(name: "status", help: "todo (default), doing (also puts it on Tasks) or done"),
                              .init(name: "link", list: true, help: "what to link to it, comma separated: a PR or issue URL, any web page, T-34, a file, an artifact URL"),
                              .init(name: "body", help: "the description in markdown; - reads stdin"), notMine],
                     example: "hq task add \"Dedup layers on push\" --project Registry --link https://github.com/acme/registry/pull/418 -q",
                     output: taskOutput) { args, model in try addCommand(args, model) },
        AgentCommand(name: "task move", summary: "Set a task's status: todo, doing or done; --list moves it to Tasks or the Backlog too. "
                        + "When the user must check something, keep it doing and tell them with hq notify.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12"),
                              .init(name: "status", required: true, positional: true, help: "todo, doing (also brings it to Tasks) or done (backlog: todo, in the Backlog)"),
                              .init(name: "list", help: "tasks or backlog: also move it there, as a top-level task"),
                              notMine],
                     example: "hq task move T-12 todo --list tasks", output: taskOutput) { args, model in try moveCommand(args, model) },
        AgentCommand(name: "task edit", summary: "Change a task's title, description, project, tags or parent. Everything else stays. "
                        + "--section and --replace change one part of the description; --body alone replaces it all, and is refused when it changed since this session read it.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12"),
                              .init(name: "title", help: "the new title"),
                              .init(name: "body", help: "the new description in markdown, or with --section that section's; - reads stdin"),
                              .init(name: "section", help: "Status: replace the text under that heading (added at the end when there's none) with --body"),
                              .init(name: "replace", help: "an exact text of the description, found once, to change"),
                              .init(name: "with", help: "what --replace becomes (empty removes it)"),
                              .init(name: "force", kind: .boolean, help: "--body writes over a description that changed since this session read it"),
                              .init(name: "project", help: "the project; empty clears it"),
                              .init(name: "add-tag", list: true, help: "tags to add, comma separated"),
                              .init(name: "remove-tag", list: true, help: "tags to remove, comma separated"),
                              .init(name: "parent", help: "T-34: its last subtask, in its list; none: top level, in the list it's in"),
                              notMine],
                     example: "hq task edit T-12 --section Status --body -", output: taskOutput + "; note: what changed") { args, model in try editCommand(args, model) },
        AgentCommand(name: "task tick", summary: "Tick one checklist item of a task's description, found by the start of its text; --untick clears it. Prints how many are ticked.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12"),
                              .init(name: "item", required: true, positional: true, help: "the start of the item's text, enough to name one"),
                              .init(name: "untick", kind: .boolean, help: "clear its box instead"), notMine],
                     example: "hq task tick T-12 \"At most 3 attempts\"", output: taskOutput + "; ticked: the item, done, total, text") { args, model in try tickCommand(args, model) },
        AgentCommand(name: "task delete", summary: "Delete a task and its subtasks, as Delete does in HQ: their notes go to the Trash.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12"), notMine],
                     example: "hq task delete T-12 --yes", output: "{deleted: [keys]}, or without --yes {wouldDelete: [keys]}", destructive: true) { args, model in
            let task = try ownTask(args, model)
            let keys = model.taskTree.subtree(of: task.id).compactMap { model.task($0)?.key }
            let named = keys.joined(separator: ", ")
            guard args.confirmed else { return ["wouldDelete": keys, "text": "Would delete \(named). Again with --yes to delete."] }
            model.deleteTasks([task.id])
            return ["deleted": keys, "text": "Deleted \(named): \(keys.count == 1 ? "its note is" : "their notes are") in the Trash."]
        },
        AgentCommand(name: "task history", summary: "What sessions changed in a task through hq in the last 30 days, the latest first. task undo reverts the latest.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12")],
                     example: "hq task history T-12", output: "{edits: [{at, command, by, session, changes, tasks}], text}", readOnly: true) { args, model in
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
                     example: "hq task undo T-12 --yes", output: "{reverted: [keys]}, or without --yes {wouldRevert: [keys]}", destructive: true) { args, model in
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
        AgentCommand(name: "task link", summary: "Link a task to a PR or issue URL, any web page, another task, a session, a file or an artifact: it shows on the task's card. "
                        + "--blocked-by T-34: it can't go on until T-34 is done. --after T-34: it comes after T-34, the order you mean; nothing moves.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12"),
                              .init(name: "item", positional: true, help: "a URL, T-34, a session id, or a file name"),
                              .init(name: "blocked-by", help: "T-34: blocked until T-34 is done"),
                              .init(name: "after", help: "T-34: comes after T-34"), notMine],
                     example: "hq task link T-12 --blocked-by T-34", output: taskOutput) { args, model in
            let task = try ownTask(args, model)
            if let (link, other) = try flowLink(args, model) {
                if let refusal = model.addLink(task.id, link, other) { throw AgentError.invalid(refusalText(refusal, task.key, link, "T-\(other)")) }
            } else {
                try linkItem(try args.required("item"), to: task.id, model)
            }
            return model.task(task.id)?.agentJSON(model) ?? [:]
        },
        AgentCommand(name: "task unlink", summary: "Unlink what task link linked: a PR or issue URL, a task, a session, a file or an artifact; or --blocked-by T-34, --after T-34.",
                     params: [.init(name: "task", required: true, positional: true, help: "T-12"),
                              .init(name: "item", positional: true, help: "a URL, T-34, a session id, or a file name"),
                              .init(name: "blocked-by", help: "T-34: no longer blocked by T-34"),
                              .init(name: "after", help: "T-34: no longer after T-34"), notMine],
                     example: "hq task unlink T-12 T-34", output: taskOutput) { args, model in
            let task = try ownTask(args, model)
            if let (link, other) = try flowLink(args, model) {
                guard (link == .blockedBy ? task.blockedBy : task.after).contains(other) else {
                    throw AgentError.notFound("\(task.key) isn't \(link == .blockedBy ? "blocked by" : "after") T-\(other). `hq task show \(task.key)` shows its links")
                }
                model.removeLink(task.id, link, other)
                return model.task(task.id)?.agentJSON(model) ?? [:]
            }
            let ref = try args.required("item")
            let route = try item(ref, model)
            guard model.isLinked(route, to: task.id) else { throw AgentError.notFound("\(task.key) doesn't link \(ref). `hq task show \(task.key)` lists its links") }
            model.unlink(route, from: task.id)
            return model.task(task.id)?.agentJSON(model) ?? [:]
        },
        AgentCommand(name: "project edit", summary: "Set a project's folder (where its sessions start) and GitHub repositories. Names a new project too.",
                     params: [.init(name: "project", required: true, positional: true, help: "its name, as on tasks"),
                              .init(name: "folder", help: "the folder its sessions start in; empty clears it"),
                              .init(name: "repo", list: true, help: "its GitHub repositories, owner/name, comma separated; empty clears them")],
                     example: "hq project edit Registry --folder ~/code/registry --repo acme/registry,acme/image-sync", output: "{name, openTasks, folder | folderGuess, repos}") { args, model in
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
        AgentCommand(name: "file new", summary: "Create a note in HQ's files, named \"<today> - <title>\", linked to this session (and --task), and print its name.",
                     params: [.init(name: "title", required: true, positional: true, help: "the note's title, without a date (one in front becomes the note's date)"),
                              .init(name: "task", help: "T-12: the task it belongs to (default: this session's, when it has one)"),
                              .init(name: "body", help: "the note in markdown; - reads stdin")],
                     example: "hq file new \"Push path plan\" --task T-12 --body -", output: fileOutput) { args, model in try newFileCommand(args, model) },
        AgentCommand(name: "file show", summary: "Show a note's text, without its front matter.",
                     params: [.init(name: "file", required: true, positional: true, help: "its name as file new printed it (.md optional), its path, or its title")],
                     example: "hq file show \"2026-11-03 - Push plan\"", output: fileOutput + "; body", readOnly: true) { args, model in
            let file = try findFile(args, model)
            var json = file.agentJSON
            json["body"] = model.fileBody(file.id)
            return json
        },
        AgentCommand(name: "file write", summary: "Replace a note's text, one ## section of it (--section), one exact text in it (--replace), or add to its end; its front matter stays.",
                     params: [.init(name: "file", required: true, positional: true, help: "its name as file new printed it (.md optional), its path, or its title"),
                              .init(name: "body", help: "the markdown, or with --section that section's; - reads stdin"),
                              .init(name: "append", kind: .boolean, help: "add --body to the end instead of replacing"),
                              .init(name: "section", help: "Findings: replace the text under that heading (added at the end when there's none) with --body"),
                              .init(name: "replace", help: "an exact text of the note, found once, to change"),
                              .init(name: "with", help: "what --replace becomes (empty removes it)")],
                     example: "hq file write \"2026-11-03 - Push plan\" --section \"Next steps\" --body -", output: fileOutput) { args, model in try writeFileCommand(args, model) },
        AgentCommand(name: "file delete", summary: "Delete a note, as Delete does in HQ: it goes to the Trash.",
                     params: [.init(name: "file", required: true, positional: true, help: "its name as file new printed it (.md optional), its path, or its title")],
                     example: "hq file delete \"2026-11-03 - Push plan\" --yes", output: "{deleted: name}, or without --yes {wouldDelete: name}",
                     destructive: true) { args, model in
            let file = try findFile(args, model)
            guard args.confirmed else { return ["wouldDelete": file.id, "text": "Would delete “\(file.title)” (\(file.id)). Again with --yes to delete."] }
            model.deleteFile(file.id)
            return ["deleted": file.id, "text": "Deleted “\(file.title)”: its note is in the Trash."]
        },
        AgentCommand(name: "artifact add", summary: "Add a claude.ai artifact HQ didn't capture, by its URL. Again with the same URL updates it.",
                     params: [.init(name: "url", required: true, positional: true, help: "https://claude.ai/artifact/…; a ?sk= share key is dropped"),
                              .init(name: "title", required: true, help: "its title"),
                              .init(name: "date", help: "when it was published, 2026-11-03 (default: now)"),
                              .init(name: "task", help: "T-12: the task it belongs to")],
                     example: "hq artifact add https://claude.ai/artifact/abc --title \"Bench speed\" --date 2026-11-03", output: "{url, title, published, tasks}") { args, model in
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
                              .init(name: "link", list: true, help: "what to open, comma-separated: T-12, a URL, a file, an artifact (default: this session's open tasks and what it made since its last notification)"),
                              .init(name: "task", list: true, help: "T-12: the task it is about, the same as --link T-12")],
                     example: "hq notify \"Retry budget ready to check: the canary is green\" --task T-12", output: noticeOutput) { args, model in
            let text = try args.required("text").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw AgentError.usage("say what the user should know") }
            let session = model.session(args.string(sessionArg))?.id
            let links = try linked(args, model) ?? session.map { model.defaultLinks(forSession: $0) } ?? []
            let level: Notice.Level = try args.bool("important") == true ? .important : .update
            let row = model.notify(text, level: level, source: session, links: links)
            return model.noticeJSON(row, section: model.section(of: row))
        },
        AgentCommand(name: "remind", summary: "Set a reminder in HQ's notification center: it shows in Later, then comes back at its time.",
                     params: [.init(name: "text", required: true, positional: true, help: "what to remember, one line"),
                              .init(name: "at", required: true, help: "when: 16:00, in 2h, tomorrow at 15:00, friday 3pm, next week, 2026-11-09T09:00; a word it doesn't read is refused"),
                              .init(name: "important", kind: .boolean, help: "Needs You, with a banner, when it's due: the user asked to be reminded"),
                              .init(name: "link", list: true, help: "what to open, comma-separated: T-12, a URL, a file, an artifact"),
                              .init(name: "task", list: true, help: "T-12: the task it is about, the same as --link T-12")],
                     example: "hq remind \"Check the canary\" --at \"in 2h\" --important --task T-12", output: noticeOutput) { args, model in
            let text = try args.required("text").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw AgentError.usage("say what to remember") }
            let due = try remindTime(args.required("at"))
            let links = try linked(args, model) ?? []
            let level: Notice.Level = try args.bool("important") == true ? .important : .update
            let row = model.remind(text, at: due, level: level, source: model.session(args.string(sessionArg))?.id, links: links)
            return model.noticeJSON(row, section: .later)
        },
        AgentCommand(name: "notification done", summary: "Mark a notification this session sent read, or a reminder it set done: it no longer needs the user.",
                     params: [.init(name: "id", required: true, positional: true, help: "its id from hq notify, hq remind or hq ls notifications; its first 8 characters do"),
                              .init(name: "not-mine", kind: .boolean, help: "one this session didn't send, that the user named")],
                     example: "hq notification done 3F2A9C1B", output: noticeOutput) { args, model in
            let row = try ownNotice(args, model)
            model.setDone(row.id, true)
            let done = model.notices.first { $0.id == row.id } ?? row
            return model.noticeJSON(done, section: model.section(of: done))
        },
        AgentCommand(name: "notification delete", summary: "Delete a notification this session sent or a reminder it set: a ping that no longer holds, a follow-up done early.",
                     params: [.init(name: "id", required: true, positional: true, help: "its id from hq notify, hq remind or hq ls notifications; its first 8 characters do"),
                              .init(name: "not-mine", kind: .boolean, help: "one this session didn't send, that the user named")],
                     example: "hq notification delete 3F2A9C1B", output: "{deleted: id, text}") { args, model in
            let row = try ownNotice(args, model)
            model.removeNotice(row.id)
            return ["deleted": row.id.uuidString, "text": row.text]
        },
        AgentCommand(name: "session new", summary: "Start a fresh, named Claude session. Started from a session, it's yours: it sits under you, "
                        + "opens in your Ghostty window and reports to you. With --task it works on that task and is linked to it.",
                     params: [.init(name: "name", required: true, positional: true, help: "the session's name, short: \"T-12 Dedup layers\""),
                              .init(name: "task", help: "T-12: the task the new session works on"),
                              .init(name: "role", help: "a role's name (hq ls roles): the text the session starts with, again on resume and after a compact"),
                              .init(name: "parent", help: "the session it starts under: its id (6 characters or more) or name; none: the top level (default: this session)"),
                              .init(name: "beside", kind: .boolean, help: "at this session's level, under the session that started it: a handoff to a fresh session"),
                              .init(name: "history", help: "a session whose conversation it starts with: its id or name"),
                              .init(name: "cwd", help: "its directory (default: the --history session's, else this session's, else the current one)"),
                              .init(name: "message", help: "its first message, markdown; - reads stdin (default: one that sends it to the task)")],
                     example: "hq session new \"T-12 Dedup layers\" --task T-12 --role Worker", output: sessionOutput + "; started") { args, model in
            try newSessionCommand(args, model)
        },
        AgentCommand(name: "session edit", summary: "Move a session under another, as Move Under does in HQ, or to the top level with --parent none. Never under its own team.",
                     params: [.init(name: "session", required: true, positional: true, help: "its id (6 characters or more) or name"),
                              .init(name: "parent", help: "the session it goes under: its id or name; none: the top level")],
                     example: "hq session edit 41ccc6 --parent 8092a3", output: sessionOutput + "; note") { args, model in
            try editSessionCommand(args, model)
        },
        AgentCommand(name: "session show", summary: "Show a session: its state, name, folder and the tasks it works on.",
                     params: [.init(name: "session", required: true, positional: true, help: "its id, or the start of it (6 characters or more)")],
                     example: "hq session show 5e55a1", output: sessionOutput, readOnly: true) { args, model in
            let ref = try args.required("session").trimmingCharacters(in: .whitespaces)
            guard let session = model.session(ref) ?? (ref.count >= 6 ? model.session(prefix: ref) : nil) else {
                throw AgentError.notFound("no session \(ref). Run `hq ls sessions --all`")
            }
            var json = session.agentJSON(model)
            if session.id == args.string(sessionArg) { json["thisSession"] = true }
            return json
        },
        AgentCommand(name: "role show", summary: "Show a role: its color, its line, the text a session with it starts with, and the open sessions that have it.",
                     params: [.init(name: "role", required: true, positional: true, help: "its name, as hq ls roles lists it")],
                     example: "hq role show Leader", output: roleOutput + "; body, text", readOnly: true) { args, model in try roleShowCommand(args, model) },
        AgentCommand(name: "role new", summary: "Make a role: a note in HQ's roles, its text what a session started with it gets, at start, on resume and after a compact.",
                     params: [.init(name: "name", required: true, positional: true, help: "its name, short: Reviewer"),
                              .init(name: "line", help: "one line: what a session with it does"),
                              .init(name: "color", help: "its chip's color: red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown or gray (default: from its name)"),
                              .init(name: "body", help: "its text in markdown; - reads stdin")],
                     example: "hq role new Reviewer --line \"Reviews one pull request, never pushes.\" --color pink --body -", output: roleOutput + "; text") { args, model in
            try roleNewCommand(args, model)
        },
        AgentCommand(name: "role edit", summary: "Change a role's name, line, color or text. Its sessions get a new text when they next start, resume or compact; a new name follows to them.",
                     params: [.init(name: "role", required: true, positional: true, help: "its name"),
                              .init(name: "name", help: "a new name: the note is renamed"),
                              .init(name: "line", help: "the new line"),
                              .init(name: "color", help: "the new color"),
                              .init(name: "body", help: "the new text in markdown; - reads stdin")],
                     example: "hq role edit Reviewer --line \"Reviews one PR\"", output: roleOutput + "; text") { args, model in try roleEditCommand(args, model) },
        AgentCommand(name: "role delete", summary: "Delete a role: its note goes to the Trash. Sessions that have it keep the text they started with.",
                     params: [.init(name: "role", required: true, positional: true, help: "its name")],
                     example: "hq role delete Reviewer --yes", output: "{deleted: name}, or without --yes {wouldDelete: name}", destructive: true) { args, model in
            try roleDeleteCommand(args, model)
        },
        AgentCommand(name: "hook", summary: "Report a Claude Code hook event (used by the hq plugin). Always exits 0; while HQ is off, the event waits for its next launch.",
                     params: [.init(name: "event", help: "the hook's JSON, read from stdin by the CLI"),
                              .init(name: "pid", kind: .integer, help: "Claude's process, added by the CLI"),
                              .init(name: "tty", help: "Claude's terminal, added by the CLI"),
                              .init(name: "ghostty", kind: .boolean, help: "true when Claude runs in Ghostty, added by the CLI"),
                              .init(name: "at", help: "when it happened (ISO 8601), for an event HQ replays after being off")],
                     example: "echo '{\"hook_event_name\":\"Stop\",\"session_id\":\"…\"}' | hq hook", output: "{received, context (SessionStart)}") { args, model in
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

    /// The check every command that changes a task goes through, a parent for a new subtask included; a needless --not-mine is told.
    private static func own(_ task: TaskItem, _ args: Args, _ model: AppModel) throws {
        guard let session = args.string(sessionArg), model.session(session) != nil else { return }
        let mine = ([task.id] + model.taskTree.ancestors(of: task.id)).contains { model.task($0)?.sessions.contains(session) == true }
        if try args.bool("not-mine") == true {
            if mine { AgentRouter.warn("\(task.key) is yours already: drop --not-mine") }
            return
        }
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
        guard let session = args.string(sessionArg), model.session(session) != nil else { return row }
        if try args.bool("not-mine") == true {
            if row.source == session { AgentRouter.warn("“\(row.text)” is from this session already: drop --not-mine") }
            return row
        }
        guard row.source == session else {
            throw AgentError.notMine("“\(row.text)” isn't from this session. Check the id (`hq ls notifications --all`); "
                + "if it's the one the user means, run again with --not-mine")
        }
        return row
    }

    /// `--blocked-by T-34` or `--after T-34`, with nothing else to link: the kind and the task.
    private static func flowLink(_ args: Args, _ model: AppModel) throws -> (TaskFlow.Link, Int)? {
        let blockedBy = args.string("blocked-by"), after = args.string("after")
        guard blockedBy != nil || after != nil else { return nil }
        guard blockedBy == nil || after == nil, args.string("item") == nil else {
            throw AgentError.usage("one link at a time: an item, --blocked-by T-34 or --after T-34")
        }
        let ref = blockedBy ?? after ?? ""
        guard let other = TaskItem.key(ref), model.task(other) != nil else { throw AgentError.notFound("no task \(ref). Run `hq ls tasks`") }
        return (blockedBy != nil ? .blockedBy : .after, other)
    }

    private static func refusalText(_ refusal: TaskFlow.Refusal, _ task: String, _ link: TaskFlow.Link, _ other: String) -> String {
        switch refusal {
        case .itself: "a task can't wait for itself"
        case .done: "\(task) is done"
        case .already: "\(task) is already \(link == .blockedBy ? "blocked by" : "after") \(other)"
        case .partOf: "\(other) is part of \(task): a task already needs its subtasks"
        case .circle: "that would go in a circle: \(other) already needs \(task)"
        }
    }

    /// `--at` read whole, still to come; else why not, with the word it doesn't read.
    private static func remindTime(_ raw: String) throws -> Date {
        let reading = ReminderTime.read(raw)
        if case .date(let due) = reading, due > .now { return due }
        let why: String
        switch reading {
        case .date(let past): why = "is \(ReminderTime.full(past)), already past"
        case .unread(let word): why = word.isEmpty || word == raw.lowercased() ? "isn't a time HQ reads" : "has a word HQ doesn't read: \"\(word)\""
        }
        throw AgentError.usage("--at \"\(raw)\" \(why). Try 16:00, in 2h, tomorrow at 15:00, friday 3pm, next week, 2026-11-09T09:00")
    }

    /// A URL, a session id or a file, linked to a task.
    private static func linkItem(_ ref: String, to id: Int, _ model: AppModel) throws {
        let route = try item(ref, model)
        guard route != .task(id) else { throw AgentError.usage("a task can't link to itself") }
        model.link(route, to: id)
    }

    /// `T-12,https://…,Push plan`: what each piece names, a task, an artifact, any other URL, a session, a file.
    /// A piece that names nothing joins the next one, so a file name with a comma still works.
    private static func links(_ list: String, _ model: AppModel) throws -> [ModalRoute] {
        var pieces = list.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        var routes: [ModalRoute] = []
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
                if !routes.contains(route) { routes.append(route) }
                pieces.removeFirst(taken)
            } else if piece.isEmpty {
                pieces.removeFirst()
            } else {
                _ = try item(piece, model)
            }
        }
        return routes
    }

    /// A notification's `--link` and `--task`, as selection keys; nil when neither is given.
    private static func linked(_ args: Args, _ model: AppModel) throws -> [String]? {
        let given = [args.string("link"), args.string("task")].compactMap { $0 }
        guard !given.isEmpty else { return nil }
        return try links(given.joined(separator: ","), model).map(\.selectionKey)
    }

    /// A note by its name, path or title.
    private static func findFile(_ args: Args, _ model: AppModel) throws -> FileItem {
        let ref = try args.required("file")
        guard let file = file(ref, model) else { throw AgentError.notFound("no note \(ref). Run `hq ls files`") }
        return file
    }

    /// The name `file new` printed (with or without .md), a path, or a title only one note has.
    private static func file(_ ref: String, _ model: AppModel) -> FileItem? {
        if let file = model.file(ref: ref) { return file }
        let titled = model.files.filter { $0.title.caseInsensitiveCompare(ref.trimmingCharacters(in: .whitespaces)) == .orderedSame }
        return titled.count == 1 ? titled[0] : nil
    }

    // MARK: Reading and writing descriptions

    /// The shapes `hq help` prints after JSON:, shared by the commands that return them.
    static let taskOutput = "{id, title, status, list, project, parent, tags, links, related, sessions, state, flow, blocked, blockedReason, blockedBy, after, modified}"
    static let fileOutput = "{name, title, path, modified, tasks}"
    static let noticeOutput = "{id, section, level, kind, text, at, due, when, read, source, links: [{kind, title, id | name | url}]}"
    static let sessionOutput = "{id, name, state, since, cwd, branch, tasks, reason, closed, role, parent, thisSession}"

    /// What each session last read of each description, as a digest: `task edit --body` refuses to write over a newer one.
    private static var reads: [String: [Int: Int]] = [:]

    /// A description's digest, blind to trailing spaces and blank lines the vault may add or drop.
    private static func digest(_ body: String) -> Int {
        body.replacing(/[ \t]+\n/, with: "\n").trimmingCharacters(in: .whitespacesAndNewlines).hashValue
    }

    /// The session has read this description.
    private static func noteRead(_ body: String, of id: Int, _ args: Args) {
        guard let session = args.string(sessionArg) else { return }
        reads[session, default: [:]][id] = digest(body)
    }

    /// The session wrote a description: it knows the new one when it wrote all of it, or when it had read the old one.
    private static func wrote(_ new: String, over old: String, of id: Int, whole: Bool, _ args: Args) {
        guard let session = args.string(sessionArg), whole || reads[session]?[id] == digest(old) else { return }
        reads[session, default: [:]][id] = digest(new)
    }

    /// The description `task edit` writes, or nil; all of it is refused when it changed since this session read it.
    private static func newBody(of task: TaskItem, _ args: Args, _ model: AppModel) throws -> String? {
        let body = args.string("body"), section = args.string("section"), old = args.string("replace")
        guard section == nil || old == nil else { throw AgentError.usage("--section or --replace: one at a time") }
        if let section {
            guard let body else { throw AgentError.usage("--section \(section) needs --body: the section's new text (- reads stdin)") }
            return PartialEdit.section(section, in: task.body, with: body).trimmingCharacters(in: .newlines)
        }
        if let old {
            guard body == nil else { throw AgentError.usage("--replace changes one text and --body all of it: one at a time") }
            guard let new = args.string("with") else { throw AgentError.usage("--replace needs --with: what it becomes (\"\" removes it)") }
            return try PartialEdit.replace(old, with: new, in: task.body, what: "\(task.key)'s description").trimmingCharacters(in: .newlines)
        }
        guard args.string("with") == nil else { throw AgentError.usage("--with goes with --replace \"the text to change\"") }
        guard let body else { return nil }
        let new = body.trimmingCharacters(in: .newlines)
        if digest(new) != digest(task.body), try args.bool("force") != true, let session = args.string(sessionArg),
           let seen = reads[session]?[task.id], seen != digest(task.body) {
            throw AgentError.stale("\(task.key)'s description changed since this session read it: the user or another session edited it. "
                + "Read it again (hq task show \(task.key) --body) and make your change on that text, or change one part with --section or --replace. "
                + "--force writes over it")
        }
        return new
    }

    /// One task as `task show` gives it, in the view asked for. A description shown counts as read.
    private static func show(_ task: TaskItem, view: String?, _ args: Args, _ model: AppModel) -> JSONObject {
        if view == "body" {
            noteRead(task.body, of: task.id, args)
            return ["id": task.key, "title": task.title, "status": task.status.rawValue, "body": task.body, "view": "body"]
        }
        let tree = model.taskTree
        let flow = model.taskFlow
        var json = task.agentJSON(model)
        if view != "brief" {
            json["body"] = task.body
            noteRead(task.body, of: task.id, args)
        }
        if let view { json["view"] = view }
        json["parents"] = tree.ancestors(of: task.id).compactMap { model.task($0) }.map(\.briefJSON)
        // The reminders that link it, the one due first first.
        let key = ModalRoute.task(task.id).selectionKey
        let reminders = model.notices.filter { $0.kind == .reminder && $0.readAt == nil && $0.links.contains(key) }
            .sorted { ($0.dueAt ?? $0.at) < ($1.dueAt ?? $1.at) }
        if !reminders.isEmpty { json["reminders"] = reminders.map { model.noticeJSON($0, section: model.section(of: $0)) } }
        // The whole tree under it, in the outline's order, with what holds each task.
        let depth = tree.depth(of: task.id)
        let subtree = tree.subtree(of: task.id).dropFirst().compactMap { model.task($0) }
        json["subtasks"] = subtree.map { sub -> JSONObject in
            var line = sub.briefJSON
            line["depth"] = tree.depth(of: sub.id) - depth
            if let parent = sub.parent { line["parent"] = "T-\(parent)" }
            if let text = model.flowText(sub.id, ready: true) { line["flow"] = text }
            if !tree.children(of: sub.id).isEmpty { line["progress"] = model.progressText(flow.tally(of: sub.id), short: true) }
            if view == "deep", sub.status != .done, !sub.body.isEmpty {
                line["body"] = sub.body
                noteRead(sub.body, of: sub.id, args)
            }
            return line
        }
        if !subtree.isEmpty {
            let tally = flow.tally(of: task.id)
            json["progress"] = model.progressText(tally, short: false)
            let leaves = subtree.filter { tree.children(of: $0.id).isEmpty }
            json["ready"] = leaves.filter { flow.state($0.id) == .ready }.map(\.key)
            json["blockedTasks"] = leaves.filter { flow.state($0.id).isBlocked }.map { ["id": $0.key, "why": model.flowText($0.id) ?? "blocked"] }
        }
        json["linked"] = model.outputs(ofTask: task.id).map { model.linkJSON($0) }
        return json
    }

    /// The repository a folder is in (the nearest folder up with a .git), else the folder itself.
    static func repository(of path: String) -> String {
        var url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        let start = url.path
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appending(path: ".git").path) { return url.path }
            url.deleteLastPathComponent()
        }
        return start
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
        if let file = file(ref, model) { return .file(file.id) }
        throw AgentError.notFound("nothing called \(ref). Use a URL, T-12, a session id, a note's name or an artifact URL")
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
        if let role = model.role(named: role) { json["role"] = role.name }
        if let parent = model.parentSession(of: id) { json["parent"] = parent.id }
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
        if blocked { json["blocked"] = true }
        if blocked, let blockedReason { json["blockedReason"] = blockedReason }
        if !blockedBy.isEmpty { json["blockedBy"] = blockedBy.map { "T-\($0)" } }
        if !after.isEmpty { json["after"] = after.map { "T-\($0)" } }
        json["state"] = model.taskFlow.state(id).rawValue
        if let flow = model.flowText(id) { json["flow"] = flow }
        if let path { json["path"] = path }
        return json
    }
}

extension FileItem {
    /// What `hq file show` takes: the note's file name without .md.
    var name: String { id.hasSuffix(".md") ? String(id.dropLast(3)) : id }

    var agentJSON: JSONObject {
        var json: JSONObject = ["name": name, "path": path ?? "hq/files/\(id)", "title": title, "modified": JSON.date(modified)]
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
    /// What holds a task, for hq's lines: "Blocked: why", "blocked by T-285", "after T-283", "held by T-280", and "ready" when asked.
    func flowText(_ id: Int, ready: Bool = false) -> String? {
        guard let task = task(id), task.status != .done else { return nil }
        let flow = taskFlow
        var parts: [String] = []
        if task.blocked { parts.append(task.blockedReason.map { "Blocked: \($0)" } ?? "Blocked") }
        let by = flow.openBlockers(id), before = flow.openBefore(id)
        if !by.isEmpty { parts.append("blocked by " + by.map { "T-\($0)" }.joined(separator: ", ")) }
        if !before.isEmpty { parts.append("after " + before.map { "T-\($0)" }.joined(separator: ", ")) }
        if flow.state(id) == .held, let holder = flow.holder(id) { parts.append("held by T-\(holder)") }
        if ready, flow.state(id) == .ready, taskTree.children(of: id).isEmpty { parts.append("ready") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The projects a session works in: its tasks', else the ones whose folder holds its own.
    func projects(of session: SessionItem, tasks: [TaskItem]) -> Set<String> {
        let named = Set(tasks.compactMap { project(ofTask: $0.id) })
        guard named.isEmpty, !session.cwd.isEmpty else { return named }
        return Set(allProjects.filter { name in
            guard let folder = folder(of: name).map({ ($0 as NSString).expandingTildeInPath }) else { return false }
            return session.cwd == folder || session.cwd.hasPrefix(folder + "/")
        })
    }

    /// "1 of 17 done · 5 doing · 5 blocked · 1 ready", or "1/17 · 5 blocked" for a subtask's line.
    func progressText(_ tally: TaskFlow.Tally, short: Bool) -> String {
        let blocked = tally.blocked > 0 ? " · \(tally.blocked) blocked" : ""
        if short { return "\(tally.done)/\(tally.total)\(blocked)" }
        let doing = tally.doing > 0 ? " · \(tally.doing) doing" : ""
        let ready = tally.ready > 0 ? " · \(tally.ready) ready" : ""
        return "\(tally.done) of \(tally.total) done\(doing)\(blocked)\(ready)"
    }

    /// What `task show` lists as linked: the files, artifacts, PRs, issues and tasks under the task's row.
    func linkJSON(_ route: ModalRoute) -> JSONObject {
        switch route {
        case .file(let id): ["kind": "file", "title": title(of: route), "name": file(id)?.name ?? id, "path": file(id)?.path ?? "hq/files/\(id)"]
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
        case .start, .closedSessions, .notifications, .roles, .newTask, .newReminder, .newFile, .importArtifact: ["kind": "other", "title": title(of: route)]
        }
    }

    func noticeJSON(_ row: Notice, section: NoticeSection) -> JSONObject {
        var json: JSONObject = ["id": row.id.uuidString, "section": "\(section)", "level": row.level.rawValue, "kind": row.kind.rawValue,
                                "text": row.text, "at": JSON.date(row.at),
                                "links": row.links.compactMap { ModalRoute(noticeKey: $0).map(linkJSON) }]
        if let source = row.source { json["source"] = source }
        if row.count > 1 { json["count"] = row.count }
        if let due = row.dueAt {
            json["due"] = JSON.date(due)
            json["when"] = ReminderTime.full(due)
        }
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

// The longer commands' bodies, out of the table so it type-checks fast.
extension AgentCommands {
    static func contextCommand(_ args: Args, _ model: AppModel) throws -> Any {
        let id = args.string("session") ?? args.string(sessionArg)
        guard let session = model.session(id) ?? (id.flatMap { model.session(prefix: $0) }) else {
            throw AgentError.notFound("no session \(id ?? "here"). Run it inside a Claude session, or pass --session <id>")
        }
        let mine = model.tasks(of: session.id)
        let doing = model.taskTree.outline(.overview).compactMap { model.task($0) }
            .filter { $0.status == .doing && !mine.contains($0) }
        // This session's projects first: its tasks', else the ones whose folder it runs in. The rest only counted.
        let projects = model.projects(of: session, tasks: mine)
        let every = try args.bool("all") == true
        let overview = every ? doing : doing.filter { model.project(ofTask: $0.id).map { projects.contains($0) } ?? false }
        let elsewhere = doing.count - overview.count
        let mineIDs = Set(mine.map(\.id))
        let files = model.files.filter { file in file.sessions.contains(session.id) || file.tasks.contains(where: mineIDs.contains) }
            .sorted { $0.modified > $1.modified }
        let artifacts = model.artifacts.filter { $0.session == session.id }.sorted { $0.published > $1.published }
        let team = teamContext(session, model)
        let teamIDs = Set(model.team(of: session.id).map(\.session.id) + [model.parentSession(of: session.id)?.id].compactMap { $0 })
        let others = model.sessions.filter { $0.id != session.id && $0.closedAt == nil && !teamIDs.contains($0.id) }
        let role = model.role(named: session.role)
        var text = ["This session: \(session.name)" + (role.map { " · \($0.name), its text arrives at start, resume and compact (hq role show \($0.name))" } ?? "")]
        text += team.started
        text.append(mine.isEmpty ? "Works on: no task yet (hq task link T-n, or the user drops one on its card)" : "Works on:")
        // Open tasks in full; done ones only counted, the latest few named, so a long session's list stays short.
        let open = mine.filter { $0.status != .done }
        let done = mine.filter { $0.status == .done }.sorted { $0.modified > $1.modified }
        text += open.map { "  \($0.key) [\($0.status.rawValue)] \($0.title)\(model.flowText($0.id).map { " · " + $0 } ?? "") (\(model.list(of: $0.id) == .backlog ? "Backlog" : "Tasks"))" }
        if !done.isEmpty {
            text.append("  \(done.count) done" + (done.count > 3 ? ", latest " : ": ") + done.prefix(3).map(\.key).joined(separator: ", "))
        }
        text += team.team
        let shown = every ? 40 : 15
        if !overview.isEmpty {
            text.append(every || projects.isEmpty ? "Doing:" : "Doing in \(projects.sorted().joined(separator: ", ")):")
            text += overview.prefix(shown).map { "  \($0.key) [\($0.status.rawValue)] \($0.title)\(model.flowText($0.id).map { " · " + $0 } ?? "")" }
            if overview.count > shown { text.append("  and \(overview.count - shown) more") }
        }
        if elsewhere > 0 {
            text.append("\(overview.isEmpty ? "" : "And ")\(elsewhere) doing in \(projects.isEmpty ? "the overview" : "other projects") (hq ctx --all)")
        }
        if !files.isEmpty {
            text.append("Recent files:")
            text += files.prefix(10).map { "  \($0.name)" }
        }
        if !artifacts.isEmpty {
            text.append("Artifacts:")
            text += artifacts.prefix(10).map { "  \($0.title) \($0.id.absoluteString)" }
        }
        if !others.isEmpty {
            text.append("Other open sessions:")
            text += others.prefix(12).map { "  \($0.name) (\($0.status.title.lowercased()))" }
        }
        var json: JSONObject = ["text": text.joined(separator: "\n"), "session": session.agentJSON(model),
                                "tasks": mine.map { $0.agentJSON(model) }, "overview": overview.prefix(shown).map { $0.agentJSON(model) }, "elsewhere": elsewhere,
                                "files": files.prefix(10).map(\.agentJSON), "artifacts": artifacts.prefix(10).map(\.agentJSON),
                                "sessions": others.map { $0.agentJSON(model) }]
        json.merge(team.json) { _, new in new }
        return json
    }

    static func listCommand(_ args: Args, _ model: AppModel) throws -> Any {
        let kind = args.string("kind") ?? "sessions"
        // Each filter applies to some kinds only: given to another, it's a mistake, not a no-op.
        let takes: [String: Set<String>] = ["sessions": ["all", "here", "tree"], "tasks": ["overview", "backlog", "parent", "project", "tag", "all"],
                                            "prs": ["all"], "notifications": ["all"], "reminders": ["all"]]
        for flag in ["here", "tree", "overview", "backlog", "parent", "project", "tag", "all"] where args.values[flag] != nil && takes[kind]?.contains(flag) != true {
            let kinds = takes.filter { $0.value.contains(flag) }.keys.sorted().joined(separator: ", ")
            guard ["sessions", "tasks", "prs", "files", "artifacts", "projects", "notifications", "reminders", "roles"].contains(kind) else { break }
            throw AgentError.usage("--\(flag) is for \(kinds), not \(kind)")
        }
        let all = try args.bool("all") ?? false
        var narrowed = false
        let items: [JSONObject]
        switch kind {
        case "sessions":
            // As a tree: each top-level session, then its team, depth first.
            let tree = try args.bool("tree") == true
            var rows = tree ? treeRows(model, all: all) : (all ? model.sessions.sorted { $0.order < $1.order } : model.gridSessions).map { (session: $0, depth: 0) }
            if try args.bool("here") == true {
                let root = repository(of: args.string(cwdArg) ?? FileManager.default.currentDirectoryPath)
                rows = rows.filter { session, _ in
                    let cwd = (session.cwd as NSString).expandingTildeInPath
                    return cwd == root || cwd.hasPrefix(root + "/")
                }
            }
            let caller = args.string(sessionArg)
            items = rows.map { session, depth in
                var json = session.agentJSON(model)
                if session.id == caller { json["thisSession"] = true }
                if tree { json["depth"] = depth }
                return json
            }
        case "tasks":
            let tree = model.taskTree
            let overview = try args.bool("overview") ?? false
            let backlog = try args.bool("backlog") ?? false
            var ids: [Int] = []
            if let ref = args.string("parent") {
                guard let parent = model.task(TaskItem.key(ref)) else { throw AgentError.notFound("no task \(ref). Run `hq ls tasks`") }
                ids = Array(tree.subtree(of: parent.id).dropFirst())
            } else {
                if !backlog { ids += tree.outline(.overview) }
                if !overview { ids += tree.outline(.backlog) }
            }
            narrowed = overview || args.string("parent") != nil || args.string("project") != nil
            items = ids.compactMap { model.task($0) }.filter { task in
                (all || task.status != .done)
                    && (args.string("project").map { $0.caseInsensitiveCompare(model.project(ofTask: task.id) ?? "") == .orderedSame } ?? true)
                    && (args.string("tag").map { tag in task.tags.contains(tag.replacingOccurrences(of: "#", with: "")) } ?? true)
            }.map { $0.agentJSON(model) }
        case "prs":
            // As on the page: Reviews (every one, whatever its filter, but those reminded later), then Yours, then the other linked ones.
            let reminded = model.remindedLater
            let reviews = model.allReviewRequests.filter { !reminded.contains($0.url) }, yours = model.ownPullRequests
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
            // What Needs You counts: sessions that wait, review requests, then the rows.
            let sections: [NoticeSection] = all ? [.needsYou, .updates, .later, .earlier] : [.needsYou, .updates, .later]
            let sessions: [JSONObject] = model.blockedSessions.map { ["section": "needsYou", "kind": "session", "session": $0.id, "text": "\($0.name): \($0.reason ?? $0.status.title)"] }
            let waiting: [JSONObject] = model.waitingReviews.map { ["section": "needsYou", "kind": "review", "url": $0.url, "text": "Review #\($0.number) \($0.title)"] }
            let later: [JSONObject] = model.laterReviews.map { ["section": "later", "kind": "review", "url": $0.item.url, "text": "Review #\($0.item.number) \($0.item.title)",
                                            "due": JSON.date($0.until), "when": ReminderTime.full($0.until)] }
            let rows: [JSONObject] = sections.flatMap { section in model.notices(in: section).map { model.noticeJSON($0, section: section) } }
            items = sessions + waiting + rows + later
        case "reminders":
            items = model.notices.filter { $0.kind == .reminder && (all || $0.readAt == nil) }
                .sorted { ($0.dueAt ?? $0.at) < ($1.dueAt ?? $1.at) }
                .map { model.noticeJSON($0, section: model.section(of: $0)) }
        case "roles":
            items = model.roles.map { $0.agentJSON(model) }
        default:
            let hint = kind == "folders" ? " (a project has the folder: hq ls projects)" : ""
            throw AgentError.usage("no kind \"\(kind)\". Kinds: sessions, tasks, prs, files, artifacts, projects, notifications, reminders, roles\(hint)")
        }
        let limit = try args.int("limit", default: narrowed ? Int.max : 50)
        let offset = try args.int("offset", default: 0)
        let page = items.dropFirst(offset).prefix(limit)
        var result: JSONObject = [kind: Array(page), "total": items.count]
        if offset + page.count < items.count { result["nextOffset"] = offset + page.count }
        return result
    }

    static func showCommand(_ args: Args, _ model: AppModel) throws -> Any {
        let refs = try args.required("task").split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        let (body, brief, deep) = (try args.bool("body") == true, try args.bool("brief") == true, try args.bool("deep") == true)
        let view: String? = body ? "body" : brief ? "brief" : deep ? "deep" : nil
        let shown = try refs.map { ref -> JSONObject in
            guard let task = model.task(TaskItem.key(ref)) else { throw AgentError.notFound("no task \(ref). Run `hq ls tasks`") }
            return show(task, view: view, args, model)
        }
        if shown.count == 1 { return shown[0] }
        return ["shown": shown] as JSONObject
    }

    static func addCommand(_ args: Args, _ model: AppModel) throws -> Any {
        let titled = TitleTags.split((try? args.required("title")) ?? "").tags.compactMap { word -> TaskStatus? in
            if case .status(let status) = model.titleWord(word) { status } else { nil }
        }.last
        let status = try args.string("status").map { raw in
            guard let status = TaskStatus(parsing: raw) else { throw AgentError.usage("no status \"\(raw)\". Statuses: todo, doing, done") }
            return status
        } ?? titled ?? .todo
        // Every link resolves before the task exists: a wrong one creates nothing.
        let routes = try args.string("link").map { try links($0, model) } ?? []
        let session = model.session(args.string(sessionArg))
        let tree = model.taskTree
        let placed: (TaskTree.Placement, changes: [Int: TaskTree.Placement])?
        var project = args.string("project")
        if let ref = args.string("parent") {
            guard let parent = model.task(TaskItem.key(ref)) else { throw AgentError.notFound("no task \(ref). Run `hq ls tasks`") }
            try own(parent, args, model)
            placed = tree.placeNew(in: .task(parent.id))
            // As in HQ: a subtask is written in the project in effect there.
            project = project ?? model.project(ofTask: parent.id)
        } else if try args.bool("backlog") == true, status != .doing {
            placed = tree.placeNew(in: .list(.backlog), at: 0)
        } else {
            placed = tree.placeNew(in: .list(.overview))
        }
        guard let (placement, renumber) = placed,
              let task = model.addTask(title: try args.required("title"), placement: placement, status: status,
                                       project: project.flatMap { $0.isEmpty ? nil : $0 },
                                       tags: tags(args.string("tag")), body: args.string("body") ?? "", session: session?.id, renumber: renumber) else {
            throw AgentError.invalid("could not create the task. Check that the vault is reachable")
        }
        for route in routes { model.link(route, to: task.id) }
        noteRead(task.body, of: task.id, args)
        return model.task(task.id)?.agentJSON(model) ?? task.agentJSON(model)
    }

    static func moveCommand(_ args: Args, _ model: AppModel) throws -> Any {
        let raw = try args.required("status").lowercased()
        if raw == "review" {
            throw AgentError.usage("there is no review status. Keep the task doing and tell the user what to check: "
                                   + "hq notify \"PR #418 is ready to merge\" --task \(args.string("task") ?? "T-12")")
        }
        var list: TaskList?
        if let name = args.string("list") {
            switch name.lowercased() {
            case "tasks", "overview": list = .overview
            case "backlog": list = .backlog
            default: throw AgentError.usage("--list takes tasks or backlog, not \"\(name)\"")
            }
        }
        let task = try ownTask(args, model)
        if raw == "backlog" {
            guard list == nil || list == .backlog else { throw AgentError.usage("backlog already says the list: hq task move \(task.key) todo --list tasks") }
            model.setStatus(task.id, .todo)
            model.move(task.id, to: .backlog)
        } else {
            guard let status = TaskStatus(rawValue: raw) else {
                throw AgentError.usage("no status \"\(raw)\". Statuses: todo, doing, done")
            }
            model.setStatus(task.id, status)
            if let list {
                model.move(task.id, to: list)
            } else if status == .doing, task.parent == nil, model.list(of: task.id) == .backlog {
                // Work started: a top-level task in the Backlog comes to Tasks.
                model.move(task.id, to: .overview)
            }
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
    }

    static func editCommand(_ args: Args, _ model: AppModel) throws -> Any {
        let task = try ownTask(args, model)
        let body = try newBody(of: task, args, model)
        if let ref = args.string("parent")?.trimmingCharacters(in: .whitespaces) {
            try moveUnder(task.id, ref, model)
        }
        let added = tags(args.string("add-tag"))
        let removed = Set(tags(args.string("remove-tag")))
        let before = model.task(task.id) ?? task
        model.changeTask(task.id, "Edit Task") { task in
            if let body { task.body = body }
            if let project = args.string("project") { task.project = project.isEmpty ? nil : project }
            task.tags = task.tags.filter { !removed.contains($0) } + added.filter { !task.tags.contains($0) }
        }
        if let title = args.string("title"), !title.isEmpty { model.setTitle(task.id, title) }
        guard let after = model.task(task.id) else { return [:] }
        if let body { wrote(body, over: before.body, of: task.id, whole: args.string("section") == nil && args.string("replace") == nil, args) }
        var result = after.agentJSON(model)
        let changed = TaskEdit.fields(before, after)
        result["note"] = changed.isEmpty ? "Nothing changed: \(task.key) already reads so" : "Changed: " + changed.joined(separator: ", ")
        return result
    }

    static func tickCommand(_ args: Args, _ model: AppModel) throws -> Any {
        let task = try ownTask(args, model)
        let tick = try PartialEdit.tick(try args.required("item"), in: task.body, checked: try args.bool("untick") != true, what: task.key)
        if tick.changed {
            model.changeTask(task.id, "Edit Task") { $0.body = tick.source }
            wrote(tick.source, over: task.body, of: task.id, whole: false, args)
        }
        var result = model.task(task.id)?.agentJSON(model) ?? [:]
        let verb = try args.bool("untick") == true ? "cleared" : "ticked"
        result["ticked"] = ["item": tick.item, "done": tick.done, "total": tick.total] as JSONObject
        result["text"] = "\(task.key) \(tick.changed ? verb : "already \(verb)") “\(tick.item)”: \(tick.done) of \(tick.total) ticked"
        return result
    }

    static func newFileCommand(_ args: Args, _ model: AppModel) throws -> Any {
        let session = model.session(args.string(sessionArg))
        let task = try args.string("task").map { ref in
            guard let task = model.task(TaskItem.key(ref)) else { throw AgentError.notFound("no task \(ref)") }
            return task.id
        } ?? session.flatMap { model.tasks(of: $0.id).count == 1 ? model.tasks(of: $0.id)[0].id : nil }
        // "2026-11-10 - Plan" is "Plan" of that day: the name gets one date.
        var title = try args.required("title").trimmingCharacters(in: .whitespacesAndNewlines)
        var date = Date.now
        if let match = title.firstMatch(of: /^(\d{4}-\d{2}-\d{2})\s+-\s+(\S.*)$/), let day = NoteDate.parse(String(match.output.1)) {
            title = String(match.output.2)
            date = day
        }
        guard let file = model.addFile(title: title, body: args.string("body") ?? "", session: session?.id, task: task, date: date) else {
            throw AgentError.invalid("could not create the note. Check that the vault is reachable")
        }
        return file.agentJSON
    }

    static func writeFileCommand(_ args: Args, _ model: AppModel) throws -> Any {
        let file = try findFile(args, model)
        let current = model.fileBody(file.id)
        let text: String
        if let old = args.string("replace") {
            guard args.string("body") == nil, args.string("section") == nil else { throw AgentError.usage("--replace changes one text: leave out --body and --section") }
            guard let new = args.string("with") else { throw AgentError.usage("--replace needs --with: what it becomes (\"\" removes it)") }
            text = try PartialEdit.replace(old, with: new, in: current, what: file.name)
        } else {
            guard let body = args.string("body") else { throw AgentError.usage("give the text with --body (- reads stdin), or change one part with --replace \"old\" --with \"new\"") }
            if let section = args.string("section") {
                text = PartialEdit.section(section, in: current, with: body)
            } else if try args.bool("append") == true {
                text = current.trimmingCharacters(in: .newlines) + "\n\n" + body.trimmingCharacters(in: .newlines) + "\n"
            } else {
                text = body
            }
        }
        model.saveFileBody(file.id, text)
        if let session = args.string(sessionArg), model.session(session) != nil, !file.sessions.contains(session) {
            model.changeFile(file.id, "Link Session") { $0.sessions.append(session) }
        }
        return file.agentJSON
    }
}
