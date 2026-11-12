import CoreServices
import Foundation
import HQKit

/// HQ's folder in the Obsidian vault (PLAN.md §5): `hq/tasks/T-<n>.md`, any note under
/// `hq/files/` and the roles, `hq/roles/<Name>.md`. The notes are the truth; hq writes only the front matter keys it owns.
nonisolated struct Vault: Sendable {
    /// `<vault>/hq`.
    let root: URL
    var tasksDirectory: URL { root.appending(path: "tasks", directoryHint: .isDirectory) }
    var filesDirectory: URL { root.appending(path: "files", directoryHint: .isDirectory) }
    var rolesDirectory: URL { root.appending(path: "roles", directoryHint: .isDirectory) }

    init(vault: URL) {
        root = vault.resolvingSymlinksInPath().appending(path: "hq", directoryHint: .isDirectory)
    }

    /// Parsed notes by path, kept between scans so only changed files are read again.
    struct Cache: Sendable {
        var tasks: [String: (Date, TaskItem)] = [:]
        var files: [String: (Date, FileItem)] = [:]
        var roles: [String: (Date, RoleItem)] = [:]
        /// Evicted notes already asked of iCloud.
        var asked: Set<String> = []
        /// Board notes already migrated, or tried: each once a launch.
        var migrated: Set<String> = []
    }

    /// What a scan read. `unreadable`: notes caught empty or mid-write; `evicted`: notes still in iCloud, downloading.
    /// Both keep their last read. `migrate`: task notes still on the board's statuses.
    struct Scan: Sendable {
        var tasks: [TaskItem] = []
        var files: [FileItem] = []
        var roles: [RoleItem] = []
        var cache = Cache()
        var unreadable: [String] = []
        var evicted: [String] = []
        var migrate: [URL] = []
    }

    // MARK: Reading

    /// HQ_SLOW_NOTES=<seconds>, in test copies only: each note read waits that long, as an evicted note's download.
    private static let slowReads: Double? = ProcessInfo.processInfo.environment["APP_STORE"].flatMap { $0.isEmpty ? nil : ProcessInfo.processInfo.environment["HQ_SLOW_NOTES"] }.flatMap(Double.init)

    /// A note's text, nil when it can't be read.
    static func read(_ url: URL) -> String? {
        if let slowReads { Thread.sleep(forTimeInterval: slowReads) }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Whether iCloud evicted the note: reading it would wait for its download.
    static func isEvicted(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_flags & UInt32(SF_DATALESS) != 0
    }

    /// Every task and file. Off the main thread. An evicted note isn't read: iCloud is asked for all of them at once, and
    /// a later scan reads each as it arrives. A note that can't be read (evicted, or caught empty mid-write) keeps its
    /// last read, uncached. A vault that can't be listed (iCloud signed out, access revoked) throws: it isn't an empty one.
    func scan(_ cache: Cache) throws -> Scan {
        let vault = root.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: vault.path) else { throw Unreadable.folder(vault.path) }
        for folder in [tasksDirectory, filesDirectory] where FileManager.default.fileExists(atPath: folder.path) {
            do { _ = try FileManager.default.contentsOfDirectory(atPath: folder.path) } catch { throw Unreadable.folder(folder.path) }
        }
        var scan = Scan()
        scan.cache.asked = cache.asked
        scan.cache.migrated = cache.migrated
        var evicted: Set<String> = []
        /// The note's text. Nil while iCloud has it (asked for once) or it can't be read, named in `evicted` or `unreadable`.
        func text(_ url: URL) -> String? {
            if Self.isEvicted(url) {
                evicted.insert(url.path)
                scan.evicted.append(url.lastPathComponent)
                if scan.cache.asked.insert(url.path).inserted { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
                return nil
            }
            guard let text = Self.read(url) else {
                scan.unreadable.append(url.lastPathComponent)
                return nil
            }
            return text
        }
        // A note that can't be read now keeps its last read.
        for url in Self.notes(in: tasksDirectory, recursive: false) where Self.taskNumber(url) != nil {
            let modified = Self.modified(url)
            var entry = cache.tasks[url.path].flatMap { $0.0 == modified ? $0 : nil }
            if entry == nil, let text = text(url) {
                if let item = Self.task(text, at: url, modified: modified) {
                    entry = (modified, item)
                    if !cache.migrated.contains(url.path), !TaskMigration.plan(FrontMatter(text), modified: modified).isEmpty { scan.migrate.append(url) }
                } else {
                    scan.unreadable.append(url.lastPathComponent)
                }
            }
            if let entry = entry ?? cache.tasks[url.path] {
                scan.tasks.append(entry.1)
                scan.cache.tasks[url.path] = entry
            }
        }
        for url in Self.notes(in: filesDirectory, recursive: true) {
            let modified = Self.modified(url)
            let entry = cache.files[url.path].flatMap { $0.0 == modified ? $0 : nil }
                ?? text(url).map { (modified, Self.file($0, at: url, in: filesDirectory, modified: modified)) } ?? cache.files[url.path]
            if let entry {
                scan.files.append(entry.1)
                scan.cache.files[url.path] = entry
            }
        }
        for url in Self.notes(in: rolesDirectory, recursive: false) {
            let modified = Self.modified(url)
            let entry = cache.roles[url.path].flatMap { $0.0 == modified ? $0 : nil }
                ?? text(url).map { (modified, Self.role($0, at: url, modified: modified)) } ?? cache.roles[url.path]
            if let entry {
                scan.roles.append(entry.1)
                scan.cache.roles[url.path] = entry
            }
        }
        // Asked again once it's back, should iCloud evict it again.
        scan.cache.asked.formIntersection(evicted)
        return scan
    }

    /// A scan that first moves the board's notes to the cockpit's lists (PLAN.md §5), after a backup: each note once.
    func scanMigrating(_ cache: Cache, backups: URL) throws -> Scan {
        let first = try scan(cache)
        guard !first.migrate.isEmpty else { return first }
        var cache = first.cache
        cache.migrated.formUnion(first.migrate.map(\.path))
        do {
            let count = try migrate(first.migrate, backups: backups)
            FileHandle.standardError.write(Data("HQ: moved \(count) task notes to the cockpit's lists\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("HQ: \(error.localizedDescription)\n".utf8))
        }
        return try scan(cache)
    }

    /// A role note: its name is the note's, `color` and `line` in the front matter, the text in the body. Nil while it
    /// can't be read: the scan keeps its last read.
    static func role(at url: URL, modified: Date) -> RoleItem? {
        read(url).map { role($0, at: url, modified: modified) }
    }

    static func role(_ text: String, at url: URL, modified: Date) -> RoleItem {
        let note = FrontMatter(text)
        let name = url.deletingPathExtension().lastPathComponent
        return RoleItem(name: name, color: note.string("color").flatMap { LabelColor(rawValue: $0.lowercased()) } ?? LabelColor.automatic(name),
                        line: note.string("line") ?? "", text: note.body.trimmingCharacters(in: .whitespacesAndNewlines),
                        builtin: RoleItem.defaults.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame },
                        modified: modified, path: url.path)
    }

    /// 12 for `T-12.md`.
    static func taskNumber(_ url: URL) -> Int? {
        let name = url.deletingPathExtension().lastPathComponent
        return name.hasPrefix("T-") ? Int(name.dropFirst(2)) : nil
    }

    /// Nil for a note that isn't a task, or that can't be read now: HQ never writes an empty task note.
    static func task(at url: URL, modified: Date) -> TaskItem? {
        read(url).flatMap { task($0, at: url, modified: modified) }
    }

    static func task(_ text: String, at url: URL, modified: Date) -> TaskItem? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let number = taskNumber(url), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let note = FrontMatter(text)
        let parent = note.string("parent").flatMap(TaskItem.key)
        // Story was a status: such a note reads as a todo story.
        let story = note.string("status")?.trimmingCharacters(in: .whitespaces).lowercased() == "story"
        return TaskItem(id: number, title: note.string("title") ?? heading(note.body) ?? name,
                        status: note.string("status").flatMap(TaskStatus.init(parsing:)) ?? .todo,
                        type: note.string("type").flatMap(TaskType.init(parsing:)) ?? (story ? .story : nil),
                        project: note.string("project").flatMap { $0.isEmpty ? nil : $0 },
                        tags: tags(note), parent: parent == number ? nil : parent,
                        list: note.string("list").flatMap(TaskList.init(rawValue:)) ?? .backlog,
                        order: note.string("order").flatMap(Double.init) ?? Double(number),
                        // Review was a status: such a note reads as doing, its reason kept until the center has it.
                        review: note.string("status")?.trimmingCharacters(in: .whitespaces).lowercased() == "review" ? note.string("review") ?? "" : nil,
                        reviewBy: note.string("review_by"), reviewAt: note.string("review_at").flatMap(NoteDate.parse),
                        done: note.string("done").flatMap(NoteDate.parse),
                        links: note.list("links").compactMap(URL.init(string:)),
                        related: note.list("related").compactMap(TaskItem.key).filter { $0 != number },
                        blocked: note.string("blocked") == "true", blockedReason: note.string("blocked_reason").flatMap { $0.isEmpty ? nil : $0 },
                        blockedBy: note.list("blocked_by").compactMap(TaskItem.key).filter { $0 != number },
                        after: note.list("after").compactMap(TaskItem.key).filter { $0 != number }, sessions: note.list("sessions"),
                        created: note.string("created").flatMap(NoteDate.parse) ?? modified, modified: modified,
                        body: note.body.trimmingCharacters(in: .newlines), path: url.path)
    }

    static func file(_ text: String, at url: URL, in directory: URL, modified: Date) -> FileItem {
        let relative = String(url.path.dropFirst(directory.path.count + 1))
        let note = FrontMatter(text)
        let name = url.deletingPathExtension().lastPathComponent
        // The user's convention: "2026-11-03 - Title.md".
        let dated = name.count > 13 && day(String(name.prefix(10))) != nil && name.dropFirst(10).hasPrefix(" - ")
        return FileItem(id: relative, title: note.string("title") ?? (dated ? String(name.dropFirst(13)) : name),
                        date: note.string("date").flatMap(day) ?? (dated ? day(String(name.prefix(10))) : nil) ?? modified,
                        modified: modified, status: note.string("status"), sessions: note.list("sessions"),
                        tasks: note.list("tasks").compactMap(TaskItem.key),
                        project: note.string("project").flatMap { $0.isEmpty ? nil : $0 }, tags: tags(note),
                        pinned: note.string("pinned") == "true", path: url.path)
    }

    /// A note's text, for the editor.
    static func body(at path: String) -> String {
        FrontMatter((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").body
    }

    // MARK: Writing

    /// A note HQ can't read is never written over: it would take it for an empty one.
    enum Unreadable: LocalizedError {
        case note(String), folder(String)

        var errorDescription: String? {
            switch self {
            case .note(let path): "couldn't read \((path as NSString).lastPathComponent), so it wasn't written over"
            case .folder(let path): "couldn't list \(path)"
            }
        }
    }

    /// What's on disk of a note HQ is about to write: nothing for a new one. One that exists but can't be read throws, and
    /// so does an empty task note (still downloading, caught mid-write): a task note is never empty.
    static func existing(_ path: String, emptyIsFine: Bool = false) throws -> FrontMatter {
        guard FileManager.default.fileExists(atPath: path) else { return FrontMatter("") }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8), !text.isEmpty || emptyIsFine else { throw Unreadable.note(path) }
        return FrontMatter(text)
    }

    /// Writes hq's keys of a task, and its description. Other keys keep their text.
    func save(_ task: TaskItem) throws {
        guard let path = task.path else { return }
        var note = try Self.existing(path)
        note.set("title", task.title)
        note.set("status", task.status.rawValue)
        optional(&note, "type", task.type?.rawValue)
        optional(&note, "project", task.project)
        if !task.tags.isEmpty || note.has("tags") { note.set("tags", list: task.tags) }
        optional(&note, "parent", task.parent.map { "T-\($0)" })
        // The list belongs to top-level tasks; a subtask shows in its root's.
        optional(&note, "list", task.parent == nil ? task.list.rawValue : nil)
        note.set("order", Self.number(task.order))
        // Review was a status: its keys go once the task is written again.
        optional(&note, "review", nil)
        optional(&note, "review_by", nil)
        optional(&note, "review_at", nil)
        optional(&note, "done", task.status == .done ? task.done.map(NoteDate.minute) : nil)
        if !task.links.isEmpty || note.has("links") { note.set("links", list: task.links.map(\.absoluteString)) }
        if !task.related.isEmpty || note.has("related") { note.set("related", list: task.related.map { "T-\($0)" }) }
        note.set("blocked", flag: task.blocked)
        optional(&note, "blocked_reason", task.blocked ? task.blockedReason : nil)
        keys(&note, "blocked_by", task.blockedBy)
        keys(&note, "after", task.after)
        if !task.sessions.isEmpty || note.has("sessions") { note.set("sessions", list: task.sessions) }
        if !note.has("created") { note.set("created", Self.dayString(task.created)) }
        note.body = task.body.isEmpty ? "" : task.body + "\n"
        try write(note, to: URL(fileURLWithPath: path))
    }

    /// A list of task keys, set while it has one, removed when it's empty.
    private func keys(_ note: inout FrontMatter, _ key: String, _ ids: [Int]) {
        if !ids.isEmpty { note.set(key, list: ids.map { "T-\($0)" }) } else if note.has(key) { note.set(key, nil) }
    }

    /// A key set while it has a value, removed when it has none.
    private func optional(_ note: inout FrontMatter, _ key: String, _ value: String?) {
        if let value, !value.isEmpty { note.set(key, value) } else if note.has(key) { note.set(key, nil) }
    }

    /// A new task note, `T-<highest + 1>.md`, or the task's own id when higher: one a deleted task's links still name isn't
    /// given again (2026-11-10).
    func create(_ task: TaskItem) throws -> TaskItem {
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        let numbers = Self.notes(in: tasksDirectory, recursive: false).compactMap { Int($0.deletingPathExtension().lastPathComponent.dropFirst(2)) }
        var item = task
        item.id = max((numbers.max() ?? 0) + 1, task.id)
        item.path = tasksDirectory.appending(path: "T-\(item.id).md").path
        try save(item)
        return item
    }

    /// Writes hq's keys of a file note: its title, status, sessions, tasks, project, tags and pin.
    func save(_ file: FileItem) throws {
        guard let path = file.path else { return }
        var note = try Self.existing(path, emptyIsFine: true)
        note.set("title", file.title)
        if !note.has("date") { note.set("date", Self.dayString(file.date)) }
        if let status = file.status { note.set("status", status) }
        if !file.sessions.isEmpty || note.has("sessions") { note.set("sessions", list: file.sessions) }
        if !file.tasks.isEmpty || note.has("tasks") { note.set("tasks", list: file.tasks.map { "T-\($0)" }) }
        optional(&note, "project", file.project)
        if !file.tags.isEmpty || note.has("tags") { note.set("tags", list: file.tags) }
        if file.pinned || note.has("pinned") { note.set("pinned", flag: file.pinned) }
        try write(note, to: URL(fileURLWithPath: path))
    }

    /// A new note, named as the user names them: "2026-11-03 - Title.md".
    func create(_ file: FileItem, body: String) throws -> FileItem {
        try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        let safe = file.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: " -")
        var name = "\(Self.dayString(file.date)) - \(safe).md"
        var n = 2
        while FileManager.default.fileExists(atPath: filesDirectory.appending(path: name).path) {
            name = "\(Self.dayString(file.date)) - \(safe) \(n).md"
            n += 1
        }
        var item = file
        item.id = name
        item.path = filesDirectory.appending(path: name).path
        try write(FrontMatter(lines: [], body: body.isEmpty ? "# \(file.title)\n" : body), to: URL(fileURLWithPath: item.path!))
        try save(item)
        return item
    }

    /// The body of a note, keeping its front matter.
    func saveBody(_ body: String, at path: String) throws {
        var note = try Self.existing(path, emptyIsFine: true)
        note.body = body
        try write(note, to: URL(fileURLWithPath: path))
    }

    /// Writes hq's keys of a role, `color` and `line`, and its text. Other keys keep their text.
    func save(_ role: RoleItem) throws {
        guard let path = role.path else { return }
        var note = try Self.existing(path, emptyIsFine: true)
        note.set("color", role.color.rawValue)
        optional(&note, "line", role.line)
        note.body = role.text.isEmpty ? "" : role.text + "\n"
        try write(note, to: URL(fileURLWithPath: path))
    }

    /// A new role note, `<Name>.md`, never over one that has the name.
    func create(_ role: RoleItem) throws -> RoleItem {
        try FileManager.default.createDirectory(at: rolesDirectory, withIntermediateDirectories: true)
        var item = role
        let path = rolesDirectory.appending(path: "\(role.name).md").path
        guard !FileManager.default.fileExists(atPath: path) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSLocalizedDescriptionKey: "a role note \(role.name).md is there already"])
        }
        item.path = path
        try save(item)
        return item
    }

    /// A renamed role: its note moves to `<new name>.md`, then takes the role's keys.
    func rename(_ role: RoleItem, from path: String) throws -> RoleItem {
        let target = rolesDirectory.appending(path: "\(role.name).md").path
        if target != path {
            if target.lowercased() == path.lowercased() {
                // A change of case alone: through a name of its own, as the disk ignores case.
                let step = path + ".renaming"
                try FileManager.default.moveItem(atPath: path, toPath: step)
                try FileManager.default.moveItem(atPath: step, toPath: target)
            } else {
                try FileManager.default.moveItem(atPath: path, toPath: target)
            }
        }
        var item = role
        item.path = target
        try save(item)
        return item
    }

    /// Whether the roles folder has a note by this name, or iCloud is still bringing one (`.<Name>.md.icloud`).
    func hasRoleNote(_ name: String) -> Bool {
        let names = Set(((try? FileManager.default.contentsOfDirectory(atPath: rolesDirectory.path)) ?? []).map { $0.lowercased() })
        return names.contains("\(name).md".lowercased()) || names.contains(".\(name).md.icloud".lowercased())
    }

    // MARK: Migration

    /// Zips `hq/tasks` into `backups`, then writes the migrated keys of these notes. Nothing is written unless the
    /// backup exists, nor over a note that can't be read.
    func migrate(_ notes: [URL], backups: URL) throws -> Int {
        guard !notes.isEmpty else { return 0 }
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        var zip = backups.appending(path: "tasks-\(NoteDate.minute(.now).replacingOccurrences(of: ":", with: "")).zip")
        var n = 2
        while FileManager.default.fileExists(atPath: zip.path) {
            zip = backups.appending(path: "tasks-\(NoteDate.minute(.now).replacingOccurrences(of: ":", with: ""))-\(n).zip")
            n += 1
        }
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", tasksDirectory.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0, FileManager.default.fileExists(atPath: zip.path) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "the tasks backup failed; nothing was migrated"])
        }
        var count = 0
        for url in notes {
            guard let text = Self.read(url), !text.isEmpty, let migrated = TaskMigration.apply(text, modified: Self.modified(url)) else { continue }
            try Data(migrated.utf8).write(to: url, options: .atomic)
            count += 1
        }
        return count
    }

    private func write(_ note: FrontMatter, to url: URL) throws {
        let text = note.text
        if (try? String(contentsOf: url, encoding: .utf8)) == text { return }
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    // MARK: Helpers

    static func notes(in directory: URL, recursive: Bool) -> [URL] {
        let files = FileManager.default
        guard recursive else {
            return ((try? files.contentsOfDirectory(atPath: directory.path)) ?? [])
                .map { directory.appending(path: $0) }
                .filter { $0.pathExtension == "md" && !isConflictCopy($0) }
        }
        // Relative paths, joined to `directory`: the enumerator's URLs can spell it another way (/private/tmp).
        let walker = files.enumerator(atPath: directory.path)
        return (walker?.allObjects as? [String] ?? [])
            .filter { !$0.split(separator: "/").contains { $0.hasPrefix(".") } }
            .map { directory.appending(path: $0) }
            .filter { $0.pathExtension == "md" && !isConflictCopy($0) }
    }

    /// iCloud's conflict copies ("T-12 2.md") are never indexed twice.
    private static func isConflictCopy(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent
        return name.range(of: #"^T-\d+ \d+$"#, options: .regularExpression) != nil
    }

    static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func tags(_ note: FrontMatter) -> [String] {
        var seen = Set<String>()
        return note.list("tags").map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func heading(_ body: String) -> String? {
        body.components(separatedBy: "\n").first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)) }
    }

    static func day(_ text: String) -> Date? { NoteDate.parse(String(text.prefix(10))) }

    static func dayString(_ date: Date) -> String { NoteDate.day(date) }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// Calls back on the main queue when anything under a directory changes (FSEvents).
final class VaultWatcher {
    private var stream: FSEventStreamRef?
    private let changed: () -> Void

    init?(_ directory: URL, changed: @escaping () -> Void) {
        self.changed = changed
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.changed() }
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, [directory.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    isolated deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
