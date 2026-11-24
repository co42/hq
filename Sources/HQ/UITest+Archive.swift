import AppKit
import HQKit

/// The Archive's window (T-471): a story archived from the list is found by a task under it, opened read only and
/// brought back; its empty and no-match states; Quick Open's last row; its speed with 10,000 archived tasks.
extension UITest {
    static func archiveWindow(_ model: AppModel, _ ui: Driver) async {
        guard let story = model.addTask(status: .todo, title: "Archive me"), let step = model.addSubtask(to: story.id, title: "Turn the knob") else {
            return await check("a story to archive", false)
        }
        model.setStatus(step.id, .done)
        model.setStatus(story.id, .done)
        model.setDescription(story.id, "What it was for.")
        await endUndoGroup(model)
        await ui.settle(0.4)
        model.archive([story.id])
        await endUndoGroup(model)
        model.flushNoteWrites()

        model.openArchive()
        await ui.until(3) { model.archiveShown != nil && ui.anchor("archived:\(story.id)") != nil }
        await ui.settle(0.4)
        await check("the Archive opens on its stories, the one just archived among them, its field with the keyboard",
                    model.modal == .archive && ui.anchor("archived:\(story.id)") != nil && ui.window.attachedSheet?.firstResponder is NSText,
                    "\(String(describing: model.modal)) \(String(describing: ui.window.attachedSheet?.firstResponder))")
        model.archiveQuery = "knob"
        await ui.settle(0.4)
        await check("its search finds a story by a task under it", ui.anchor("archived:\(story.id)") != nil
                    && model.archiveShown?.searcher.search("knob").first?.under.map(\.id) == [step.id])
        await sheetKey(ui, 36, "\r")
        await ui.until(2) { model.modal == .archivedTask(story.id) }
        await ui.until(3) { model.archiveShown?.notes[story.id] != nil }
        await check("Return opens the story's window, read only, its description read in",
                    model.modal == .archivedTask(story.id) && model.archiveShown?.notes[story.id]?.body == "What it was for.",
                    "\(String(describing: model.modal))")
        model.back()
        await ui.until(2) { model.modal == .archive }
        await check("Back returns to the Archive, its search kept", model.modal == .archive && model.archiveQuery == "knob")
        model.archiveQuery = "nothing like this"
        await ui.settle(0.3)
        await check("a search that finds nothing says so", ui.anchor("archive-none") != nil)
        model.archiveQuery = "knob"
        await ui.settle(0.3)
        await ui.click(await ui.steadyAnchor("unarchive:\(story.id)"), inSheet: true)
        await ui.until(3) { model.task(story.id) != nil }
        await ui.settle(0.4)
        await check("Unarchive on its card brings it back first in Tasks, and its card leaves the results",
                    model.task(story.id) != nil && model.task(step.id) != nil && model.taskTree.top().first == story.id
                    && ui.anchor("archived:\(story.id)") == nil, "\(model.taskTree.top())")
        model.closeModal()
        await ui.until(2) { model.modal == nil }
        await ui.settle(0.6)
        await check("closed, the page selects the story it brought back, Done turned on to show it",
                    model.selectedTasks == [story.id] && model.showDone, "\(model.selectedTasks) done shown \(model.showDone)")
        await check("Quick Open's last row searches the Archive", QuickOpen.results(model, query: "knob").last?.route == .archive)

        // Opened with a search, as Quick Open's row does: the first story found is selected, and ⌃⌘A brings it back.
        guard let other = model.addTask(status: .todo, title: "Pull the lever"), let dial = model.addTask(status: .todo, title: "Turn the dial") else {
            return await check("two more stories", false)
        }
        model.setStatus(other.id, .done)
        model.setStatus(dial.id, .done)
        await endUndoGroup(model)
        model.archive([other.id, dial.id])
        await endUndoGroup(model)
        model.flushNoteWrites()
        model.openArchive(query: "lever")
        await ui.until(3) { ui.anchor("archived:\(other.id)") != nil && model.archiveSelection == other.id }
        await check("opened with a search, the Archive selects the first story found", model.archiveSelection == other.id,
                    "\(String(describing: model.archiveSelection))")
        await check("in the Archive, Task's ⌃⌘A item is Unarchive, on the selected story", MenuState.shared.archivedStory == other.id,
                    "\(String(describing: MenuState.shared.archivedStory))")
        // Through the queue, as a real key: HQ's key monitor takes it before the menus, whose ⌃⌘A item may be off.
        await ui.key("a", [.command, .control], code: 0)
        await ui.until(3) { model.task(other.id) != nil }
        await ui.settle(0.3)
        await check("⌃⌘A in the Archive unarchives the selected story", model.task(other.id) != nil && ui.anchor("archived:\(other.id)") == nil)
        model.archiveQuery = "dial"
        await ui.until(2) { model.archiveSelection == dial.id }
        model.open(.archivedTask(dial.id), push: true)
        await ui.click(await ui.steadyAnchor("unarchive-task"), inSheet: true)
        await ui.until(3) { model.task(dial.id) != nil && model.modal == .archive }
        await check("Unarchive in an archived task's window brings it back and returns to the Archive",
                    model.task(dial.id) != nil && model.modal == .archive, "\(String(describing: model.modal))")
        model.closeModal()
        await ui.until(2) { model.modal == nil }
        model.deleteTasks([other.id, dial.id])
        // Nothing to archive: ⌃⌘A does nothing, and never opens the Archive (⇧⌘A).
        model.selectedTasks = []
        await ui.key("a", [.command, .control], code: 0)
        await ui.settle(0.4)
        await check("⌃⌘A with nothing to archive leaves the Archive shut", model.modal == nil, "\(String(describing: model.modal))")
        await endUndoGroup(model)

        // Archive All Done (T-537): asks naming how many, takes every story done throughout, one Undo brings them all back.
        if let first = model.addTask(status: .done, title: "Done one"), let second = model.addTask(status: .done, title: "Done two"),
           let held = model.addTask(status: .done, title: "Done, a step open"), let open = model.addSubtask(to: held.id, title: "Open step") {
            model.setStatus(open.id, .todo)
            await endUndoGroup(model)
            let done = model.doneStories, log = model.ghosttyLog.count
            model.archiveAllDone()
            await endUndoGroup(model)
            await ui.settle(0.3)
            await check("Archive All Done asks naming how many, then takes every story done throughout, not one with a step open",
                        model.ghosttyLog.dropFirst(log).contains("confirm archive all done, \(done.count)") && done.contains(first.id)
                        && model.task(first.id) == nil && model.task(second.id) == nil && model.task(held.id) != nil,
                        "\(model.ghosttyLog.suffix(1)) \(done)")
            model.flushNoteWrites()
            model.undoManager?.undo()
            await ui.until(3) { model.task(first.id) != nil && model.task(second.id) != nil }
            await check("one Undo brings them all back", model.task(first.id) != nil && model.task(second.id) != nil)
            await ui.settle(0.3)
            model.deleteTasks([first.id, second.id, held.id])
            await endUndoGroup(model)
        }

        // Nothing archived.
        model.archiveQuery = ""
        model.archiveShown = .empty
        model.open(.archive)
        await ui.settle(0.5)
        await check("with nothing archived, it says so", ui.anchor("archive-empty") != nil)
        model.closeModal()
        model.archiveShown = nil
        await ui.until(2) { model.modal == nil }

        // 10,000 archived tasks: opening and each keystroke stay quick.
        let big = SeedData.archiveIndex(stories: 2_000, now: .now)
        let searcher = ArchiveIndex.Searcher(big)
        // Five opens, their median judged: a loaded shard can hold one (T-519).
        var opens: [Int] = []
        for round in 0..<5 {
            let one = await Stall.measure([{ model.archiveShown = ArchiveShown(index: big, searcher: searcher); model.open(.archive) }], gap: 1)
            opens.append(one.worst)
            guard round < 4 else { break }
            model.closeModal()
            await ui.until(2) { model.modal == nil }
        }
        let open = Stall.Result(steps: opens)
        let typing = await Stall.measure(["s", "st", "sto", "stor", "story 1", "story 19", "story 199", ""].map { text in { model.archiveQuery = text } })
        print("  perf: archive open \(open); typing \(typing)")
        await check("the Archive opens with 10,000 archived tasks holding the main thread under 150 ms, the median of five (debug ×1.5)",
                    open.median < Stall.budget(150), "\(open)")
        // As the list's search: a search that changes every card on screen lays them all out anew, SwiftUI's part (2026-11-16).
        await check("a keystroke in its search with 10,000 holds it under 100 ms, as the list's search (debug ×1.5)",
                    typing.worst < Stall.budget(100), "\(typing)")
        model.closeModal()
        model.archiveShown = nil
        model.archiveQuery = ""
        await ui.until(2) { model.modal == nil }
        model.deleteTasks([story.id])
        await endUndoGroup(model)
    }

    /// A key to the sheet, as AppKit gives it: a ⌘ key to the sheet's views, then the menu bar; others to its first responder.
    private static func sheetKey(_ ui: Driver, _ code: UInt16, _ characters: String, ignoring: String? = nil,
                                 _ modifiers: NSEvent.ModifierFlags = []) async {
        guard let sheet = ui.window.attachedSheet else { return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: sheet.windowNumber, context: nil, characters: characters,
                                            charactersIgnoringModifiers: ignoring ?? characters, isARepeat: false, keyCode: code) {
                if modifiers.contains(.command) {
                    if type == .keyDown, !sheet.performKeyEquivalent(with: event) { _ = NSApp.mainMenu?.performKeyEquivalent(with: event) }
                } else {
                    NSApp.sendEvent(event)
                }
            }
        }
        await ui.settle(0.2)
    }
}
