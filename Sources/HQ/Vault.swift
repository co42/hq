import CoreServices
import Foundation
import HQKit

/// HQ's folder in the Obsidian vault (PLAN.md §5): `hq/tasks/T-<n>.md` and any note under
/// `hq/files/`. The notes are the truth; hq writes only the front matter keys it owns.
nonisolated struct Vault: Sendable {
    /// `<vault>/hq`.
    let root: URL
    var tasksDirectory: URL { root.appending(path: "tasks", directoryHint: .isDirectory) }
    var filesDirectory: URL { root.appending(path: "files", directoryHint: .isDirectory) }

    init(vault: URL) {
        root = vault.resolvingSymlinksInPath().appending(path: "hq", directoryHint: .isDirectory)
    }

    /// Parsed notes by path, kept between scans so only changed files are read again.
    struct Cache: Sendable {
        var tasks: [String: (Date, TaskItem)] = [:]
        var files: [String: (Date, FileItem)] = [:]
    }

    // MARK: Reading

    /// Every task and file. Off the main thread: an iCloud file that isn't downloaded yet blocks.
    /// A task note that can't be read (still downloading, or caught empty mid-write) keeps its last read, uncached,
    /// and is named in `unreadable` so the caller reads it again.
    func scan(_ cache: Cache) -> (tasks: [TaskItem], files: [FileItem], cache: Cache, unreadable: [String]) {
        var next = Cache()
        var tasks: [TaskItem] = []
        var files: [FileItem] = []
        var unreadable: [String] = []
        for url in Self.notes(in: tasksDirectory, recursive: false) {
            let modified = Self.modified(url)
            if let cached = cache.tasks[url.path], cached.0 == modified {
                tasks.append(cached.1)
                next.tasks[url.path] = cached
            } else if let item = Self.task(at: url, modified: modified) {
                tasks.append(item)
                next.tasks[url.path] = (modified, item)
            } else if Self.taskNumber(url) != nil {
                unreadable.append(url.lastPathComponent)
                if let cached = cache.tasks[url.path] {
                    tasks.append(cached.1)
                    next.tasks[url.path] = cached
                }
            }
        }
        for url in Self.notes(in: filesDirectory, recursive: true) {
            let modified = Self.modified(url)
            let item = cache.files[url.path].flatMap { $0.0 == modified ? $0.1 : nil } ?? Self.file(at: url, in: filesDirectory, modified: modified)
            files.append(item)
            next.files[url.path] = (modified, item)
        }
        return (tasks, files, next, unreadable)
    }

    /// 12 for `T-12.md`.
    static func taskNumber(_ url: URL) -> Int? {
        let name = url.deletingPathExtension().lastPathComponent
        return name.hasPrefix("T-") ? Int(name.dropFirst(2)) : nil
    }

    /// Nil for a note that isn't a task, or that can't be read now: HQ never writes an empty task note.
    static func task(at url: URL, modified: Date) -> TaskItem? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let number = taskNumber(url), let text = try? String(contentsOf: url, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
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
                        related: note.list("related").compactMap(TaskItem.key).filter { $0 != number }, sessions: note.list("sessions"),
                        created: note.string("created").flatMap(NoteDate.parse) ?? modified, modified: modified,
                        body: note.body.trimmingCharacters(in: .newlines), path: url.path)
    }

    static func file(at url: URL, in directory: URL, modified: Date) -> FileItem {
        let relative = String(url.path.dropFirst(directory.path.count + 1))
        let note = FrontMatter((try? String(contentsOf: url, encoding: .utf8)) ?? "")
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

    /// Writes hq's keys of a task, and its description. Other keys keep their text.
    func save(_ task: TaskItem) throws {
        guard let path = task.path else { return }
        var note = FrontMatter((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
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
        if !task.sessions.isEmpty || note.has("sessions") { note.set("sessions", list: task.sessions) }
        if !note.has("created") { note.set("created", Self.dayString(task.created)) }
        note.body = task.body.isEmpty ? "" : task.body + "\n"
        try write(note, to: URL(fileURLWithPath: path))
    }

    /// A key set while it has a value, removed when it has none.
    private func optional(_ note: inout FrontMatter, _ key: String, _ value: String?) {
        if let value, !value.isEmpty { note.set(key, value) } else if note.has(key) { note.set(key, nil) }
    }

    /// A new task note, `T-<highest + 1>.md`.
    func create(_ task: TaskItem) throws -> TaskItem {
        try FileManager.default.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        let numbers = Self.notes(in: tasksDirectory, recursive: false).compactMap { Int($0.deletingPathExtension().lastPathComponent.dropFirst(2)) }
        var item = task
        item.id = (numbers.max() ?? 0) + 1
        item.path = tasksDirectory.appending(path: "T-\(item.id).md").path
        try save(item)
        return item
    }

    /// Writes hq's keys of a file note: its title, status, sessions, tasks, project, tags and pin.
    func save(_ file: FileItem) throws {
        guard let path = file.path else { return }
        var note = FrontMatter((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
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
        var note = FrontMatter((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
        note.body = body
        try write(note, to: URL(fileURLWithPath: path))
    }

    // MARK: Migration

    /// Notes still on the board's statuses (TaskMigration), by path.
    func notesToMigrate() -> [URL] {
        Self.notes(in: tasksDirectory, recursive: false).filter { url in
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return !TaskMigration.plan(FrontMatter(text), modified: Self.modified(url)).isEmpty
        }
    }

    /// Zips `hq/tasks` into `backups`, then writes the migrated keys. Nothing is written unless the backup exists.
    func migrate(backups: URL) throws -> Int {
        let notes = notesToMigrate()
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
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            guard let migrated = TaskMigration.apply(text, modified: Self.modified(url)) else { continue }
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
