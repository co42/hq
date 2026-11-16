import AppKit

/// A launch on a vault whose reads are slow, as notes iCloud evicted (HQ_SLOW_NOTES): the window comes up at once, Tasks
/// and Files say they're loading, and the tasks come in once read (T-431).
extension UITest {
    static func slowVault(_ model: AppModel, _ ui: Driver) async {
        let shown = LaunchLog.times["window"] ?? .infinity
        await check("on a slow vault the window opens at once", shown < 3, String(format: "%.1f s after launch", shown))
        await check("Tasks say they're loading, never an empty list", ui.anchorFrame("tasks-loading") != nil && model.tasks.isEmpty, "\(model.tasks.count) tasks")
        await check("Files say they're loading", ui.anchorFrame("files-loading") != nil)
        let notes = Vault.notes(in: model.vault?.tasksDirectory ?? URL(fileURLWithPath: "/"), recursive: false).count
        await check("the tasks show once read", notes > 0 && model.tasks.count == notes && ui.anchorFrame("tasks-loading") == nil,
                    "\(model.tasks.count) of \(notes)", within: 30)
        await check("and Files say they're empty", ui.anchorFrame("files-loading") == nil)
        // T-486: a file's window reads its note in the background, a loading line in place of its text.
        guard let files = model.vault?.filesDirectory else { return await check("the slow vault has a files folder", false) }
        let name = "2026-11-16 - Slow note.md"
        try? "---\ntitle: Slow note\n---\n# Slow note\n\nRead slowly.\n".write(to: files.appending(path: name), atomically: true, encoding: .utf8)
        model.rescanVault()
        await check("a note added on disk shows", model.files.contains { $0.id == name }, within: 30)
        model.open(.file(name))
        await check("its window says it's loading the note", ui.anchorFrame("file-loading") != nil)
        await check("then shows the note's text", ui.anchorFrame("file-text") != nil && ui.anchorFrame("file-loading") == nil, within: 10)
        model.closeModal()
        await check("and its window closes", model.modal == nil && ui.anchorFrame("file-page") == nil)
    }
}
