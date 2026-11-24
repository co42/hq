import Foundation
import HQKit

extension SelfTest {
    /// The Archive's storage on the scratch vault (T-471): Archive and Unarchive move a story's notes there and back,
    /// keys are never given again, Archive All Done takes the stories done throughout, a lost index comes back from the notes,
    /// and `hq` reads archived tasks without changing them.
    static func archiveChecks(_ model: AppModel) async {
        guard let vault = model.vault else { return check("a vault for the Archive", false) }
        let store = ArchiveStore.shared
        func settle() async {
            model.flushNoteWrites()
            try? await Task.sleep(for: .milliseconds(300))
            model.flushNoteWrites()
        }
        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
        func note(_ url: URL) -> FrontMatter { FrontMatter((try? String(contentsOf: url, encoding: .utf8)) ?? "") }
        guard let story = model.addTask(status: .todo, title: "To archive"), let step = model.addSubtask(to: story.id, title: "Its step") else {
            return check("a story to archive", false)
        }
        model.setDescription(story.id, "Kept **as written**.")
        await settle()

        // Archive: out of the list at once, the notes moved by the writer.
        model.archive([story.id])
        check("Archive takes a story and its tasks out of the list at once", model.task(story.id) == nil && model.task(step.id) == nil)
        await settle()
        check("their notes move to the Archive's folder, the story's with the time it went",
              !exists(vault.liveURL(story.id)) && exists(vault.archivedURL(story.id)) && exists(vault.archivedURL(step.id))
                && note(vault.archivedURL(story.id)).string("archived") != nil)
        // [[T-n]] in other notes opens by the note's name, which the move keeps: it finds the note in the Archive's folder.
        let link = model.obsidianLink(named: Markdown.noteName(URL(string: "hq-note:\(story.key)")!) ?? "").flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        check("a [[T-n]] link to an archived story still opens it: by its name, which its moved note keeps",
              link?.queryItems?.first { $0.name == "file" }?.value == story.key
                && vault.archivedURL(story.id).deletingPathExtension().lastPathComponent == story.key, "\(String(describing: link))")
        let index = store.index()
        check("the index has the story and the task under it", index.entry(story.id)?.root == story.id && index.entry(step.id)?.root == story.id
              && index.highestKey >= step.id, "\(index.entries.map(\.id))")
        store.release()
        model.rescanVault()
        for _ in 0..<100 where model.vaultScanning { try? await Task.sleep(for: .milliseconds(20)) }
        check("a vault read leaves archived notes out", model.task(story.id) == nil && model.task(step.id) == nil)
        if let fresh = model.addTask(status: .todo, title: "After the Archive") {
            check("a new task never takes an archived key", fresh.id > step.id, "T-\(fresh.id)")
            model.deleteTasks([fresh.id])
        }

        // hq reads it, read only.
        let shown = agent("task show", ["task": story.key])
        check("hq task show reads an archived task, read only, with what's under it", shown["title"] as? String == "To archive"
              && (shown["flow"] as? String)?.contains("read only") == true && (shown["body"] as? String)?.contains("Kept") == true
              && (shown["subtasks"] as? [JSONObject])?.first?["id"] as? String == step.key, "\(shown)")
        let refused = agent("task edit", ["task": story.key, "title": "Changed"])
        check("a change to an archived task is refused, with the way back",
              ((refused["error"] as? JSONObject)?["message"] as? String)?.contains("is archived: hq task unarchive \(story.key)") == true, "\(refused)")
        let listed = agent("ls", ["kind": "tasks", "archived": "true"])["tasks"] as? [JSONObject] ?? []
        check("ls tasks --archived lists the archived stories", listed.contains { $0["id"] as? String == story.key }
              && !listed.contains { $0["id"] as? String == step.key }, "\(listed.map { $0["id"] ?? "" })")
        let found = agent("ls", ["kind": "tasks", "archived": "true", "search": "its step"])["tasks"] as? [JSONObject] ?? []
        check("--search finds a story by a task under it", found.first?["id"] as? String == story.key
              && (found.first?["found"] as? [JSONObject])?.first?["id"] as? String == step.key, "\(found)")
        check("a subtask can't be archived alone", (agent("task archive", ["task": step.key])["error"] as? JSONObject) != nil)

        // Unarchive: back first in the list, the archived key gone, the description as written.
        model.unarchive(story.id)
        await expect("Unarchive brings a story and its task back first in the list",
                     model.task(story.id) != nil && model.task(step.id) != nil && model.taskTree.top().first == story.id, "\(model.taskTree.top())")
        await settle()
        check("their notes come back, the archived key gone, the description as written",
              exists(vault.liveURL(story.id)) && !exists(vault.archivedURL(story.id)) && !note(vault.liveURL(story.id)).has("archived")
                && note(vault.liveURL(story.id)).body == "Kept **as written**.\n" && model.taskTree.parent(of: step.id) == story.id)
        check("the index lets it go", store.index().entry(story.id) == nil)
        store.release()

        // Undo of Archive puts it back in its place.
        let order = model.taskTree.top()
        model.archive([story.id])
        model.undoManager?.undo()
        await expect("Undo of Archive puts the story back in its place", model.taskTree.top() == order && model.task(step.id) != nil,
                     "\(model.taskTree.top()) for \(order)")
        await settle()

        // hq task archive and unarchive.
        agent("task archive", ["task": story.key])
        await settle()
        check("hq task archive archives a story", model.task(story.id) == nil && exists(vault.archivedURL(story.id)))
        agent("task unarchive", ["task": story.key])
        await expect("hq task unarchive brings it back", model.task(story.id) != nil && model.task(step.id) != nil)
        await settle()

        // Archive All Done: every story done throughout goes, as one Undo step; not one still holding an open task (T-537).
        guard let old = model.addTask(status: .done, title: "Done long ago"), let held = model.addTask(status: .done, title: "Done, a step still open"),
              let open = model.addSubtask(to: held.id, title: "Still open"), let fresh = model.addTask(status: .done, title: "Done the other day") else {
            return check("done stories", false)
        }
        model.setStatus(open.id, .todo)
        let before = model.doneStories
        model.archiveAllDone()
        check("Archive All Done takes every story done throughout, not one holding an open task",
              before.contains(old.id) && before.contains(fresh.id) && !before.contains(held.id)
              && model.task(old.id) == nil && model.task(fresh.id) == nil && model.task(held.id) != nil)
        await settle()

        // A lost index comes back from the notes, each task under its story.
        store.release()
        try? FileManager.default.removeItem(at: Store.directory.appending(path: "archive.json"))
        let rebuilt = store.index()
        check("a lost index is read back from the Archive's notes", rebuilt.entry(old.id)?.root == old.id && rebuilt.entry(fresh.id) != nil
              && exists(Store.directory.appending(path: "archive.json")), "\(rebuilt.entries.map(\.id))")
        store.release()
        model.deleteTasks([story.id, held.id])
        await settle()
    }
}
