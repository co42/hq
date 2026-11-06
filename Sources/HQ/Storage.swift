import Foundation
import HQKit
import SwiftData

/// A session in the store: everything hq knows about it, so a relaunch shows it again.
@Model
final class SessionRecord {
    var sessionID: String = ""
    var customName: String?
    var title: String?
    var renamed: String?
    var firstPrompt: String?
    var stateKey: String = "idle"
    var unread: Bool = false
    var since: Date = Date.now
    var lastActivity: Date = Date.now
    var cwd: String = ""
    var repo: String = ""
    var branch: String = ""
    var origin: String?
    var started: Date = Date.now
    var pid: Int = 0
    var tty: String?
    var inGhostty: Bool = true
    var tool: String?
    var toolInput: String?
    var question: String?
    var options: [String] = []
    var planPath: String?
    var error: String?
    var lastMessage: String?
    var transcriptPath: String?
    var order: Double = 0
    /// Unused: kept so the store opens without a migration.
    var hidden: Bool = false
    var closedAt: Date?
    var faceSalt: Int = 0
    var links: [String] = []

    init(_ item: SessionItem) {
        sessionID = item.id
        update(item)
    }

    func update(_ item: SessionItem) {
        func set<T: Equatable>(_ path: ReferenceWritableKeyPath<SessionRecord, T>, _ value: T) {
            if self[keyPath: path] != value { self[keyPath: path] = value }
        }
        set(\.customName, item.customName)
        set(\.title, item.title)
        set(\.renamed, item.renamed)
        set(\.firstPrompt, item.firstPrompt)
        set(\.stateKey, item.status.state.key)
        set(\.unread, item.status.unread)
        set(\.since, item.status.since)
        set(\.lastActivity, item.status.lastActivity)
        set(\.cwd, item.cwd)
        set(\.repo, item.repo)
        set(\.branch, item.branch)
        set(\.origin, item.origin)
        set(\.started, item.started)
        set(\.pid, Int(item.pid ?? 0))
        set(\.tty, item.tty)
        set(\.inGhostty, item.inGhostty)
        set(\.tool, item.tool)
        set(\.toolInput, item.toolInput)
        set(\.question, item.question)
        set(\.options, item.options)
        set(\.planPath, item.planPath)
        set(\.error, item.error)
        set(\.lastMessage, item.lastMessage)
        set(\.transcriptPath, item.transcriptPath)
        set(\.order, item.order)
        set(\.closedAt, item.closedAt)
        set(\.faceSalt, item.faceSalt)
        set(\.links, item.links)
    }

    var item: SessionItem {
        let state = SessionState(key: stateKey) ?? .idle
        return SessionItem(id: sessionID, customName: customName, title: title, renamed: renamed, firstPrompt: firstPrompt,
                           status: SessionStatus(state: state, unread: unread, since: since, lastActivity: lastActivity),
                           cwd: cwd, repo: repo, branch: branch, origin: origin, started: started,
                           pid: pid > 0 ? Int32(pid) : nil, tty: tty, inGhostty: inGhostty,
                           tool: tool, toolInput: toolInput, question: question, options: options, planPath: planPath,
                           error: error, lastMessage: lastMessage, transcriptPath: transcriptPath,
                           order: order,
                           // A session that ended before the cockpit has no closing time: its state's.
                           closedAt: closedAt ?? (state == .ended ? since : nil),
                           faceSalt: faceSalt, links: links)
    }
}

/// A page Claude published on claude.ai.
@Model
final class ArtifactRecord {
    var url: String = ""
    var title: String = ""
    var session: String?
    var published: Date = Date.now
    var tasks: [Int] = []
    var project: String?
    var tags: [String] = []
    var pinned: Bool = false

    init(_ item: ArtifactItem) {
        url = item.id.absoluteString
        update(item)
    }

    func update(_ item: ArtifactItem) {
        if title != item.title { title = item.title }
        if session != item.session { session = item.session }
        if published != item.published { published = item.published }
        if tasks != item.tasks { tasks = item.tasks }
        if project != item.project { project = item.project }
        if tags != item.tags { tags = item.tags }
        if pinned != item.pinned { pinned = item.pinned }
    }

    var item: ArtifactItem? {
        URL(string: url).map { ArtifactItem(id: $0, title: title, session: session, published: published, tasks: tasks,
                                         project: project, tags: tags, pinned: pinned) }
    }
}

/// When the user last looked at an item: `task:T-13`, `file:<id>`, `artifact:<url>`, `gh:<url>`.
@Model
final class SeenRecord {
    var key: String = ""
    var seenAt: Date = Date.now

    init(key: String, seenAt: Date) {
        self.key = key
        self.seenAt = seenAt
    }
}

/// When Claude or GitHub last changed an item, and who.
@Model
final class ChangeRecord {
    var key: String = ""
    var changedAt: Date = Date.now
    var by: String = ""

    init(key: String, changedAt: Date, by: String) {
        self.key = key
        self.changedAt = changedAt
        self.by = by
    }
}

/// A change Claude or GitHub made, as AppModel keeps it.
nonisolated struct Change: Hashable, Sendable {
    var at: Date
    /// A session id, or "github".
    var by: String
}

/// HQ's store (PLAN.md §2): what has no file of its own. The app is its only writer.
final class Storage {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(url: URL) throws {
        container = try ModelContainer(for: SessionRecord.self, ArtifactRecord.self, SeenRecord.self, ChangeRecord.self,
                                       configurations: ModelConfiguration(url: url))
    }

    func sessions() -> [SessionItem] {
        ((try? context.fetch(FetchDescriptor<SessionRecord>())) ?? []).map(\.item)
    }

    func save(_ sessions: [SessionItem]) {
        sync(sessions, key: \.sessionID, id: \.id, make: SessionRecord.init) { $0.update($1) }
    }

    func artifacts() -> [ArtifactItem] {
        ((try? context.fetch(FetchDescriptor<ArtifactRecord>())) ?? []).compactMap(\.item)
    }

    func save(_ artifacts: [ArtifactItem]) {
        sync(artifacts, key: \.url, id: \.id.absoluteString, make: ArtifactRecord.init) { $0.update($1) }
    }

    func seen() -> [String: Date] {
        Dictionary(((try? context.fetch(FetchDescriptor<SeenRecord>())) ?? []).map { ($0.key, $0.seenAt) }, uniquingKeysWith: max)
    }

    func save(seen: [String: Date]) {
        let records = (try? context.fetch(FetchDescriptor<SeenRecord>())) ?? []
        var byKey = Dictionary(records.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        for (key, date) in seen {
            if let record = byKey.removeValue(forKey: key) {
                if record.seenAt != date { record.seenAt = date }
            } else {
                context.insert(SeenRecord(key: key, seenAt: date))
            }
        }
        for record in byKey.values { context.delete(record) }
        commit("seen items")
    }

    func changes() -> [String: Change] {
        Dictionary(((try? context.fetch(FetchDescriptor<ChangeRecord>())) ?? []).map { ($0.key, Change(at: $0.changedAt, by: $0.by)) },
                   uniquingKeysWith: { $0.at > $1.at ? $0 : $1 })
    }

    func save(changes: [String: Change]) {
        let records = (try? context.fetch(FetchDescriptor<ChangeRecord>())) ?? []
        var byKey = Dictionary(records.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        for (key, change) in changes {
            if let record = byKey.removeValue(forKey: key) {
                if record.changedAt != change.at { record.changedAt = change.at }
                if record.by != change.by { record.by = change.by }
            } else {
                context.insert(ChangeRecord(key: key, changedAt: change.at, by: change.by))
            }
        }
        for record in byKey.values { context.delete(record) }
        commit("changes")
    }

    /// Changed records update, new ones insert, missing ones go. Saves only when something changed.
    private func sync<Item, Record: PersistentModel>(_ items: [Item], key: KeyPath<Record, String>, id: KeyPath<Item, String>,
                                                     make: (Item) -> Record, update: (Record, Item) -> Void) {
        let records = (try? context.fetch(FetchDescriptor<Record>())) ?? []
        var byID = Dictionary(records.map { ($0[keyPath: key], $0) }, uniquingKeysWith: { first, _ in first })
        for item in items {
            if let record = byID.removeValue(forKey: item[keyPath: id]) {
                update(record, item)
            } else {
                context.insert(make(item))
            }
        }
        for record in byID.values { context.delete(record) }
        commit(String(describing: Record.self))
    }

    private func commit(_ what: String) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            FileHandle.standardError.write(Data("HQ: could not save \(what): \(error)\n".utf8))
        }
    }
}

/// Lines in ~/Library/Logs/HQ/<name>, to see afterwards what happened in the user's HQ. Never in a test run.
/// HQ_LAUNCH_LOG=1: when each step of the launch happened, as `launch <step> <seconds since 1970>` (tools/launch.sh).
enum LaunchLog {
    private static let enabled = ProcessInfo.processInfo.environment["HQ_LAUNCH_LOG"] == "1"
    private static var marked: Set<String> = []

    static func mark(_ step: String) {
        guard enabled, marked.insert(step).inserted else { return }
        print("launch \(step) \(Date.now.timeIntervalSince1970)")
        fflush(stdout)
    }
}

enum AppLog {
    static func write(_ line: String, to name: String) {
        // Test runs leave the user's logs alone: the line goes in their output.
        guard !Store.isOverridden else { return print("  log \(name): \(line)") }
        let directory = URL.libraryDirectory.appending(path: "Logs/HQ", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: name)
        let entry = Data("\(Date.now.formatted(.iso8601)) \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: entry)
        } else {
            try? entry.write(to: file)
        }
    }
}
