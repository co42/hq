import AppKit
import HQKit

/// Several tasks selected (T-568, DESIGN.md §7 Keys, §18): ⌘-click and ⇧-click, X on the focus, the arrows moving the
/// focus while the selection stays, the keys that act on all of them or on the focus alone, Escape back
/// to one; and several cards dragged together, through AppKit's own drag (moving several crashed in v10, T-391).
extension UITest {
    static func severalTasks(_ model: AppModel, _ ui: Driver) async {
        let ids = await makeTree(model)
        await ui.settle(0.8)
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator,
              let a = ids["A"], let a1 = ids["A1"], let a2 = ids["A2"], let b = ids["B"], let c = ids["C"] else {
            return await check("the outline's tasks", false)
        }
        let state = {
            "selected \(model.selectedTasks) focus \(String(describing: coordinator.focus)) menu \(MenuState.shared.tasks) on \(String(describing: MenuState.shared.task)) responder \(ui.responder)"
        }
        /// Every selected card has its ring and nothing more: the full one on the focus or a lone task, the thin one on the
        /// others among several; the focus, unselected, has the hover fill alone (T-708).
        func rings(selected: [Int]) -> Bool {
            var filled: Set<Int> = []
            outline.enumerateAvailableRowViews { view, row in
                if let view = view as? OutlineRowView, view.focused, !view.isSelected, let id = (outline.item(atRow: row) as? OutlineNode)?.task { filled.insert(id) }
            }
            // Rings and the fill show only while the rows have the keyboard in the key window: never in a background run.
            guard outline.hasKeyboard else { return filled.isEmpty }
            let full = Set(outline.cardShapes.filter { $0.ring == .selected }.map(\.key))
            let thin = Set(outline.cardShapes.filter { $0.ring == .kept }.map(\.key))
            let wantFull = selected.filter { selected.count == 1 || $0 == coordinator.focus }
            let focus = coordinator.focus.flatMap { selected.contains($0) ? nil : $0 }
            return full == Set(wantFull.map { "card:\($0)" }) && thin == Set(selected.filter { !wantFull.contains($0) }.map { "card:\($0)" })
                && filled == Set(focus.map { [$0] } ?? [])
        }

        // X on a lone task starts keeping it; ↓ moves the focus, the selection stays; X adds, X again removes.
        coordinator.select(a)
        await ui.settle(0.3)
        await check("one task selected has no focus", coordinator.focus == nil && rings(selected: [a]), state())
        await ui.key("x", code: 7)
        await check("X on a lone task keeps it: still one task", coordinator.focus == a && model.selectedTasks == [a]
                    && rings(selected: [a]), state())
        await ui.key(.down)
        await check("Down moves the focus, shown by the hover fill; the selection stays", coordinator.focus == a1 && model.selectedTasks == [a] && rings(selected: [a]), state())
        await ui.key("x", code: 7)
        await ui.key(.down)
        await ui.key(.down)
        await ui.key("x", code: 7)
        await check("X adds the focused task each time", model.selectedTasks == [a, a1, b] && coordinator.focus == b && rings(selected: [a, a1, b]), state())
        await ui.key(.up)
        await ui.key(.up)
        await ui.key("x", code: 7)
        await check("X on a selected focus takes it out, the focus stays on it", model.selectedTasks == [a, b] && coordinator.focus == a1
                    && rings(selected: [a, b]), state())
        await check("the Task menu acts on the selection, its one-task items on the focus", MenuState.shared.tasks == [a, b] && MenuState.shared.task == a1, state())

        // Keys on several: ⌘Return on every selected task, B nothing, Space opens the focus.
        await ui.key("\r", .command, code: 36)
        await check("Command-Return moves every selected task on, not the focus", model.task(a)?.status == .doing && model.task(b)?.status == .doing
                    && model.task(a1)?.status == .todo, state())
        await endUndoGroup(model)
        model.undoManager?.undo()
        await ui.settle(0.3)
        await check("Undo brings back every selected task, selected, the focus kept", model.selectedTasks == [a, b] && coordinator.focus == a1 && model.task(a)?.status == .todo, state())
        await ui.key("b", code: 11)
        await ui.settle(0.3)
        await check("B does nothing on several", ui.anchor("hold-picker") == nil && ui.anchor("hold-reason") == nil && model.task(a)?.blocked != true && ui.window.firstResponder === outline, state())
        await ui.key(" ")
        await ui.until { model.modal == .task(a1) }
        await check("Space opens the focused task", model.modal == .task(a1), "\(String(describing: model.modal)) \(state())")
        model.closeModal()
        await ui.settle(0.4)
        await check("its window closed, the selection and the focus stay", model.selectedTasks == [a, b] && coordinator.focus == a1, state())

        // Escape: back to one, the focus; again, none.
        if ui.window.firstResponder !== outline { ui.window.makeFirstResponder(outline) }
        await ui.key(.escape)
        await check("Escape goes back to one task, the focused one", model.selectedTasks == [a1] && coordinator.focus == nil && rings(selected: [a1]), state())
        await ui.key(.escape)
        await check("Escape again unselects", model.selectedTasks.isEmpty, state())

        // X on the last one kept goes back to one task, never none.
        coordinator.select(b)
        await ui.key("x", code: 7)
        await ui.key("x", code: 7)
        await check("X on the last one kept goes back to one task", model.selectedTasks == [b] && coordinator.focus == nil && rings(selected: [b]), state())

        // ⇧ with the arrows moves them together; ⌫ deletes them all, one Undo.
        coordinator.select([a, b])
        await ui.settle(0.3)
        await check("several selected from code take a focus", model.selectedTasks == [a, b] && coordinator.focus != nil, state())
        await ui.key(.down, .shift)
        await endUndoGroup(model)
        await check("Shift-Down moves the selected tasks together", tops(model) == [c, a, b] && model.selectedTasks == [a, b], "\(tops(model)) \(state())")
        model.undoManager?.undo()
        await ui.settle(0.3)
        coordinator.select([b, c])
        await ui.settle(0.2)
        await ui.key(.delete)
        await endUndoGroup(model)
        await check("Delete deletes every selected task", model.task(b) == nil && model.task(c) == nil && tops(model) == [a], "\(tops(model))")
        model.undoManager?.undo()
        await ui.settle(0.4)
        await check("one Undo brings them back", tops(model) == [a, b, c], "\(tops(model))")

        // Clicks: ⌘-click adds and removes, ⇧-click a range, a plain click back to one.
        await ui.click(ui.titlePoint(b))
        await ui.click(ui.titlePoint(c), flags: .command)
        await tableCheck(ui, "Command-click adds a task; the focus goes to it", model.selectedTasks == [b, c] && coordinator.focus == c && rings(selected: [b, c]), state())
        await ui.click(ui.titlePoint(b), flags: .command)
        await tableCheck(ui, "Command-click on a selected task takes it out", model.selectedTasks == [c] && coordinator.focus == nil, state())
        await ui.click(ui.titlePoint(a))
        await ui.click(ui.titlePoint(b), flags: .shift)
        await tableCheck(ui, "Shift-click selects the range", model.selectedTasks == [a, a1, a2, b] && coordinator.focus == b, state())
        await ui.click(ui.titlePoint(a1))
        await tableCheck(ui, "a plain click goes back to one task", model.selectedTasks == [a1] && coordinator.focus == nil && rings(selected: [a1]), state())

        await severalUpdates(model, ui, outline, coordinator, ids, state)
        await severalDrag(model, ui, outline, coordinator, b, c, a)
    }

    /// The tasks change under several kept (a session, the vault): the selection and the focus stay, and X still adds the
    /// focused task (T-712).
    private static func severalUpdates(_ model: AppModel, _ ui: Driver, _ outline: TaskOutlineView, _ coordinator: OutlineCoordinator, _ ids: [String: Int],
                                       _ state: () -> String) async {
        guard let a = ids["A"], let a2 = ids["A2"], let b = ids["B"], let c = ids["C"] else { return await check("the outline's tasks", false) }
        if ui.window.firstResponder !== outline { ui.window.makeFirstResponder(outline) }
        coordinator.select(a)
        await ui.settle(0.2)
        for key in ["x", "↓", "↓", "↓", "x", "↑"] {
            if key == "x" { await ui.key("x", code: 7) } else { await ui.key(key == "↓" ? .down : .up) }
        }
        await check("A and B kept, the focus on A2", model.selectedTasks == [a, b] && coordinator.focus == a2, state())
        await endUndoGroup(model)
        let changes: [(String, () -> Void)] = [
            ("a task added first", { _ = model.addTask(status: .todo, title: "F") }),
            ("a task renamed", { model.setTitle(c, "C again") }),
            ("a task added between kept ones", { _ = model.addTask(after: a, title: "A after") }),
            ("the focus gets a subtask", { _ = model.addSubtask(to: a2, title: "A21") }),
            ("a kept task moves on", { model.setStatus(b, .doing) }),
            ("a kept task moves under another", { _ = model.drop([b], into: .task(c), at: 0) }),
        ]
        for (name, change) in changes {
            change()
            await endUndoGroup(model)
            await ui.settle(0.4)
            await check("\(name): the selection and the focus stay", model.selectedTasks == [a, b] && coordinator.focus == a2, state())
        }
        await ui.key(.tab)
        await ui.settle(0.3)
        await check("Tab leaves Tasks: its rows unselect", model.selectedTasks.isEmpty && model.selectedSection != .tasks, state())
        await ui.key(.tab, .shift)
        await ui.settle(0.3)
        await check("Shift-Tab back: the kept tasks and the focus come back", model.selectedTasks == [a, b] && coordinator.focus == a2, state())
        await ui.key("x", code: 7)
        await check("X then adds the focused task", model.selectedTasks == [a, a2, b] && coordinator.focus == a2, state())
        for _ in changes { model.undoManager?.undo() }
        await ui.settle(0.4)
        await check("the changes undone", tops(model) == [a, b, c] && model.task(b)?.status == .todo, "\(tops(model))")
    }

    /// Two selected cards dragged through AppKit's own mouse tracking: the drag starts with both (moving several crashed
    /// in v10, T-391: code-lint holds its cause, `isFlipped` nonisolated); then dropped together, one Undo.
    private static func severalDrag(_ model: AppModel, _ ui: Driver, _ outline: TaskOutlineView, _ coordinator: OutlineCoordinator, _ b: Int, _ c: Int, _ a: Int) async {
        coordinator.select([b, c])
        await ui.settle(0.3)
        let row = outline.row(forItem: coordinator.node(.task(b)))
        guard row >= 0, let card = outline.cardFrame(ofRow: row) else { return await check("B's card for the drag", false) }
        let start = outline.convert(NSPoint(x: card.minX + card.width * 0.75, y: card.midY), to: nil)
        func event(_ type: NSEvent.EventType, _ dy: CGFloat) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: start.x, y: start.y - dy), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: ui.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
        }
        var began: [Int] = []
        OutlineCoordinator.dragStarted = { began = $0 }
        defer { OutlineCoordinator.dragStarted = nil }
        // AppKit's tracking reads the moves from the queue, then starts its drag session with the selected rows.
        for dy in stride(from: CGFloat(4), through: 40, by: 6) { if let move = event(.leftMouseDragged, dy) { NSApp.postEvent(move, atStart: false) } }
        if let up = event(.leftMouseUp, 40) { NSApp.postEvent(up, atStart: false) }
        if let down = event(.leftMouseDown, 0) { outline.mouseDown(with: down) }
        await ui.until(3) { !began.isEmpty }
        await check("AppKit starts a drag of two selected cards with both", began == [b, c], "began \(began)")
        // The session runs only on the system's own mouse events, never on posted ones, in front or not: the rows let go
        // as AppKit would tell them. The v10 crash came while it drew the cards; code-lint holds its cause.
        coordinator.dragEnded()
        skip("a real drag of two cards runs and ends", because: "AppKit runs a drag session on the system's mouse events only")
        await ui.settle(0.5)
        // Dropped together between cards: they land there, in their order, still selected.
        let info = FakeDrag(tasks: [b, c], source: outline)
        let header = coordinator.node(.header)
        let operation = coordinator.outlineView(outline, validateDrop: info, proposedItem: header, proposedChildIndex: 0)
        let accepted = operation == .move && coordinator.outlineView(outline, acceptDrop: info, item: header, childIndex: 0)
        coordinator.dragEnded()
        await ui.settle(0.5)
        await endUndoGroup(model)
        await check("two tasks dropped together land there in their order, still selected", accepted && tops(model) == [b, c, a] && model.selectedTasks == [b, c],
                    "\(tops(model)) \(model.selectedTasks)")
        model.undoManager?.undo()
        await ui.settle(0.3)
        await check("one Undo puts both back", tops(model) == [a, b, c], "\(tops(model))")
    }
}
