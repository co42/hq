import AppKit
import HQKit

/// Tasks and files: notes in the vault. Every change to `tasks` or `files` writes hq's keys of
/// the notes that changed (AppModel's didSet); a rescan after FSEvents brings in other edits.
extension AppModel {
    // MARK: Vault

    /// The vault: HQ_VAULT, else Obsidian's iCloud vault. A test run uses only HQ_VAULT.
    static func resolveVault() -> Vault? {
        if let path = ProcessInfo.processInfo.environment["HQ_VAULT"], !path.isEmpty {
            return Vault(vault: URL(fileURLWithPath: path))
        }
        guard !Store.isOverridden else { return nil }
        let chosen = Prefs.defaults.string(forKey: "vault.path")
        let notes = URL(fileURLWithPath: ((chosen ?? SetupStatus.defaultVault) as NSString).expandingTildeInPath)
        return FileManager.default.fileExists(atPath: notes.path) ? Vault(vault: notes) : nil
    }

    func startVault() {
        guard let vault else { return }
        setup.vaultPath = vault.root.deletingLastPathComponent().path
        migrateVault()
        vaultWatcher = VaultWatcher(vault.root) { [weak self] in self?.rescanVault() }
        rescanVault()
    }

    /// The board's notes move to the cockpit's lists once, after a backup (PLAN.md §5).
    func migrateVault() {
        guard let vault else { return }
        do {
            let count = try vault.migrate(backups: Store.backups)
            if count > 0 { FileHandle.standardError.write(Data("HQ: moved \(count) task notes to the cockpit's lists\n".utf8)) }
        } catch {
            FileHandle.standardError.write(Data("HQ: \(error.localizedDescription)\n".utf8))
        }
    }

    func rescanVault() {
        guard let vault else { return }
        guard !vaultScanning else {
            vaultRescanAgain = true
            return
        }
        vaultScanning = true
        let cache = vaultCache
        let started = Date.now
        Task {
            let scanned = await Task.detached { Result { try vault.scan(cache) } }.value
            guard case .success(let result) = scanned else {
                // Nothing changes: the tasks and files stay as last read, and nothing is written over.
                if problem != .vaultUnreadable {
                    if case .failure(let error) = scanned { AppLog.write("vault: \(error.localizedDescription); kept what HQ had", to: "vault.log") }
                    problem = .vaultUnreadable
                }
                vaultScanning = false
                try? await Task.sleep(for: .seconds(5))
                rescanVault()
                return
            }
            if problem == .vaultUnreadable { problem = nil }
            vaultCache = result.cache
            // A note HQ wrote after the scan began: the scan read it too early, HQ's copy is newer.
            let recent = Set(vaultWrites.filter { $0.value >= started }.keys)
            let tasks = Dictionary(
                (result.tasks.filter { !recent.contains($0.path ?? "") } + self.tasks.filter { recent.contains($0.path ?? "") }).map { ($0.id, $0) },
                uniquingKeysWith: { _, mine in mine }).values.sorted { $0.id < $1.id }
            let files = Dictionary(
                (result.files.filter { !recent.contains($0.path ?? "") } + self.files.filter { recent.contains($0.path ?? "") }).map { ($0.id, $0) },
                uniquingKeysWith: { _, mine in mine }).values.sorted { $0.id < $1.id }
            LaunchLog.mark("vault")
            readingVault = true
            if self.tasks != tasks { self.tasks = tasks }
            if self.files != files { self.files = files }
            readingVault = false
            vaultWrites = vaultWrites.filter { $0.value >= started }
            vaultScanning = false
            migrateReviews()
            forgetEmptySessions()
            // A note read too early (downloading, mid-write) keeps its last read: read it again soon.
            let unreadable = Set(result.unreadable)
            if unreadable != vaultUnreadable {
                if !unreadable.isEmpty { AppLog.write("vault: couldn't read \(unreadable.sorted().joined(separator: ", ")); kept their last read, trying again", to: "vault.log") }
                vaultUnreadable = unreadable
            }
            if vaultRescanAgain {
                vaultRescanAgain = false
                rescanVault()
            } else if !unreadable.isEmpty {
                try? await Task.sleep(for: .seconds(3))
                rescanVault()
            }
        }
    }

    /// Writes the notes whose hq keys changed. New and removed notes go through their own calls.
    func persistTasks(from old: [TaskItem]) {
        guard let vault, !readingVault else { return }
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for task in tasks {
            guard let previous = before[task.id], !task.sameNote(as: previous) else { continue }
            report { try vault.save(task) }
            wrote(task.path)
        }
    }

    func persistFiles(from old: [FileItem]) {
        guard let vault, !readingVault else { return }
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for file in files {
            guard let previous = before[file.id], !file.sameNote(as: previous) else { continue }
            report { try vault.save(file) }
            wrote(file.path)
        }
    }

    /// Remembers when HQ wrote a note, so a scan that read it earlier doesn't undo the write.
    func wrote(_ path: String?) {
        if let path { vaultWrites[path] = .now }
    }

    func report(_ write: () throws -> Void) {
        do {
            try write()
        } catch {
            NSSound.beep()
            FileHandle.standardError.write(Data("HQ: could not write a note: \(error)\n".utf8))
        }
    }

    // MARK: Reading tasks

    var taskTree: TaskTree {
        // Reading the tasks makes SwiftUI views that use the tree follow them.
        _ = tasks.count
        if let cached = treeCache, cached.version == tasksVersion { return cached.tree }
        let tree = TaskTree(tasks.map(\.node))
        treeCache = (tasksVersion, tree)
        return tree
    }

    func task(_ id: Int?) -> TaskItem? {
        guard let id else { return nil }
        if let index = taskIndex[id], tasks.indices.contains(index), tasks[index].id == id { return tasks[index] }
        return tasks.first { $0.id == id }
    }

    /// The list a task shows in: its own, or its root's.
    func list(of id: Int) -> TaskList { taskTree.list(of: id) ?? .backlog }

    /// Projects in use, for the Project pop-up and the Backlog filter.
    var projects: [String] {
        var names: [String] = tasks.compactMap(\.project)
        names += files.compactMap(\.project)
        names += artifacts.compactMap(\.project)
        return Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var allTags: [String] {
        var names: [String] = tasks.flatMap(\.tags)
        names += files.flatMap(\.tags)
        names += artifacts.flatMap(\.tags)
        return Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: Label colors

    enum LabelKind: String { case tag, project }

    func labelColor(_ kind: LabelKind, _ name: String) -> LabelColor {
        labelColors["\(kind.rawValue):\(name.lowercased())"].flatMap(LabelColor.init(rawValue:)) ?? .automatic(name)
    }

    /// The user's pick; nil goes back to the color the name gives.
    func setLabelColor(_ color: LabelColor?, _ kind: LabelKind, _ name: String) {
        labelColors["\(kind.rawValue):\(name.lowercased())"] = color?.rawValue
    }

    /// What `#word` in a title means: a status, an existing project, else a tag (T-220: `#bug` is a tag).
    enum TitleWord: Equatable { case status(TaskStatus), project(String), tag(String) }

    func titleWord(_ word: String) -> TitleWord {
        if let status = TaskStatus(rawValue: word.lowercased()) { return .status(status) }
        let key = Self.projectKey(word)
        if let project = projects.first(where: { Self.projectKey($0) == key }) { return .project(project) }
        return .tag(word)
    }

    /// Projects match `#word` without case, spaces or dashes: `#machineidentities`, `#machine-identities`.
    static func projectKey(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The words to complete after `#` in a title: statuses, projects, tags.
    func titleCompletions(_ partial: String) -> [String] {
        let words = TaskStatus.allCases.map(\.rawValue) + projects.map { $0.replacingOccurrences(of: " ", with: "-") } + allTags
        var seen = Set<String>()
        return words.filter { word in
            (partial.isEmpty || word.lowercased().hasPrefix(partial.lowercased())) && word.lowercased() != partial.lowercased()
                && seen.insert(word.lowercased()).inserted
        }
    }

    // MARK: Editing tasks

    /// Applies an edit to any number of tasks as one Undo step named after it. The notes that
    /// changed are written; Claude's edits (through the socket) mark the tasks new.
    func editTasks(_ action: String, _ edit: (inout [Int: TaskItem]) -> Void) {
        var byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let before = byID
        edit(&byID)
        // Per task, the fields this edit changed and their old values: Undo puts back those only, never what a session
        // or Obsidian changed since.
        var changes: [(old: TaskItem, fields: [TaskItem.Field])] = []
        var next = tasks
        for index in next.indices {
            guard let edited = byID[next[index].id], let old = before[next[index].id] else { continue }
            var fields = TaskItem.noteFields.filter { $0.differs(old, edited) }
            guard !fields.isEmpty else { continue }
            // Parent, list and order are one place: a subtask's list is read back as the Backlog's, so Undo puts all three.
            let place: Set = ["parent", "list", "order"]
            if fields.contains(where: { place.contains($0.name) }) {
                fields = TaskItem.noteFields.filter { place.contains($0.name) || fields.map(\.name).contains($0.name) }
            }
            changes.append((old, fields))
            var changed = edited
            changed.modified = .now
            next[index] = changed
        }
        guard !changes.isEmpty else { return }
        tasks = next
        registerUndo(action) { model in
            model.editTasks(action) { tasks in
                for change in changes {
                    guard var task = tasks[change.old.id] else { continue }
                    for field in change.fields { field.copy(&task, change.old) }
                    tasks[change.old.id] = task
                }
            }
        }
    }

    func changeTask(_ id: Int, _ action: String, _ change: (inout TaskItem) -> Void) {
        editTasks(action) { tasks in
            guard var task = tasks[id] else { return }
            change(&task)
            tasks[id] = task
        }
    }

    /// Writes the placements a tree operation returned.
    func place(_ changes: [Int: TaskTree.Placement]?, _ action: String) {
        guard let changes, !changes.isEmpty else { return }
        editTasks(action) { tasks in
            for (id, placement) in changes {
                tasks[id]?.parent = placement.parent
                tasks[id]?.list = placement.list
                tasks[id]?.order = placement.order
            }
        }
    }

    /// A new task's id: above every id a task, file or artifact still names (a link, Blocked By, After), so a deleted
    /// task's links never pass to a new one.
    var nextTaskID: Int {
        let named = tasks.flatMap { [$0.id] + $0.related + $0.blockedBy + $0.after } + files.flatMap(\.tasks) + artifacts.flatMap(\.tasks)
        return (named.max() ?? 0) + 1
    }

    /// A new task note, placed by the tree. Undo moves the note to the Trash.
    @discardableResult
    func addTask(title: String, placement: TaskTree.Placement, status: TaskStatus = .todo,
                 project: String? = nil, tags: [String] = [], body: String = "", session: String? = nil, links: [URL] = [],
                 renumber: [Int: TaskTree.Placement] = [:]) -> TaskItem? {
        let split = TitleTags.split(title)
        var item = TaskItem(id: nextTaskID, title: split.title, status: status,
                            project: project, tags: tags,
                            parent: placement.parent, list: placement.list, order: placement.order,
                            done: status == .done ? .now : nil,
                            sessions: session.map { [$0] } ?? [], created: .now, modified: .now, body: body)
        item.links = links
        apply(split.tags, to: &item)
        if let vault {
            do {
                item = try vault.create(item)
            } catch {
                report { throw error }
                return nil
            }
        }
        wrote(item.path)
        place(renumber, "New Task")
        tasks.append(item)
        registerUndo("New Task") { $0.deleteTasks([item.id], action: "New Task") }
        return item
    }

    /// Return on a row: a new task below it, or its first child when it's open with children; it takes the project in
    /// effect there, written on it so it shows.
    @discardableResult
    func addTask(after id: Int, title: String = "") -> TaskItem? {
        let tree = taskTree
        let open = !tree.children(of: id).isEmpty && fold[id] != .hidden
        guard let (placement, renumber) = tree.placeNew(after: id, asFirstChild: open) else { return nil }
        if open { showSubtasks(id) } else if let parent = tree.parent(of: id) { showSubtasks(parent) }
        return addTask(title: title, placement: placement, project: project(ofTask: id), renumber: renumber)
    }

    /// The quick-add line: the end of Tasks, the top of the Backlog.
    @discardableResult
    func addTask(to list: TaskList, title: String, body: String = "", session: String? = nil, project: String? = nil,
                 links: [URL] = []) -> TaskItem? {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty,
              let (placement, renumber) = taskTree.placeNew(in: .list(list), at: list == .backlog ? 0 : nil) else { return nil }
        return addTask(title: title, placement: placement, project: project, body: body, session: session, links: links, renumber: renumber)
    }

    /// Add Subtask: the last child, the parent opened, in the parent's project.
    @discardableResult
    func addSubtask(to id: Int, title: String = "") -> TaskItem? {
        guard let (placement, renumber) = taskTree.placeNew(in: .task(id)) else { return nil }
        showSubtasks(id)
        return addTask(title: title, placement: placement, project: project(ofTask: id), renumber: renumber)
    }

    /// The title as typed: `#word` sets the status or the project it names, else becomes a tag.
    func setTitle(_ id: Int, _ text: String) {
        let split = TitleTags.split(text)
        changeTask(id, "Rename Task") { task in
            task.title = split.title
            apply(split.tags, to: &task)
        }
    }

    /// `#words` typed in a title, applied to the task.
    private func apply(_ words: [String], to task: inout TaskItem) {
        for word in words {
            switch titleWord(word) {
            case .status(let status):
                guard task.status != status else { continue }
                task.status = status
                task.done = status == .done ? .now : nil
            case .project(let project): task.project = project
            case .tag(let tag): if !task.tags.contains(tag) { task.tags.append(tag) }
            }
        }
    }

    func setStatus(_ id: Int, _ status: TaskStatus) {
        changeTask(id, status == .done ? "Mark Done" : "Move to \(status.title)") { task in
            guard task.status != status else { return }
            task.status = status
            task.done = status == .done ? (task.done ?? .now) : nil
            if status == .done {
                task.blocked = false
                task.blockedReason = nil
            }
        }
    }

    /// Tasks still in Review from before v9: doing now, and on the overview a row in the center with their reason.
    func migrateReviews() {
        let pending = tasks.filter { $0.review != nil }
        guard !pending.isEmpty else { return }
        undoManager?.disableUndoRegistration()
        defer { undoManager?.enableUndoRegistration() }
        for task in pending {
            if list(of: task.id) == .overview {
                let reason = task.review.flatMap { $0.isEmpty ? nil : $0 }
                notify("\(task.key) was in Review" + (reason.map { ": \($0)" } ?? ""), level: .update, source: nil,
                       links: [ModalRoute.task(task.id).selectionKey])
            }
            changeTask(task.id, "Review") { $0.review = nil; $0.reviewBy = nil; $0.reviewAt = nil }
        }
    }

    /// ⌘Return and ⌘-click on the glyph: the next status, from Done back to Todo.
    func nextStatus(_ ids: [Int]) {
        let all = TaskStatus.allCases
        for id in ids {
            guard let status = task(id)?.status, let index = all.firstIndex(of: status) else { continue }
            setStatus(id, all[(index + 1) % all.count])
        }
    }

    /// Mark Done: done, or back to what it was (todo when unknown).
    func toggleDone(_ id: Int) {
        guard let task = task(id) else { return }
        setStatus(id, task.status == .done ? (doneBefore[id] ?? .todo) : .done)
        if task.status != .done { doneBefore[id] = task.status }
    }

    func indent(_ id: Int) {
        let tree = taskTree
        if let index = tree.index(of: id), index > 0, let container = tree.container(of: id) {
            showSubtasks(tree.children(of: container)[index - 1])
        }
        place(tree.indent(id), "Indent")
    }

    func outdent(_ id: Int) {
        guard !keptInWindow(id) else { return }
        place(taskTree.outdent(id), "Outdent")
        keepShown(id)
    }

    func shift(_ id: Int, by offset: Int) {
        place(taskTree.shift(id, by: offset), offset < 0 ? "Move Up" : "Move Down")
        keepShown(id)
    }

    /// A subtask of the task whose window is open: moves keep it in that window (2026-11-10).
    func keptInWindow(_ id: Int) -> Bool {
        if case .task(let root) = modal, taskTree.parent(of: id) == root { return true }
        return false
    }

    /// A task just moved or added stays on screen: its parent shows all its subtasks when a mode would hide it.
    func keepShown(_ id: Int) {
        if let parent = taskTree.parent(of: id) { showSubtasks(parent) }
    }

    /// ⇧⌘B and the row button: to the top of the Backlog, or the end of Tasks.
    func toggleList(_ id: Int) {
        let target = list(of: id).other
        place(taskTree.moveToList(id, target), target == .backlog ? "Move to Backlog" : "Move to Tasks")
    }

    func move(_ id: Int, to list: TaskList) {
        place(taskTree.moveToList(id, list), list == .backlog ? "Move to Backlog" : "Move to Tasks")
    }

    /// A drop in the outline. False when refused.
    @discardableResult
    func drop(_ ids: [Int], into container: TaskTree.Container, at index: Int) -> Bool {
        guard let changes = taskTree.move(ids, to: container, at: index) else { return false }
        place(changes, ids.count == 1 ? "Move Task" : "Move Tasks")
        if case .task(let parent) = container { showSubtasks(parent) }
        return true
    }

    /// Delete, ⌘⌫, Backspace on an empty title: the task and its subtasks go to the Trash; Undo brings them back.
    func deleteTasks(_ ids: [Int], action: String = "Delete Task") {
        let tree = taskTree
        // Each once: a task and its own subtask both asked for are one subtree.
        var seen = Set<Int>()
        let all = ids.flatMap { tree.subtree(of: $0) }.filter { seen.insert($0).inserted }
        let items = all.compactMap { task($0) }
        guard !items.isEmpty else { return }
        var trashed: [Int: URL] = [:]
        for item in items { trashed[item.id] = trash(item.path) }
        let gone = Set(all)
        tasks.removeAll { gone.contains($0.id) }
        leaveModal { if case .task(let id) = $0 { gone.contains(id) } else { false } }
        registerUndo(action) { model in model.restoreTasks(items, from: trashed, action: action) }
    }

    private func restoreTasks(_ items: [TaskItem], from trashed: [Int: URL], action: String) {
        for item in items { untrash(trashed[item.id], to: item.path) }
        tasks.append(contentsOf: items.filter { item in !tasks.contains { $0.id == item.id } })
        registerUndo(action) { $0.deleteTasks(items.map(\.id), action: action) }
    }

    /// The description, whole.
    func setDescription(_ id: Int, _ text: String) {
        changeTask(id, "Edit Description") { $0.body = text.trimmingCharacters(in: .newlines) }
    }

    /// An editor's description, as it ends: nothing when untouched, else written over the note as it is now, joined
    /// with what a session wrote meanwhile when they touched other lines (TextMerge).
    func commitDescription(_ draft: TextDraft) {
        guard let current = task(draft.id)?.body else { return }
        switch TextMerge.commit(base: draft.base, mine: draft.text, theirs: current) {
        case .unchanged: break
        case .write(let text): setDescription(draft.id, text)
        case .conflict(let mine):
            setDescription(draft.id, mine)
            changedUnder("T-\(draft.id)'s description", link: "task:\(draft.id)")
        }
    }

    /// A file's text, as its editor ends: the same rule.
    func commitFile(_ id: FileItem.ID, base: String, text: String) {
        switch TextMerge.commit(base: base, mine: text, theirs: fileBody(id)) {
        case .unchanged: break
        case .write(let merged): editFileBody(id, merged + "\n")
        case .conflict(let mine):
            editFileBody(id, mine + "\n")
            changedUnder("“\(file(id)?.title ?? id)”", link: "file:\(id)")
        }
    }

    /// Both the user and someone else changed the same lines: the user's text was kept; Undo brings back the other.
    private func changedUnder(_ what: String, link: String) {
        _ = notify("\(what) changed while you edited it: yours is kept, and ⌘Z brings back the other.", level: .update, source: nil, links: [link])
    }

    /// A checkbox ticked in a rendered description.
    func toggleCheckbox(_ id: Int, at index: Int) {
        guard let body = task(id)?.body, let toggled = Markdown.toggleTask(body, at: index) else { return }
        changeTask(id, "Tick Checkbox") { $0.body = toggled }
    }


    func setProject(_ id: Int, _ project: String?) {
        changeTask(id, "Set Project") { $0.project = project.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } }
    }

    func setTags(_ id: Int, _ tags: [String]) {
        var seen = Set<String>()
        let clean = tags.map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "") }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        changeTask(id, "Change Tags") { $0.tags = clean }
    }

    /// A session works on the task: both modals and the faces show it.
    func link(task id: Int, session: String) {
        changeTask(id, "Link Session") { task in
            if !task.sessions.contains(session) { task.sessions.append(session) }
        }
    }

    func unlink(task id: Int, session: String) {
        changeTask(id, "Unlink Session") { $0.sessions.removeAll { $0 == session } }
    }

    func link(task id: Int, url: URL) {
        changeTask(id, "Link") { task in
            if !task.links.contains(url) { task.links.append(url) }
        }
    }

    /// A task linked to another: it shows under that one's row only.
    func relate(_ id: Int, to other: Int) {
        guard id != other, task(other) != nil else { return }
        changeTask(id, "Link Task") { task in
            if !task.related.contains(other) { task.related.append(other) }
        }
    }

    func unrelate(_ id: Int, from other: Int) {
        changeTask(id, "Unlink Task") { $0.related.removeAll { $0 == other } }
    }

    // MARK: Blocked, blocked by, after

    /// Each task's place in its story, worked out once per change to the tasks.
    var taskFlow: TaskFlow {
        _ = tasks.count
        if let cached = flowCache, cached.version == tasksVersion { return cached.flow }
        let flow = TaskFlow(tasks.map {
            TaskFlow.Node(id: $0.id, parent: $0.parent, done: $0.status == .done, doing: $0.status == .doing,
                          blocked: $0.blocked, blockedBy: $0.blockedBy, after: $0.after)
        })
        flowCache = (tasksVersion, flow)
        return flow
    }

    /// Blocked: it can't be done now. The reason is optional.
    func block(_ id: Int, reason: String? = nil) {
        let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        changeTask(id, "Block") { task in
            task.blocked = true
            task.blockedReason = reason?.isEmpty == false ? reason : nil
        }
    }

    func unblock(_ id: Int) {
        changeTask(id, "Unblock") { task in
            task.blocked = false
            task.blockedReason = nil
        }
    }

    /// `id` is blocked by `other`, or comes after it. Nil once it's linked, else why it can't be.
    @discardableResult
    func addLink(_ id: Int, _ link: TaskFlow.Link, _ other: Int) -> TaskFlow.Refusal? {
        if let refusal = taskFlow.refusal(id, link, other) { return refusal }
        changeTask(id, link == .blockedBy ? "Blocked By" : "After") { task in
            if link == .blockedBy { task.blockedBy.append(other) } else { task.after.append(other) }
        }
        return nil
    }

    func removeLink(_ id: Int, _ link: TaskFlow.Link, _ other: Int) {
        changeTask(id, link == .blockedBy ? "Not Blocked By" : "Not After") { task in
            if link == .blockedBy { task.blockedBy.removeAll { $0 == other } } else { task.after.removeAll { $0 == other } }
        }
    }

    func unlink(task id: Int, url: URL) {
        changeTask(id, "Unlink") { $0.links.removeAll { $0 == url } }
    }

    /// A file, an artifact, a PR or issue, or a task linked to a task: it shows under the task's row. One Undo.
    func link(_ route: ModalRoute, to id: Int) {
        switch route {
        case .file(let name): changeFile(name, "Link to Task") { if !$0.tasks.contains(id) { $0.tasks.append(id) } }
        case .artifact(let url): changeArtifact(url, "Link to Task") { if !$0.tasks.contains(id) { $0.tasks.append(id) } }
        case .github(let url):
            if let address = URL(string: url) { link(task: id, url: address) }
            if GitHubLinks.isItem(url) && githubItem(url) == nil { pollGitHubSoon() }
        case .web(let url): if let address = URL(string: url) { link(task: id, url: address) }
        case .slack(let url):
            if let address = URL(string: url) { link(task: id, url: address) }
            resolveSlack(url)
        case .task(let other): relate(id, to: other)
        case .session(let session): link(task: id, session: session)
        case .start, .closedSessions, .notifications, .newTask, .newReminder, .newFile, .importArtifact: break
        }
    }

    /// Several items dropped on a task at once: one Undo, the event's.
    func link(_ routes: [ModalRoute], to id: Int) {
        for route in routes { link(route, to: id) }
    }

    func unlink(_ route: ModalRoute, from id: Int) {
        switch route {
        case .file(let name): changeFile(name, "Unlink") { $0.tasks.removeAll { $0 == id } }
        case .artifact(let url): changeArtifact(url, "Unlink") { $0.tasks.removeAll { $0 == id } }
        case .github(let url), .web(let url), .slack(let url): if let address = URL(string: url) { unlink(task: id, url: address) }
        case .task(let other): unrelate(id, from: other)
        case .session(let session): unlink(task: id, session: session)
        case .start, .closedSessions, .notifications, .newTask, .newReminder, .newFile, .importArtifact: break
        }
    }

    /// Linked by hand, so it can be unlinked: not a PR a session on the task opened.
    func isLinked(_ route: ModalRoute, to id: Int) -> Bool {
        switch route {
        case .file(let name): file(name)?.tasks.contains(id) ?? false
        case .artifact(let url): artifacts.first { $0.id == url }?.tasks.contains(id) ?? false
        case .github(let url), .web(let url), .slack(let url): task(id)?.links.contains { $0.absoluteString == url } ?? false
        case .task(let other): task(id)?.related.contains(other) == true
        case .session(let session): task(id)?.sessions.contains(session) ?? false
        case .start, .closedSessions, .notifications, .newTask, .newReminder, .newFile, .importArtifact: false
        }
    }

    func changeArtifact(_ url: URL, _ action: String, _ change: (inout ArtifactItem) -> Void) {
        guard let index = artifacts.firstIndex(where: { $0.id == url }) else { return }
        let old = artifacts[index]
        var new = old
        change(&new)
        let fields = ArtifactItem.fields.filter { $0.differs(old, new) }
        guard !fields.isEmpty else { return }
        artifacts[index] = new
        registerUndo(action) { model in model.changeArtifact(url, action) { ItemField.undo(fields, from: old, into: &$0) } }
    }

    // MARK: Outline state

    func setFold(_ id: Int, _ mode: FoldMode?) {
        if fold[id] != mode { fold[id] = mode }
    }

    /// All of a task's subtasks show: one was just added, indented or dropped under it.
    func showSubtasks(_ id: Int) {
        guard fold[id] != .all else { return }
        if fold[id] != nil || taskTree.ancestors(of: id).contains(where: { fold[$0] == .important }) { setFold(id, .all) }
    }

    // MARK: Files

    /// A note named by its date and title, linked to the session that wrote it and to a task.
    @discardableResult
    func addFile(title: String, body: String = "", session: String? = nil, task: Int? = nil, date: Date = .now) -> FileItem? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        var item = FileItem(id: "\(Vault.dayString(date)) - \(title).md", title: title, date: date, modified: .now,
                            sessions: session.map { [$0] } ?? [], tasks: task.map { [$0] } ?? [])
        // A note for a task is in the task's project.
        item.project = project(ofTask: task)
        if let vault {
            do {
                item = try vault.create(item, body: body)
            } catch {
                report { throw error }
                return nil
            }
        } else {
            fileDrafts[item.id] = body.isEmpty ? "# \(title)\n" : body
        }
        wrote(item.path)
        files.append(item)
        return item
    }

    func changeFile(_ id: FileItem.ID, _ action: String, _ change: (inout FileItem) -> Void) {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        let old = files[index]
        var new = old
        change(&new)
        let fields = FileItem.noteFields.filter { $0.differs(old, new) }
        guard !fields.isEmpty else { return }
        files[index] = new
        registerUndo(action) { model in model.changeFile(id, action) { ItemField.undo(fields, from: old, into: &$0) } }
    }

    /// Delete on a file: its note goes to the Trash; Undo brings it back.
    func deleteFile(_ id: FileItem.ID) {
        guard let file = file(id) else { return }
        let trashed = trash(file.path)
        files.removeAll { $0.id == id }
        leaveModal { $0 == .file(id) }
        registerUndo("Delete File") { model in
            model.untrash(trashed, to: file.path)
            if !model.files.contains(where: { $0.id == id }) { model.files.append(file) }
            model.registerUndo("Delete File") { $0.deleteFile(id) }
        }
    }

    func file(_ id: FileItem.ID?) -> FileItem? {
        id.flatMap { id in files.first { $0.id == id } }
    }

    /// A file by its path under hq/files, its full path, or its name (with or without `.md`).
    func file(ref: String) -> FileItem? {
        var name = ref.hasPrefix("hq/files/") ? String(ref.dropFirst(9)) : ref
        if !name.hasSuffix(".md") && !files.contains(where: { $0.id == name }) { name += ".md" }
        return files.first { $0.id == name || $0.path == ref || ($0.path?.hasSuffix("/" + name) ?? false) }
    }

    /// The note's markdown, without its front matter.
    func fileBody(_ id: FileItem.ID) -> String {
        if let path = files.first(where: { $0.id == id })?.path { return Vault.body(at: path) }
        return fileDrafts[id] ?? "# \(files.first { $0.id == id }?.title ?? "")\n\nSample text.\n"
    }

    /// A saved edit: the note's markdown, with Undo.
    func editFileBody(_ id: FileItem.ID, _ body: String, action: String = "Edit File") {
        let old = fileBody(id)
        guard body != old, let index = files.firstIndex(where: { $0.id == id }) else { return }
        saveFileBody(id, body)
        files[index].modified = .now
        registerUndo(action) { $0.editFileBody(id, old, action: action) }
    }

    /// A checkbox ticked in a file's rendered view.
    func toggleFileCheckbox(_ id: FileItem.ID, at index: Int) {
        guard let toggled = Markdown.toggleTask(fileBody(id), at: index) else { return }
        editFileBody(id, toggled, action: "Tick Checkbox")
    }

    /// The markdown written back, keeping the front matter.
    func saveFileBody(_ id: FileItem.ID, _ body: String) {
        guard let path = files.first(where: { $0.id == id })?.path else {
            fileDrafts[id] = body
            return
        }
        report { try vault?.saveBody(body, at: path) }
        wrote(path)
    }

    // MARK: Obsidian and the Trash

    /// Opens a note in Obsidian (`obsidian://open?path=`).
    func openInObsidian(_ path: String?) {
        guard let path, var url = URLComponents(string: "obsidian://open") else { return }
        url.queryItems = [URLQueryItem(name: "path", value: path)]
        if let link = url.url { NSWorkspace.shared.open(link) }
    }

    /// A `[[link]]` in a note: Obsidian finds the note by its name.
    func openNoteInObsidian(named name: String) {
        let vaultName = vault?.root.deletingLastPathComponent().lastPathComponent
            ?? setup.vaultPath.map { ($0 as NSString).lastPathComponent } ?? "Notes"
        guard var url = URLComponents(string: "obsidian://open") else { return }
        url.queryItems = [URLQueryItem(name: "vault", value: vaultName), URLQueryItem(name: "file", value: name)]
        if let link = url.url { NSWorkspace.shared.open(link) }
    }

    private func trash(_ path: String?) -> URL? {
        guard let path else { return nil }
        wrote(path)
        var result: NSURL?
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &result)
        } catch {
            report { throw error }
        }
        return result as URL?
    }

    private func untrash(_ trashed: URL?, to path: String?) {
        guard let trashed, let path else { return }
        wrote(path)
        report { try FileManager.default.moveItem(at: trashed, to: URL(fileURLWithPath: path)) }
    }

    /// One Undo step, named after the action.
    func registerUndo(_ name: String, _ action: @escaping (AppModel) -> Void) {
        guard let undo = undoManager else { return }
        undo.registerUndo(withTarget: self) { model in MainActor.assumeIsolated { action(model) } }
        if !undo.isUndoing && !undo.isRedoing { undo.setActionName(name) }
    }
}
