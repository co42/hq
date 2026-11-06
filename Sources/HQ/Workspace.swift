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

    /// The user's name, else Claude's title, else the first prompt, else the repository.
    var name: String {
        customName ?? title ?? firstPrompt.map { String($0.prefix(120)) } ?? (repo.isEmpty ? "New session" : repo)
    }

    var face: FaceSpec { FaceSpec(id: id, salt: faceSalt) }

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
    /// Why it waits for the user, while in Review.
    var review: String?
    /// Who put it in Review (a session id, or "you"), and when.
    var reviewBy: String?
    var reviewAt: Date?
    /// When it was done.
    var done: Date?
    var links: [URL] = []
    /// Tasks linked to it, both ways.
    var related: [Int] = []
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
        title == other.title && status == other.status && type == other.type && project == other.project
            && tags == other.tags && parent == other.parent && list == other.list && order == other.order
            && review == other.review && reviewBy == other.reviewBy && reviewAt == other.reviewAt && done == other.done
            && links == other.links && related == other.related && sessions == other.sessions && body == other.body
    }

    var node: TaskTree.Node { TaskTree.Node(id: id, parent: parent, list: list, order: order) }

    static func key(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: "T-", with: ""))
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
}
