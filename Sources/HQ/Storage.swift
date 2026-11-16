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
    var faceID: String?
    var parentID: String?
    var role: String?

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
        set(\.faceID, item.faceID)
        set(\.parentID, item.parent)
        set(\.role, item.role)
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
                           faceSalt: faceSalt, links: links, faceID: faceID, parent: parentID, role: role)
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

/// Unused: kept so the store opens without a migration.
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

/// HQ's store (PLAN.md §2): what has no file of its own. The app is its only writer.
final class Storage {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(url: URL) throws {
        container = try ModelContainer(for: SessionRecord.self, ArtifactRecord.self, SeenRecord.self, ChangeRecord.self,
                                       configurations: ModelConfiguration(url: url))
    }

    /// A test run's switch: every read of the store fails, as one did on 2026-11-13.
    static var failReads = false
    /// The kinds of record read whole at launch: only those may lose rows their list no longer has.
    private var loaded: Set<ObjectIdentifier> = []

    func sessions() -> [SessionItem] {
        load(key: \SessionRecord.sessionID) { $0.lastActivity > $1.lastActivity }.map(\.item)
    }

    func save(_ sessions: [SessionItem]) {
        sync(sessions, key: \.sessionID, id: \.id, make: SessionRecord.init) { $0.update($1) }
    }

    func artifacts() -> [ArtifactItem] {
        load(key: \ArtifactRecord.url) { $0.published > $1.published }.compactMap(\.item)
    }

    func save(_ artifacts: [ArtifactItem]) {
        sync(artifacts, key: \.url, id: \.id.absoluteString, make: ArtifactRecord.init) { $0.update($1) }
    }

    func seen() -> [String: Date] {
        Dictionary(uniqueKeysWithValues: load(key: \SeenRecord.key) { $0.seenAt > $1.seenAt }.map { ($0.key, $0.seenAt) })
    }

    func save(seen: [String: Date]) {
        sync(seen.map { Seen(key: $0.key, date: $0.value) }, key: \.key, id: \.key,
             make: { SeenRecord(key: $0.key, seenAt: $0.date) }) { if $0.seenAt != $1.date { $0.seenAt = $1.date } }
    }

    /// SwiftData's change history, which HQ never reads: what's older than an hour goes, in the background, 10 s after
    /// launch and every 6 hours.
    func pruneHistoryRegularly() {
        let container = container
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(10))
            while !Task.isCancelled {
                let failure = Self.pruneHistory(container, before: .now.addingTimeInterval(-3600))
                await MainActor.run {
                    LaunchLog.mark("pruned")
                    if let failure { AppLog.write("couldn't prune the store's history: \(failure)", to: "store.log") }
                }
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    /// Deletes the history before `cutoff`; what went wrong, if anything.
    nonisolated static func pruneHistory(_ container: ModelContainer, before cutoff: Date) -> String? {
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>()
        descriptor.predicate = #Predicate { $0.timestamp < cutoff }
        do {
            try ModelContext(container).deleteHistory(descriptor)
            return nil
        } catch {
            return "\(error)"
        }
    }

    /// How many history transactions the store holds (the self-test).
    func historyCount() -> Int {
        (try? context.fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>()).count) ?? -1
    }

    /// How many rows of a kind the store holds (the self-test counts duplicates).
    func rows<Record: PersistentModel>(_ type: Record.Type) -> Int {
        (try? context.fetchCount(FetchDescriptor<Record>())) ?? -1
    }

    private struct Seen {
        let key: String
        let date: Date
    }

    /// Every record of a kind, one per key: a key's other rows go, the newest kept.
    private func load<Record: PersistentModel>(key: KeyPath<Record, String>, newer: (Record, Record) -> Bool) -> [Record] {
        guard let records = read(Record.self) else { return [] }
        loaded.insert(ObjectIdentifier(Record.self))
        var kept: [String: Record] = [:]
        var extra = 0
        for record in records {
            let id = record[keyPath: key]
            guard let other = kept[id] else { kept[id] = record; continue }
            extra += 1
            if newer(record, other) { kept[id] = record; context.delete(other) } else { context.delete(record) }
        }
        guard extra > 0 else { return records }
        AppLog.write("removed \(extra) duplicate \(Record.self) rows at launch, \(kept.count) kept", to: "store.log")
        commit(String(describing: Record.self))
        return records.filter { kept[$0[keyPath: key]] === $0 }
    }

    /// Changed records update, new ones insert, missing ones go, and so does a key's second row. Saves only when
    /// something changed. A failed read writes nothing: every item would be stored again.
    private func sync<Item, Record: PersistentModel>(_ items: [Item], key: KeyPath<Record, String>, id: KeyPath<Item, String>,
                                                     make: (Item) -> Record, update: (Record, Item) -> Void) {
        guard let records = read(Record.self) else { return }
        var byID: [String: Record] = [:]
        var extra = 0
        for record in records {
            if byID[record[keyPath: key]] == nil { byID[record[keyPath: key]] = record } else { context.delete(record); extra += 1 }
        }
        if extra > 0 { AppLog.write("removed \(extra) duplicate \(Record.self) rows on save", to: "store.log") }
        var written: Set<String> = []
        for item in items where written.insert(item[keyPath: id]).inserted {
            if let record = byID.removeValue(forKey: item[keyPath: id]) {
                update(record, item)
            } else {
                context.insert(make(item))
            }
        }
        if loaded.contains(ObjectIdentifier(Record.self)) {
            for record in byID.values { context.delete(record) }
        }
        commit(String(describing: Record.self))
    }

    private func read<Record: PersistentModel>(_ type: Record.Type) -> [Record]? {
        do {
            if Self.failReads { throw CocoaError(.fileReadUnknown) }
            return try context.fetch(FetchDescriptor<Record>())
        } catch {
            AppLog.write("couldn't read \(Record.self): \(error)", to: "store.log")
            return nil
        }
    }

    private func commit(_ what: String) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            // Unsaved inserts left in the context would be saved again with the next change.
            context.rollback()
            AppLog.write("couldn't save \(what): \(error)", to: "store.log")
        }
    }
}

/// Lines in ~/Library/Logs/HQ/<name>, to see afterwards what happened in the user's HQ. Never in a test run.
/// HQ_LAUNCH_LOG=1: when each step of the launch happened, as `launch <step> <seconds since 1970>` (tools/launch.sh).
enum LaunchLog {
    private static let enabled = ProcessInfo.processInfo.environment["HQ_LAUNCH_LOG"] == "1"
    /// When each step first happened, since the process started (a UI test reads them).
    private(set) static var times: [String: TimeInterval] = [:]

    static func mark(_ step: String) {
        guard times[step] == nil else { return }
        times[step] = Date.now.timeIntervalSince(started)
        guard enabled else { return }
        print("launch \(step) \(Date.now.timeIntervalSince1970)")
        fflush(stdout)
    }

    /// When the process started, as the kernel has it.
    static let started: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0 else { return .now }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }()
}

enum AppLog {
    /// Lines a check makes on purpose, by a part of their text: printed apart from the defects a run finds.
    static var expected: [String] = []
    /// The lines written to each log by a test run, those expected aside.
    static var written: [String: Int] = [:]

    static func write(_ line: String, to name: String) {
        // Test runs leave the user's logs alone: the line goes in their output.
        if Store.isOverridden, let index = expected.firstIndex(where: line.contains) {
            expected.remove(at: index)
            return print("  expected log \(name): \(line)")
        }
        guard !Store.isOverridden else {
            written[name, default: 0] += 1
            return print("  log \(name): \(line)")
        }
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
