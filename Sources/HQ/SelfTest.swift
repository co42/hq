import AppKit
import HQKit

/// Self-test: runs the app's real functions on sample data and a scratch vault, prints PASS or
/// FAIL per check, and quits with 0 or 1.
///   APP_STORE=/tmp/HQ-self.store HQ --selftest     (tools/selftest.sh)
///   HQ_OLD_STORE=<copy of a store>                  also checks that an older store opens
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            let missing = KitIcon.allCases.filter { $0.nsImage == nil }.map(\.name)
            check("every KitIcon symbol exists", missing.isEmpty, missing.joined(separator: ", "))
            oldStore()
            SeedData.fill(model, now: .now)
            attentionChecks(model)
            faceChecks(model)
            await sessionChecks(model)
            await vaultChecks(model)
            await cliChecks(model)
            labelChecks(model)
            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    /// A store written by an older HQ (folders, archived sessions) opens, with its sessions.
    private static func oldStore() {
        guard let path = ProcessInfo.processInfo.environment["HQ_OLD_STORE"], !path.isEmpty else { return }
        do {
            let storage = try Storage(url: URL(fileURLWithPath: path))
            let sessions = storage.sessions()
            check("an older store opens with its sessions", !sessions.isEmpty, "\(sessions.count) sessions")
            check("its ended sessions are closed", sessions.filter { $0.status.state == .ended }.allSatisfy { $0.closedAt != nil })
        } catch {
            check("an older store opens with its sessions", false, "\(error)")
        }
    }

    // MARK: Attention

    private static func attentionChecks(_ model: AppModel) {
        check("orange counts sessions that wait, tasks in Review and PRs waiting for review",
              model.needsYouCount == 4 + 2 + 2, "\(model.needsYouCount)")
        let queue = model.attentionQueue
        check("Review Next starts at the top of the page: the first PR that waits for the user", queue.first == .github("https://github.com/acme/registry/pull/430"), "\(queue.prefix(3))")
        check("then the first card that needs the user", queue.first { if case .session = $0 { true } else { false } } == .session("250a8563-5c74-4592-a463-b41398dc5b55"))
        if let pr = queue.firstIndex(where: { if case .github = $0 { true } else { false } }),
           let outline = queue.firstIndex(of: .task(45)) {
            check("Review Next walks cards, then PRs, then the outline", pr < outline)
        }
        model.closeModal()
        model.reviewNext()
        let first = model.modal
        model.reviewNext()
        check("Review Next moves on", model.modal != first && model.modal != nil, "\(String(describing: first)) → \(String(describing: model.modal))")
        model.closeModal()
        let before = model.newCount
        model.open(.task(45))
        check("opening a new item marks it seen", !model.isNew(.task(45)) && model.newCount == before - 1)
        model.closeModal()
        model.markAllSeen()
        check("Mark All Seen clears every blue item, orange stays", model.newCount == 0 && model.needsYouCount == 8)
        model.markReviewed("https://github.com/acme/static-cdn/pull/512")
        check("Mark Reviewed quiets a PR until its next commit", model.needsYouCount == 7)
    }

    // MARK: Faces

    private static func faceChecks(_ model: AppModel) {
        let open = model.sessions.filter { $0.closedAt == nil }
        let signatures = open.map(\.face.signature)
        check("no two open sessions share background and headwear", Set(signatures).count == signatures.count, "\(signatures)")
        model.saveSessionsNow()
        let stored = (try? Storage(url: Store.url))?.sessions() ?? []
        check("a session's face salt survives a relaunch",
              open.allSatisfy { session in stored.first { $0.id == session.id }?.faceSalt == session.faceSalt } && !stored.isEmpty)
        // A session that would look like an open one gets the next salt.
        let id = "5eed0000-face-4000-8000-000000000001"
        let taken = model.sessions.first { $0.closedAt == nil }!.face.signature
        var salt = 0
        for candidate in 0...8 where FaceSpec(id: id, salt: candidate).signature != taken { salt = candidate; break }
        check("a face salt is the first that differs from the open sessions", model.faceSalt(for: id) >= 0 && FaceSpec(id: id, salt: salt).signature != taken)
    }

    // MARK: Sessions

    /// A command through the socket's router, as `hq` sends it.
    @discardableResult
    private static func agent(_ command: String, _ args: [String: String]) -> JSONObject {
        let reply = AgentRouter.handle(JSON.data(["command": command, "args": args]))
        let object = (try? JSONSerialization.jsonObject(with: reply)) as? JSONObject
        return object?["result"] as? JSONObject ?? object ?? [:]
    }

    private static func hook(_ name: String, _ id: String, _ extra: String = "", pid: Int32? = nil) {
        var args = ["event": "{\"hook_event_name\":\"\(name)\",\"session_id\":\"\(id)\",\"cwd\":\"\(FileManager.default.currentDirectoryPath)\"\(extra)}"]
        if let pid { args["pid"] = "\(pid)" }
        agent("hook", args)
    }

    private static func sessionChecks(_ model: AppModel) async {
        let id = "5e550000-0000-4000-8000-000000000001"
        let end = model.gridSessions.count
        hook("SessionStart", id, #","source":"startup""#)
        check("a new session joins the end of the grid", model.gridSessions.last?.id == id && model.gridSessions.count == end + 1)
        hook("UserPromptSubmit", id, #","prompt":"Harden the registry push path\nwith retries""#)
        check("the first prompt names the session", model.session(id)?.name == "Harden the registry push path")
        hook("PermissionRequest", id, #","tool_name":"Bash","tool_input":{"command":"kubectl rollout restart deploy/api"}"#)
        check("a permission request needs the user, with the command", model.session(id)?.reason == "Wants to run Bash · kubectl rollout restart deploy/api")
        hook("PostToolUse", id, #","tool_name":"Bash","tool_input":{"command":"gh pr create --fill"},"tool_response":{"stdout":"https://github.com/acme/registry/pull/999\n"}"#)
        check("a PR the session opens links to it", model.session(id)?.links == ["https://github.com/acme/registry/pull/999"])
        hook("Stop", id, #","last_assistant_message":"Done.""#)
        check("Stop makes the session new, not orange", model.session(id)?.status.isNew == true && model.session(id)?.status.needsYou == false)
        // A /rename writes the transcript only: HQ sees it without waiting for the next prompt.
        let transcript = "/tmp/HQ-self-transcript.jsonl"
        try? "{\"type\":\"ai-title\",\"aiTitle\":\"Registry push path\"}\n".write(toFile: transcript, atomically: false, encoding: .utf8)
        hook("Stop", id, ",\"transcript_path\":\"\(transcript)\"")
        check("Stop reads the transcript's title", model.session(id)?.name == "Registry push path", model.session(id)?.name ?? "-")
        func append(_ text: String) {
            guard let handle = FileHandle(forWritingAtPath: transcript) else { return }
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        }
        // A name HQ gave the session gives way to a /rename.
        model.renameSession(id, to: "Named by HQ")
        append("{\"type\":\"custom-title\",\"customTitle\":\"Registry retries\"}\n")
        try? await Task.sleep(for: .seconds(1.6))
        check("a /rename shows within a second or two, over a name HQ gave", model.session(id)?.name == "Registry retries", model.session(id)?.name ?? "-")
        // Far past the end HQ reads, Claude's next title doesn't undo the /rename.
        append(String(repeating: "{\"type\":\"progress\"}\n", count: 4_000) + "{\"type\":\"ai-title\",\"aiTitle\":\"Something else\"}\n")
        hook("Stop", id, ",\"transcript_path\":\"\(transcript)\"")
        check("a /rename stays when Claude retitles later", model.session(id)?.name == "Registry retries", model.session(id)?.name ?? "-")
        check("the last /rename is found however far back", TranscriptTitle.lastRename(transcript) == "Registry retries")
        // The user renames it in HQ after: the old /rename doesn't come back.
        model.renameSession(id, to: "My own name")
        append("{\"type\":\"custom-title\",\"customTitle\":\"Registry retries\"}\n")
        hook("Stop", id, ",\"transcript_path\":\"\(transcript)\"")
        check("an old /rename doesn't undo the user's rename in HQ", model.session(id)?.name == "My own name", model.session(id)?.name ?? "-")
        // Esc or Ctrl+C in the terminal: no Stop comes; the transcript's interrupt makes the session idle.
        hook("UserPromptSubmit", id, #","prompt":"Go on""#)
        check("a prompt makes it work", model.session(id)?.status.state == .working)
        if let handle = FileHandle(forWritingAtPath: transcript) {
            let stamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(.now)
            handle.seekToEndOfFile()
            handle.write(Data(#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]},"timestamp":"\#(stamp)"}"#.utf8))
            handle.write(Data("\n".utf8))
            try? handle.close()
        }
        try? await Task.sleep(for: .seconds(1.6))
        check("Esc in its terminal stops Working within a second or two", model.session(id)?.status.state == .idle,
              String(describing: model.session(id)?.status.state))
        let order = model.gridSessions.map(\.id)
        model.moveSession(id, to: 0)
        check("a card moves to where it's dropped", model.gridSessions.first?.id == id)
        model.undoManager?.undo()
        try? await Task.sleep(for: .milliseconds(100))
        check("Undo puts the cards back", model.gridSessions.map(\.id) == order, "\(model.gridSessions.map { $0.id.prefix(4) })")
        model.setHidden(id, true)
        check("Hide takes the card off the grid, the session keeps running", !model.gridSessions.contains { $0.id == id } && model.hiddenSessions.contains { $0.id == id })
        model.setHidden(id, false)
        check("Show puts it back at the end", model.gridSessions.last?.id == id)
        hook("SessionEnd", id, #","reason":"prompt_input_exit""#)
        check("an ended session leaves the grid for Closed", !model.gridSessions.contains { $0.id == id } && model.closedSessions.first?.id == id)
        let before = model.ghosttyLog.count
        model.open(id)
        check("Resume opens a Ghostty tab and puts the card at the end", model.ghosttyLog.count == before + 1
              && model.ghosttyLog.last?.contains("claude --resume \(id)") == true && model.gridSessions.last?.id == id)
        hook("SessionStart", id, #","source":"resume""#)
        check("a resumed session runs again", model.session(id)?.isRunning == true && model.session(id)?.closedAt == nil)
        // Running in no terminal HQ knows: focusing it opens its modal, which says so, instead of nothing.
        if var lone = model.session(id) {
            let saved = lone
            lone.tty = nil
            model.put(lone)
            model.closeModal()
            let logged = model.ghosttyLog.count
            model.openFace(id)
            check("a running session with no known terminal opens its modal on a face click", model.modal == .session(id)
                  && model.ghosttyLog.count == logged, String(describing: model.modal))
            model.closeModal()
            model.put(saved)
        }
        // The task dropped on a card links to its session.
        model.link(task: 45, session: id)
        check("a task dropped on a card works on its session", model.tasks(of: id).map(\.id) == [45] && model.sessions(on: 45).contains { $0.id == id })
        // Ended, its face stays on the task, dimmed; a double-click on it asks before resuming.
        hook("SessionEnd", id, #","reason":"prompt_input_exit""#)
        check("an ended session's face stays on its task, after the open ones",
              !model.sessions(on: 45).contains { $0.id == id } && model.sessions(on: 45, includeEnded: true).last?.id == id)
        let asks = model.ghosttyLog.count
        model.openFace(id)
        check("a double-click on an ended face asks before resuming", model.ghosttyLog.last == "ask resume \(id)" && model.ghosttyLog.count == asks + 1)
        hook("SessionStart", id, #","source":"resume""#)
        // Close Session: /exit in its terminal, then the terminal closes once Claude has quit.
        if var item = model.session(id) {
            item.pid = 999_999
            item.tty = "/dev/ttys099"
            model.put(item)
            model.closeSession(id)
            model.processExited(999_999)
            check("Close Session types /exit, then closes its terminal once Claude quits",
                  model.ghosttyLog.suffix(2) == ["type /exit in /dev/ttys099", "close /dev/ttys099"], "\(model.ghosttyLog.suffix(2))")
            hook("SessionStart", id, #","source":"resume""#)
        }
        // A review session shows on its PR from the start.
        let review = model.startSession(named: "Review #7", in: NSTemporaryDirectory(), pullRequest: "https://github.com/acme/registry/pull/7")
        check("a review session is linked to its PR", model.session(review)?.links == ["https://github.com/acme/registry/pull/7"])
        model.sessions.removeAll { $0.id == review }
    }

    // MARK: Vault

    /// The board's notes on a scratch vault: the migration with its backup, then edits through the tree.
    private static func vaultChecks(_ model: AppModel) async {
        func settle(_ seconds: Double = 0.3) async { try? await Task.sleep(for: .seconds(seconds)) }
        let root = URL(fileURLWithPath: "/tmp/HQ-self-vault")
        let tasks = root.appending(path: "hq/tasks")
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: Store.backups)
        try? FileManager.default.createDirectory(at: tasks, withIntermediateDirectories: true)
        let old: [(Int, String)] = [
            (1, "---\ntitle: Backlog idea\nstatus: backlog\naliases: [idea]\n---\nKeep this **body**.\n"),
            (2, "---\ntitle: Next up\nstatus: todo\ntags: [registry]\n---\n"),
            (3, "---\ntitle: In progress\nstatus: doing\nsessions: [abc]\n---\nBody.\n\n**2026-11-03 16:12 · Claude**: a note.\n"),
            (4, "---\ntitle: Finished\nstatus: done\n---\n"),
        ]
        for (id, text) in old { try? text.write(to: tasks.appending(path: "T-\(id).md"), atomically: true, encoding: .utf8) }
        model.tasks = []
        model.files = []
        model.vault = Vault(vault: root)
        model.startVault()
        await settle(0.8)
        let backups = (try? FileManager.default.contentsOfDirectory(atPath: Store.backups.path)) ?? []
        check("the migration backs up hq/tasks first", backups.contains { $0.hasPrefix("tasks-") && $0.hasSuffix(".zip") }, "\(backups)")
        func note(_ id: Int) -> FrontMatter { FrontMatter((try? String(contentsOf: tasks.appending(path: "T-\(id).md"), encoding: .utf8)) ?? "") }
        check("backlog becomes todo in the Backlog", note(1).string("status") == "todo" && note(1).string("list") == "backlog")
        check("todo goes to the Backlog, doing to the overview", note(2).string("list") == "backlog" && note(3).string("list") == "overview")
        check("done goes to the Backlog with its date", note(4).string("list") == "backlog" && note(4).string("done") != nil)
        check("a note without a type keeps none", (1...4).allSatisfy { note($0).string("type") == nil })
        check("other keys and bodies stay byte for byte",
              note(1).list("aliases") == ["idea"] && note(1).body == "Keep this **body**.\n" && note(3).body.contains("**2026-11-03 16:12 · Claude**: a note."))
        let snapshot = (1...4).map { (try? String(contentsOf: tasks.appending(path: "T-\($0).md"), encoding: .utf8)) ?? "" }
        model.migrateVault()
        check("a second run changes nothing", (1...4).map { (try? String(contentsOf: tasks.appending(path: "T-\($0).md"), encoding: .utf8)) ?? "" } == snapshot)
        check("the outline reads the lists", model.taskTree.top(.overview) == [3] && Set(model.taskTree.top(.backlog)) == [1, 2, 4], "\(model.taskTree.top(.overview)) \(model.taskTree.top(.backlog))")

        // Edits write only what changed, one Undo each.
        model.indent(4)
        await settle()
        check("Tab nests a task: parent written, list dropped", note(4).string("parent") != nil && !note(4).has("list"), note(4).text)
        model.undoManager?.undo()
        await settle()
        check("Undo Indent puts it back at the top", note(4).string("parent") == nil && note(4).string("list") == "backlog", note(4).text)
        model.move(1, to: .overview)
        await settle()
        check("Move to Tasks writes the list", note(1).string("list") == "overview" && model.taskTree.top(.overview).last == 1)
        model.setStatus(3, .review, reason: "PR is ready")
        await settle()
        check("Review writes its reason", note(3).string("status") == "review" && note(3).string("review") == "PR is ready")
        model.setStatus(3, .doing)
        await settle()
        check("leaving Review drops its reason", !note(3).has("review"))
        model.setDescription(2, "- [ ] one\n- [ ] two")
        model.toggleCheckbox(2, at: 1)
        await settle()
        check("a checkbox ticks in the note", note(2).body == "- [ ] one\n- [x] two\n", note(2).body)
        // The done rule: done yesterday, still on the overview, moves to the Backlog.
        model.setStatus(1, .done)
        model.changeTask(1, "Seed") { $0.done = Date.now.addingTimeInterval(-36 * 3600) }
        model.rollDoneTasks()
        await settle()
        check("a done task moves to the top of the Backlog the next morning", model.list(of: 1) == .backlog && model.taskTree.top(.backlog).first == 1)
        // The user's own edits never make anything blue.
        check("the user's edits never make a task new", !model.isNew(.task(3)))
        model.deleteTasks([3])
        await settle()
        check("Delete moves the note to the Trash", !FileManager.default.fileExists(atPath: tasks.appending(path: "T-3.md").path))
        model.undoManager?.undo()
        await settle(0.6)
        check("Undo brings it back", FileManager.default.fileExists(atPath: tasks.appending(path: "T-3.md").path) && model.task(3) != nil)
    }

    // MARK: Labels

    /// Title words, completions, colors, the Story status and a description's first line.
    private static func labelChecks(_ model: AppModel) {
        guard let task = model.addTask(to: .backlog, title: "Labels") else { return check("a task for labels", false) }
        let untyped = agent("task add", ["title": "No type yet"])
        check("a task has no type until one is set", task.type == nil && untyped["type"] == nil && untyped["id"] != nil, "\(untyped)")
        if let key = untyped["id"] as? String, let id = TaskItem.key(key) {
            agent("task edit", ["task": key, "type": "bug", "title": "Typed now #infra"])
            check("task edit --type sets it; --title applies its #words", model.task(id)?.type == .bug && model.task(id)?.tags.contains("infra") == true
                  && model.task(id)?.title == "Typed now", "\(String(describing: model.task(id)))")
            agent("task move", ["task": key, "status": "doing"])
            check("doing brings a Backlog task to Tasks", model.list(of: id) == .overview && model.task(id)?.status == .doing)
            if let artifact = model.artifacts.first {
                agent("task link", ["task": key, "item": artifact.id.absoluteString])
                check("task link with an artifact's URL links the artifact", model.outputs(ofTask: id).contains(.artifact(artifact.id))
                      && model.task(id)?.links.isEmpty == true)
            }
            let doing = agent("task add", ["title": "Start now #doing"])
            check("#doing in a new task's title puts it on Tasks", doing["list"] as? String == "overview" && doing["status"] as? String == "doing", "\(doing)")
            if let other = (doing["id"] as? String).flatMap(TaskItem.key) { model.deleteTasks([other]) }
            model.deleteTasks([id])
        }
        model.setProject(task.id, "Machine Identities")
        model.setTitle(task.id, "Rotate keys #doing #machine-identities #infra")
        let renamed = model.task(task.id)
        check("#status, #project and #tag in a title set the status, the project and a tag",
              renamed?.title == "Rotate keys" && renamed?.status == .doing && renamed?.project == "Machine Identities" && renamed?.tags.contains("infra") == true,
              "\(String(describing: renamed))")
        model.setTitle(task.id, "Rotate keys #story")
        check("#story makes it a story, a type: the status stays", model.task(task.id)?.type == .story && model.task(task.id)?.status == .doing
              && TaskStatus(parsing: "story") == nil, "\(String(describing: model.task(task.id)))")
        let legacy = FileManager.default.temporaryDirectory.appending(path: "T-9001.md")
        try? "---\ntitle: Old idea\nstatus: story\n---\n".write(to: legacy, atomically: true, encoding: .utf8)
        let read = Vault.task(at: legacy, modified: .now)
        check("a note still on the story status reads as a todo story", read?.status == .todo && read?.type == .story, "\(String(describing: read))")
        try? FileManager.default.removeItem(at: legacy)
        // A subtask's note read empty (downloading, mid-write) keeps its last read and its parent, then reads again.
        let notes = FileManager.default.temporaryDirectory.appending(path: "HQ-selftest-vault-\(UUID().uuidString)")
        let taskNotes = notes.appending(path: "hq/tasks")
        try? FileManager.default.createDirectory(at: taskNotes, withIntermediateDirectories: true)
        let child = taskNotes.appending(path: "T-2.md")
        try? "---\ntitle: Parent\nlist: overview\n---\n".write(to: taskNotes.appending(path: "T-1.md"), atomically: true, encoding: .utf8)
        try? "---\ntitle: Child\nparent: T-1\n---\n".write(to: child, atomically: true, encoding: .utf8)
        let vault = Vault(vault: notes)
        let first = vault.scan(Vault.Cache())
        try? "".write(to: child, atomically: false, encoding: .utf8)
        try? FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(5)], ofItemAtPath: child.path)
        let early = vault.scan(first.cache)
        check("a subtask's note read empty keeps its parent and says so", early.tasks.first { $0.id == 2 }?.parent == 1
              && early.unreadable == ["T-2.md"], "\(early.unreadable) \(String(describing: early.tasks.first { $0.id == 2 }))")
        try? "---\ntitle: Child, renamed\nparent: T-1\n---\n".write(to: child, atomically: true, encoding: .utf8)
        let again = vault.scan(early.cache)
        check("and is read again once it's whole", again.tasks.first { $0.id == 2 }?.title == "Child, renamed" && again.unreadable.isEmpty)
        try? FileManager.default.removeItem(at: notes)
        let completions = model.titleCompletions("re")
        check("completions after # list statuses first, then projects and tags", completions.first == "review", "\(completions)")
        check("completions find projects by their dashed name", model.titleCompletions("mach").contains("Machine-Identities"), "\(model.titleCompletions("mach"))")
        let automatic = model.labelColor(.tag, "infra")
        check("a tag's color follows its name until picked", automatic == LabelColor.automatic("infra") && model.labelColor(.tag, "Infra") == automatic)
        let picked: LabelColor = automatic == .green ? .pink : .green
        model.setLabelColor(picked, .tag, "infra")
        check("a picked color sticks", model.labelColor(.tag, "infra") == picked)
        model.setLabelColor(nil, .tag, "infra")
        check("Automatic goes back to the name's color", model.labelColor(.tag, "infra") == automatic)
        check("a description's first line drops markdown marks",
              Markdown.firstLine("\n# Retry **budget**\nMore") == "Retry budget" && Markdown.firstLine("```\ncode\n```") == "code"
                && Markdown.firstLine("- [ ] Ship [it](https://x.y) in `cli`") == "Ship it in cli", Markdown.firstLine("- [ ] Ship [it](https://x.y) in `cli`"))
        // Links between tasks, both ways; pins and labels on files.
        guard let other = model.addTask(to: .backlog, title: "Linked") else { return check("a task to link", false) }
        let linked = agent("task link", ["task": task.key, "item": other.key])
        check("task link T-a T-b links two tasks, each shows the other",
              (linked["related"] as? [String]) == [other.key] && model.outputs(ofTask: other.id).contains(.task(task.id))
                && model.outputs(ofTask: task.id).contains(.task(other.id)) && model.tasksWithOutputs.isSuperset(of: [task.id, other.id]), "\(linked)")
        check("a task can't link to itself", (agent("task link", ["task": task.key, "item": task.key])["error"] as? JSONObject) != nil)
        model.unrelate(other.id, from: task.id)
        check("Unlink removes the link both ways", !model.outputs(ofTask: task.id).contains(.task(other.id)) && !model.outputs(ofTask: other.id).contains(.task(task.id)))
        if let old = model.addFile(title: "Older note"), let pinned = model.addFile(title: "Pinned note") {
            model.setFileLabels(pinned.id, project: .some("Registry"), tags: ["#perf", "perf"])
            model.setFileLabels(pinned.id, pinned: true)
            let saved = model.file(pinned.id).flatMap(\.path).flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? ""
            check("a file's project, tags and pin go to its front matter", saved.contains("pinned: true") && saved.contains("project: Registry") && saved.contains("perf")
                  && model.file(pinned.id)?.tags == ["perf"], saved)
            check("pinned files come first", model.listedFiles.first?.id == pinned.id)
            model.pinnedOnly = true
            check("Pinned Only shows pinned files only", model.listedFiles.map(\.id) == [pinned.id])
            model.pinnedOnly = false
            _ = old
        }
        let imported = agent("artifact add", ["url": "https://claude.ai/artifact/AbC123?sk=secret", "title": "Bench", "date": "2026-11-03", "task": task.key])
        agent("artifact add", ["url": "https://claude.ai/artifact/AbC123", "title": "Bench speed"])
        let artifacts = model.artifacts.filter { $0.id.absoluteString == "https://claude.ai/artifact/AbC123" }
        check("artifact add imports an artifact once, without its share key, with its date and task",
              imported["url"] as? String == "https://claude.ai/artifact/AbC123" && artifacts.count == 1 && artifacts.first?.title == "Bench speed"
                && artifacts.first?.tasks == [task.id] && artifacts.first.map { NoteDate.day($0.published) } == "2026-11-03", "\(imported)")
        // Projects: a folder and repositories, where sessions on their tasks and PRs start.
        let folder = FileManager.default.temporaryDirectory.path
        let projectLinked = agent("project edit", ["project": "Registry", "folder": folder, "repo": "https://github.com/acme/registry.git, acme/image-sync"])
        check("project edit sets a project's folder and repositories", projectLinked["folder"] as? String == (folder as NSString).abbreviatingWithTildeInPath
              && (projectLinked["repos"] as? [String]) == ["acme/registry", "acme/image-sync"], "\(projectLinked)")
        check("ls projects lists it", ((agent("ls", ["kind": "projects"])["projects"] as? [JSONObject]) ?? []).contains { $0["name"] as? String == "Registry" })
        model.setProject(task.id, "Registry")
        if let sub = model.addSubtask(to: task.id, title: "Part") {
            model.beginStart(task: sub.id)
            check("Start Session on a subtask starts in its parent's project's folder",
                  model.startDraft?.folder == (folder as NSString).abbreviatingWithTildeInPath || model.startDraft?.folder == folder, model.startDraft?.folder ?? "-")
            model.closeModal()
            model.deleteTasks([sub.id])
        }
        check("a PR's repository finds its project", model.project(ofRepo: "Acme/image-sync") == "Registry")
        model.setLinks("Registry", folder: .some(nil), repos: [])
        // task show: the tasks it's part of, its subtasks and what's linked, in JSON and as text.
        if let middle = model.addSubtask(to: task.id, title: "Middle"), let leaf = model.addSubtask(to: middle.id, title: "Leaf") {
            model.link(task: middle.id, url: URL(string: "https://github.com/acme/registry/pull/9")!)
            let shown = agent("task show", ["task": middle.key])
            let parents = (shown["parents"] as? [JSONObject])?.compactMap { $0["id"] as? String }
            let subtasks = (shown["subtasks"] as? [JSONObject])?.compactMap { $0["id"] as? String }
            let linked = (shown["linked"] as? [JSONObject])?.compactMap { $0["url"] as? String }
            check("task show carries its parents, subtasks and links", parents == [task.key] && subtasks == [leaf.key]
                  && linked == ["https://github.com/acme/registry/pull/9"], "\(shown)")
            let text = AgentCLI.human(shown)
            check("and prints them", text.contains("\nPart of: \(task.key) [") && text.contains("Subtasks:\n  \(leaf.key) [")
                  && text.contains("Linked:\n  ") && text.contains("pull/9"), text)
            model.deleteTasks([middle.id])
        }
        // Reviews: what nobody approved by default, reviewed ones included; what waits; or all.
        let github = model.github
        let filter = model.reviewFilter
        if model.github == nil { model.github = GitHubService.fixture() }
        model.reviewFilter = .notApproved
        let notApproved = model.reviewRequests
        model.reviewFilter = .waiting
        let waiting = model.reviewRequests
        model.reviewFilter = .all
        let all = model.reviewRequests
        check("Reviews lists what nobody approved, reviewed ones too, by default", !notApproved.isEmpty
              && notApproved.allSatisfy { !$0.approved } && notApproved.contains { !model.waitsForReview($0) }
              && all.count > notApproved.count, "\(notApproved.count) of \(all.count)")
        check("Reviews' Waiting for You lists only what waits", !waiting.isEmpty && waiting.allSatisfy(model.waitsForReview)
              && waiting.count < notApproved.count)
        check("Reviews lists the latest asked first", all.map(\.reviewAskedAt) == all.map(\.reviewAskedAt).sorted(by: >),
              all.map { "\($0.number)" }.joined(separator: " "))
        let mine = model.ownPullRequests
        check("Yours lists the latest updated first", mine.count > 1 && mine.map(\.updatedAt) == mine.map(\.updatedAt).sorted(by: >),
              mine.map { "\($0.number)" }.joined(separator: " "))
        // A new PR selected is seen, as a task is; so is one under a task as a chip.
        let seenBefore = model.seen
        if let fresh = (all + mine).first(where: { model.isNew(.github($0.url)) }) {
            model.selectedItem = ModalRoute.github(fresh.url).selectionKey
            check("a new PR a click selects is seen", !model.isNew(.github(fresh.url)))
            model.selectedItem = nil
        } else {
            check("a new PR to select", false)
        }
        check("a chip's selection key names its link", ModalRoute(selectionKey: ModalRoute.github("https://github.com/a/b/pull/1").chipKey(task: 12))
              == .github("https://github.com/a/b/pull/1") && ModalRoute(selectionKey: "task:12") == nil)
        model.seen = seenBefore
        // hq ls prs: as on the page, every review then Yours, each with its status.
        let listed = (agent("ls", ["kind": "prs"])["prs"] as? [JSONObject]) ?? []
        let cards = listed.compactMap { $0["card"] as? String }
        check("hq ls prs lists Reviews then Yours, as on the page", cards == Array(repeating: "reviews", count: all.count) + Array(repeating: "yours", count: mine.count)
              && listed.prefix(all.count).compactMap { $0["number"] as? Int } == all.map(\.number)
              && listed.first?["status"] as? String == all.first.map { PRRow.reviewText($0, waits: model.waitsForReview($0)) }, cards.joined(separator: " "))
        model.reviewFilter = filter
        model.github = github
        check("the PR section says when GitHub last answered", PullRequestsSection.updated(.now, now: .now) == "Updated just now"
              && PullRequestsSection.updated(.now.addingTimeInterval(-180), now: .now).hasPrefix("Updated 3 min"),
              PullRequestsSection.updated(.now.addingTimeInterval(-180), now: .now))

        // Linking by hand: a file, an artifact, a PR and a task; Link… offers what isn't linked yet; each unlinks.
        if let target = model.addTask(to: .backlog, title: "Link target"), let other = model.addTask(to: .backlog, title: "Other"),
           let file = model.addFile(title: "Link me", body: "# Link me\n", session: nil, task: nil) {
            let artifact = model.importArtifact(URL(string: "https://claude.ai/artifact/selftest-link")!, title: "Linked page")
            let pr = ModalRoute.github("https://github.com/acme/registry/pull/77")
            let routes: [ModalRoute] = [.file(file.id), .artifact(artifact.id), pr, .task(other.id)]
            check("Link… offers files and artifacts not linked yet", LinkPicker.matches(model, task: target.id, query: "Link").contains(.file(file.id))
                  && LinkPicker.matches(model, task: target.id, query: "Linked page") == [.artifact(artifact.id)])
            for route in routes { model.link(route, to: target.id) }
            check("a file, an artifact, a PR and a task link to a task by hand", routes.allSatisfy { model.isLinked($0, to: target.id) }
                  && Set(routes).isSubset(of: Set(model.outputs(ofTask: target.id))), "\(model.outputs(ofTask: target.id))")
            check("and Link… no longer offers them", !LinkPicker.matches(model, task: target.id, query: "").contains(.file(file.id)))
            let unlinked = agent("task unlink", ["task": target.key, "item": other.key])
            check("task unlink unlinks a task", !model.isLinked(.task(other.id), to: target.id) && unlinked["error"] == nil, "\(unlinked)")
            check("and says when there's nothing to unlink", agent("task unlink", ["task": target.key, "item": other.key])["error"] != nil)
            for route in routes { model.unlink(route, from: target.id) }
            check("each unlinks", routes.allSatisfy { !model.isLinked($0, to: target.id) })
            check("a dragged item's key names it again", routes.allSatisfy { ModalRoute(itemKey: $0.selectionKey) == $0 })
            // A file's checkbox ticks from its view, one Undo step.
            model.editFileBody(file.id, "# Link me\n\n- [ ] one\n- [ ] two\n")
            model.toggleFileCheckbox(file.id, at: 1)
            check("a click on a file's checkbox ticks it in the note, one Undo step", model.fileBody(file.id).contains("- [ ] one\n- [x] two")
                  && model.undoManager?.undoActionName == "Tick Checkbox", model.fileBody(file.id))
            model.deleteTasks([target.id, other.id])
            model.deleteFile(file.id)
            model.artifacts.removeAll { $0.id == artifact.id }
        }
        // The terminal the user looks at: its done session is read; one that waits for an answer stays.
        var done = SessionItem(id: "look-done", status: SessionStatus(state: .done, unread: true, since: .now), cwd: "/tmp", repo: "", branch: "",
                               origin: nil, started: .now, order: 900)
        done.tty = "/dev/ttys901"
        var asks = SessionItem(id: "look-asks", status: SessionStatus(state: .waiting(.question), unread: true, since: .now), cwd: "/tmp", repo: "", branch: "",
                               origin: nil, started: .now, order: 901)
        asks.tty = "/dev/ttys902"
        model.put(done)
        model.put(asks)
        check("a card blinks while its session asks or is done unread", model.blinks(done) && model.blinks(asks))
        model.lookedAt(tty: "/dev/ttys902")
        model.lookedAt(tty: "/dev/ttys901")
        check("looking at a done session's terminal reads it; a question waits", model.session("look-done")?.status.unread == false
              && model.session("look-asks")?.status.needsYou == true)
        check("and both stop blinking", model.session("look-asks").map(model.blinks) == false && model.session("look-done").map(model.blinks) == false)
        model.sessions.removeAll { $0.id.hasPrefix("look-") }
        // A task added below one with a project takes it; a first child has it from its parent.
        if let above = model.addTask(to: .backlog, title: "Above") {
            model.setProject(above.id, "Registry")
            let below = model.addTask(after: above.id)
            check("a task added below one with a project takes its project", below?.project == "Registry", "\(String(describing: below?.project))")
            let child = model.addSubtask(to: above.id)
            check("a subtask takes its parent's project", child?.project == "Registry")
            if let child, let first = model.addTask(after: above.id) {
                // N on a task open with subtasks: its new first child, with the project too.
                check("a new first child takes the project in effect", first.project == "Registry" && model.taskTree.parent(of: first.id) == above.id,
                      "\(String(describing: first.project)) under \(String(describing: model.taskTree.parent(of: first.id)))")
                _ = child
            }
            model.deleteTasks([above.id] + (below.map { [$0.id] } ?? []))
        }
        // View › Zoom scales every size and font, and Actual Size brings them back.
        let row = Metric.outlineRow
        let text = KitType.title.nsFont.pointSize
        model.zoom(by: 2)
        let zoomed = model.zoom
        check("Zoom In scales rows, spacing and text", zoomed == 1.3 && Metric.outlineRow == row * 1.3 && Space.md == 12 * 1.3
              && abs(KitType.title.nsFont.pointSize - text * 1.3) < 0.01, "zoom \(zoomed), row \(Metric.outlineRow), text \(KitType.title.nsFont.pointSize)")
        model.zoom = 1
        check("Actual Size puts them back", Metric.outlineRow == row && KitType.title.nsFont.pointSize == text)
        // Remove from HQ takes an artifact off the list; the page stays on claude.ai.
        let elsewhere = ArtifactItem(id: URL(string: "https://claude.ai/artifact/selftest-v3")!, title: "Pitch visuals", session: "s-2",
                                     published: .now, tasks: [])
        model.artifacts.append(elsewhere)
        model.removeArtifact(elsewhere.id)
        check("Remove from HQ takes an artifact off the list", !model.artifacts.contains { $0.id == elsewhere.id })
        // Link to Task…'s finder: a number finds its task first, words find titles.
        if let found = model.addTask(to: .backlog, title: "Findable widget") {
            check("the task finder finds a task by its number and by its title",
                  TaskFinder.matches(model, query: "\(found.id)").first?.id == found.id
                  && TaskFinder.matches(model, query: "findable").contains { $0.id == found.id })
            model.deleteTasks([found.id])
        }
        // A search shows the tasks whose title has it, and their parents: not their siblings.
        if let parent = model.addTask(to: .overview, title: "Searchable parent"), let hit = model.addSubtask(to: parent.id, title: "Needle here"),
           model.addSubtask(to: parent.id, title: "Hay") != nil {
            model.listSearch[.overview] = "needle"
            let snapshot = OutlineSnapshot.make(model)
            check("a search shows the tasks that match and their parents, not their siblings",
                  snapshot.children(of: .header(.overview)).contains(.task(parent.id)) && snapshot.children(of: .task(parent.id)) == [.task(hit.id)],
                  "\(snapshot.children(of: .task(parent.id)))")
            model.listSearch = [:]
            model.deleteTasks([parent.id])
        }
        // Hide Done and Descriptions apply to their own list.
        if let open = model.addTask(to: .overview, title: "On Tasks"), let openDone = model.addSubtask(to: open.id, title: "Done here"),
           let later = model.addTask(to: .backlog, title: "In the Backlog"), let laterDone = model.addSubtask(to: later.id, title: "Done there") {
            model.setStatus(openDone.id, .done)
            model.setStatus(laterDone.id, .done)
            model.setDescription(open.id, "Why.")
            model.setDescription(later.id, "Why.")
            let saved = (model.hideDone, model.allDescriptions, model.backlogOpen)
            model.backlogOpen = true
            model.hideDone = [.backlog]
            model.allDescriptions = [.backlog]
            let snapshot = OutlineSnapshot.make(model)
            check("Hide Done in the Backlog hides its done subtasks, not those in Tasks",
                  snapshot.children(of: .task(open.id)) == [.task(openDone.id)] && snapshot.children(of: .task(later.id)).isEmpty,
                  "\(snapshot.children(of: .task(open.id))) \(snapshot.children(of: .task(later.id)))")
            check("Descriptions in the Backlog shows its descriptions, not those in Tasks",
                  model.descriptionShownInOutline(later.id) && !model.descriptionShownInOutline(open.id))
            (model.hideDone, model.allDescriptions, model.backlogOpen) = saved
            model.deleteTasks([open.id, later.id])
        }
        // --parent moves a task under another, or out to the top.
        if let child = model.addTask(to: .backlog, title: "Child") {
            let moved = agent("task edit", ["task": child.key, "parent": task.key])
            check("task edit --parent makes it the last subtask", model.taskTree.parent(of: child.id) == task.id && model.taskTree.children(of: task.id).last == child.id,
                  "\(moved)")
            let refused = agent("task edit", ["task": task.key, "parent": child.key])
            check("and refuses a parent inside its own subtree", refused["error"] != nil && model.taskTree.parent(of: task.id) == nil, "\(refused)")
            _ = agent("task edit", ["task": child.key, "parent": "none"])
            check("--parent none makes it top level", model.taskTree.parent(of: child.id) == nil)
            model.deleteTasks([child.id])
        }
        check("Import Artifact takes only claude.ai artifact links",
              AppModel.artifactURL(" https://claude.ai/artifact/x?sk=k#top\n")?.absoluteString == "https://claude.ai/artifact/x"
                && AppModel.artifactURL("https://claude.ai/chat/x") == nil && AppModel.artifactURL("http://claude.ai/artifact/x") == nil
                && AppModel.artifactURL("not a link") == nil)
        model.deleteTasks([task.id, other.id])
    }

    // MARK: CLI

    private static func cliChecks(_ model: AppModel) async {
        func settle(_ seconds: Double = 0.3) async { try? await Task.sleep(for: .seconds(seconds)) }
        let session = "5e550000-0000-4000-8000-000000000001"
        let added = agent("task add", ["title": "Dedup layers on push #perf", "type": "bug", "project": "Registry", "body": "Goal.", "_session": session])
        let key = added["id"] as? String ?? ""
        let id = TaskItem.key(key) ?? -1
        check("task add goes to the top of the Backlog, with type, project, tags and the session",
              added["list"] as? String == "backlog" && model.taskTree.top(.backlog).first == id && added["type"] as? String == "bug"
                && added["project"] as? String == "Registry" && (added["tags"] as? [String]) == ["perf"] && model.task(id)?.sessions == [session], "\(added)")
        check("Claude's new task in the Backlog is not blue: the Backlog is for later", !model.isNew(.task(id)) && !model.attentionQueue.contains(.task(id)))
        let now = agent("task add", ["title": "Pair on this", "now": "true"])
        check("task add --now goes to the end of Tasks", now["list"] as? String == "overview" && model.taskTree.top(.overview).last == TaskItem.key(now["id"] as? String ?? ""))
        check("Claude's new task in Tasks is blue", model.isNew(.task(TaskItem.key(now["id"] as? String ?? "") ?? -1)))
        if let mine = TaskItem.key(now["id"] as? String ?? "") {
            model.setStatus(mine, .done)
            check("a task the user changes themselves is no longer blue", !model.isNew(.task(mine)))
            model.setStatus(mine, .todo)
            if let other = model.sessions.first(where: { $0.id != session })?.id {
                agent("task edit", ["task": "T-\(mine)", "project": "Registry", "type": "chore", "_session": other])
                check("an edit from another session doesn't link it to the task", model.task(mine)?.sessions.contains(other) == false)
                agent("task move", ["task": "T-\(mine)", "status": "doing", "_session": other])
                check("starting the task links the session", model.task(mine)?.sessions.contains(other) == true)
            }
        }
        let sub = agent("task add", ["title": "Part of it", "parent": key])
        check("task add --parent makes a subtask", sub["parent"] as? String == key && model.taskTree.children(of: id).count == 1)
        let refused = agent("task move", ["task": key, "status": "review"])
        check("review needs a reason", (refused["error"] as? JSONObject)?["code"] as? String == "usage")
        agent("task move", ["task": key, "status": "review", "reason": "PR #418 is ready"])
        check("task move review sets the reason", model.task(id)?.status == .review && model.task(id)?.review == "PR #418 is ready")
        check("a task in Review in the Backlog doesn't need the user", !model.needsYou(.task(id)) && !model.attentionQueue.contains(.task(id)))
        if let path = model.task(id)?.path {
            try? (try? String(contentsOfFile: path, encoding: .utf8))?.replacingOccurrences(of: "type: bug", with: "type: bug\naliases: [dedup]")
                .write(toFile: path, atomically: true, encoding: .utf8)
            await settle(0.8)
            agent("task edit", ["task": key, "body": "New description.", "add-tag": "chunks", "remove-tag": "perf", "type": "feature"])
            await settle()
            let note = FrontMatter((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
            check("task edit changes what it's given and keeps the rest",
                  note.body == "New description.\n" && note.list("tags") == ["chunks"] && note.string("type") == "feature"
                    && note.list("aliases") == ["dedup"] && note.string("review") == "PR #418 is ready", note.text)
        }
        agent("task link", ["task": key, "item": "https://github.com/acme/registry/pull/418"])
        check("task link adds a PR", model.task(id)?.links.map(\.absoluteString) == ["https://github.com/acme/registry/pull/418"])
        let listed = agent("ls", ["kind": "tasks", "backlog": "true", "type": "feature"])["tasks"] as? [JSONObject] ?? []
        check("ls tasks filters by list and type", listed.contains { $0["id"] as? String == key } && listed.allSatisfy { $0["list"] as? String == "backlog" && $0["type"] as? String == "feature" })
        let file = agent("file new", ["title": "Push path plan", "body": "# Push path plan\n", "_session": session, "task": key])
        check("file new links the file to its task and session", (file["tasks"] as? [String]) == [key] && model.files.contains { $0.tasks == [id] && $0.sessions == [session] })
        check("a note made for a task is in the task's project", model.files.first { $0.title == "Push path plan" }?.project == model.project(ofTask: id),
              "\(String(describing: model.files.first { $0.title == "Push path plan" }?.project)) vs \(String(describing: model.project(ofTask: id)))")
        check("file show takes a name without .md", agent("file show", ["file": "\(Vault.dayString(.now)) - Push path plan"])["body"] as? String == "# Push path plan\n")
        if let made = model.files.first(where: { $0.title == "Push path plan" }), let path = made.path {
            model.setProject(of: .file(made.id), "Registry")
            check("a file's row sets its project", model.file(made.id)?.project == "Registry")
            model.deleteFile(made.id)
            check("Delete on a file moves its note to the Trash", model.file(made.id) == nil && !FileManager.default.fileExists(atPath: path))
            try? await Task.sleep(for: .milliseconds(100))
            model.undoManager?.undo()
            try? await Task.sleep(for: .milliseconds(100))
            check("Undo brings it back", model.file(made.id) != nil && FileManager.default.fileExists(atPath: path))
        }

        // A session started with a first message: a prompt file any shell reads whole.
        let message = "Work on \(key): it's \"quoted\", costs $5, runs `ls`,\nhas lines\nand 🦀."
        let before = model.ghosttyLog.count
        let started = agent("session new", ["name": "\(key) Dedup", "task": key, "message": message, "_cwd": "/tmp"])
        let spawned = started["id"] as? String ?? "-"
        let command = model.ghosttyLog.count > before ? model.ghosttyLog[before] : ""
        let promptPath = Store.directory.appending(path: "Prompts/\(spawned).md").path
        check("session new types claude with its id, name and the prompt file",
              command.contains("claude --session-id \(spawned) --name '\(key) Dedup' \"$(cat '\(promptPath)')\""), command)
        check("the prompt file keeps quotes, $, backticks, newlines and emoji",
              (try? String(contentsOfFile: promptPath, encoding: .utf8)) == message)
        check("the new session works on the task, at the end of the grid", model.task(id)?.sessions.contains(spawned) == true && model.gridSessions.last?.id == spawned)
        model.ghosttyFails = true
        model.beginStart(task: id)
        model.startFromDraft()
        await settle()
        check("a start Ghostty refuses keeps the form and says why", model.modal == .start && model.startDraft != nil && model.problem == .ghosttyUnreachable)
        model.ghosttyFails = false
        model.closeModal()
        model.problem = nil
        check("session new needs a name", (agent("session new", ["name": " ", "_cwd": "/tmp"])["error"] as? JSONObject)?["code"] as? String == "usage")
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate and closes sheets first: an open sheet refuses terminate.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
