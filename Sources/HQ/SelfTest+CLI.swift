import Foundation
import HQKit

extension SelfTest {
    /// The CLI as sessions use it: parsing, lists that say when they're cut, partial edits, deep reads, stale writes.
    static func cliFixChecks(_ model: AppModel) async {
        func failure(_ result: JSONObject) -> (code: String, message: String)? {
            (result["error"] as? JSONObject).map { ($0["code"] as? String ?? "", $0["message"] as? String ?? "") }
        }
        func command(_ name: String) -> AgentCommand? { AgentCommands.all.first { $0.name == name } }
        func key(_ result: JSONObject) -> String { result["id"] as? String ?? "" }
        func id(_ result: JSONObject) -> Int { TaskItem.key(key(result)) ?? -1 }
        func body(_ ref: String) -> String { model.task(TaskItem.key(ref))?.body ?? "" }

        // Parsing, as models write flags.
        if let add = command("task add"), let notify = command("notify"), let link = command("task link") {
            let inline = try? AgentCLI.parse(["Title", "--project=HQ", "--status=doing"], for: add)
            check("--name=value is parsed", inline?["project"] == "HQ" && inline?["status"] == "doing" && inline?["title"] == "Title",
                  "\(String(describing: inline))")
            let twice = try? AgentCLI.parse(["Ready", "--link", "T-1", "--link", "T-2"], for: notify)
            check("a list option given twice keeps both", twice?["link"] == "T-1,T-2", "\(String(describing: twice))")
            let scalar = Result { try AgentCLI.parse(["Title", "--project", "A", "--project", "B"], for: add) }
            check("any other option given twice with two values is refused", (try? scalar.get()) == nil)
            let empty = Result { try AgentCLI.parse(["", "https://example.com/a"], for: link) }
            var message = ""
            if case .failure(let error as AgentError) = empty { message = error.message }
            check("an empty argument is reported as empty, not as a missing flag", message.hasPrefix("<task> is empty"), message)
            let routed = failure(agent("task link", ["task": " ", "item": "https://example.com/a"]))
            check("so is one the app gets", routed?.message.hasPrefix("<task> is empty") == true, "\(String(describing: routed))")
            check("a retired flag is dropped, with its value, so the command runs",
                  AgentCLI.retired(["A title", "--type", "bug", "--now", "--project", "HQ"], for: add) == ["A title", "--project", "HQ"])
            check("hq link <item> <task> runs task link <task> <item>",
                  (try? AgentCLI.retired(["link", "https://example.com/a", "T-12"])) == ["task", "link", "T-12", "https://example.com/a"])
        }
        let silent = AgentCommands.all.filter { $0.output.isEmpty }.map(\.name)
        check("every command's help ends with the shape of its JSON", silent.isEmpty && command("ls").map { AgentCLI.usage($0).contains("\nJSON: {") } == true,
              silent.joined(separator: ", "))
        check("hq status gives the build that runs", (agent("status", [:])["version"] as? String).map { !$0.isEmpty } == true
              && agent("status", [:])["startedAt"] != nil)
        check("a build stamp orders two builds", AgentVersion.build("0.1 (202611111020)") == 202_611_111_020 && AgentVersion.build("dev") == nil)

        // Lists say when they're cut, and refuse a filter that doesn't apply.
        let cut = agent("ls", ["kind": "tasks", "limit": "1"])
        let footer = AgentCLI.human(cut)
        check("a cut list says so on its last line", cut["nextOffset"] as? Int == 1
              && footer.components(separatedBy: "\n").last?.hasPrefix("1 of \(cut["total"] as? Int ?? 0): --limit") == true, footer)
        check("--tag on sessions is refused", failure(agent("ls", ["kind": "sessions", "tag": "hq"]))?.code == "usage")
        check("so is --here on tasks", failure(agent("ls", ["kind": "tasks", "here": "true"]))?.code == "usage")
        if let session = model.gridSessions.first(where: { !$0.cwd.isEmpty }) {
            let here = agent("ls", ["kind": "sessions", "here": "true", "_cwd": session.cwd, "_session": session.id])["sessions"] as? [JSONObject] ?? []
            let root = AgentCommands.repository(of: session.cwd)
            check("ls sessions --here lists the sessions in this repository, this one marked", here.contains { $0["id"] as? String == session.id && $0["thisSession"] as? Bool == true }
                  && here.allSatisfy { ($0["cwd"] as? String).map { ($0 as NSString).expandingTildeInPath }.map { $0 == root || $0.hasPrefix(root + "/") } == true }, "\(here.count) in \(root)")
            let nowhere = agent("ls", ["kind": "sessions", "here": "true", "_cwd": "/tmp/hq-nowhere-\(UUID().uuidString.prefix(6))"])["sessions"] as? [JSONObject]
            check("and none from a folder no session runs in", nowhere?.isEmpty == true)
            let shown = agent("session show", ["session": String(session.id.prefix(8))])
            check("session show takes the start of an id", shown["id"] as? String == session.id && shown["cwd"] != nil, "\(shown)")
            check("but not a start too short to be sure", failure(agent("session show", ["session": String(session.id.prefix(3))]))?.code == "not_found")
        }
        let reviewRows = (agent("ls", ["kind": "notifications"])["notifications"] as? [JSONObject] ?? []).filter { $0["kind"] as? String == "review" && $0["section"] as? String == "needsYou" }
        check("ls notifications lists the review requests Needs You counts", reviewRows.count == model.waitingReviews.count,
              "\(reviewRows.count) of \(model.waitingReviews.count)")

        // A subtask takes its parent's project; a new task takes its links; -q gives the key.
        let story = agent("task add", ["title": "CLI story", "project": "Registry", "body": "The goal."])
        let child = agent("task add", ["title": "CLI child", "parent": key(story)])
        let other = agent("task add", ["title": "CLI child elsewhere", "parent": key(story), "project": "Billing"])
        check("task add --parent takes the parent's project, unless --project says otherwise",
              child["project"] as? String == "Registry" && other["project"] as? String == "Billing", "\(child) \(other)")
        let listed = agent("ls", ["kind": "tasks", "parent": key(story)])
        check("ls tasks --parent lists the tree under it, uncut", (listed["tasks"] as? [JSONObject])?.compactMap { $0["id"] as? String } == [key(child), key(other)]
              && listed["nextOffset"] == nil, "\(listed)")
        let linked = agent("task add", ["title": "CLI linked", "link": "https://github.com/acme/registry/pull/9,\(key(story))"])
        let linkedShow = agent("task show", ["task": key(linked)])
        check("task add --link links what it names", (linkedShow["linked"] as? [JSONObject])?.count == 2, "\(linkedShow["linked"] ?? "none")")
        check("-q prints the key alone", AgentCLI.keys(linked) == key(linked) && AgentCLI.keys(listed) == "\(key(child))\n\(key(other))")
        let before = model.tasks.count
        check("a link that names nothing creates no task", failure(agent("task add", ["title": "CLI bad link", "link": "nothing-called-this"]))?.code == "not_found"
              && model.tasks.count == before)

        // Notes: one date in the name, found by title.
        let dated = agent("file new", ["title": "2026-11-08 - CLI dated plan", "body": "# CLI dated plan\n\n## Next steps\nNone yet.\n"])
        let today = agent("file new", ["title": "\(Vault.dayString(.now)) - CLI today plan", "body": "# CLI today plan\n"])
        check("file new doesn't double a dated title's date, and takes it as the note's", dated["name"] as? String == "2026-11-08 - CLI dated plan"
              && today["name"] as? String == "\(Vault.dayString(.now)) - CLI today plan" && dated["title"] as? String == "CLI dated plan", "\(dated) \(today)")
        check("file show finds a note by its title", agent("file show", ["file": "CLI dated plan"])["name"] as? String == "2026-11-08 - CLI dated plan")
        agent("file write", ["file": "CLI dated plan", "section": "Next steps", "body": "Ship it."])
        agent("file write", ["file": "CLI dated plan", "replace": "# CLI dated plan", "with": "# CLI dated plan, v2"])
        let note = agent("file show", ["file": "2026-11-08 - CLI dated plan"])["body"] as? String ?? ""
        check("file write --section and --replace change one part", note == "# CLI dated plan, v2\n\n## Next steps\nShip it.\n", note)

        // task show: names, not paths; its reminders; several at once; deep, brief, body.
        agent("task link", ["task": key(story), "item": "2026-11-08 - CLI dated plan"])
        let reminder = model.remind("Look at the CLI story again", at: .now.addingTimeInterval(3600), level: .update, links: [ModalRoute.task(id(story)).selectionKey])
        let text = AgentCLI.human(agent("task show", ["task": key(story)]))
        check("task show prints a note by the name file show takes, and no vault path", text.contains("file: 2026-11-08 - CLI dated plan")
              && !text.contains("hq/tasks/") && !text.contains("hq/files/"), text)
        check("and the reminders that link the task", text.contains("Reminder: \(reminder.id.uuidString.prefix(8)) [later] Look at the CLI story again"), text)
        check("ls reminders lists them", (agent("ls", ["kind": "reminders"])["reminders"] as? [JSONObject] ?? []).contains { $0["text"] as? String == reminder.text })
        model.removeNotice(reminder.id)
        if let childID = TaskItem.key(key(child)) { model.changeTask(childID, "Edit Task") { $0.body = "Child detail." } }
        if let otherID = TaskItem.key(key(other)) {
            model.changeTask(otherID, "Edit Task") { $0.body = "Done detail." }
            model.setStatus(otherID, .done)
        }
        let deep = agent("task show", ["task": key(story), "deep": "true"])["subtasks"] as? [JSONObject] ?? []
        check("task show --deep gives each open subtask's description, not a done one's", deep.first?["body"] as? String == "Child detail."
              && deep.dropFirst().first?["body"] == nil, "\(deep)")
        check("--deep prints it under the subtask's line", AgentCLI.human(agent("task show", ["task": key(story), "deep": "true"])).contains("\n      Child detail."))
        let brief = agent("task show", ["task": key(story), "brief": "true"])
        check("--brief leaves the description out", brief["body"] == nil && brief["subtasks"] != nil)
        check("--body prints the description only", AgentCLI.human(agent("task show", ["task": key(story), "body": "true"])) == "The goal.")
        let several = agent("task show", ["task": "\(key(story)),\(key(child))"])
        check("task show takes several tasks", (several["shown"] as? [JSONObject])?.count == 2 && AgentCLI.human(several).contains("\n-----\n"))

        // Partial edits: a box, a section, an exact text.
        let checklist = "The goal.\n\n## Done when\n- [x] One\n- [ ] At most 3 attempts\n- [ ] At most 3 retries\n- [ ] Canary green\n\n## Status\nStarted."
        agent("task edit", ["task": key(story), "body": checklist])
        let ticked = agent("task tick", ["task": key(story), "item": "canary"])
        check("task tick ticks the one item that starts so, and says how many are", AgentCLI.human(ticked).hasSuffix("ticked “Canary green”: 2 of 4 ticked")
              && body(key(story)).contains("- [x] Canary green"), AgentCLI.human(ticked))
        check("an item two start is refused, naming them", failure(agent("task tick", ["task": key(story), "item": "At most 3"]))?.code == "usage")
        check("an item none starts is not found", failure(agent("task tick", ["task": key(story), "item": "Nothing like it"]))?.code == "not_found")
        check("a ticked one says so", (agent("task tick", ["task": key(story), "item": "- [ ] Canary green"])["text"] as? String)?.contains("already ticked") == true)
        check("--untick clears it", (agent("task tick", ["task": key(story), "item": "One", "untick": "true"])["text"] as? String)?.hasSuffix("1 of 4 ticked") == true)
        agent("task edit", ["task": key(story), "section": "Status", "body": "## Status\nMerged; watching the canary."])
        agent("task edit", ["task": key(story), "section": "Decisions", "body": "- A budget per upload."])
        check("task edit --section replaces one section and adds a missing one at the end",
              body(key(story)) == checklist.replacingOccurrences(of: "- [x] One", with: "- [ ] One").replacingOccurrences(of: "- [ ] Canary", with: "- [x] Canary")
                .replacingOccurrences(of: "Started.", with: "Merged; watching the canary.") + "\n\n## Decisions\n- A budget per upload.", body(key(story)))
        let replaced = agent("task edit", ["task": key(story), "replace": "The goal.", "with": "The goal, in one line."])
        check("task edit --replace changes the one text, and says what changed", body(key(story)).hasPrefix("The goal, in one line.\n")
              && replaced["note"] as? String == "Changed: description", "\(replaced["note"] ?? "")")
        check("a text found twice is refused", failure(agent("task edit", ["task": key(story), "replace": "At most 3", "with": "x"]))?.code == "usage")
        check("a text not there is not found", failure(agent("task edit", ["task": key(story), "replace": "absent words", "with": "x"]))?.code == "not_found")
        check("--with alone is refused", failure(agent("task edit", ["task": key(story), "with": "x"]))?.code == "usage")
        check("an edit that changes nothing says so", (agent("task edit", ["task": key(story), "project": "Registry"])["note"] as? String)?.hasPrefix("Nothing changed") == true)

        // Moves between lists; notifications about a task.
        let later = agent("task add", ["title": "CLI later", "backlog": "true"])
        let brought = agent("task move", ["task": key(later), "status": "todo", "list": "tasks"])
        check("task move todo --list tasks brings a Backlog task to Tasks, todo", brought["list"] as? String == "overview" && brought["status"] as? String == "todo", "\(brought)")
        check("--list takes tasks or backlog only", failure(agent("task move", ["task": key(later), "status": "todo", "list": "inbox"]))?.code == "usage")
        let told = agent("notify", ["text": "CLI story ready", "task": key(story)])
        let set = agent("remind", ["text": "CLI story again", "at": "in 2h", "task": key(story)])
        check("notify and remind take --task", (told["links"] as? [JSONObject])?.first?["id"] as? String == key(story)
              && (set["links"] as? [JSONObject])?.first?["id"] as? String == key(story), "\(told) \(set)")
        for row in [told, set] { if let rowID = (row["id"] as? String).flatMap({ UUID(uuidString: $0) }) { model.removeNotice(rowID) } }

        // A session's view: its project first, a stale write refused, a needless --not-mine said.
        let session = "5e550000-0000-4000-8000-00000000c71a"
        agent("hook", ["event": "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"\(session)\",\"cwd\":\"/tmp\",\"source\":\"startup\"}", "ghostty": "true"])
        let mine = agent("task add", ["title": "CLI ctx mine", "project": "CtxHome", "status": "doing", "body": "Mine.", "_session": session])
        let sibling = agent("task add", ["title": "CLI ctx sibling", "project": "CtxHome", "status": "doing"])
        let away = agent("task add", ["title": "CLI ctx away", "project": "CtxAway", "status": "doing"])
        let ctx = agent("ctx", ["_session": session])["text"] as? String ?? ""
        check("hq ctx lists what is doing in this session's project, and counts the rest", ctx.contains("CLI ctx sibling") && !ctx.contains("CLI ctx away")
              && ctx.contains("doing in other projects (hq ctx --all)"), ctx)
        check("hq ctx --all lists every project's", (agent("ctx", ["_session": session, "all": "true"])["text"] as? String)?.contains("CLI ctx away") == true)
        let due = model.remind("CLI due one", at: .now.addingTimeInterval(-60), level: .update, links: [ModalRoute.task(id(mine)).selectionKey])
        let start = model.startContext(session)
        check("the start text names the hq skill and a reminder due on its task", start.contains("Load the hq skill") && !start.contains("hq-tasks")
              && start.contains("A reminder is due on it: CLI due one"), start)
        model.removeNotice(due.id)
        agent("task show", ["task": key(mine), "_session": session])
        model.changeTask(id(mine), "Edit Task") { $0.body = "The user's edit." }
        let stale = failure(agent("task edit", ["task": key(mine), "body": "The session's old copy.", "_session": session]))
        check("task edit --body is refused when the description changed since the session read it", stale?.code == "stale"
              && stale?.message.contains("Read it again") == true && body(key(mine)) == "The user's edit.",
              "\(String(describing: stale))")
        agent("task edit", ["task": key(mine), "section": "Status", "body": "Going.", "_session": session])
        check("a section edit goes through: it changes only its part", body(key(mine)) == "The user's edit.\n\n## Status\nGoing.", body(key(mine)))
        agent("task show", ["task": key(mine), "body": "true", "_session": session])
        agent("task edit", ["task": key(mine), "body": "Read, then written.", "_session": session])
        check("read again, the write goes through", body(key(mine)) == "Read, then written.")
        agent("task edit", ["task": key(mine), "body": "Its own text, again.", "_session": session])
        check("and the session's own write counts as read", body(key(mine)) == "Its own text, again.")
        model.changeTask(id(mine), "Edit Task") { $0.body = "Another edit." }
        agent("task edit", ["task": key(mine), "body": "Forced.", "force": "true", "_session": session])
        check("--force writes over it", body(key(mine)) == "Forced.")
        let needless = (try? JSONSerialization.jsonObject(with: AgentRouter.handle(JSON.data(["command": "task edit", "args":
            ["task": key(mine), "add-tag": "cli", "not-mine": "true", "_session": session]])))) as? JSONObject ?? [:]
        check("a needless --not-mine is said, and the command runs", (needless["warnings"] as? [String])?.first == "\(key(mine)) is yours already: drop --not-mine"
              && model.task(id(mine))?.tags.contains("cli") == true, "\(needless["warnings"] ?? "none")")
        check("every reply names the build that runs", needless["app"] as? String == AgentVersion.atLaunch)
        agent("hook", ["event": "{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"\(session)\",\"reason\":\"other\"}"])

        // Leave the seed as it was.
        model.deleteTasks([story, linked, later, mine, sibling, away].map(id))
        for name in ["CLI dated plan", "CLI today plan"] { if let file = model.files.first(where: { $0.title == name }) { model.deleteFile(file.id) } }
    }

    /// Teams and roles through hq (T-407, T-414): session new under its caller, beside it, with a role and a history;
    /// session edit --parent; ctx with the team; ls sessions --tree; ls roles; role show, new, edit, delete; each refusal.
    static func cliTeamChecks(_ model: AppModel) async {
        func failure(_ result: JSONObject) -> (code: String, message: String)? {
            (result["error"] as? JSONObject).map { ($0["code"] as? String ?? "", $0["message"] as? String ?? "") }
        }
        let lead = "c11ea100-0000-4000-8000-000000000001", other = "c11ea200-0000-4000-8000-000000000002"
        let folder = NSTemporaryDirectory()
        model.put(SessionItem(id: lead, customName: "CLI lead", status: SessionStatus(state: .idle, since: .now), cwd: folder, repo: "cli", branch: "main",
                              started: .now, tty: "/dev/ttys077", order: model.nextGridOrder, role: "Leader"))
        model.put(SessionItem(id: other, customName: "CLI other lead", status: SessionStatus(state: .idle, since: .now), cwd: "/tmp", repo: "cli", branch: "other",
                              started: .now, order: model.nextGridOrder))
        guard let task = model.addTask(to: .overview, title: "CLI team piece", session: lead) else { return check("a task for the team", false) }

        // session new: under its caller, in its Ghostty window, with a role.
        var log = model.ghosttyLog.count
        let worker = agent("session new", ["name": "CLI worker", "task": task.key, "role": "worker", "_session": lead])
        let workerID = worker["id"] as? String ?? ""
        check("session new from a session starts under it, with its role, in a tab of its Ghostty window",
              model.session(workerID)?.parent == lead && model.session(workerID)?.role == "Worker" && worker["role"] as? String == "Worker"
              && worker["parent"] as? String == lead && model.ghosttyLog.count == log + 1
              && model.ghosttyLog.last?.hasPrefix("new tab in the window of /dev/ttys077, in \(folder): claude --session-id \(workerID)") == true
              && (worker["started"] as? String)?.contains("it reports to you") == true, "\(worker) \(model.ghosttyLog.last ?? "-")")
        let beside = agent("session new", ["name": "CLI handoff", "beside": "true", "_session": workerID])
        check("--beside starts it at the caller's level: under the caller's parent", model.session(beside["id"] as? String)?.parent == lead, "\(beside)")
        let top = agent("session new", ["name": "CLI top", "parent": "none", "_session": lead])
        check("--parent none starts it at the top level", (top["id"] as? String).map { model.session($0)?.parent == nil && model.session($0) != nil } == true, "\(top)")
        log = model.ghosttyLog.count
        let named = agent("session new", ["name": "CLI under other", "parent": "CLI other lead", "history": String(lead.prefix(8)), "_session": lead])
        check("--parent takes a name, --history a session's conversation and its folder; a parent not in Ghostty opens a tab in the front window",
              model.session(named["id"] as? String)?.parent == other && model.ghosttyLog.count == log + 1
              && model.ghosttyLog.last?.hasPrefix("new tab in \(folder): claude --resume \(lead) --fork-session") == true, model.ghosttyLog.last ?? "-")
        let both = failure(agent("session new", ["name": "CLI both", "beside": "true", "parent": "none", "_session": lead]))
        let alone = failure(agent("session new", ["name": "CLI alone", "beside": "true", "cwd": folder]))
        let noRole = failure(agent("session new", ["name": "CLI no role", "role": "Pilot", "_session": lead]))
        let noParent = failure(agent("session new", ["name": "CLI no parent", "parent": "nobody-at-all", "_session": lead]))
        check("--beside with --parent, or outside a session, is refused", both?.code == "usage" && alone?.code == "usage", "\(String(describing: both)) \(String(describing: alone))")
        check("an unknown role is refused, naming the roles", noRole?.code == "not_found" && noRole?.message.contains("Roles: Leader, Worker") == true, noRole?.message ?? "-")
        check("an unknown session is refused, naming the open ones, the latest first", noParent?.code == "not_found"
              && noParent?.message.contains("Open sessions: ") == true && noParent?.message.contains("CLI worker") == true, noParent?.message ?? "-")
        let refused = model.sessions.filter { ["CLI both", "CLI alone", "CLI no role", "CLI no parent"].contains($0.name) }
        check("and a refused one starts nothing", refused.isEmpty, "\(refused.map(\.name))")

        // session edit --parent: Move Under, Make Root, never under its own team.
        let handoff = beside["id"] as? String ?? ""
        let moved = agent("session edit", ["session": handoff, "parent": String(workerID.prefix(8))])
        check("session edit --parent moves it under another", model.session(handoff)?.parent == workerID && moved["note"] as? String == "Moved under “CLI worker”", "\(moved)")
        let loop = failure(agent("session edit", ["session": lead, "parent": handoff]))
        let itself = failure(agent("session edit", ["session": lead, "parent": lead]))
        check("never under a session of its own team, nor itself", loop?.code == "invalid" && loop?.message.contains("its own team") == true
              && itself?.code == "invalid" && model.session(lead)?.parent == nil, "\(String(describing: loop)) \(String(describing: itself))")
        check("without --parent it says what to change", failure(agent("session edit", ["session": handoff]))?.code == "usage")
        agent("session edit", ["session": handoff, "parent": "none"])
        check("--parent none makes it a root", model.session(handoff)?.parent == nil)
        check("a move that changes nothing says so", (agent("session edit", ["session": handoff, "parent": "none"])["note"] as? String)?.hasPrefix("Nothing changed") == true)
        agent("session edit", ["session": handoff, "parent": lead])

        // ctx: the role, who started it, and its sessions with their role, state and task.
        let leadCtx = agent("ctx", ["_session": lead])
        let leadText = leadCtx["text"] as? String ?? ""
        check("hq ctx shows the session's role and its sessions with their role, state and task, indented",
              leadText.hasPrefix("This session: CLI lead · Leader") && leadText.contains("Your sessions (")
              && leadText.contains("\n  \(workerID.prefix(8)) [idle] CLI worker · Worker · \(task.key)")
              && (leadCtx["team"] as? [JSONObject])?.compactMap { $0["id"] as? String }.contains(handoff) == true, leadText)
        let workerText = agent("ctx", ["_session": workerID])["text"] as? String ?? ""
        check("and the session that started it, with how to message it", workerText.contains("Started by: CLI lead (Leader, idle) · \(lead.prefix(8)). You report to it: SendMessage, to “CLI lead”")
              && !workerText.contains("Other open sessions:\n  CLI lead"), workerText)

        // ls sessions --tree, ls roles.
        let tree = agent("ls", ["kind": "sessions", "tree": "true"])
        let rows = (tree["sessions"] as? [JSONObject] ?? []).map { ($0["id"] as? String ?? "", $0["depth"] as? Int ?? -1) }
        let at = rows.firstIndex { $0.0 == lead }
        check("ls sessions --tree lists each team under its top session, with depths", at.map { rows.indices.contains($0 + 1) && rows[$0 + 1] == (workerID, 1) && rows[$0].1 == 0 } == true
              && AgentCLI.human(tree).contains("\n  \(workerID.prefix(8)) [Idle] CLI worker · Worker"), "\(rows.suffix(6))")
        check("--tree is for sessions only", failure(agent("ls", ["kind": "tasks", "tree": "true"]))?.code == "usage")
        let roles = agent("ls", ["kind": "roles"])
        check("ls roles lists them, shipped ones first, with how many open sessions have each", (roles["roles"] as? [JSONObject])?.prefix(2).compactMap { $0["name"] as? String } == ["Leader", "Worker"]
              && AgentCLI.human(roles).hasPrefix("Leader [indigo] Leads a story and keeps its task tree small and current. Never writes the code. · opus xhigh · ships with HQ · "), AgentCLI.human(roles))

        // role show, new, edit, delete.
        let shown = AgentCLI.human(agent("role show", ["role": "worker"]))
        check("role show prints its line, its text and who uses it", shown.hasPrefix("Worker [brown] · opus high · ships with HQ · ") && shown.contains(RoleItem.workerText)
              && shown.contains("\n\nUsed by:\n") && shown.contains("\n  \(workerID.prefix(8)) [idle] CLI worker"), shown)
        let made = agent("role new", ["name": "CLI Reviewer", "line": "Reviews one PR.", "color": "pink", "body": "Read the diff.\n"])
        check("role new makes its note", model.role(named: "CLI Reviewer").map { $0.color == .pink && $0.line == "Reviews one PR." && $0.text == "Read the diff." && $0.path != nil } == true
              && (made["text"] as? String)?.hasPrefix("Made role CLI Reviewer [pink]") == true, "\(made)")
        check("one with that name again is refused", failure(agent("role new", ["name": "cli reviewer"]))?.code == "invalid")
        let badColor = failure(agent("role new", ["name": "CLI Painter", "color": "beige"]))
        check("an unknown color is refused, naming the colors", badColor?.code == "usage" && badColor?.message.contains("indigo") == true, badColor?.message ?? "-")
        check("a name with a slash is refused: it names a note", failure(agent("role new", ["name": "CLI a/b"]))?.code == "usage")
        let edited = agent("role edit", ["role": "CLI Reviewer", "name": "CLI Critic", "line": "Reviews one pull request."])
        check("role edit renames its note and changes its line, saying what changed", model.role(named: "CLI Critic")?.line == "Reviews one pull request."
              && model.role(named: "CLI Reviewer") == nil && edited["text"] as? String == "Changed role CLI Critic: name, line", "\(edited)")
        let written = "Read the diff.\n\n- Say what to fix, with the line."
        _ = agent("role edit", ["role": "CLI Critic", "body": written])
        let again = agent("role show", ["role": "CLI Critic"])
        check("role show --json's text is what role edit --body wrote: show then edit gives the role back",
              again["text"] as? String == written && again["body"] as? String == written
              && AgentCLI.human(again).hasPrefix("CLI Critic [pink]") && AgentCLI.human(again).contains(written), "\(again)")
        check("role edit with nothing to change is refused", failure(agent("role edit", ["role": "CLI Critic"]))?.code == "usage")
        check("so is a name another role has", failure(agent("role edit", ["role": "CLI Critic", "name": "Leader"]))?.code == "invalid")
        check("role show on a role that isn't there names the roles", failure(agent("role show", ["role": "CLI Reviewer"]))?.message.contains("Roles: Leader, Worker") == true)
        let would = agent("role delete", ["role": "CLI Critic"])
        check("role delete without --yes only says what it would do", would["wouldDelete"] as? String == "CLI Critic" && model.role(named: "CLI Critic") != nil)
        let deleted = agent("role delete", ["role": "CLI Critic", "yes": "true"])
        check("with --yes its note goes to the Trash", deleted["deleted"] as? String == "CLI Critic" && model.role(named: "CLI Critic") == nil, "\(deleted)")
        let names = Set(AgentCommands.all.map(\.name))
        check("hq help has each command for teams and roles", ["session new", "session edit", "role show", "role new", "role edit", "role delete"].allSatisfy(names.contains)
              && AgentCommands.all.first { $0.name == "session new" }.map { cmd in ["role", "parent", "beside", "history"].allSatisfy { p in cmd.params.contains { $0.name == p } } } == true)

        model.deleteTasks([task.id])
        let started = Set([workerID, handoff, top["id"] as? String, named["id"] as? String].compactMap { $0 })
        model.sessions.removeAll { started.contains($0.id) || [lead, other].contains($0.id) }
    }
}
