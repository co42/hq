import Foundation
import HQKit

/// The Archive's index (T-471, PLAN.md §5): `archive.json` beside the store. Read only when the Archive opens or `hq`
/// asks, off the main thread, and kept while someone holds it; written on the note writer as stories come and go.
nonisolated final class ArchiveStore: @unchecked Sendable {
    static let shared = ArchiveStore()

    private let lock = NSLock()
    private var cached: ArchiveIndex?
    private var holds = 0
    private var file: URL?
    private var vault: Vault?
    /// Archived notes an `hq` call asked for, read with the index before the call runs.
    private var notes: [Int: TaskItem] = [:]

    /// Where the index is and which vault's Archive it indexes: set by the app as its vault starts.
    func use(file: URL, vault: Vault?) {
        lock.withLock {
            if self.file != file || self.vault?.root != vault?.root { cached = nil }
            self.file = file
            self.vault = vault
        }
    }

    /// The index in memory, if something read it: never reads the disk.
    var current: ArchiveIndex? { lock.withLock { cached } }

    /// The index, read and checked against the Archive's folder when it isn't in memory. Off the main thread.
    func index() -> ArchiveIndex {
        if let cached = current { return cached }
        let (file, vault) = lock.withLock { (self.file, self.vault) }
        var index = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(ArchiveIndex.self, from: $0) } ?? ArchiveIndex()
        if let vault {
            let entries = vault.archiveEntries(known: index.entries)
            if entries != index.entries {
                index = ArchiveIndex(entries: entries)
                save(index)
            }
        }
        lock.withLock { cached = index }
        return index
    }

    /// Changes the index and writes it. Off the main thread: the note writer runs it after the moves it follows.
    func update(_ change: (inout ArchiveIndex) -> Void) {
        var index = index()
        change(&index)
        save(index)
        lock.withLock { cached = holds > 0 ? index : nil }
    }

    private func save(_ index: ArchiveIndex) {
        guard let file = lock.withLock({ self.file }) else { return }
        try? JSONEncoder().encode(index).write(to: file, options: .atomic)
    }

    /// Keeps the index in memory: the Archive's window while it's open, an `hq` call while it runs.
    func hold() { lock.withLock { holds += 1 } }

    func release() {
        lock.withLock {
            holds = max(holds - 1, 0)
            if holds == 0 {
                cached = nil
                notes = [:]
            }
        }
    }

    /// Reads archived notes with the index, for what an `hq` call shows of them. Off the main thread.
    func prepare(notes ids: [Int]) {
        guard let vault = lock.withLock({ self.vault }) else { return }
        let read = vault.readArchived(ids)
        lock.withLock { for item in read { notes[item.id] = item } }
    }

    /// A note `prepare` read: memory only.
    func note(_ id: Int) -> TaskItem? { lock.withLock { notes[id] } }

    /// The archived note's file is there: a task that isn't in the list may be in the Archive.
    func isArchived(_ id: Int) -> Bool {
        guard let vault = lock.withLock({ self.vault }) else { return false }
        return FileManager.default.fileExists(atPath: vault.archivedURL(id).path)
    }
}

extension AppModel {
    /// Settings › General: how long a done story waits before the Archive takes it, in days (T-471).
    var archiveDelayDays: Int {
        get { TaskArchive.delayChoices.contains(archiveDelay) ? archiveDelay : TaskArchive.defaultDelay }
        set { archiveDelay = newValue }
    }

    /// The highest key archived, kept apart from the index so a new key never reads it.
    var archivedHighestKey: Int {
        get { Prefs.defaults.integer(forKey: "archive.highestKey") }
        set { Prefs.defaults.set(newValue, forKey: "archive.highestKey") }
    }

    /// Archive (⌃⌘A): top-level tasks with everything under them leave the list now; the note writer moves their notes
    /// to the Archive's folder after any save queued before. One Undo step, which brings them back in their place; none
    /// for what goes on its own.
    func archive(_ ids: [Int], auto: Bool = false) {
        guard let vault else { return }
        let tree = taskTree
        let stories = ids.filter { tree.parent(of: $0) == nil && task($0) != nil }
        guard !stories.isEmpty else { return }
        let date = Date.now
        let selected = stories.first(where: selectedTasks.contains)
        var gone = Set<Int>()
        for story in stories {
            let items = tree.subtree(of: story).compactMap { task($0) }
            guard let top = items.first else { continue }
            let under = Array(items.dropFirst())
            gone.formUnion(items.map(\.id))
            archivedHighestKey = max(archivedHighestKey, items.map(\.id).max() ?? 0)
            writeNotes(items.compactMap(\.path)) {
                let entries = try vault.archive(story: top, under: under, at: date)
                ArchiveStore.shared.update { $0.add(entries) }
            }
        }
        tasks.removeAll { gone.contains($0.id) }
        leaveModal { if case .task(let id) = $0 { gone.contains(id) } else { false } }
        if auto {
            AppLog.write("archive: \(stories.count) done \(stories.count == 1 ? "story" : "stories") went on their own: "
                         + stories.map { "T-\($0)" }.joined(separator: ", "), to: "vault.log")
        } else {
            registerUndo("Archive") { model in for story in stories { model.unarchive(story, inPlace: true, select: story == selected) } }
        }
    }

    /// Unarchive: a story and its tasks come back from the Archive's folder, read in the background. In its old place
    /// from Undo, else at the end of the list, selected, the toggle that would hide it turned on (T-471). One Undo step.
    func unarchive(_ story: Int, inPlace: Bool = false, select: Bool = true) {
        guard let vault else { return }
        registerUndo("Unarchive") { $0.archive([story]) }
        let store = ArchiveStore.shared
        store.hold()
        Task {
            let items = await Task.detached(priority: .userInitiated) { () -> [TaskItem] in
                // After the moves queued before: Undo right after Archive finds the notes in the Archive's folder.
                NoteWriter.queue.sync {}
                let ids = [story] + store.index().tasks(under: story).map(\.id)
                return vault.readArchived(ids)
            }.value
            defer { store.release() }
            guard var top = items.first(where: { $0.id == story }) else {
                AppLog.write("archive: T-\(story) isn't in the Archive's folder; nothing came back", to: "vault.log")
                return
            }
            if !inPlace, let place = taskTree.placeNew(in: .top)?.0 { top.order = place.order }
            let placed = top
            let restored = items.map { $0.id == story ? placed : $0 }
            writeNotes(restored.compactMap(\.path)) {
                for item in restored { try vault.unarchive(item.id, top: item.id == story) }
                ArchiveStore.shared.update { $0.remove(story: story) }
                if !inPlace { try vault.save(placed) }
            }
            let known = Set(tasks.map(\.id))
            tasks.append(contentsOf: restored.filter { !known.contains($0.id) })
            if !inPlace {
                if top.status == .done && !OutlineSnapshot.openBelow(self).contains(story) { showDone = true }
                if top.status == .backlog { showBacklog = true }
                folded.remove(.tasks)
            }
            if select { outlineFocus = .row(story) }
        }
    }

    /// The done stories due for the Archive, after the first full vault read and every hour: done for the delay, every
    /// task under them done. Nothing while notes are still coming from iCloud or caught mid-write.
    func archiveDue() {
        guard vault != nil, vaultRead, !vaultLoading, vaultDownloading == 0, vaultUnreadable.isEmpty else { return }
        let tree = taskTree
        let due = TaskArchive.due(roots: tree.top(), subtree: { tree.subtree(of: $0) }, status: { self.task($0)?.status },
                                  done: { id in self.task(id).map { $0.done ?? $0.modified } }, now: .now, delayDays: archiveDelayDays)
        guard !due.isEmpty else { return }
        archive(due, auto: true)
    }
}
