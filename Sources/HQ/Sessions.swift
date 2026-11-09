import AppKit
import HQKit

/// Sessions (PLAN.md §6): hook events move them, the store keeps them, Ghostty shows them.
extension AppModel {
    // MARK: Hook events

    /// One hook event from `hq hook`. Every event of every session lands here: keep it quick.
    /// What sessions did while HQ was off: the events `hq hook` kept (`HookSpool`), replayed in order with their times.
    func replayPendingHooks() {
        let url = Store.directory.appending(path: HookSpool.fileName)
        let taken = url.appendingPathExtension("replaying")
        try? FileManager.default.removeItem(at: taken)
        guard (try? FileManager.default.moveItem(at: url, to: taken)) != nil else { return }
        defer { try? FileManager.default.removeItem(at: taken) }
        guard let data = try? Data(contentsOf: taken) else { return }
        for entry in HookSpool.replayable(HookSpool.entries(data)) {
            _ = AgentRouter.handle(JSON.data(["command": "hook", "args": entry.args]))
        }
    }

    func receive(_ event: HookEvent) {
        let now = event.at ?? Date.now
        lastHookEvent = now
        var item = session(event.sessionID) ?? newItem(for: event, now: now)
        let waited = item.status.needsYou
        var live = item.live
        live.apply(event, now: now)
        item.live = live
        if let cwd = event.cwd, !cwd.isEmpty, cwd != item.cwd { item.cwd = cwd }
        if ["SessionStart", "Stop"].contains(event.name) || item.repo.isEmpty {
            (item.repo, item.branch) = GitInfo.describe(item.cwd)
            item.origin = GitInfo.origin(item.cwd)
        }
        if let title = event.title { item.title = title }
        if item.firstPrompt == nil, let prompt = event.prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty, !prompt.hasPrefix("/") {
            item.firstPrompt = prompt.components(separatedBy: .newlines).first
        }
        if let path = event.transcriptPath { item.transcriptPath = path }
        // A /rename writes the transcript only: read again on each prompt and Stop.
        if ["UserPromptSubmit", "Stop"].contains(event.name), let path = item.transcriptPath {
            Self.applyTitles(TranscriptTitle.read(path), to: &item)
        }
        if let pid = event.pid { item.pid = pid }
        if let tty = event.tty { item.tty = tty }
        if let inGhostty = event.inGhostty { item.inGhostty = inGhostty }
        for url in event.pullRequests where !item.links.contains(url) { item.links.append(url) }
        if item.status.state == .ended {
            if item.closedAt == nil { item.closedAt = now }
        } else if item.closedAt != nil {
            // Resumed, from HQ or from a terminal: back at the end of the grid.
            item.closedAt = nil
            item.order = nextGridOrder
        }
        // Done while the user watches its terminal, or while its modal shows: nothing left unread.
        if event.name == "Stop", item.status.unread,
           (modal == .session(item.id) && NSApp.isActive) || (item.tty != nil && watchedTTY() == item.tty) {
            item.status.unread = false
        }
        // A tool call in a session already working moves only its last activity: kept aside, the page has nothing to redraw.
        if let stored = session(item.id) {
            var same = item
            same.status.lastActivity = stored.status.lastActivity
            if same == stored {
                activity[item.id] = now
            } else {
                activity[item.id] = nil
                put(item)
            }
        } else {
            put(item)
        }
        watchTitle(of: item)
        if item.status.needsYou, !waited { sessionBlocked(item.id) }
        if let published = event.artifact { capture(published, from: item) }
        if !event.pullRequests.isEmpty { pollGitHubSoon() }
        // After put: a process that already exited ends the stored session.
        if let pid = event.pid, event.name != "SessionEnd" { watch(pid) }
    }

    /// A session HQ hasn't seen: at the end of the grid, with a face no open session shares.
    private func newItem(for event: HookEvent, now: Date) -> SessionItem {
        let cwd = event.cwd ?? ""
        let git = GitInfo.describe(cwd)
        var item = SessionItem(id: event.sessionID, status: SessionStatus(state: .idle, since: now), cwd: cwd,
                               repo: git.repo, branch: git.branch, origin: GitInfo.origin(cwd), started: now,
                               order: nextGridOrder)
        item.faceSalt = faceSalt(for: item.id)
        // After /clear the new id takes the place of the one it replaced (same process).
        if event.source == "clear", let pid = event.pid,
           let replaced = sessions.filter({ $0.pid == pid && $0.id != event.sessionID }).max(by: { $0.status.since < $1.status.since }) {
            item.order = replaced.order
        }
        return item
    }

    /// A new session's face, set apart from the open sessions' (`FaceSpec.salt(for:among:)`, T-293).
    func faceSalt(for id: String) -> Int {
        FaceSpec.salt(for: id, among: sessions.filter { $0.closedAt == nil && $0.id != id }.map(\.face))
    }

    /// Randomize Face in a session's menu (T-334): another face at random, whatever the open sessions wear. One Undo.
    func randomizeFace(_ id: String) {
        guard var item = session(id) else { return }
        let old = item.faceSalt
        var salt = old
        while salt == old { salt = Int.random(in: FaceSpec.tries...Int(Int32.max)) }
        item.faceSalt = salt
        put(item)
        registerUndo("Randomize Face") { model in
            guard var back = model.session(id) else { return }
            back.faceSalt = old
            model.put(back)
        }
    }

    var nextGridOrder: Double { (sessions.map(\.order).max() ?? 0) + 1 }

    /// A page the session published: linked to the session, and to its task when it works on exactly one.
    func capture(_ published: PublishedArtifact, from session: SessionItem) {
        guard let url = URL(string: published.url) else { return }
        let file = published.file.map { $0.hasPrefix("/") || $0.hasPrefix("~") ? $0 : (session.cwd as NSString).appendingPathComponent($0) }
        let title = file.flatMap(PublishedArtifact.title(ofPage:)) ?? published.title
        if let index = artifacts.firstIndex(where: { $0.id == url }) {
            if let title, artifacts[index].title != title { artifacts[index].title = title }
            return
        }
        let name = title ?? file.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? url.lastPathComponent
        let worksOn = tasks(of: session.id)
        var artifact = ArtifactItem(id: url, title: name, session: session.id, published: .now, tasks: worksOn.count == 1 ? [worksOn[0].id] : [])
        // A page for a task is in the task's project.
        artifact.project = project(ofTask: artifact.tasks.first)
        artifacts.append(artifact)
    }

    /// The artifact's own title, read from its page: what HQ lists it by.
    func setArtifactTitle(_ url: URL, _ title: String) {
        guard let index = artifacts.firstIndex(where: { $0.id == url }), artifacts[index].title != title else { return }
        artifacts[index].title = title
    }

    /// Remove from HQ on an artifact: its entry goes, the page stays on claude.ai; Undo brings it back.
    func removeArtifact(_ url: URL) {
        guard let index = artifacts.firstIndex(where: { $0.id == url }) else { return }
        let artifact = artifacts.remove(at: index)
        leaveModal { $0 == .artifact(url) }
        registerUndo("Remove from HQ") { model in
            if !model.artifacts.contains(where: { $0.id == url }) { model.artifacts.insert(artifact, at: min(index, model.artifacts.count)) }
            model.registerUndo("Remove from HQ") { $0.removeArtifact(url) }
        }
    }

    func put(_ item: SessionItem) {
        if let index = sessions.firstIndex(where: { $0.id == item.id }) {
            if sessions[index] != item { sessions[index] = item }
        } else {
            sessions.append(item)
        }
    }

    func session(_ id: String?) -> SessionItem? {
        id.flatMap { id in sessions.first { $0.id == id } }
    }

    /// A session by the start of its id, when only one matches.
    func session(prefix: String) -> SessionItem? {
        let found = sessions.filter { $0.id.hasPrefix(prefix.lowercased()) }
        return found.count == 1 ? found[0] : nil
    }

    /// The grid, in the user's order.
    var gridSessions: [SessionItem] {
        sessions.filter(\.onGrid).sorted { ($0.order, $0.started) < ($1.order, $1.started) }
    }

    /// Closed in the last 14 days, newest first.
    var closedSessions: [SessionItem] {
        let recent = now.addingTimeInterval(-14 * 86_400)
        return sessions.filter { ($0.closedAt ?? .distantPast) >= recent }.sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }
    }

    /// Tasks a session works on.
    func tasks(of session: String) -> [TaskItem] {
        tasks.filter { $0.sessions.contains(session) }
    }

    /// Open sessions on a task, and on its subtasks while it's folded.
    /// The sessions on a task: open ones, then with `includeEnded` the ended ones, latest first.
    func sessions(on id: Int, withSubtasks: Bool = false, includeEnded: Bool = false) -> [SessionItem] {
        let ids = withSubtasks ? taskTree.subtree(of: id) : [id]
        var seen = Set<String>()
        let linked = ids.compactMap { task($0) }.flatMap(\.sessions).filter { seen.insert($0).inserted }
        return Self.openFirst(linked.compactMap { session($0) }, includeEnded: includeEnded)
    }

    /// Open sessions in their order, then the ended ones when asked, the latest to end first.
    /// Sessions by what matters most, for the one face a row shows: one that needs the user, one working, the latest
    /// active open one, then ended ones, latest first.
    func byImportance(_ sessions: [SessionItem]) -> [SessionItem] {
        func rank(_ item: SessionItem) -> Int { !item.isRunning ? 0 : item.status.needsYou ? 3 : item.isWorking ? 2 : 1 }
        return sessions.sorted { (rank($0), lastActivity($0)) > (rank($1), lastActivity($1)) }
    }

    /// When a session last sent a hook event, tool calls kept aside included.
    func lastActivity(_ session: SessionItem) -> Date {
        max(activity[session.id] ?? .distantPast, session.status.lastActivity)
    }

    /// The tool calls kept aside go into the sessions: on the clock's tick, and before a save at quit.
    func settleActivity() {
        guard !activity.isEmpty else { return }
        let pending = activity
        activity = [:]
        for (id, date) in pending {
            guard var item = session(id), date > item.status.lastActivity else { continue }
            item.status.lastActivity = date
            put(item)
        }
    }

    static func openFirst(_ sessions: [SessionItem], includeEnded: Bool) -> [SessionItem] {
        let open = sessions.filter { $0.closedAt == nil }
        guard includeEnded else { return open }
        return open + sessions.filter { $0.closedAt != nil }.sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }
    }

    // MARK: Processes

    /// Ends a session when its Claude exits, even without a SessionEnd.
    func watch(_ pid: Int32) {
        guard exitWatchers[pid] == nil else { return }
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { @Sendable [weak self] in
            MainActor.assumeIsolated { self?.processExited(pid) }
        }
        source.resume()
        exitWatchers[pid] = source
        if !ClaudeProcess.isRunningClaude(pid) { processExited(pid) }
    }

    func processExited(_ pid: Int32) {
        exitWatchers.removeValue(forKey: pid)?.cancel()
        if let tty = closingTerminals.removeValue(forKey: pid) { closeTerminal(tty) }
        let now = Date.now
        for var item in sessions where item.pid == pid {
            titleWatchers.removeValue(forKey: item.id)?.cancel()
            var live = item.live
            live.end(now)
            item.live = live
            item.pid = nil
            if item.closedAt == nil { item.closedAt = now }
            put(item)
        }
    }

    /// A /rename writes only the transcript: while the session runs, HQ reads its title a moment after the file changes.
    func watchTitle(of item: SessionItem) {
        guard item.isRunning, let path = item.transcriptPath else {
            titleWatchers.removeValue(forKey: item.id)?.cancel()
            return
        }
        guard titleWatchers[item.id] == nil else { return }
        let descriptor = Darwin.open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .extend], queue: .main)
        let id = item.id
        source.setEventHandler { @Sendable [weak self] in
            MainActor.assumeIsolated { self?.transcriptChanged(id) }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        titleWatchers[id] = source
    }

    /// Claude's title, and a /rename: a new /rename names the session, over a name HQ gave it or the user's earlier one.
    @discardableResult
    static func applyTitles(_ titles: TranscriptTitle.Titles, to item: inout SessionItem) -> Bool {
        var changed = false
        if let claude = titles.claude, claude != item.title {
            item.title = claude
            changed = true
        }
        if let renamed = titles.renamed, renamed != item.renamed {
            item.renamed = renamed
            item.customName = renamed
            changed = true
        }
        return changed
    }

    /// At launch: a /rename too far back for the end of a running session's transcript still names it.
    func adoptRenames() {
        let paths = sessions.filter(\.isRunning).compactMap { item in item.transcriptPath.map { (item.id, $0) } }
        guard !paths.isEmpty else { return }
        Task.detached(priority: .utility) {
            let found = paths.compactMap { id, path in TranscriptTitle.lastRename(path).map { (id, $0) } }
            await MainActor.run { [weak self] in
                guard let self else { return }
                for (id, renamed) in found {
                    guard var item = self.session(id), Self.applyTitles(.init(renamed: renamed), to: &item) else { continue }
                    self.put(item)
                }
            }
        }
    }

    /// At most one read a second while Claude writes.
    private func transcriptChanged(_ id: String) {
        guard titleReads.insert(id).inserted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            titleReads.remove(id)
            guard var item = session(id), item.isRunning, let path = item.transcriptPath else {
                titleWatchers.removeValue(forKey: id)?.cancel()
                return
            }
            var changed = Self.applyTitles(TranscriptTitle.read(path), to: &item)
            // Esc or Ctrl+C in the terminal: no Stop comes, the transcript says so.
            if let stopped = TranscriptInterrupt.read(path) {
                var live = item.live
                if live.interrupt(at: stopped, now: .now) {
                    item.live = live
                    changed = true
                }
            }
            if changed { put(item) }
        }
    }

    /// At launch: sessions whose Claude still runs are watched, the others have ended.
    func reviveSessions() {
        // Sessions from before the grid had an order take one by age.
        if sessions.contains(where: { $0.order == 0 }) {
            for (index, item) in sessions.sorted(by: { $0.started < $1.started }).enumerated() where item.order == 0 {
                var placed = item
                placed.order = Double(index + 1)
                put(placed)
            }
        }
        for var item in sessions where item.isRunning {
            if let pid = item.pid, ClaudeProcess.isRunningClaude(pid) {
                watch(pid)
                watchTitle(of: item)
            } else if item.pid != nil || item.status.state != .idle {
                var live = item.live
                live.end(item.status.lastActivity)
                item.live = live
                item.pid = nil
                item.closedAt = item.closedAt ?? item.status.lastActivity
                put(item)
            }
        }
    }

    /// Saves a second after the last change: hook events come in bursts.
    func saveSessionsSoon() {
        guard sessionSave == nil else { return }
        sessionSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.saveSessionsNow()
        }
    }

    func saveSessionsNow() {
        sessionSave?.cancel()
        sessionSave = nil
        storage?.save(sessions)
    }

    // MARK: The grid

    /// A card dragged to `index` of the grid as it shows now. One Undo step.
    func moveSession(_ id: String, to index: Int) {
        var grid = gridSessions
        guard let from = grid.firstIndex(where: { $0.id == id }) else { return }
        let moving = grid.remove(at: from)
        let at = min(max(index > from ? index - 1 : index, 0), grid.count)
        guard at != from else { return }
        grid.insert(moving, at: at)
        let old = Dictionary(gridSessions.map { ($0.id, $0.order) }, uniquingKeysWith: { first, _ in first })
        for (position, item) in grid.enumerated() {
            var placed = item
            placed.order = Double(position + 1)
            put(placed)
        }
        registerUndo("Move Session") { model in model.restoreOrder(old) }
    }

    private func restoreOrder(_ orders: [String: Double]) {
        let current = Dictionary(gridSessions.map { ($0.id, $0.order) }, uniquingKeysWith: { first, _ in first })
        for (id, order) in orders {
            guard var item = session(id) else { continue }
            item.order = order
            put(item)
        }
        registerUndo("Move Session") { $0.restoreOrder(current) }
    }

    /// Close Session: a running session gets `/exit` and Return in its terminal.
    /// Close Session: /exit in its terminal, then the terminal closes once Claude has quit.
    func closeSession(_ id: String) {
        guard let item = session(id), item.isRunning, let tty = item.tty else { return }
        if let pid = item.pid { closingTerminals[pid] = tty }
        if Store.isOverridden {
            ghosttyLog.append("type /exit in \(tty)")
            return
        }
        Task {
            let result = await Task.detached { () -> Result<Bool, Ghostty.Failure> in
                do throws(Ghostty.Failure) { return .success(try Ghostty.type("/exit", tty: tty)) } catch { return .failure(error) }
            }.value
            ghostty { _ = try result.get() }
        }
    }

    // MARK: Ghostty

    /// The terminal a closed session ran in, once its shell is back at the prompt.
    private func closeTerminal(_ tty: String) {
        if Store.isOverridden {
            ghosttyLog.append("close \(tty)")
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            let result = await Task.detached { () -> Result<Bool, Ghostty.Failure> in
                do throws(Ghostty.Failure) { return .success(try Ghostty.close(tty: tty)) } catch { return .failure(error) }
            }.value
            ghostty { _ = try result.get() }
        }
    }

    /// Double-click, Return, Open in Ghostty: its terminal forward, or a resume.
    func open(_ id: SessionItem.ID) {
        guard let item = session(id) else { return }
        markSessionSeen(id)
        guard item.isRunning else {
            resume(id)
            return
        }
        // Not in a terminal HQ knows, or not found in Ghostty: its modal says where it runs. Nothing starts.
        guard let tty = item.tty else { return open(.session(id)) }
        if Store.isOverridden {
            ghosttyLog.append("focus \(tty)")
            return
        }
        Task {
            let result = await Task.detached { () -> Result<Bool, Ghostty.Failure> in
                do throws(Ghostty.Failure) { return .success(try Ghostty.focus(tty: tty)) } catch { return .failure(error) }
            }.value
            AppLog.write("focus \(item.name) (\(item.status.state)) on \(tty): \(result)", to: "clicks.log")
            ghostty {
                let found = try result.get()
                self.setInGhostty(id, found)
                if !found, self.modal != .session(id) { self.open(.session(id)) }
            }
        }
    }

    /// A double-click on a face: a running session comes forward in Ghostty; an ended one asks before it resumes.
    func openFace(_ id: SessionItem.ID) {
        guard let item = session(id) else { return }
        guard !item.isRunning else { return open(id) }
        if Store.isOverridden {
            ghosttyLog.append("ask resume \(id)")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Resume “\(item.name)”?"
        alert.informativeText = "It ended \(Elapsed.short(from: item.status.since, to: .now)) ago. Resume opens a Ghostty tab running claude --resume in \(item.cwd)."
        alert.addButton(withTitle: "Resume")
        alert.addButton(withTitle: "Cancel")
        let finish = { [weak self] (response: NSApplication.ModalResponse) in
            if response == .alertFirstButtonReturn { self?.open(id) }
        }
        if let window = window.map({ $0.attachedSheet ?? $0 }) {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    /// Done and new until the user looks: opening it or its modal, or watching its terminal.
    // MARK: The terminal the user looks at

    /// While Ghostty is in front, the terminal the user looks at, every few seconds: a done session on it is read (DESIGN.md §11).
    /// Only with the Automation grant, and only while a done session waits unread on a terminal.
    func watchGhosttyFocus() {
        guard !Store.isOverridden, activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let ghostty = app?.bundleIdentifier == Ghostty.bundleID
            MainActor.assumeIsolated { self?.ghosttyInFront(ghostty) }
        }
    }

    private func ghosttyInFront(_ front: Bool) {
        focusTimer?.invalidate()
        focusTimer = nil
        guard front, setup.ghosttyAllowed else { return }
        checkFocusedTerminal()
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFocusedTerminal() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        focusTimer = timer
    }

    private func checkFocusedTerminal() {
        guard !focusChecking, sessions.contains(where: { $0.tty != nil && (blinks($0) || $0.status.isNew) }) else { return }
        focusChecking = true
        Task { [weak self] in
            let tty = await Task.detached { try? Ghostty.focusedTTY() }.value
            self?.focusChecking = false
            if let tty { self?.lookedAt(tty: tty) }
        }
    }

    /// The user looks at the terminal on `tty`: its card stops blinking, and a done session there is read. One waiting for an answer stays orange.
    func lookedAt(tty: String) {
        for session in sessions where session.tty == tty {
            acknowledge(session.id)
            if session.status.isNew { markSessionSeen(session.id) }
        }
    }

    /// A card blinks while its session needs the user, until the user clicks it, opens it or looks at its terminal.
    func blinks(_ session: SessionItem) -> Bool {
        guard session.isRunning, session.status.needsYou else { return false }
        return (seen["blink:\(session.id)"] ?? .distantPast) < session.status.since
    }

    /// The user saw the card: it stops blinking until the session's next state.
    func acknowledge(_ id: SessionItem.ID) {
        guard let item = session(id), blinks(item) else { return }
        seen["blink:\(id)"] = .now
    }

    func markSessionSeen(_ id: SessionItem.ID) {
        acknowledge(id)
        guard var item = session(id), item.status.unread else { return }
        item.status.unread = false
        put(item)
    }

    /// A new Ghostty tab running `claude --resume`, in the session's directory; its card joins the end of the grid.
    func resume(_ id: SessionItem.ID) {
        guard var item = session(id), !item.isRunning else { return }
        item.closedAt = nil
        item.order = nextGridOrder
        put(item)
        newTab(in: item.cwd, command: item.resumeCommand) { _ in }
    }

    /// Start a session: a Ghostty tab running Claude with an id and a name HQ gives it, its first
    /// message read from a file so any shell takes it whole. Linked to the task it starts for.
    @discardableResult
    func startSession(named name: String, in directory: String, task taskID: Int? = nil, pullRequest: String? = nil, message: String = "",
                      done: @escaping (Bool) -> Void = { _ in }) -> SessionItem.ID {
        let id = UUID().uuidString.lowercased()
        let git = GitInfo.describe(directory)
        var item = SessionItem(id: id, customName: name, status: SessionStatus(state: .idle, since: .now), cwd: directory,
                               repo: git.repo, branch: git.branch, origin: GitInfo.origin(directory), started: .now,
                               order: nextGridOrder)
        item.faceSalt = faceSalt(for: id)
        // A review session shows on its PR from the start.
        if let pullRequest { item.links.append(pullRequest) }
        put(item)
        if let taskID, task(taskID) != nil { link(task: taskID, session: id) }
        var command = "claude --session-id \(id) --name \(Self.shellQuoted(name))"
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, let file = writePrompt(text, id: id) {
            command += " \"$(cat \(Self.shellQuoted(file.path)))\""
        }
        newTab(in: directory, command: command) { [weak self] started in
            if !started { self?.sessions.removeAll { $0.id == id } }
            done(started)
        }
        return id
    }

    /// `~/Library/Application Support/HQ/Prompts/<id>.md`, read by the shell when Claude starts.
    private func writePrompt(_ text: String, id: String) -> URL? {
        let dir = Store.directory.appending(path: "Prompts", directoryHint: .isDirectory)
        let file = dir.appending(path: "\(id).md")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file, options: .atomic)
            return file
        } catch {
            report { throw error }
            return nil
        }
    }

    /// A task's first message: the task holds the context, not the chat that started it.
    static func taskPrompt(_ task: TaskItem) -> String {
        "Work on HQ task \(task.key), \(task.title). Start with `hq task show \(task.key)`: its description holds the context. "
            + "Move it to doing and keep it current as the hq-tasks skill says."
    }

    /// A review's first message.
    static func reviewPrompt(_ item: GitHubItem) -> String {
        "Review PR \(item.url) (\(item.title)). Read it with `gh pr view \(item.number) --repo \(item.repo)` and its diff, "
            + "then tell me what you think before posting anything."
    }

    /// One shell word for fish, zsh and bash alike: single quotes, with none inside.
    static func shellQuoted(_ text: String) -> String {
        let clean = text.replacingOccurrences(of: "'", with: "’").replacingOccurrences(of: "\\", with: "/")
            .components(separatedBy: .newlines).joined(separator: " ")
        return "'\(clean)'"
    }

    /// The tty the user is looking at: Ghostty's focused terminal while Ghostty is in front. Only with
    /// the Automation grant, so it never prompts.
    func watchedTTY() -> String? {
        guard setup.ghosttyAllowed, !Store.isOverridden,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Ghostty.bundleID else { return nil }
        return try? Ghostty.focusedTTY()
    }

    /// Ghostty waits for the new shell, so the call runs off the main thread.
    private func newTab(in directory: String, command: String, done: @escaping (Bool) -> Void) {
        if Store.isOverridden {
            ghosttyLog.append("new tab in \(directory): \(command)")
            done(!ghosttyFails)
            if ghosttyFails { problem = .ghosttyUnreachable }
            return
        }
        Task {
            let failure = await Task.detached { () -> Ghostty.Failure? in
                do throws(Ghostty.Failure) {
                    try Ghostty.newTab(in: directory, command: command)
                    return nil
                } catch {
                    return error
                }
            }.value
            ghostty { if let failure { throw failure } }
            done(failure == nil)
        }
    }

    /// Folders for Start a session: the project's own, the task's sessions', the project's sessions', then recent ones.
    func recentDirectories(for taskID: Int? = nil) -> [String] {
        let byActivity = sessions.sorted { lastActivity($0) > lastActivity($1) }
        let task = task(taskID)
        let project = project(ofTask: taskID)
        let ofTask = task.map { task in byActivity.filter { task.sessions.contains($0.id) } } ?? []
        let ofProject = project.map { project in
            byActivity.filter { session in tasks(of: session.id).contains { $0.project == project } }
        } ?? []
        let linked = project.flatMap { links(of: $0).folder }.map { [($0 as NSString).expandingTildeInPath] } ?? []
        var seen = Set<String>()
        return (linked + (ofTask + ofProject + byActivity).map(\.cwd)).filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(8).map { $0 }
    }

    /// A local clone of a repository, from the sessions that ran in one.
    func clone(of repo: String) -> String? {
        sessions.sorted { lastActivity($0) > lastActivity($1) }
            .first { $0.origin?.caseInsensitiveCompare(repo) == .orderedSame }?.cwd
    }

    private func setInGhostty(_ id: SessionItem.ID, _ found: Bool) {
        guard var item = session(id), item.inGhostty != found else { return }
        item.inGhostty = found
        put(item)
    }

    /// Runs a Ghostty call; a missing Automation grant or an unreachable Ghostty shows the banner.
    private func ghostty(_ call: () throws -> Void) {
        do {
            try call()
            if problem == .ghosttyAccess || problem == .ghosttyUnreachable { problem = nil }
            setup.ghosttyAllowed = true
        } catch Ghostty.Failure.notPermitted {
            setup.ghosttyAllowed = false
            problem = .ghosttyAccess
        } catch {
            problem = .ghosttyUnreachable
            FileHandle.standardError.write(Data("HQ: Ghostty: \(error)\n".utf8))
        }
    }

    // MARK: Editing

    /// Rename: the user's name, or Claude's again when empty.
    func renameSession(_ id: SessionItem.ID, to name: String) {
        guard var item = session(id) else { return }
        let old = item.customName
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let new: String? = trimmed.isEmpty || trimmed == item.title ? nil : trimmed
        guard new != old else { return }
        item.customName = new
        put(item)
        registerUndo("Rename Session") { $0.renameSession(id, to: old ?? "") }
    }

    /// What a new Claude session learns at its start (PLAN.md §7): what it works on, and how to keep it current.
    func startContext(_ id: SessionItem.ID) -> String {
        var lines: [String] = []
        let mine = tasks(of: id)
        if mine.isEmpty {
            lines.append("HQ tracks this session.")
        } else {
            lines.append("HQ tracks this session. It works on: " + mine.prefix(5).map { "\($0.key) \($0.title) (\($0.status.rawValue))" }.joined(separator: "; ") + ".")
        }
        let doing = taskTree.outline(.overview).compactMap { task($0) }.filter { $0.status == .doing }
        if !doing.isEmpty { lines.append("On the overview: \(doing.count) doing (`hq ctx`).") }
        lines.append("Keep the work visible in HQ: use the hq-tasks skill for tasks and the hq-files skill for notes. "
                     + "Artifacts you publish land in HQ on their own.")
        return lines.joined(separator: "\n")
    }
}
