import AppKit
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
    /// The highest key archived, kept apart from the index so a new key never reads it.
    var archivedHighestKey: Int {
        get { Prefs.defaults.integer(forKey: "archive.highestKey") }
        set { Prefs.defaults.set(newValue, forKey: "archive.highestKey") }
    }

    /// Archive (⌃⌘A): top-level tasks with everything under them leave the list now; the note writer moves their notes
    /// to the Archive's folder after any save queued before. One Undo step, which brings them back in their place.
    func archive(_ ids: [Int]) {
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
        registerUndo("Archive") { model in for story in stories { model.unarchive(story, inPlace: true, select: story == selected) } }
    }

    /// Unarchive: a story and its tasks come back from the Archive's folder, read in the background. In its old place
    /// from Undo, else first in the list, selected, the toggle that would hide it turned on (T-471). One Undo step.
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
            if !inPlace, let place = taskTree.placeNew(in: .top, at: 0)?.0 { top.order = place.order }
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

    /// The stories done with every task under them done: what Archive All Done takes (T-537).
    var doneStories: [Int] {
        let tree = taskTree
        return TaskArchive.allDone(roots: tree.top(), subtree: { tree.subtree(of: $0) }, status: { self.task($0)?.status })
    }

    /// Archive All Done… (Task menu, the Archive button's menu): asks, naming how many, then archives them as one Undo step.
    func archiveAllDone() {
        let stories = doneStories
        guard !stories.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Done Story to Archive"
            alert.informativeText = "A story goes once it's done with every task under it done."
            if let window = window.map({ $0.attachedSheet ?? $0 }) { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return
        }
        let count = stories.count == 1 ? "1 done story" : "\(stories.count) done stories"
        if Store.isOverridden {
            ghosttyLog.append("confirm archive all done, \(stories.count)")
            return archive(stories)
        }
        let alert = NSAlert()
        alert.messageText = "Archive \(count)?"
        alert.informativeText = "Each leaves Tasks for the Archive with every task under it. Undo (⌘Z) brings them back."
        alert.addButton(withTitle: stories.count == 1 ? "Archive 1 Story" : "Archive \(stories.count) Stories")
        alert.addButton(withTitle: "Cancel")
        let finish = { (response: NSApplication.ModalResponse) in
            if response == .alertFirstButtonReturn { self.archive(stories) }
        }
        if let window = window.map({ $0.attachedSheet ?? $0 }) {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }
}

/// The Archive as the window shows it (T-471): the index read in the background when it opens, folded once for its
/// search, let go when the window closes.
struct ArchiveShown {
    var index: ArchiveIndex
    var searcher: ArchiveIndex.Searcher
    /// Archived notes read for an archived task's window, by key.
    var notes: [Int: TaskItem] = [:]

    static var empty: ArchiveShown { ArchiveShown(index: ArchiveIndex(), searcher: ArchiveIndex.Searcher(ArchiveIndex())) }
}

extension AppModel {
    /// Go › Archive (⇧⌘A), the Tasks header's button, Quick Open's last row: the Archive's window, its search typed.
    func openArchive(query: String = "") {
        archiveQuery = query
        showWindow()
        open(.archive, push: modal != nil && modal != .archive)
        loadArchive()
    }

    /// The index, read off the main thread once the window opens; the window says it's loading meanwhile.
    func loadArchive() {
        guard archiveShown == nil, !archiveLoading else { return }
        archiveLoading = true
        let store = ArchiveStore.shared
        store.hold()
        archiveHeld = true
        Task {
            // The search's folded text is made there too: with 10,000 tasks it's the slow part.
            let (index, searcher) = await Task.detached(priority: .userInitiated) { () -> (ArchiveIndex, ArchiveIndex.Searcher) in
                NoteWriter.queue.sync {}
                let index = store.index()
                return (index, ArchiveIndex.Searcher(index))
            }.value
            archiveLoading = false
            guard archiveHeld else { return }
            archiveShown = ArchiveShown(index: index, searcher: searcher)
            archivedHighestKey = max(archivedHighestKey, index.highestKey)
        }
    }

    /// The index again, after an Unarchive or a Delete changed it: what the window shows follows.
    func reloadArchive() {
        guard archiveHeld else { return }
        let store = ArchiveStore.shared
        Task {
            let (index, searcher) = await Task.detached(priority: .userInitiated) { () -> (ArchiveIndex, ArchiveIndex.Searcher) in
                NoteWriter.queue.sync {}
                let index = store.index()
                return (index, ArchiveIndex.Searcher(index))
            }.value
            guard archiveHeld else { return }
            let notes = archiveShown?.notes ?? [:]
            archiveShown = ArchiveShown(index: index, searcher: searcher, notes: notes)
        }
    }

    /// An archived task's note, for its window: read in the background, nil until it's in.
    func loadArchivedNote(_ id: Int) {
        guard archiveShown?.notes[id] == nil, let vault else { return }
        Task {
            let read = await Task.detached(priority: .userInitiated) { vault.readArchived([id]) }.value
            if let item = read.first { archiveShown?.notes[id] = item }
        }
    }

    /// The window and the archived tasks over it closed: the index goes from memory.
    func archiveFollowsModal() {
        let routes = [modal].compactMap(\.self) + modalStack
        let open = routes.contains { route in
            switch route {
            case .archive, .archivedTask: true
            default: false
            }
        }
        guard !open, archiveHeld else { return }
        archiveHeld = false
        archiveShown = nil
        ArchiveStore.shared.release()
    }

    /// ⌃⌘A outside the outline: what Task › Archive says, Unarchive on the Archive's story or Archive on the selected stories;
    /// nothing else.
    func archiveFromKeys() {
        let menu = MenuState.shared
        if let story = menu.archivedStory {
            unarchiveFromWindow(story)
        } else if menu.taskIsTop {
            archive(menu.tasks)
        }
    }

    /// Unarchive in the Archive (its card, Task › Unarchive, an archived task's window): the story leaves the results, the
    /// next one found takes the selection, its windows close; it comes back first in Tasks, selected once the Archive closes.
    func unarchiveFromWindow(_ story: Int) {
        let ids = Set(archiveShown?.index.entries.filter { $0.root == story }.map(\.id) ?? [story])
        if archiveSelection == story, let shown = archiveShown {
            let found = shown.searcher.search(archiveQuery).map(\.story.id)
            let rest = found.filter { $0 != story }
            archiveSelection = rest.isEmpty ? nil : rest[min(found.firstIndex(of: story) ?? 0, rest.count - 1)]
        }
        unarchive(story)
        // What the window shows follows at once; the writer updates the index file after the moves.
        archiveShown?.index.remove(story: story)
        archiveShown?.searcher.remove(story: story)
        leaveModal { route in if case .archivedTask(let id) = route { ids.contains(id) } else { false } }
    }

    /// Delete in the Archive: a story's notes go to the Trash, with the tasks under it; Undo brings them back archived.
    func deleteArchived(_ story: Int) {
        guard let vault, let index = archiveShown?.index ?? ArchiveStore.shared.current else { return }
        let entries = index.entries.filter { $0.root == story }
        guard !entries.isEmpty else { return }
        let trashed: [Int: URL]
        do {
            trashed = try trashAll(entries.map { ($0.id, vault.archivedURL($0.id).path) })
        } catch {
            return tellNoteStayed("T-\(story)", error, stays: "the Archive")
        }
        writeNotes([]) { ArchiveStore.shared.update { $0.remove(story: story) } }
        archiveShown?.index.remove(story: story)
        archiveShown?.searcher.remove(story: story)
        let ids = Set(entries.map(\.id))
        leaveModal { route in if case .archivedTask(let id) = route { ids.contains(id) } else { false } }
        registerUndo("Delete") { model in
            for entry in entries { model.untrash(trashed[entry.id], to: vault.archivedURL(entry.id).path) }
            model.writeNotes([]) { ArchiveStore.shared.update { $0.add(entries) } }
            model.reloadArchive()
            model.registerUndo("Delete") { $0.deleteArchived(story) }
        }
    }
}

