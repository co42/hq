import AppKit
import HQKit
import SwiftUI

/// The page's cards and grid, and the modal: keys past a card's fifth row, the modal's own selection, New File… and
/// Import Artifact… as sheets, the grid under a filtered or busy drag, a PR page a poll drops, Escape in forms over a modal,
/// ⇧⌘B on a subtask in its task's window.
extension UITest {
    static func pageFixes(_ model: AppModel, _ ui: Driver) async {
        await keysPastFive(model, ui)
        await scenario(model, ui)
        await modalSelection(model, ui)
        await scenario(model, ui)
        await fileSheets(model, ui)
        await scenario(model, ui)
        await filteredGridDrag(model, ui)
        await scenario(model, ui)
        await gridHoldsUnderDrag(model, ui)
        await scenario(model, ui)
        await prPageStays(model, ui)
        await scenario(model, ui)
        await escapeInForms(model, ui)
        await scenario(model, ui)
        await subtaskToBacklog(model, ui)
    }

    /// A key pressed in the sheet, as AppKit gives it to the key window: its key equivalents first (a button's shortcut),
    /// then its first responder. A background run's sheet is never key, so the window gets it directly.
    private static func sheetKey(_ ui: Driver, _ characters: String, _ flags: NSEvent.ModifierFlags = [], code: UInt16) async {
        guard let sheet = ui.window.attachedSheet,
              let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: sheet.windowNumber, context: nil, characters: characters,
                                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { return }
        if !sheet.performKeyEquivalent(with: event) { sheet.sendEvent(event) }
        await ui.settle(0.4)
    }

    /// Text typed into the field that has the sheet's keyboard, as its editor takes it.
    private static func typeInSheet(_ ui: Driver, _ text: String) async {
        (ui.window.attachedSheet?.firstResponder as? NSTextView)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        await ui.settle(0.2)
    }

    /// Show N More: the arrows reach every row it shows, Return opens one past the fifth; a filter that shows every row
    /// never lets the arrows select one the card doesn't draw.
    private static func keysPastFive(_ model: AppModel, _ ui: Driver) async {
        let made = (1...7).compactMap { model.addFile(title: "Page note \($0)") }
        await ui.settle(0.5)
        let rows = model.listedFiles.map { ModalRoute.file($0.id).selectionKey }
        guard made.count == 7, rows.count == 7 else { return await check("seven files to walk", false, "\(rows.count)") }
        await ui.click(ui.anchor("show-more:files"))
        await check("Show 2 More shows every file", model.expandedCards.contains(.files) && ui.anchorFrame("item:\(rows[6])") != nil)
        await ui.click(ui.anchor("item:\(rows[0])"))
        await check("a click selects the first file", model.selectedItem == rows[0], model.selectedItem ?? "none")
        for _ in 0..<6 { await ui.key(.down) }
        await check("↓ walks past the fifth row once Show More shows them", model.selectedItem == rows[6], model.selectedItem ?? "none")
        await ui.key(.return)
        await ui.until(2) { model.modal != nil }
        await check("Return opens the seventh", model.modal?.selectionKey == rows[6], "\(String(describing: model.modal))")
        model.closeModal()
        await ui.until(2) { ui.window.attachedSheet == nil }
        await ui.settle(0.4)

        // Show Fewer, then Pinned Only: a filter shows every pinned row, and the arrows walk only those.
        await ui.click(ui.anchor("show-more:files"))
        await check("Show Fewer folds the card back to five", !model.expandedCards.contains(.files))
        for file in made { model.setPinned(.file(file.id), true) }
        model.pinnedOnly = true
        await ui.settle(0.5)
        let pinned = model.listedFiles.map { ModalRoute.file($0.id).selectionKey }
        await ui.click(ui.anchor("item:\(pinned[0])"))
        var unshown: [String] = []
        for _ in 0..<6 {
            await ui.key(.down)
            if let key = model.selectedItem, ui.anchorFrame("item:\(key)") == nil { unshown.append(key) }
        }
        await check("with Pinned Only, the card shows every pinned file and ↓ selects only rows it shows",
              unshown.isEmpty && model.selectedItem == pinned.last, "not shown: \(unshown), at \(model.selectedItem ?? "none")")
    }

    /// A row clicked in the modal selects there: the page's selection is still the one thing selected once it closes.
    private static func modalSelection(_ model: AppModel, _ ui: Driver) async {
        guard let pr = model.reviewRequests.first ?? model.ownPullRequests.first, let file = model.addFile(title: "Linked note"),
              let task = model.addTask(to: .overview, title: "Has a note") else { return await check("a PR, a file and a task", false) }
        model.link(.file(file.id), to: task.id)
        await endUndoGroup(model)
        await ui.settle(0.4)
        let prKey = ModalRoute.github(pr.url).selectionKey
        let fileKey = ModalRoute.file(file.id).selectionKey
        await ui.click(ui.anchor("pr:\(pr.number)"))
        await check("a click selects the PR", model.selectedItem == prKey, model.selectedItem ?? "none")
        model.open(.task(task.id))
        await ui.until(2) { ui.window.attachedSheet != nil }
        await ui.settle(0.6)
        // A background run's sheet takes no click on a row: the click's own path stands in.
        if ui.canClickTables {
            await ui.click(await ui.steadyAnchor("row:\(fileKey)"), inSheet: true)
        } else {
            model.select(fileKey, in: nil, inModal: true)
        }
        await check("a click on a link's row in the modal selects it there", model.modalSelection == fileKey, model.modalSelection ?? "none")
        await check("and leaves the page's selection as it was", model.selectedItem == prKey, model.selectedItem ?? "none")
        await ui.click(ui.anchor("modal-close"), inSheet: true)
        await ui.until(2) { ui.window.attachedSheet == nil }
        await check("closed, one thing is selected on the page, and the menus act on it: the PR",
              model.selectedItem == prKey && model.modalSelection == nil && model.menuRoute == .github(pr.url),
              "\(model.selectedItem ?? "none"), modal's \(model.modalSelection ?? "none")")
    }

    /// New File… and Import Artifact… are sheets: they work with Files folded, and over a task go back to it.
    private static func fileSheets(_ model: AppModel, _ ui: Driver) async {
        model.folded.insert(.files)
        await ui.settle(0.4)
        // File › New File… (⌃⌘N): the menu's action.
        model.beginNewFile()
        await ui.until(2) { ui.sheetIsTyping }
        await check("New File… with Files folded opens its sheet, the keyboard in its title", model.modal == .newFile && ui.sheetIsTyping,
              ui.sheetResponder)
        await typeInSheet(ui, "Sheet note")
        await ui.click(await ui.steadyAnchor("new-file-create"), inSheet: true)
        let note = model.files.first { $0.title == "Sheet note" }
        await check("Create writes the note and opens it in its editor; Files unfolds with its row selected",
              note != nil && model.modal == note.map { .file($0.id) } && model.editingFile == note?.id && !model.folded.contains(.files)
              && model.selectedItem == note.map { ModalRoute.file($0.id).selectionKey }, "\(String(describing: model.modal)) \(model.selectedItem ?? "none")")
        model.editingFile = nil
        model.closeModal()
        await ui.until(2) { ui.window.attachedSheet == nil }

        // Import Artifact… with Files folded: a sheet; the artifact imported is selected on the page.
        model.folded.insert(.files)
        await ui.settle(0.4)
        model.beginImport()
        await ui.until(2) { ui.sheetIsTyping }
        await check("Import Artifact… with Files folded opens its sheet with the keyboard", model.modal == .importArtifact && ui.sheetIsTyping,
              ui.sheetResponder)
        let link = "https://claude.ai/artifact/0f0f0f0f-aaaa-4bbb-8ccc-0123456789ab"
        let fields = textFields(ui.window.attachedSheet?.contentView)
        let titleField = fields.first { ($0.placeholderString ?? $0.placeholderAttributedString?.string) == "HQ Notification Center" } ?? fields.last
        for (field, text) in [(fields.first { $0 !== titleField }, link), (titleField, "Imported page")] {
            guard let field else { continue }
            ui.window.attachedSheet?.makeFirstResponder(field)
            (ui.window.attachedSheet?.firstResponder as? NSTextView)?.selectAll(nil)
            await typeInSheet(ui, text)
        }
        await ui.click(await ui.steadyAnchor("import-add"), inSheet: true)
        await ui.until(2) { model.modal == nil }
        let key = URL(string: link).map { ModalRoute.artifact($0).selectionKey }
        await check("Import adds it, the sheet goes and its row is selected in Files and Artifacts",
              model.artifacts.contains { $0.title == "Imported page" } && model.modal == nil && model.selectedItem == key
              && model.selectedSection == .files && !model.folded.contains(.files),
              "\(model.selectedItem ?? "none"), modal \(String(describing: model.modal)), fields \(fields.map { "\($0.placeholderString ?? "-")=\($0.stringValue)" })")

        // Over a task's window: Cancel (Escape) goes back to it.
        guard let task = model.addTask(to: .overview, title: "Under the sheet") else { return }
        await endUndoGroup(model)
        model.open(.task(task.id))
        await ui.until(2) { ui.window.attachedSheet != nil }
        await ui.settle(0.5)
        model.beginNewFile()
        await ui.until(2) { model.modal == .newFile && ui.sheetIsTyping }
        await sheetKey(ui, "\u{1b}", code: 53)
        await check("Escape in New File… over a task goes back to the task", model.modal == .task(task.id), "\(String(describing: model.modal))")
    }

    private static func textFields(_ view: NSView?) -> [NSTextField] {
        guard let view else { return [] }
        return ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(textFields)
    }

    /// A card dropped while the search filters the grid lands right before the card it was dropped before.
    private static func filteredGridDrag(_ model: AppModel, _ ui: Driver) async {
        guard let collection = ui.find(SessionGrid.CardCollection.self),
              let coordinator = collection.delegate as? SessionGrid.Coordinator else { return await check("the session grid", false) }
        model.search = "registry"
        await ui.until(2) { coordinator.ids == model.filteredGrid.map(\.id) }
        let shown = model.filteredGrid.map(\.id)
        let all = model.gridSessions.map(\.id)
        guard shown.count >= 2, let first = all.firstIndex(of: shown[0]), first > 0, let moving = shown.last else {
            return await check("a search that hides a card before the first one it shows", false, "\(shown.count) of \(all.count)")
        }
        let info = FakeDrag(session: moving, source: collection)
        _ = validate(coordinator, collection, info, item: 0, operation: .before)
        await endUndoGroup(model)
        _ = coordinator.collectionView(collection, acceptDrop: info, indexPath: IndexPath(item: 0, section: 0), dropOperation: .before)
        await endUndoGroup(model)
        coordinator.dragEnded()
        await ui.settle(0.4)
        var expected = all.filter { $0 != moving }
        expected.insert(moving, at: expected.firstIndex(of: shown[0]) ?? 0)
        await check("a card dropped on a filtered grid lands right before the card it was dropped before",
              model.gridSessions.map(\.id) == expected, "\(model.gridSessions.map { $0.id.suffix(2) }) for \(expected.map { $0.suffix(2) })")
        await check("and the grid shows the model's order", coordinator.ids == model.filteredGrid.map(\.id))
    }

    /// The cards hold still under a drag: a session that ends mid-drag leaves once it's over, and a drop goes where AppKit
    /// said; an index past the cards puts the card last.
    private static func gridHoldsUnderDrag(_ model: AppModel, _ ui: Driver) async {
        guard let collection = ui.find(SessionGrid.CardCollection.self), let coordinator = collection.delegate as? SessionGrid.Coordinator,
              let task = model.addTask(to: .overview, title: "Drop me on a card") else { return await check("the grid and a task", false) }
        await endUndoGroup(model)
        await ui.settle(0.4)
        let before = coordinator.ids
        guard before.count >= 3 else { return await check("three cards", false) }
        let target = before[1], leaving = before[0]
        let drag = FakeDrag(tasks: [task.id], source: nil)
        _ = validate(coordinator, collection, drag, item: 1, operation: .before)
        model.sessions.removeAll { $0.id == leaving }
        await ui.settle(0.4)
        await check("the cards hold still while a drag is over the grid", coordinator.ids == before, "\(coordinator.ids.count) of \(before.count)")
        _ = coordinator.collectionView(collection, acceptDrop: drag, indexPath: IndexPath(item: 1, section: 0), dropOperation: .on)
        await endUndoGroup(model)
        await check("a task dropped on a card links the session it was over, not its new neighbour", model.task(task.id)?.sessions == [target],
              "\(model.task(task.id)?.sessions ?? [])")
        coordinator.dragEnded()
        await ui.until(2) { coordinator.ids == model.filteredGrid.map(\.id) }
        await check("the drag over, the card whose session ended leaves", coordinator.ids == model.filteredGrid.map(\.id) && !coordinator.ids.contains(leaving))

        // AppKit's index past the cards: the card goes last, nothing traps.
        let moving = coordinator.ids[0]
        let info = FakeDrag(session: moving, source: collection)
        _ = validate(coordinator, collection, info, item: 0, operation: .before)
        _ = coordinator.collectionView(collection, acceptDrop: info, indexPath: IndexPath(item: coordinator.ids.count + 3, section: 0), dropOperation: .before)
        await endUndoGroup(model)
        coordinator.dragEnded()
        await ui.settle(0.4)
        await check("a drop index past the cards puts the card last", model.gridSessions.last?.id == moving && coordinator.ids.last == moving)
    }

    /// A PR's page in the modal stays when a poll no longer brings its item (a read notification's thread, a merge from HQ).
    private static func prPageStays(_ model: AppModel, _ ui: Driver) async {
        guard let pr = model.ownPullRequests.first ?? model.reviewRequests.first else { return await check("a PR", false) }
        model.open(.github(pr.url))
        await ui.until(2) { ui.window.attachedSheet != nil }
        await ui.settle(0.6)
        let gone = Snapshot.goneShown
        await check("the PR's page shows with its actions", ui.anchor("reload") != nil)
        model.github?.items.removeAll { $0.url == pr.url }
        await ui.settle(0.6)
        await check("a poll that drops it leaves its page, never This Item Is Gone",
              Snapshot.goneShown == gone && ui.anchor("reload") != nil && model.modal == .github(pr.url), "gone \(Snapshot.goneShown - gone)")
        await check("and the next poll asks GitHub for what the modal shows", model.modalGitHubURLs == [pr.url])
    }

    /// Escape in a form over a modal goes back to what's under it; in the center's reminder editor it ends the edit.
    private static func escapeInForms(_ model: AppModel, _ ui: Driver) async {
        guard let task = model.addTask(to: .overview, title: "Remind me of this") else { return }
        await endUndoGroup(model)
        model.open(.task(task.id))
        await ui.until(2) { ui.window.attachedSheet != nil }
        await ui.settle(0.5)
        model.beginReminder(about: .task(task.id))
        await ui.until(2) { model.modal == .newReminder && ui.sheetIsTyping }
        await sheetKey(ui, "\u{1b}", code: 53)
        await check("Escape in Remind Me… over a task goes back to the task", model.modal == .task(task.id), "\(String(describing: model.modal))")

        model.closeModal()
        await ui.until(2) { ui.window.attachedSheet == nil }
        model.openCenter()
        await ui.until(2) { ui.window.attachedSheet != nil }
        await ui.settle(0.5)
        model.beginReminder()
        await ui.until(2) { model.modal == .newReminder && ui.sheetIsTyping }
        await sheetKey(ui, "\u{1b}", code: 53)
        await check("Escape in New Reminder… over the center goes back to the center", model.modal == .notifications, "\(String(describing: model.modal))")

        let waiting = model.remind("Call the bank", at: .now.addingTimeInterval(7200), level: .update)
        await ui.settle(0.4)
        model.noticeSelection = waiting.id.uuidString
        await ui.settle(0.3)
        await ui.click(await ui.steadyAnchor("edit:\(waiting.id.uuidString)"), inSheet: true)
        await ui.until(2) { ui.anchor("reminder-text") != nil && ui.sheetIsTyping }
        await sheetKey(ui, "\u{1b}", code: 53)
        await check("Escape in the center's reminder editor ends the edit and leaves the center",
              model.modal == .notifications && ui.anchorFrame("reminder-text") == nil, "\(String(describing: model.modal))")
    }

    /// ⇧⌘B in a task's window moves the selected subtask, as B and ⌘⌫ act on it, not the window's task.
    private static func subtaskToBacklog(_ model: AppModel, _ ui: Driver) async {
        guard let parent = model.addTask(to: .overview, title: "Window's task"), let sub = model.addSubtask(to: parent.id, title: "Its subtask") else {
            return await check("a task with a subtask", false)
        }
        await endUndoGroup(model)
        model.open(.task(parent.id))
        await ui.until(2) { ui.window.attachedSheet != nil }
        await ui.settle(0.8)
        guard let sheet = ui.window.attachedSheet, let scoped = OutlineCoordinator.scoped(parent.id) else { return await check("the task's window and its outline", false) }
        scoped.select(sub.id)
        await ui.settle(0.3)
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: sheet.windowNumber, context: nil, characters: "B", charactersIgnoringModifiers: "b",
                                           isARepeat: false, keyCode: 11) else { return }
        // As AppKit sends a key equivalent: the window's views first, then the menu bar.
        if !sheet.performKeyEquivalent(with: event) { _ = NSApp.mainMenu?.performKeyEquivalent(with: event) }
        await endUndoGroup(model)
        await ui.settle(0.4)
        await check("⇧⌘B on a selected subtask in its task's window moves the subtask, not the window's task",
              model.list(of: sub.id) == .backlog && model.list(of: parent.id) == .overview && model.modal == .task(parent.id),
              "subtask in \(model.list(of: sub.id)), task in \(model.list(of: parent.id))")
        model.closeModal()
        await ui.until(2) { ui.window.attachedSheet == nil }
    }
}
