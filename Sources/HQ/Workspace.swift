import Foundation
import HQKit

/// One Claude Code conversation.
nonisolated struct SessionItem: Identifiable, Hashable, Sendable {
    /// Claude's session_id.
    var id: String
    /// The user's name for it, or the one HQ gave a session it started.
    var customName: String?
    /// Claude's title for it.
    var title: String?
    /// The last /rename read from its transcript: a new one names the session.
    var renamed: String?
    var firstPrompt: String?
    var status: SessionStatus
    var cwd: String
    var repo: String
    var branch: String
    /// `owner/name` of the repository's origin, for matching pull requests.
    var origin: String?
    var started: Date
    /// Claude's process and terminal, while it runs.
    var pid: Int32?
    var tty: String?
    var inGhostty = true
    /// Permission: the tool and its input.
    var tool: String?
    var toolInput: String?
    /// Question: what Claude asks, and the options it offers.
    var question: String?
    var options: [String] = []
    /// Plan: the plan file Claude wrote.
    var planPath: String?
    /// Failed: the error.
    var error: String?
    /// Claude's last message, from Stop. Markdown.
    var lastMessage: String?
    var transcriptPath: String?
    /// The user's place for it in the grid.
    var order: Double = 0
    /// When it ended: it leaves the grid for Closed Sessions.
    var closedAt: Date?
    /// Chosen once so its face differs from the other open sessions'.
    var faceSalt = 0
    /// Pull requests it opened.
    var links: [String] = []
    /// The session whose face it wears: the one it continues after /clear.
    var faceID: String?
    /// The subagent whose wait it shows; nil: the main thread's.
    var waiter: String?
    /// The session that started it, by hq or from the page: its card sits in that one's team.
    var parent: String?
    /// The name of the role it started with: a note in hq/roles/.
    var role: String?
    /// What its last reply ran on and the tokens its context holds, from its transcript; not stored (T-446, T-475).
    var model: String?
    var effort: String?
    var contextTokens: Int?
    /// When HQ last typed /model or /effort in its terminal: a reply older than that doesn't undo it.
    var runChangedAt: Date?

    /// The user's name, else Claude's title, else the first prompt, else the repository.
    var name: String {
        customName ?? title ?? firstPrompt.map { String($0.prefix(120)) } ?? (repo.isEmpty ? "New session" : repo)
    }

    var face: FaceSpec { FaceSpec(id: faceID ?? id, salt: faceSalt) }

    /// On the grid: open.
    var onGrid: Bool { closedAt == nil }

    var searchText: String { "\(name) \(repo) \(branch)" }

    /// The state and what it waits on, for the state machine.
    var live: SessionLive {
        get {
            var live = SessionLive(status: status)
            live.tool = tool
            live.toolInput = toolInput
            live.question = question
            live.options = options
            live.planPath = planPath
            live.error = error
            live.lastMessage = lastMessage
            live.waiter = waiter
            return live
        }
        set {
            status = newValue.status
            tool = newValue.tool
            toolInput = newValue.toolInput
            question = newValue.question
            options = newValue.options
            planPath = newValue.planPath
            error = newValue.error
            lastMessage = newValue.lastMessage
            waiter = newValue.waiter
        }
    }

    /// What the session needs from the user, as a sentence without a subject (DESIGN.md §14).
    var reason: String? {
        switch status.state {
        case .waiting(.permission): ["Wants to run \(tool ?? "a tool")", toolInput].compactMap(\.self).joined(separator: " · ")
        case .waiting(.question): "Asks: \(question ?? "a question")"
        case .waiting(.plan): "Plan ready for review"
        case .failed: "Failed: \(error ?? "unknown error")"
        default: nil
        }
    }

    var place: String { branch.isEmpty ? repo : "\(repo) · \(branch)" }

    var resumeCommand: String { "claude --resume \(id)" }

    var isRunning: Bool { status.state != .ended }
    var isWorking: Bool { status.state == .working }
}

/// One field of an item: compared, and copied from another copy of the item. An edit's Undo puts back the fields
/// it changed only, so it never reverts what a session or Obsidian changed since.
nonisolated struct ItemField<Item> {
    let name: String
    let differs: (Item, Item) -> Bool
    let copy: (inout Item, Item) -> Void

    init<Value: Equatable>(_ name: String, _ path: WritableKeyPath<Item, Value>) {
        self.name = name
        differs = { $0[keyPath: path] != $1[keyPath: path] }
        copy = { $0[keyPath: path] = $1[keyPath: path] }
    }

    /// `old`'s values of the fields `edited` changed, put back on `current`.
    static func undo(_ fields: [ItemField], from old: Item, into current: inout Item) {
        for field in fields { field.copy(&current, old) }
    }
}

/// A task note: <vault>/hq/tasks/T-<n>.md.
nonisolated struct TaskItem: Identifiable, Hashable, Sendable, Codable {
    var id: Int
    var title: String
    var status: TaskStatus = .todo
    var type: TaskType?
    var project: String?
    var tags: [String] = []
    var parent: Int?
    /// Tasks or the Backlog; a subtask shows in its root's.
    var list: TaskList = .backlog
    var order: Double = 0
    /// Read from a note still in Review, the status v9 dropped: its reason, until the center has it (`migrateReviews`).
    var review: String?
    /// Who put it in Review (a session id, or "you"), and when.
    var reviewBy: String?
    var reviewAt: Date?
    /// When it was done.
    var done: Date?
    var links: [URL] = []
    /// Tasks linked to it: they show under its row, not it under theirs.
    var related: [Int] = []
    /// Blocked: it can't be done now; the user or a session sets it and clears it.
    var blocked = false
    /// Why it's blocked, when someone said.
    var blockedReason: String?
    /// Tasks it can't go on without: it's blocked until each is done.
    var blockedBy: [Int] = []
    /// Tasks it comes after: the order the user means. It never moves a task.
    var after: [Int] = []
    var sessions: [String] = []
    var created: Date
    var modified: Date
    /// The description: the note's markdown after the front matter.
    var body: String = ""
    /// The note on disk; nil for sample data.
    var path: String?

    var key: String { "T-\(id)" }
    var searchText: String { "\(key) \(title) \(tags.map { "#\($0)" }.joined(separator: " ")) \(project ?? "")" }

    /// Everything hq writes back: all but the file's own dates.
    func sameNote(as other: TaskItem) -> Bool {
        !Self.noteFields.contains { $0.differs(self, other) }
    }

    typealias Field = ItemField<TaskItem>
    /// Every stored field but the id, the note's path and its dates. Undo puts back only the fields an edit changed,
    /// so it never reverts what a session wrote since; the self-test holds this list to the type's fields.
    static var noteFields: [Field] {
        [Field("title", \.title), Field("status", \.status), Field("type", \.type), Field("project", \.project),
         Field("tags", \.tags), Field("parent", \.parent), Field("list", \.list), Field("order", \.order),
         Field("review", \.review), Field("reviewBy", \.reviewBy), Field("reviewAt", \.reviewAt), Field("done", \.done),
         Field("links", \.links), Field("related", \.related), Field("blocked", \.blocked), Field("blockedReason", \.blockedReason),
         Field("blockedBy", \.blockedBy), Field("after", \.after), Field("sessions", \.sessions), Field("body", \.body)]
    }

    var node: TaskTree.Node { TaskTree.Node(id: id, parent: parent, list: list, order: order) }

    static func key(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: "T-", with: ""))
    }
}

extension TaskItem {
    /// Reads tasks saved before Blocked and its links (`hq task history`): those keys default.
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        status = try c.decode(TaskStatus.self, forKey: .status)
        type = try c.decodeIfPresent(TaskType.self, forKey: .type)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        parent = try c.decodeIfPresent(Int.self, forKey: .parent)
        list = try c.decodeIfPresent(TaskList.self, forKey: .list) ?? .backlog
        order = try c.decodeIfPresent(Double.self, forKey: .order) ?? 0
        review = try c.decodeIfPresent(String.self, forKey: .review)
        reviewBy = try c.decodeIfPresent(String.self, forKey: .reviewBy)
        reviewAt = try c.decodeIfPresent(Date.self, forKey: .reviewAt)
        done = try c.decodeIfPresent(Date.self, forKey: .done)
        links = try c.decodeIfPresent([URL].self, forKey: .links) ?? []
        related = try c.decodeIfPresent([Int].self, forKey: .related) ?? []
        blocked = try c.decodeIfPresent(Bool.self, forKey: .blocked) ?? false
        blockedReason = try c.decodeIfPresent(String.self, forKey: .blockedReason)
        blockedBy = try c.decodeIfPresent([Int].self, forKey: .blockedBy) ?? []
        after = try c.decodeIfPresent([Int].self, forKey: .after) ?? []
        sessions = try c.decodeIfPresent([String].self, forKey: .sessions) ?? []
        created = try c.decode(Date.self, forKey: .created)
        modified = try c.decode(Date.self, forKey: .modified)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        path = try c.decodeIfPresent(String.self, forKey: .path)
    }
}

/// A markdown note under <vault>/hq/files/.
nonisolated struct FileItem: Identifiable, Hashable, Sendable {
    /// The path inside hq/files/.
    var id: String
    var title: String
    var date: Date
    var modified: Date
    var status: String?
    var sessions: [String] = []
    /// Tasks it belongs to.
    var tasks: [Int] = []
    var project: String?
    var tags: [String] = []
    var pinned = false
    /// The note on disk; nil for sample data.
    var path: String?

    var searchText: String { "\(title) \(tags.map { "#\($0)" }.joined(separator: " ")) \(project ?? "")" }

    func sameNote(as other: FileItem) -> Bool {
        title == other.title && status == other.status && sessions == other.sessions && tasks == other.tasks
            && project == other.project && tags == other.tags && pinned == other.pinned
    }

    /// What hq writes back of a file note, and what Undo puts back.
    static var noteFields: [ItemField<FileItem>] {
        [ItemField("title", \.title), ItemField("status", \.status), ItemField("sessions", \.sessions), ItemField("tasks", \.tasks),
         ItemField("project", \.project), ItemField("tags", \.tags), ItemField("pinned", \.pinned)]
    }
}

/// A page Claude published on claude.ai.
nonisolated struct ArtifactItem: Identifiable, Hashable, Sendable {
    var id: URL
    var title: String
    var session: String?
    var published: Date
    var tasks: [Int] = []
    var project: String?
    var tags: [String] = []
    var pinned = false

    var searchText: String { "\(title) \(tags.map { "#\($0)" }.joined(separator: " ")) \(project ?? "")" }

    /// What Undo puts back of an artifact.
    static var fields: [ItemField<ArtifactItem>] {
        [ItemField("title", \.title), ItemField("session", \.session), ItemField("published", \.published), ItemField("tasks", \.tasks),
         ItemField("project", \.project), ItemField("tags", \.tags), ItemField("pinned", \.pinned)]
    }
}

/// A role: <vault>/hq/roles/<Name>.md, its color and line in the front matter and its text in the body. A session started
/// with it gets the text at its start, on resume and after a compact (PLAN.md §7).
nonisolated struct RoleItem: Identifiable, Hashable, Sendable {
    var id: String { name }
    /// The note's name, unique, case ignored.
    var name: String
    var color: LabelColor
    /// One line: what a session with it does.
    var line: String = ""
    /// What a session with it starts with: markdown.
    var text: String = ""
    /// The model and effort a session with it starts on, as `claude --model --effort` takes them; nil, Claude Code's own (T-446).
    var model: String?
    var effort: String?
    /// One that ships with HQ (Leader, Worker): Restore Default brings its text back.
    var builtin = false
    var modified: Date = .distantPast
    /// The note on disk; nil for sample data.
    var path: String?
}
