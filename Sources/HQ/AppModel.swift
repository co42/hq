import AppKit
import Combine
import HQKit
import Observation
import SwiftUI

/// What the modal shows. Opening an item from inside the modal pushes; from the page it starts fresh.
enum ModalRoute: Hashable {
    case task(Int)
    case session(String)
    case file(String)
    case artifact(URL)
    case github(String)
    case start
    case hiddenAndClosed

    /// The key its unread state goes by.
    var seenKey: String? {
        switch self {
        case .task(let id): "task:T-\(id)"
        case .file(let id): "file:\(id)"
        case .artifact(let url): "artifact:\(url.absoluteString)"
        case .github(let url): "gh:\(url)"
        case .session, .start, .hiddenAndClosed: nil
        }
    }
}

/// The Start a session form, before it starts.
struct StartDraft: Hashable {
    var name: String
    var folder: String
    var message: String
    var task: Int?
    var pullRequest: String?
}

/// The Backlog's filter bar.
struct BacklogFilter: Hashable {
    enum Status: String, CaseIterable, Identifiable {
        case open, todo, doing, review, done, any
        var id: String { rawValue }
        var title: String {
            switch self {
            case .open: "Open"
            case .todo: "Todo"
            case .doing: "Doing"
            case .review: "Review"
            case .done: "Done"
            case .any: "Any"
            }
        }
    }

    var status = Status.open
    var project: String?
    var tag: String?

    var isActive: Bool { status != .open || project != nil || tag != nil }

    /// "Status Done, Project Registry": what applies, for the menu's tooltip.
    var summary: String {
        [status != .open ? "Status \(status.title)" : nil, project.map { "Project \($0)" },
         tag.map { "Tag #\($0)" }].compactMap { $0 }.joined(separator: ", ")
    }

    func matches(_ task: TaskItem) -> Bool {
        let statusOK: Bool = switch status {
        case .open: task.status != .done
        case .todo: task.status == .todo
        case .doing: task.status == .doing
        case .review: task.status == .review
        case .done: task.status == .done
        case .any: true
        }
        return statusOK && (project == nil || task.project == project)
            && (tag == nil || task.tags.contains(tag!))
    }
}

/// A problem HQ shows in its banner (DESIGN.md §3).
enum Problem: String, CaseIterable {
    case pluginMissing, ghosttyAccess, ghosttyUnreachable, githubSignedOut, githubMissing, githubFailing

    var message: String {
        switch self {
        case .pluginMissing: "The hq plugin isn’t installed"
        case .ghosttyAccess: "HQ can’t control Ghostty"
        case .ghosttyUnreachable: "Ghostty didn’t open the tab"
        case .githubSignedOut: "GitHub CLI is signed out"
        case .githubMissing: "GitHub CLI isn’t installed"
        case .githubFailing: "GitHub isn’t answering"
        }
    }

    var detail: String {
        switch self {
        case .pluginMissing: "Claude sessions show up here once the plugin is installed. Sessions you start after that report to HQ."
        case .ghosttyAccess: "Allow HQ in System Settings › Privacy & Security › Automation."
        case .ghosttyUnreachable: "Nothing was lost: try again once Ghostty is running."
        case .githubSignedOut: "Run `gh auth login` in a terminal, then HQ shows your pull requests."
        case .githubMissing: "Install it with `brew install gh`, then run `gh auth login`."
        case .githubFailing: "HQ shows what it had and tries again in a few minutes."
        }
    }

    var fixTitle: String {
        switch self {
        case .pluginMissing: "Install Plugin"
        case .ghosttyAccess: "Open Settings…"
        case .ghosttyUnreachable, .githubFailing: "Try Again"
        case .githubSignedOut, .githubMissing: "Copy Command"
        }
    }
}

/// The things HQ needs (DESIGN.md §15).
struct SetupStatus: Hashable {
    var pluginInstalled = false
    var ghosttyAllowed = false
    var vaultPath: String?
    /// GitHub: `gh` found, and the account it's signed in to.
    var ghPath: String?
    var githubAccount: String?

    var isComplete: Bool { pluginInstalled && ghosttyAllowed && vaultPath != nil }

    static let defaultVault = "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Notes"

    /// "“Notes” in iCloud Drive" for Obsidian’s iCloud folder, else the path.
    var vaultName: String? {
        guard let path = vaultPath else { return nil }
        let name = (path as NSString).lastPathComponent
        return path.contains("iCloud~md~obsidian") ? "“\(name)” in iCloud Drive" : path
    }
}

/// App-wide state that menus, toolbars and views share.
@Observable
final class AppModel {
    /// Every session HQ heard of. Saved a second after a change.
    var sessions: [SessionItem] = [] { didSet { attentionCache = nil; outputsCache = nil; syncMenu(); saveSessionsSoon() } }
    /// Notes in the vault; a change writes the notes that changed.
    var tasks: [TaskItem] = [] {
        didSet {
            tasksVersion += 1
            attentionCache = nil; outputsCache = nil
            taskIndex = Dictionary(tasks.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            persistTasks(from: oldValue)
            syncMenu()
        }
    }
    var files: [FileItem] = [] { didSet { attentionCache = nil; outputsCache = nil; persistFiles(from: oldValue) } }
    /// Pages Claude published, captured from its hooks. Saved at once.
    var artifacts: [ArtifactItem] = [] { didSet { attentionCache = nil; outputsCache = nil; if artifacts != oldValue { storage?.save(artifacts) } } }
    /// GitHub's last answer, shown while the next one comes.
    var github: GitHubSnapshot? { didSet { attentionCache = nil; outputsCache = nil; syncMenu() } }

    /// When the user last opened each item, and when Claude or GitHub last changed it.
    var seen: [String: Date] = [:] { didSet { attentionCache = nil; outputsCache = nil; saveAttentionSoon(); syncMenu() } }
    var changes: [String: Change] = [:] { didSet { attentionCache = nil; outputsCache = nil; saveAttentionSoon(); syncMenu() } }

    // MARK: The page

    var search = ""
    /// The Backlog's disclosure, remembered.
    var backlogOpen = UserDefaults.standard.bool(forKey: "backlog.open") {
        didSet { remember(backlogOpen, as: "backlog.open"); syncMenu() }
    }
    var backlogFilter = BacklogFilter()
    /// Each list's own search, in its header.
    var listSearch: [TaskList: String] = [:]
    /// Files and Artifacts' own search, by title.
    var filesSearch = ""
    /// The lists whose Descriptions toggle shows every description, remembered.
    /// Sections folded to their header, remembered; the Backlog has its own.
    var folded: Set<PageSection> = Set(((UserDefaults.standard.array(forKey: "page.folded") as? [String]) ?? []).compactMap(PageSection.init(rawValue:))) {
        didSet { remember(folded.map(\.rawValue).sorted(), as: "page.folded"); syncMenu() }
    }
    var allDescriptions: Set<TaskList> = AppModel.storedLists("outline.descriptions") {
        didSet { remember(allDescriptions.map(\.rawValue).sorted(), as: "outline.descriptions"); syncMenu() }
    }
    /// View › Zoom, remembered: every size scales with it.
    var zoom: CGFloat = {
        let stored = CGFloat(UserDefaults.standard.double(forKey: "view.zoom"))
        return Zoom.steps.contains(stored) ? stored : 1
    }() {
        didSet {
            Zoom.factor = zoom
            KitType.resetFonts()
            remember(Double(zoom), as: "view.zoom")
        }
    }
    /// Waiting for your review also lists the PRs the user already reviewed, remembered.
    var showReviewed = UserDefaults.standard.bool(forKey: "prs.showReviewed") {
        didSet { remember(showReviewed, as: "prs.showReviewed") }
    }
    /// GitHub is being asked: the PR section's Refresh turns into a spinner.
    var githubPolling = false
    /// Files and Artifacts shows pinned items only, remembered.
    var pinnedOnly = UserDefaults.standard.bool(forKey: "files.pinnedOnly") {
        didSet { remember(pinnedOnly, as: "files.pinnedOnly") }
    }
    /// The lists whose Hide Done is on, remembered.
    var hideDone: Set<TaskList> = AppModel.storedLists("outline.hideDone").subtracting([.backlog]) {
        didSet { remember(hideDone.map(\.rawValue).sorted(), as: "outline.hideDone"); syncMenu() }
    }
    /// Descriptions shown one by one.
    var shownDescriptions: Set<Int> = []
    /// The description whose markdown is in an editor in the outline.
    var editingDescription: Int?
    /// Folded tasks, remembered by key.
    var collapsed: Set<Int> = Set((UserDefaults.standard.array(forKey: "outline.collapsed") as? [Int]) ?? []) {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(Array(collapsed), forKey: "outline.collapsed") } }
    }
    /// Colors the user picked, by "tag:name" or "project:name" (lowercased); the others follow their name.
    var labelColors: [String: String] = (UserDefaults.standard.dictionary(forKey: "labels.colors") as? [String: String]) ?? [:] {
        didSet { remember(labelColors, as: "labels.colors") }
    }
    /// Each project's folder and repositories, by its key.
    var projectLinks: [String: StoredProject] = UserDefaults.standard.data(forKey: "projects.links")
        .flatMap { try? JSONDecoder().decode([String: StoredProject].self, from: $0) } ?? [:] {
        didSet { if let data = try? JSONEncoder().encode(projectLinks) { remember(data, as: "projects.links") } }
    }
    /// The task row or the session card the Task and Session menus act on.
    var focusedTask: Int? { didSet { syncMenu() } }
    /// Every selected outline row, in order: the Task menu's targets when there are several.
    var selectedTasks: [Int] = [] { didSet { syncMenu() } }
    var selectedSession: String? { didSet { syncMenu() } }
    /// A PR, a chip or a modal row a click selected; a double-click opens it.
    var selectedItem: String? { didSet { if selectedItem != oldValue { syncMenu() } } }
    /// The outline's rows or a title have the keyboard: the Task menu's keys follow.
    var outlineKeyboard = OutlineKeyboard.none { didSet { syncMenu() } }
    /// New Task: the quick-add line of this list takes the keyboard.
    var quickAddFocus: TaskList?
    /// Where the outline puts the keyboard after its next update.
    var outlineFocus: OutlineFocus?
    /// The section that takes the keyboard next: Tab and ⇧Tab.
    var sectionFocus: PageSection?
    /// A row of Pull Requests or Files and Artifacts that the keyboard selected: the page scrolls to it.
    var scrollTarget: String?
    /// The section whose selection shows; nil when nothing on the page is selected.
    var selectedSection: PageSection?
    /// What each section had selected when it lost the selection, for when Tab comes back: a row's key, a session's id.
    @ObservationIgnored var parkedItems: [PageSection: String] = [:]
    /// Reload on an artifact's page.
    var artifactReloads = 0
    /// Bumped by File › Import Artifact…: the import popover opens.
    var importRequests = 0
    /// Bumped by New File: its popover opens.
    var newFileRequests = 0

    // MARK: The modal

    var modal: ModalRoute? { didSet { syncMenu() } }
    /// What Back returns to, newest last.
    var modalStack: [ModalRoute] = [] { didSet { syncMenu() } }
    var startDraft: StartDraft?
    /// A file's markdown in the modal's editor, and the text so far.
    var editingFile: FileItem.ID?
    var fileDraft = ""
    /// The modal's description editor, and the text so far.
    var modalEditingDescription = false
    var descriptionDraft = ""

    // MARK: Window and health

    var now = Date.now
    var problem: Problem?
    var lastHookEvent: Date?
    var setup = SetupStatus()
    var showSetup = false
    var pluginInstalling = false
    /// The installer's last line when it failed.
    var pluginError: String?
    var quickOpenQuery = ""
    var quickOpenIndex = 0
    /// The window's content size: the modal is sized from it.
    var windowSize = CGSize.zero
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    @ObservationIgnored private var clock: AnyCancellable?
    @ObservationIgnored let storage: Storage?
    @ObservationIgnored var exitWatchers: [Int32: DispatchSourceProcess] = [:]
    /// Close Session's terminals, by their Claude's pid: they close when it exits.
    @ObservationIgnored var closingTerminals: [Int32: String] = [:]
    /// Running sessions' transcripts, watched for a /rename.
    @ObservationIgnored var titleWatchers: [String: DispatchSourceFileSystemObject] = [:]
    /// Sessions whose transcript changed, read again in a moment.
    @ObservationIgnored var titleReads: Set<String> = []
    @ObservationIgnored var sessionSave: Task<Void, Never>?
    @ObservationIgnored var attentionSave: Task<Void, Never>?
    @ObservationIgnored var vault: Vault? = AppModel.resolveVault()
    @ObservationIgnored var vaultWatcher: VaultWatcher?
    @ObservationIgnored var vaultCache = Vault.Cache()
    @ObservationIgnored var vaultScanning = false
    @ObservationIgnored var vaultRescanAgain = false
    /// Set while a scan of the vault replaces tasks and files: nothing to write back.
    @ObservationIgnored var readingVault = false
    /// When HQ last wrote each note (by path).
    @ObservationIgnored var vaultWrites: [String: Date] = [:]
    /// Sample files' text, with no vault.
    @ObservationIgnored var fileDrafts: [FileItem.ID: String] = [:]
    @ObservationIgnored var tasksVersion = 0
    /// The last search's tasks and their parents, by list, tasks' version and words.
    @ObservationIgnored var foundCache: [TaskList: (key: String, found: Set<Int>)] = [:]
    @ObservationIgnored var treeCache: (version: Int, tree: TaskTree)?
    @ObservationIgnored var taskIndex: [Int: Int] = [:]
    /// The attention queue until sessions, tasks, outputs, GitHub or what the user saw change.
    @ObservationIgnored var attentionCache: [ModalRoute]?
    /// Every task's outputs, by task.
    @ObservationIgnored var outputsCache: [Int: [ModalRoute]]?
    /// The status a done task had, for ⌘Return twice.
    @ObservationIgnored var doneBefore: [Int: TaskStatus] = [:]
    /// The session or "claude" behind a socket command: what it changes turns blue.
    @ObservationIgnored var actor: String?
    /// What a test run would have asked Ghostty to do; with `ghosttyFails`, every call fails.
    @ObservationIgnored var ghosttyLog: [String] = []
    @ObservationIgnored var ghosttyFails = false
    @ObservationIgnored var gitHubService: GitHubService?
    /// While Ghostty is in front: reads the terminal the user looks at, every few seconds.
    @ObservationIgnored var focusTimer: Timer?
    @ObservationIgnored var focusChecking = false
    @ObservationIgnored var activationObserver: NSObjectProtocol?
    /// The main window: its undo manager backs Edit › Undo.
    @ObservationIgnored weak var window: NSWindow?
    var undoManager: UndoManager? { window?.undoManager }

    init() {
        do {
            storage = try Storage(url: Store.url)
        } catch {
            fatalError("Could not open the store at \(Store.url.path): \(error)")
        }
        sessions = storage?.sessions() ?? []
        artifacts = storage?.artifacts() ?? []
        seen = storage?.seen() ?? [:]
        changes = storage?.changes() ?? [:]
        Zoom.factor = Store.isOverridden ? 1 : zoom
        KitType.resetFonts()
        if Store.isOverridden {
            zoom = 1
            backlogOpen = false
            folded = []
            collapsed = []
            hideDone = []
            allDescriptions = []
            showReviewed = false
        }
        clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect().sink { [weak self] date in
            MainActor.assumeIsolated {
                self?.now = date
                self?.rollDoneTasks()
            }
        }
        reviveSessions()
        adoptRenames()
        startVault()
        gitHubService = GitHubService(model: self)
        watchGhosttyFocus()
    }

    /// Saves a preference, except in test and snapshot runs.
    /// A section's header shows it or folds it.
    func sectionOpen(_ section: PageSection) -> Binding<Bool> {
        Binding(get: { !self.folded.contains(section) }, set: { open in
            if open { self.folded.remove(section) } else { self.folded.insert(section) }
        })
    }

    private func remember(_ value: Any, as key: String) {
        if !Store.isOverridden { UserDefaults.standard.set(value, forKey: key) }
    }

    private static func storedLists(_ key: String) -> Set<TaskList> {
        Set(((UserDefaults.standard.array(forKey: key) as? [String]) ?? []).compactMap(TaskList.init(rawValue:)))
    }

    /// Zoom In and Zoom Out: the next step of View › Zoom, if there is one.
    func zoom(by step: Int) {
        let steps = Zoom.steps
        let index = steps.firstIndex(of: zoom) ?? steps.firstIndex(of: 1) ?? 0
        let next = min(max(index + step, 0), steps.count - 1)
        if steps[next] != zoom { zoom = steps[next] }
    }

    /// One list's switch in a per-list setting: Descriptions, Hide Done.
    func toggle(_ setting: ReferenceWritableKeyPath<AppModel, Set<TaskList>>, _ list: TaskList) -> Binding<Bool> {
        Binding(get: { self[keyPath: setting].contains(list) },
                set: { on in if on { self[keyPath: setting].insert(list) } else { self[keyPath: setting].remove(list) } })
    }

    // MARK: Toolbar

    /// "Wednesday 4 November".
    var dateLine: String { now.formatted(.dateTime.weekday(.wide).day().month(.wide)) }

    // MARK: The modal

    /// From the page or Next: a fresh modal. From inside it: pushed, so Back returns.
    func open(_ route: ModalRoute, push: Bool = false) {
        showWindow()
        saveModalEdits()
        if push, let current = modal, current != route {
            modalStack.append(current)
        } else if !push {
            modalStack = []
        }
        modal = route
        markSeen(route)
    }

    func back() {
        saveModalEdits()
        guard let previous = modalStack.popLast() else { return closeModal() }
        modal = previous
    }

    /// What went away leaves the modal: the item it was opened from shows again, else the modal closes.
    func leaveModal(_ gone: (ModalRoute) -> Bool) {
        modalStack.removeAll(where: gone)
        if let modal, gone(modal) { back() }
    }

    /// ⌘W hid the window: what opens on it brings it back.
    func showWindow() {
        guard let window, !window.isVisible else { return }
        window.makeKeyAndOrderFront(nil)
    }

    /// Edit Description: in the task's modal when it's open, else in the outline.
    func editDescription(_ id: Int) {
        if modal == .task(id) {
            descriptionDraft = task(id)?.body ?? ""
            modalEditingDescription = true
        } else {
            shownDescriptions.insert(id)
            editingDescription = id
        }
    }

    /// File › Import Artifact…: the Files and Artifacts header's import popover.
    func beginImport() {
        closeModal()
        showWindow()
        folded.remove(.files)
        importRequests += 1
    }

    /// New File…: the Files header's popover asks for its title.
    func beginNewFile() {
        closeModal()
        showWindow()
        folded.remove(.files)
        newFileRequests += 1
    }

    /// A new note by its title, opened in its modal to write in.
    func newFile(title: String) {
        guard let file = addFile(title: title) else { return }
        pinnedOnly = false
        filesSearch = ""
        selectedItem = ModalRoute.file(file.id).selectionKey
        open(.file(file.id))
        beginFileEdit(file.id)
    }

    func closeModal() {
        saveModalEdits()
        modal = nil
        modalStack = []
    }

    /// Leaving a modal keeps what was typed.
    func saveModalEdits() {
        if let id = editingFile {
            editingFile = nil
            editFileBody(id, fileDraft)
        }
        if modalEditingDescription, case .task(let id) = modal {
            modalEditingDescription = false
            setDescription(id, descriptionDraft)
        }
    }

    /// Start Session… on a task, a PR, or New Session….
    func beginStart(task: Int? = nil, pullRequest: GitHubItem? = nil, push: Bool = false) {
        showWindow()
        let item = self.task(task)
        let name = item.map { "\($0.key) \($0.title)" } ?? pullRequest.map { "Review \($0.reference)" } ?? ""
        // The project's folder: the task's (or a parent's) project, or the one the PR's repository belongs to.
        let project = task.flatMap(project(ofTask:)) ?? pullRequest.flatMap { project(ofRepo: $0.repo) }
        let folder = project.flatMap { links(of: $0).folder } ?? pullRequest.flatMap { clone(of: $0.repo) }
            ?? recentDirectories(for: task).first ?? NSHomeDirectory()
        let message = item.map(Self.taskPrompt) ?? pullRequest.map(Self.reviewPrompt) ?? ""
        startDraft = StartDraft(name: name, folder: folder, message: message + (message.isEmpty ? "" : "\n\n"), task: task,
                                pullRequest: pullRequest?.url)
        open(.start, push: push)
    }

    /// Start (⌘Return). On failure the form stays with its text and the banner says why.
    func startFromDraft() {
        guard let draft = startDraft, !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        startSession(named: draft.name.trimmingCharacters(in: .whitespaces), in: (draft.folder as NSString).expandingTildeInPath,
                     task: draft.task, pullRequest: draft.pullRequest, message: draft.message) { [weak self] started in
            guard let self, started else { return }
            if self.modal == .start { self.closeModal() }
        }
    }

    // MARK: Menus

    func syncMenu() {
        MenuState.shared.update(model: self)
        let count = needsYouCount
        NSApp?.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }
}

/// A mirror of what the menus need. SwiftUI Commands don't observe @Observable models.
@MainActor
final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published private(set) var task: Int?
    @Published private(set) var taskIsDone = false
    @Published private(set) var taskInBacklog = false
    @Published private(set) var session: String?
    @Published private(set) var sessionRunning = false
    @Published private(set) var sessionHidden = false
    @Published private(set) var outlineKeyboard = OutlineKeyboard.none
    @Published private(set) var canGoBack = false
    @Published private(set) var hasAttention = false
    @Published private(set) var hasNew = false
    @Published private(set) var backlogOpen = false
    @Published private(set) var folded: Set<PageSection> = []
    /// A task's modal is open: the Task menu acts on it, not on the outline behind it.
    @Published private(set) var inModal = false
    @Published private(set) var tasksToBacklog = true
    @Published private(set) var allDone = false
    @Published private(set) var sessionCanFocus = false
    @Published private(set) var sessionClosable = false
    @Published private(set) var hasHiddenOrClosed = false
    @Published private(set) var github = false
    @Published private(set) var showReviewed = false
    @Published private(set) var pinnedOnly = false
    @Published private(set) var descriptions: Set<TaskList> = []
    @Published private(set) var zoom: CGFloat = 1
    @Published private(set) var hideDone: Set<TaskList> = []
    @Published private(set) var canEditFile = false
    @Published private(set) var taskDescriptionShown = false
    /// What the Task menu acts on: the selected rows, or the one task.
    @Published private(set) var tasks: [Int] = []
    @Published private(set) var taskStatus: TaskStatus?
    /// A markdown editor or its find bar has the keyboard.
    @Published private(set) var editorFind = false
    /// The open item's way out of HQ ("Open on GitHub"), its web link, and what a PR's modal allows.
    @Published private(set) var outside: String?
    @Published private(set) var link: String?
    @Published private(set) var pullRequest = false
    @Published private(set) var reviewable = false
    @Published private(set) var artifact = false

    func update(model: AppModel) {
        func set<T: Equatable>(_ path: ReferenceWritableKeyPath<MenuState, T>, _ value: T) {
            if self[keyPath: path] != value { self[keyPath: path] = value }
        }
        // The open modal's item wins over the page's selection, and an open modal of another kind leaves none.
        let modalTask: Int? = if case .task(let id) = model.modal { id } else { nil }
        let modalSession: String? = if case .session(let id) = model.modal { id } else { nil }
        let task = model.modal == nil ? model.focusedTask.flatMap { model.task($0) } : model.task(modalTask)
        set(\.task, task?.id)
        set(\.taskIsDone, task?.status == .done)
        set(\.taskInBacklog, task.map { model.list(of: $0.id) == .backlog } ?? false)
        let session = model.modal == nil ? model.session(model.selectedSession) : model.session(modalSession)
        set(\.session, session?.id)
        set(\.sessionRunning, session?.isRunning ?? false)
        set(\.sessionHidden, session?.hidden ?? false)
        set(\.sessionCanFocus, session.map { !$0.isRunning || $0.tty != nil } ?? false)
        set(\.sessionClosable, session.map { $0.isRunning && $0.tty != nil } ?? false)
        set(\.outlineKeyboard, model.modal == nil ? model.outlineKeyboard : .none)
        set(\.canGoBack, !model.modalStack.isEmpty)
        let queue = model.attentionQueue
        set(\.hasAttention, !queue.isEmpty)
        set(\.hasNew, queue.contains { model.isNew($0) })
        set(\.backlogOpen, model.backlogOpen)
        set(\.folded, model.folded)
        set(\.inModal, modalTask != nil)
        set(\.github, model.github != nil)
        set(\.showReviewed, model.showReviewed)
        set(\.pinnedOnly, model.pinnedOnly)
        set(\.hasHiddenOrClosed, !model.hiddenSessions.isEmpty || !model.closedSessions.isEmpty)
        set(\.descriptions, model.allDescriptions)
        set(\.zoom, model.zoom)
        set(\.hideDone, model.hideDone)
        let file: Bool = if case .file = model.modal { model.editingFile == nil } else { false }
        set(\.canEditFile, file)
        set(\.taskDescriptionShown, task.map { model.descriptionShownInOutline($0.id) } ?? false)
        let targets = model.modal == nil && model.selectedTasks.count > 1 ? model.selectedTasks : task.map { [$0.id] } ?? []
        set(\.tasks, targets)
        set(\.tasksToBacklog, targets.contains { model.list(of: $0) != .backlog })
        set(\.allDone, !targets.isEmpty && targets.allSatisfy { model.task($0)?.status == .done })
        set(\.taskStatus, targets.count == 1 ? task?.status : nil)
        set(\.editorFind, model.findEditor() != nil)
        set(\.outside, model.outsideTitle(model.menuRoute))
        set(\.link, model.link(of: model.menuRoute))
        let item: GitHubItem? = if case .github(let url) = model.menuRoute { model.githubItem(url) } else { nil }
        set(\.pullRequest, item?.kind == .pullRequest)
        set(\.reviewable, item.map(model.waitsForReview) ?? false)
        let artifact: Bool = switch model.modal { case .artifact, .github: true; default: false }
        set(\.artifact, artifact)
    }
}
