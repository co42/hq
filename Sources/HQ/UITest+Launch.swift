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
    }
}
