import AppKit
import Combine
import HQKit
import Observation
import SwiftUI
import UserNotifications

/// What the modal shows. Opening an item from inside the modal pushes; from the page it starts fresh.
enum ModalRoute: Hashable {
    case task(Int)
    case session(String)
    case file(String)
    case artifact(URL)
    case github(String)
    /// Any other web page linked to a task (T-299): it opens in the browser.
    case web(String)
    /// A Slack message, thread or channel linked to a task or a reminder (T-312): it opens in Slack.
    case slack(String)
    /// New Task…: a small sheet of its own (T-332), for Tasks or the Backlog.
    case newTask(TaskList)
    /// New Reminder…: a small sheet of its own.
    case newReminder
    /// New File… and Import Artifact…: small sheets of their own.
    case newFile, importArtifact
    case start
    case closedSessions
    case notifications
    /// The Roles modal (T-415): the roles' list beside the one picked.
    case roles
}

/// The Start a session form, before it starts.
struct StartDraft: Hashable {
    var name: String
    var folder: String
    var message: String
    var task: Int?
    var pullRequest: String?
    /// The session it starts under: nil, the top level.
    var parent: String?
    /// The name of its role.
    var role: String?
    /// The session whose conversation it starts with.
    var history: String?
    /// The user picked the role: a new parent no longer changes it.
    var roleChosen = false
}

/// The Backlog's filter bar.
/// Which reviews the Pull Requests' Reviews card lists.
enum ReviewFilter: String, CaseIterable, Identifiable {
    case notApproved, waiting, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .notApproved: "Not Approved"
        case .waiting: "Waiting for You"
        case .all: "All"
        }
    }
    var help: String {
        switch self {
        case .notApproved: "Open pull requests you review that nobody approved yet, you included"
        case .waiting: "Only those that wait for your review"
        case .all: "Every open pull request you review, approved ones too"
        }
    }
}

struct BacklogFilter: Hashable {
    enum Status: String, CaseIterable, Identifiable {
        case open, todo, doing, done, any
        var id: String { rawValue }
        var title: String {
            switch self {
            case .open: "Open"
            case .todo: "Todo"
            case .doing: "Doing"
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
        case .done: task.status == .done
        case .any: true
        }
        return statusOK && (project == nil || task.project == project)
            && (tag == nil || task.tags.contains(tag!))
    }
}

/// An editor's text: the task it edits, the text it started from, and what's typed (TextMerge decides what's written).
struct TextDraft: Equatable {
    var id: Int
    var base: String
    var text: String

    init(id: Int, base: String) {
        self.id = id
        self.base = base
        text = base
    }
}

/// What a task shows of its subtasks: none, only the blocked and doing ones, or all (2026-11-10).
enum FoldMode: String, CaseIterable {
    case hidden, important, all

    /// The modes as they open, fewest subtasks first.
    static let opening: [FoldMode] = [.hidden, .important, .all]

    /// Its name in the card's menu.
    var title: String {
        switch self {
        case .hidden: "None"
        case .important: "Only Blocked and Doing"
        case .all: "All"
        }
    }

    /// What the user chose, by task; the tasks folded before the three modes stay hidden.
    static func remembered() -> [Int: FoldMode] {
        let defaults = Prefs.defaults
        if let saved = defaults.dictionary(forKey: "outline.fold") as? [String: String] {
            return Dictionary(uniqueKeysWithValues: saved.compactMap { key, value in Int(key).flatMap { id in FoldMode(rawValue: value).map { (id, $0) } } })
        }
        return Dictionary(uniqueKeysWithValues: ((defaults.array(forKey: "outline.collapsed") as? [Int]) ?? []).map { ($0, .hidden) })
    }

    static func remember(_ fold: [Int: FoldMode]) {
        Prefs.defaults.set(Dictionary(uniqueKeysWithValues: fold.map { (String($0.key), $0.value.rawValue) }), forKey: "outline.fold")
    }
}

/// A problem HQ shows in its banner (DESIGN.md §3).
enum Problem: String, CaseIterable {
    case pluginMissing, ghosttyAccess, ghosttyUnreachable, githubSignedOut, githubMissing, githubFailing, vaultUnreadable, movedAside

    var message: String {
        switch self {
        case .pluginMissing: "The hq plugin isn’t installed"
        case .ghosttyAccess: "HQ can’t control Ghostty"
        case .ghosttyUnreachable: "Ghostty didn’t open the tab"
        case .githubSignedOut: "GitHub CLI is signed out"
        case .githubMissing: "GitHub CLI isn’t installed"
        case .githubFailing: "GitHub isn’t answering"
        case .vaultUnreadable: "HQ can’t read the vault"
        case .movedAside: "HQ couldn’t read some of its own data"
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
        case .vaultUnreadable: "Your tasks and files stay as HQ last read them, and nothing is written over. HQ tries again every few seconds."
        case .movedAside: "It was moved aside, never written over: Show in Finder. HQ started that part fresh."
        }
    }

    var fixTitle: String {
        switch self {
        case .pluginMissing: "Install Plugin"
        case .ghosttyAccess: "Open Settings…"
        case .ghosttyUnreachable, .githubFailing, .vaultUnreadable: "Try Again"
        case .movedAside: "Show in Finder"
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
    var sessions: [SessionItem] = [] { didSet { outputsCache = nil; syncMenu(); saveSessionsSoon() } }
    /// Notes in the vault; a change writes the notes that changed.
    var tasks: [TaskItem] = [] {
        didSet {
            tasksVersion += 1
            outputsCache = nil
            taskIndex = Dictionary(tasks.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            persistTasks(from: oldValue)
            syncMenu()
        }
    }
    var files: [FileItem] = [] { didSet { outputsCache = nil; persistFiles(from: oldValue) } }
    /// The roles a session can start with: notes in <vault>/hq/roles/, Leader and Worker first.
    var roles: [RoleItem] = []
    /// Pages Claude published, captured from its hooks. Saved at once.
    var artifacts: [ArtifactItem] = [] { didSet { outputsCache = nil; if artifacts != oldValue { storage?.save(artifacts) } } }
    /// GitHub's last answer, shown while the next one comes.
    var github: GitHubSnapshot? { didSet { outputsCache = nil; syncMenu() } }
    /// The Slack messages links show, read once each (`slack.json`), by permalink.
    var slackMessages: [String: SlackMessage] = [:]
    /// Who the Slack token in Settings › Slack is for; nil without one, or when Slack refused it.
    var slackAccount: SlackAccount?
    /// What Slack said when it refused the token or a link.
    var slackError: String?
    /// A Slack link copied before New Task: the next task from its quick-add line links it (T-313).
    var pendingTaskLink: PendingTaskLink?

    /// When the user acknowledged a card (`blink:<id>`) or marked a PR reviewed (`review:<url>`).
    var seen: [String: Date] = [:] { didSet { saveAttentionSoon() } }
    /// The notification center's rows, and what it remembers (`notifications.json`).
    var noticeStore = NoticeStore() { didSet { reminderMarks = nil; saveNoticesSoon(); syncMenu() } }
    var notices: [Notice] {
        get { noticeStore.notices }
        set { noticeStore.notices = newValue }
    }
    /// The row the center has selected: a notification's id, or `session:<id>` for one that waits.
    var noticeSelection: String?
    /// Remind Me… on a task, a PR, a file or an artifact: what the New Reminder sheet opening now links (T-343).
    var reminderAbout: ModalRoute?
    /// How often HQ asked GitHub to poll soon, for the self-test.
    @ObservationIgnored var githubAsks = 0
    /// The center's reminder form is open.

    // MARK: The page

    var search = ""
    /// The Backlog's disclosure, remembered.
    var backlogOpen = Prefs.defaults.bool(forKey: "backlog.open") {
        didSet { remember(backlogOpen, as: "backlog.open"); syncMenu() }
    }
    var backlogFilter = BacklogFilter()
    /// Each list's own search, in its header.
    var listSearch: [TaskList: String] = [:]
    /// Files and Artifacts' own search, by title.
    var filesSearch = ""
    /// The lists whose Descriptions toggle shows every description, remembered.
    /// Sections folded to their header, remembered; the Backlog has its own.
    var folded: Set<PageSection> = Set(((Prefs.defaults.array(forKey: "page.folded") as? [String]) ?? []).compactMap(PageSection.init(rawValue:))) {
        didSet { remember(folded.map(\.rawValue).sorted(), as: "page.folded"); syncMenu() }
    }
    /// The notification center's Earlier, folded by default as the Backlog is; remembered.
    var earlierOpen = Prefs.defaults.bool(forKey: "notifications.earlierOpen") {
        didSet { remember(earlierOpen, as: "notifications.earlierOpen") }
    }
    var allDescriptions: Set<TaskList> = AppModel.storedLists("outline.descriptions") {
        didSet { remember(allDescriptions.map(\.rawValue).sorted(), as: "outline.descriptions"); hiddenDescriptions = []; syncMenu() }
    }
    /// View › Zoom, remembered: every size scales with it.
    var zoom: CGFloat = {
        let stored = CGFloat(Prefs.defaults.double(forKey: "view.zoom"))
        return Zoom.steps.contains(stored) ? stored : 1
    }() {
        didSet {
            Zoom.factor = zoom
            KitType.resetFonts()
            remember(Double(zoom), as: "view.zoom")
            syncMenu()
        }
    }
    /// Which reviews the Reviews card lists, remembered.
    var reviewFilter = Prefs.defaults.string(forKey: "prs.reviewFilter").flatMap(ReviewFilter.init(rawValue:)) ?? .notApproved {
        didSet { remember(reviewFilter.rawValue, as: "prs.reviewFilter") }
    }
    /// GitHub is being asked: the PR section's Refresh turns into a spinner.
    var githubPolling = false
    /// When GitHub last answered, when that's later than `github`: a poll that changed nothing sets only this.
    var githubAnswered: Date?
    var githubUpdated: Date? { [githubAnswered, github?.fetchedAt].compactMap(\.self).max() }
    /// How far back GitHub events notify, in days: what HQ catches up on after being off. Settings › GitHub.
    var githubLookback = Prefs.defaults.object(forKey: "github.lookbackDays") as? Int ?? AppModel.defaultLookback {
        didSet { remember(githubLookback, as: "github.lookbackDays") }
    }
    static let defaultLookback = 10
    static let lookbackChoices = [3, 7, 10, 14, 30]
    /// Files and Artifacts shows pinned items only, remembered.
    var pinnedOnly = Prefs.defaults.bool(forKey: "files.pinnedOnly") {
        didSet { remember(pinnedOnly, as: "files.pinnedOnly") }
    }
    /// The lists whose Hide Done is on, remembered.
    var hideDone: Set<TaskList> = AppModel.storedLists("outline.hideDone").subtracting([.backlog]) {
        didSet { remember(hideDone.map(\.rawValue).sorted(), as: "outline.hideDone"); syncMenu() }
    }
    /// Descriptions shown one by one.
    var shownDescriptions: Set<Int> = []
    /// Descriptions hidden one by one while their list shows them all.
    var hiddenDescriptions: Set<Int> = []
    /// The description whose markdown is in an editor in the outline.
    var editingDescription: Int? {
        didSet {
            guard editingDescription != oldValue else { return }
            descriptionEditorHeight = 0
            // A draft is never dropped: the one being left is saved by the editors' rule.
            if let draft = outlineDraft, draft.id != editingDescription {
                outlineDraft = nil
                commitDescription(draft)
            }
            if let id = editingDescription, outlineDraft?.id != id { outlineDraft = TextDraft(id: id, base: task(id)?.body ?? "") }
        }
    }
    /// Its editor's text height, once it reports one: the row grows with it.
    var descriptionEditorHeight: CGFloat = 0
    /// Where a double-click landed on rendered markdown, from its top-left: the next editor puts the caret there.
    @ObservationIgnored var editorCaret: CGPoint?
    /// What each task shows of its subtasks, where the user chose, by key (2026-11-10). A task not in it shows them all,
    /// but under a task that shows only some: it follows that one.
    var fold: [Int: FoldMode] = FoldMode.remembered() {
        didSet { FoldMode.remember(fold) }
    }
    /// Colors the user picked, by "tag:name" or "project:name" (lowercased); the others follow their name.
    var labelColors: [String: String] = (Prefs.defaults.dictionary(forKey: "labels.colors") as? [String: String]) ?? [:] {
        didSet { remember(labelColors, as: "labels.colors") }
    }
    /// Each project's folder and repositories, by its key.
    var projectLinks: [String: StoredProject] = Prefs.defaults.data(forKey: "projects.links")
        .flatMap { try? JSONDecoder().decode([String: StoredProject].self, from: $0) } ?? [:] {
        didSet { if let data = try? JSONEncoder().encode(projectLinks) { remember(data, as: "projects.links") } }
    }
    /// The task row or the session card the Task and Session menus act on.
    var focusedTask: Int? { didSet { syncMenu() } }
    /// Every selected outline row, in order: the Task menu's targets when there are several.
    var selectedTasks: [Int] = [] { didSet { syncMenu() } }
    var selectedSession: String? { didSet { syncMenu() } }
    /// The one team shown open on the grid, its top card's id; nil folds it.
    var openTeam: SessionItem.ID? { didSet { if openTeam != oldValue { syncMenu() } } }
    /// The session cards have the keyboard: the Session menu's ⌘↓ ⌘↑ follow.
    var cardsKeyboard = false { didSet { if cardsKeyboard != oldValue { syncMenu() } } }
    /// The session grid's columns: on two, a card's ⇧ arrows move it on screen, and the Session menu says so.
    var gridColumns = 1 { didSet { if gridColumns != oldValue { syncMenu() } } }
    /// A PR, a chip or a modal row a click selected; a double-click opens it.
    var selectedItem: String? {
        didSet {
            guard selectedItem != oldValue else { return }
            syncMenu()
        }
    }
    /// The outline's rows or a title have the keyboard: the Task menu's keys follow.
    var outlineKeyboard = OutlineKeyboard.none { didSet { syncMenu() } }
    /// New Task: the quick-add line of this list takes the keyboard.
    var quickAddFocus: TaskList?
    /// ↓ on a task window's last subtask: that task's new subtask card takes the keyboard.
    var newSubtaskFocus: Int?
    /// Where the outline puts the keyboard after its next update.
    var outlineFocus: OutlineFocus?
    /// A PR opened from a notification at its review or comment: the PR's URL and the page to load (T-328).
    var githubPage: (pr: String, page: String)?
    /// Link… on a task's row: the outline shows the link picker under it (T-298).
    @ObservationIgnored var showLinkPicker: (Int) -> Void = { _ in }
    /// Block…, Blocked By… and After… on a task's row: the outline shows their picker under it.
    @ObservationIgnored var showHoldPicker: (Int, HoldPicker.Kind) -> Void = { _, _ in }
    /// Sets what tasks show of their subtasks, as the outline does it: the selection moves to a task that hid it.
    @ObservationIgnored var foldTasks: ([Int], FoldMode) -> Void = { _, _ in }
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
    /// The modal page (an artifact's, a PR's) that is loading: its Reload turns.
    var loadingPage: String?
    /// The cards of rows opened past their first five ("Show N More").
    var expandedCards: Set<RowCard> = []
    /// The row selected inside the modal: its own, so the page's selection stays as it was.
    var modalSelection: String?

    // MARK: The modal

    var modal: ModalRoute? {
        // Every way out of an item saves what its editor holds: Back, Close, a chip, ⌘J, a banner.
        willSet { if newValue != modal { saveModalEdits() } }
        didSet {
            syncMenu()
            // Back from a PR's page, where the user may have reviewed it: Reviews catch up in seconds (T-366).
            if case .github? = oldValue, modal != oldValue { pollGitHubSoon() }
        }
    }
    /// What Back returns to, newest last.
    var modalStack: [ModalRoute] = [] { didSet { syncMenu() } }
    var startDraft: StartDraft?
    /// The role picked in the Roles modal, and its name, line or text while edited in place.
    var selectedRole: String?
    var roleEdit: RoleEdit? { didSet { syncMenu() } }
    /// A file's markdown in the modal's editor, the text it started from, and the text so far.
    var editingFile: FileItem.ID?
    var fileDraftBase = ""
    var fileDraft = ""
    /// The task window's description editor: the task, the text it started from, and the text so far.
    var modalDescription: TextDraft?
    var modalEditingDescription: Bool { modalDescription != nil }
    var descriptionDraft: String {
        get { modalDescription?.text ?? "" }
        set { modalDescription?.text = newValue }
    }
    /// The outline's description editor (`editingDescription`): its task, base and text.
    var outlineDraft: TextDraft?

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
    var settingsTab: SettingsTab = SettingsTab(rawValue: Prefs.defaults.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { Prefs.defaults.set(settingsTab.rawValue, forKey: "settings.tab") }
    }

    @ObservationIgnored private var clock: AnyCancellable?
    @ObservationIgnored let storage: Storage?
    @ObservationIgnored var exitWatchers: [Int32: DispatchSourceProcess] = [:]
    /// Close Session's terminals, by their Claude's pid: they close when it exits.
    @ObservationIgnored var closingTerminals: [Int32: String] = [:]
    /// Background sessions (`claude --bg`) by their handle in `claude stop`, learnt when first reached.
    var backgroundHandles: [String: String] = [:]
    /// Running sessions' transcripts, watched for a /rename.
    @ObservationIgnored var titleWatchers: [String: DispatchSourceFileSystemObject] = [:]
    /// Hook events that moved only a session's last activity, by session: not in `sessions` yet (`settleActivity`).
    @ObservationIgnored var activity: [String: Date] = [:]
    /// Sessions whose transcript changed, read again in a moment.
    @ObservationIgnored var titleReads: Set<String> = []
    @ObservationIgnored var sessionSave: Task<Void, Never>?
    @ObservationIgnored var attentionSave: Task<Void, Never>?
    @ObservationIgnored var noticeSave: Task<Void, Never>?
    /// Wakes when the next reminder or row put Later is due.
    @ObservationIgnored var dueTimer: Task<Void, Never>?
    @ObservationIgnored let bannerDelegate = BannerDelegate()
    @ObservationIgnored var vault: Vault? = AppModel.resolveVault()
    @ObservationIgnored var vaultWatcher: VaultWatcher?
    @ObservationIgnored var vaultCache = Vault.Cache()
    @ObservationIgnored var vaultScanning = false
    @ObservationIgnored var vaultRescanAgain = false
    /// Task notes the last scan couldn't read, logged once.
    @ObservationIgnored var vaultUnreadable: Set<String> = []
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
    @ObservationIgnored var flowCache: (version: Int, flow: TaskFlow)?
    @ObservationIgnored var taskIndex: [Int: Int] = [:]
    /// Every task's outputs, by task.
    @ObservationIgnored var outputsCache: [Int: [ModalRoute]]?
    /// Open reminders by the selection key of what they link, the soonest first (T-311).
    @ObservationIgnored var reminderMarks: [String: [Notice]]?
    /// The status a done task had, for ⌘Return twice.
    @ObservationIgnored var doneBefore: [Int: TaskStatus] = [:]
    /// The session or "claude" behind a socket command: what it changes turns blue.
    @ObservationIgnored var actor: String?
    /// What a test run would have asked Ghostty to do; with `ghosttyFails`, every call fails.
    @ObservationIgnored var ghosttyLog: [String] = []
    @ObservationIgnored var ghosttyFails = false
    @ObservationIgnored var gitHubService: GitHubService?
    @ObservationIgnored var slackService: SlackService?
    /// The Slack links a test run would have opened.
    @ObservationIgnored var slackLog: [String] = []
    /// Pages a test run would have opened in the browser.
    @ObservationIgnored var browserLog: [String] = []
    /// Files HQ couldn't read and moved aside this run (Problem.movedAside shows them).
    @ObservationIgnored var movedAside: [String] = []
    /// How many times a test run asked HQ to restart.
    @ObservationIgnored var restarts = 0
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
            // A store that doesn't open goes aside and HQ starts on a fresh one: hooks rebuild the sessions.
            AppLog.write("couldn't open the store: \(error)", to: "store.log")
            if let aside = Store.moveAside(Store.url) { movedAside.append(aside.path) }
            storage = try? Storage(url: Store.url)
            problem = .movedAside
        }
        sessions = storage?.sessions() ?? []
        artifacts = storage?.artifacts() ?? []
        seen = storage?.seen() ?? [:]
        loadNotices()
        // A test run starts on its own empty preferences (Prefs): zoom 1, nothing folded.
        Zoom.factor = zoom
        KitType.resetFonts()
        clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect().sink { [weak self] date in
            MainActor.assumeIsolated {
                self?.settleActivity()
                self?.now = date
            }
        }
        reviveSessions()
        adoptRenames()
        startVault()
        gitHubService = GitHubService(model: self)
        slackService = SlackService(model: self)
        watchGhosttyFocus()
        if !Store.isOverridden {
            bannerDelegate.model = self
            UNUserNotificationCenter.current().delegate = bannerDelegate
        }
    }

    /// Saves a preference (a test run's own, Prefs).
    /// A section's header shows it or folds it.
    func sectionOpen(_ section: PageSection) -> Binding<Bool> {
        Binding(get: { !self.folded.contains(section) }, set: { open in
            if open { self.folded.remove(section) } else { self.folded.insert(section) }
        })
    }

    private func remember(_ value: Any, as key: String) {
        Prefs.defaults.set(value, forKey: key)
    }

    private static func storedLists(_ key: String) -> Set<TaskList> {
        Set(((Prefs.defaults.array(forKey: key) as? [String]) ?? []).compactMap(TaskList.init(rawValue:)))
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
        // A web page opens in the browser, a Slack link in Slack: HQ shows its own items only.
        if case .web(let url) = route {
            if let address = URL(string: url) { NSWorkspace.shared.open(address) }
            return
        }
        if case .slack(let url) = route { return openInSlack(url) }
        // A PR or an issue HQ hasn't loaded from GitHub yet (a link just made, a preview's first poll) opens on GitHub:
        // never a window that says it's gone. Test runs only log it.
        if case .github(let url) = route, githubItem(url) == nil {
            guard !Store.isOverridden || GitHubService.asksGitHub else { return browserLog.append(url) }
            if let address = URL(string: url) { NSWorkspace.shared.open(address) }
            return
        }
        if case .github(let url) = route, githubPage?.pr == url {} else { githubPage = nil }
        showWindow()
        saveModalEdits()
        if push, let current = modal, current != route {
            modalStack.append(current)
        } else if !push {
            modalStack = []
        }
        modal = route
        if case .session(let id) = route { markSessionSeen(id) }
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
            beginModalDescription(id)
        } else {
            shownDescriptions.insert(id)
            editingDescription = id
        }
    }

    func closeModal() {
        saveModalEdits()
        modal = nil
        modalStack = []
    }

    /// Leaving a modal keeps what was typed, by the editors' rule (TextMerge), in the task or file it was typed for.
    func saveModalEdits() {
        if let id = editingFile {
            editingFile = nil
            commitFile(id, base: fileDraftBase, text: fileDraft)
        }
        if let draft = modalDescription {
            modalDescription = nil
            commitDescription(draft)
        }
        if roleEdit != nil { commitRoleEdit() }
    }

    /// The task window's description in its editor.
    func beginModalDescription(_ id: Int) {
        saveModalEdits()
        modalDescription = TextDraft(id: id, base: task(id)?.body ?? "")
    }

    /// Start Session… on a task, a PR, or New Session…; Start Child Session… (`parent`) and Start Session from Its
    /// History… (`history`: at that session's level, with its role and folder, its name marked ⑂).
    func beginStart(task: Int? = nil, pullRequest: GitHubItem? = nil, parent: SessionItem.ID? = nil, history: SessionItem.ID? = nil,
                    push: Bool = false) {
        showWindow()
        let item = self.task(task)
        let source = session(history)
        let under = source.map { $0.parent } ?? session(parent)?.id
        var name = item.map { "\($0.key) \($0.title)" } ?? pullRequest.map { "Review \($0.reference)" } ?? ""
        if let source { name = "\(source.name) ⑂" }
        // The project's folder: the task's (or a parent's) project, or the one the PR's repository belongs to.
        let project = task.flatMap(project(ofTask:)) ?? pullRequest.flatMap { project(ofRepo: $0.repo) }
        let folder = source?.cwd ?? session(parent)?.cwd ?? project.flatMap { links(of: $0).folder } ?? pullRequest.flatMap { clone(of: $0.repo) }
            ?? recentDirectories(for: task).first ?? NSHomeDirectory()
        let message = item.map(Self.taskPrompt) ?? pullRequest.map(Self.reviewPrompt) ?? ""
        startDraft = StartDraft(name: name, folder: folder, message: message + (message.isEmpty ? "" : "\n\n"), task: task,
                                pullRequest: pullRequest?.url, parent: under, role: source.map { $0.role } ?? siblingsRole(under: under),
                                history: source?.id)
        open(.start, push: push)
    }

    /// The role most of a new session's siblings have, else none: a leader's next session is a Worker, and no rule names one.
    func siblingsRole(under parent: SessionItem.ID?) -> String? {
        let tree = sessionTree
        let roles = (parent.map { tree.children(of: $0) } ?? tree.roots).compactMap { session($0) }.map { role(named: $0.role)?.name ?? "" }
        let counts = Dictionary(roles.map { ($0, 1) }, uniquingKeysWith: +)
        guard let best = counts.max(by: { $0.value < $1.value }), !best.key.isEmpty,
              counts.values.filter({ $0 == best.value }).count == 1 else { return nil }
        return best.key
    }

    /// Start (⌘Return). On failure the form stays with its text and the banner says why.
    func startFromDraft() {
        guard let draft = startDraft, !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        startSession(named: draft.name.trimmingCharacters(in: .whitespaces), in: (draft.folder as NSString).expandingTildeInPath,
                     task: draft.task, pullRequest: draft.pullRequest, message: draft.message,
                     parent: draft.parent, role: draft.role, history: draft.history) { [weak self] started in
            guard let self, started else { return }
            if self.modal == .start { self.closeModal() }
        }
    }

    // MARK: Menus

    func syncMenu() {
        MenuState.shared.update(model: self)
        let count = importantCount
        MenuBarIcon.shared.update(count: count, blinks: bellBreathes)
        let badge = count > 0 ? "\(count)" : nil
        if NSApp?.dockTile.badgeLabel != badge { NSApp?.dockTile.badgeLabel = badge }
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
    @Published private(set) var outlineKeyboard = OutlineKeyboard.none
    @Published private(set) var canGoBack = false
    @Published private(set) var inCenter = false
    @Published private(set) var backlogOpen = false
    @Published private(set) var folded: Set<PageSection> = []
    /// A task's modal is open: the Task menu acts on it, not on the outline behind it.
    @Published private(set) var inModal = false
    @Published private(set) var tasksToBacklog = true
    @Published private(set) var allDone = false
    @Published private(set) var sessionCanFocus = false
    @Published private(set) var sessionClosable = false
    @Published private(set) var hasClosed = false
    @Published private(set) var github = false
    @Published private(set) var reviewFilter = ReviewFilter.notApproved
    @Published private(set) var pinnedOnly = false
    @Published private(set) var descriptions: Set<TaskList> = []
    @Published private(set) var zoom: CGFloat = 1
    @Published private(set) var hideDone: Set<TaskList> = []
    @Published private(set) var canEditFile = false
    @Published private(set) var canEditRole = false
    /// The Session menu's team items: its team shown open, has one, sits under a session, its open sessions as a top card,
    /// and the sessions it can move under.
    @Published private(set) var teamShown = false
    @Published private(set) var cardsKeyboard = false
    @Published private(set) var sessionHasTeam = false
    @Published private(set) var sessionHasParent = false
    @Published private(set) var teamOpenCount = 0
    @Published private(set) var moveUnder: [String] = []
    /// Its moves, as a task's: Move Up, Move Down, Indent, Outdent.
    @Published private(set) var sessionUp = false
    @Published private(set) var sessionDown = false
    @Published private(set) var sessionRight = false
    @Published private(set) var sessionLeft = false
    /// A card on two columns: ⇧→ and ⇧← move it on screen, Move Right and Move Left, not Indent and Outdent.
    @Published private(set) var sessionMovesOnScreen = false
    @Published private(set) var taskDescriptionShown = false
    @Published private(set) var taskBlocked = false
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
    /// What Remind Me… acts on: the open or selected task, PR, file or artifact.
    @Published private(set) var remindable: ModalRoute?

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
        set(\.sessionCanFocus, session.map { !$0.isRunning || $0.tty != nil } ?? false)
        set(\.sessionClosable, session.map { $0.isRunning && $0.tty != nil } ?? false)
        let tree = model.sessionTree
        let root = session.map { tree.root(of: $0.id) }
        set(\.sessionHasTeam, root.map { !tree.rows(under: $0).isEmpty } ?? false)
        set(\.teamShown, root != nil && model.openTeam == root)
        set(\.cardsKeyboard, model.modal == nil && model.cardsKeyboard)
        set(\.sessionHasParent, session.map { tree.parent(of: $0.id) != nil } ?? false)
        set(\.teamOpenCount, session.map { item in tree.parent(of: item.id) == nil && !tree.rows(under: item.id).isEmpty ? model.openSessions(ofTeam: item.id).count : 0 } ?? 0)
        set(\.moveUnder, session.map { model.moveUnderChoices(for: $0.id) } ?? [])
        let moves = session.map { model.sessionMoves($0.id) }
        set(\.sessionUp, moves?.up ?? false)
        set(\.sessionDown, moves?.down ?? false)
        set(\.sessionRight, moves?.right ?? false)
        set(\.sessionLeft, moves?.left ?? false)
        set(\.sessionMovesOnScreen, session.map { model.movesOnScreen($0.id) } ?? false)
        set(\.outlineKeyboard, model.modal == nil ? model.outlineKeyboard : .none)
        set(\.canGoBack, !model.modalStack.isEmpty)
        set(\.inCenter, model.modal == .notifications)
        set(\.backlogOpen, model.backlogOpen)
        set(\.folded, model.folded)
        set(\.inModal, modalTask != nil)
        set(\.github, model.github != nil)
        set(\.reviewFilter, model.reviewFilter)
        set(\.pinnedOnly, model.pinnedOnly)
        set(\.hasClosed, !model.closedSessions.isEmpty)
        set(\.descriptions, model.allDescriptions)
        set(\.zoom, model.zoom)
        set(\.hideDone, model.hideDone)
        let file: Bool = if case .file = model.modal { model.editingFile == nil } else { false }
        set(\.canEditFile, file)
        set(\.canEditRole, model.modal == .roles && model.roleEdit == nil && model.role(named: model.selectedRole) != nil)
        set(\.taskDescriptionShown, task.map { model.descriptionShownInOutline($0.id) } ?? false)
        set(\.taskBlocked, task?.blocked ?? false)
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
        let remindable: ModalRoute? = switch model.menuRoute {
        case .task, .github, .file, .artifact: model.menuRoute
        default: model.modal == nil ? task.map { .task($0.id) } : nil
        }
        set(\.remindable, remindable)
    }
}
