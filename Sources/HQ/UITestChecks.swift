import AppKit
import SwiftUI
import HQKit

/// The cockpit's interactions, checked with real keys and clicks, and drops through the views' own code.
extension UITest {
    /// Lets one event through, so AppKit closes the open Undo group as after any click or key:
    /// direct calls come with no events, and closing AppKit's group by hand makes it throw later.
    static func endUndoGroup(_ model: AppModel) async {
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
            NSApp.postEvent(event, atStart: false)
        }
        try? await Task.sleep(for: .milliseconds(100))
    }

    // MARK: Session grid

    static func grid(_ model: AppModel, _ ui: Driver) async {
        await ui.settle(0.5)
        guard let collection = ui.find(SessionGrid.CardCollection.self),
              let coordinator = collection.delegate as? SessionGrid.Coordinator else { return check("the session grid is on the page", false) }
        let first = model.gridSessions[0]
        // The cards sit in the page's column, not across the page's scroll view.
        let grid = collection.superview?.bounds ?? .zero
        let frames = (0..<collection.numberOfItems(inSection: 0)).compactMap { collection.item(at: IndexPath(item: $0, section: 0))?.view.frame }
        check("the cards stay inside the grid's column", collection.frame.size == grid.size && !frames.isEmpty && frames.allSatisfy { $0.maxX <= grid.width + 0.5 },
              "grid \(Int(grid.width)), collection \(Int(collection.frame.width)), right edges \(frames.map { Int($0.maxX) })")
        // Every face takes its click: a card past the grid's edge shows, but AppKit sends it nothing.
        let missed = (0..<collection.numberOfItems(inSection: 0)).filter { index in
            guard let card = collection.item(at: IndexPath(item: index, section: 0))?.view else { return true }
            card.scrollToVisible(card.bounds.insetBy(dx: 0, dy: -Driver.overlayClearance))
            ui.window.layoutIfNeeded()
            let face = SessionGrid.CardView.face
            let point = card.convert(NSPoint(x: face.midX, y: card.isFlipped ? face.midY : card.bounds.height - face.midY), to: nil)
            return ui.hitView(point) !== card
        }
        check("every card's face takes its click", missed.isEmpty, "missed cards \(missed)")
        check("cards take the click that brings HQ forward", ui.takesFirstClick(ui.cardPoint(first.id)))
        await ui.click(ui.cardPoint(first.id))
        await ui.settle(0.5)
        tableCheck(ui, "a click on a card selects it and opens nothing", model.modal == nil && model.selectedSession == first.id,
                   "\(String(describing: model.modal))")
        let running = model.gridSessions.first { $0.tty != nil && $0.isRunning }!
        let before = model.ghosttyLog.count
        await ui.click(ui.cardPoint(running.id), count: 2)
        await ui.settle(0.6)
        tableCheck(ui, "a double-click on a card opens its modal, not Ghostty", model.modal == .session(running.id) && model.ghosttyLog.count == before,
                   "\(model.ghosttyLog.count - before) calls, modal \(String(describing: model.modal))")
        model.closeModal()

        // Reorder: the card dropped before the first one goes first, the others keep their order.
        let order = model.gridSessions.map(\.id)
        let moving = order[3]
        let info = FakeDrag(session: moving, source: collection)
        let accepted = validate(coordinator, collection, info, item: 0, operation: .before)
        check("a card dragged over the grid is a move", accepted.0 == .move)
        await endUndoGroup(model)
        _ = coordinator.collectionView(collection, acceptDrop: info, indexPath: IndexPath(item: 0, section: 0), dropOperation: .before)
        await endUndoGroup(model)
        await ui.settle(0.4)
        check("a dropped card lands where it was dropped", model.gridSessions.map(\.id) == [moving] + order.filter { $0 != moving },
              "\(model.gridSessions.map { $0.id.prefix(4) })")
        check("the grid shows the new order without a reload", coordinator.ids == model.gridSessions.map(\.id))
        model.undoManager?.undo()
        await ui.settle(0.4)
        check("Undo Move Session puts it back", model.gridSessions.map(\.id) == order)

        // A task dropped on a card links to that session.
        guard let task = model.addTask(to: .overview, title: "Link me") else { return check("a task to drop", false) }
        await endUndoGroup(model)
        await ui.settle(0.3)
        let taskDrag = FakeDrag(tasks: [task.id], source: nil)
        let link = validate(coordinator, collection, taskDrag, item: 1, operation: .before)
        check("a task over a card proposes a link onto it", link.0 == .link && link.1 == .on)
        collection.draggingExited(taskDrag)
        check("a task dragged off the grid leaves no card highlighted", coordinator.dropTarget == nil)
        _ = validate(coordinator, collection, taskDrag, item: 1, operation: .before)
        _ = coordinator.collectionView(collection, acceptDrop: taskDrag, indexPath: IndexPath(item: 1, section: 0), dropOperation: .on)
        await endUndoGroup(model)
        check("a task dropped on a card works on its session", model.task(task.id)?.sessions == [model.gridSessions[1].id])
        let action = model.undoManager?.undoActionName ?? "-"
        model.undoManager?.undo()
        await ui.settle(0.2)
        check("Undo unlinks it", model.task(task.id)?.sessions.isEmpty == true, "undid \(action)")
        coordinator.dragEnded()

        // A running session stays on the grid: its menu has no Hide.
        let cardMenu = coordinator.menu(at: ui.cardLocal(collection, 0))
        cardMenu?.update()
        let titles = cardMenu?.items.map(\.title) ?? []
        check("a card has a context menu, with no Hide", titles.contains("Show Details") && !titles.contains { $0.hasPrefix("Hide") }, titles.joined(separator: ", "))
        model.deleteTasks([task.id])
    }

    /// One selection on the page: a click in a section unselects the others, a click on nothing unselects all;
    /// a click on a card's face shows the card's menu.
    static func pageSelection(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator,
              let collection = ui.find(SessionGrid.CardCollection.self), let grid = collection.delegate as? SessionGrid.Coordinator,
              let pr = model.reviewRequests.first ?? model.ownPullRequests.first,
              let task = model.addTask(to: .overview, title: "Select me") else { return check("a task, a card and a PR to select", false) }
        await endUndoGroup(model)
        await ui.settle(0.4)
        coordinator.select(task.id)
        await ui.settle(0.3)
        check("a selected row gives the tasks the page's selection", model.selectedSection == .tasks && model.selectedTasks == [task.id],
              "\(String(describing: model.selectedSection))")
        let prKey = ModalRoute.github(pr.url).selectionKey
        await ui.click(ui.anchor("pr:\(pr.number)"))
        await ui.until { model.selectedItem == prKey && outline.selectedRowIndexes.isEmpty }
        tableCheck(ui, "a click on a PR selects it, and the task's row unselects", model.selectedItem == prKey && model.selectedSection == .pullRequests
                   && outline.selectedRowIndexes.isEmpty, "\(model.selectedItem ?? "-"), \(outline.selectedRowIndexes.count) rows")
        // What the click does, for a background run, whose SwiftUI rows take no synthetic clicks.
        model.selectedItem = prKey
        model.selectSection(.pullRequests)
        await ui.until { outline.selectedRowIndexes.isEmpty }
        check("a PR taking the selection unselects the task's row", outline.selectedRowIndexes.isEmpty && model.selectedTasks.isEmpty,
              "\(outline.selectedRowIndexes.count) rows")
        _ = ui.cardPoint(grid.ids[0])
        grid.collectionView(collection, didSelectItemsAt: [IndexPath(item: 0, section: 0)])
        await ui.settle(0.3)
        check("a card selected unselects the PR", model.selectedSession == grid.ids[0] && model.selectedItem == nil && model.selectedSection == .sessions,
              model.selectedItem ?? "-")
        // The Sessions header, between its title and its buttons: nothing there.
        let gridFrame = collection.convert(collection.bounds, to: nil)
        await ui.click(NSPoint(x: gridFrame.midX, y: gridFrame.maxY + Space.md + 12))
        await ui.until { model.selectedSession == nil }
        tableCheck(ui, "a click on nothing unselects everything", model.selectedSession == nil && model.selectedItem == nil && model.selectedSection == nil
                   && collection.selectionIndexPaths.isEmpty, "\(model.selectedSession ?? "-") \(String(describing: model.selectedSection))")
        model.selectSection(nil)
        await ui.settle(0.3)
        check("with nothing selected, no card stays selected", model.selectedSession == nil && collection.selectionIndexPaths.isEmpty)
        model.selectedItem = ModalRoute.github(pr.url).chipKey(task: task.id)
        check("a link chip under a task is selected apart from its row in Pull Requests", model.selectedItem != prKey
              && AppModel.section(ofItem: model.selectedItem ?? "") == .tasks)
        model.selectedItem = nil

        // A click on a card's face focuses its session at once, with no menu.
        var shown: String?
        let showMenu = FaceMenu.show
        FaceMenu.show = { _, id, _, _ in shown = id }
        func facePoint() -> NSPoint? {
            guard let card = collection.item(at: IndexPath(item: 0, section: 0))?.view else { return nil }
            card.scrollToVisible(card.bounds)
            let local = NSPoint(x: Space.md + Metric.faceCard / 2, y: Space.md + Metric.faceCard / 2)
            return card.convert(card.isFlipped ? local : NSPoint(x: local.x, y: card.bounds.height - local.y), to: nil)
        }
        func press(_ point: NSPoint, clicks: Int) async {
            guard let down = ui.mouseDown(point, clicks: clicks),
                  let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: ui.window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 0) else { return }
            // The window never saw this press: the release goes to the grid directly, after any it tracked itself.
            NSApp.postEvent(up, atStart: false)
            collection.mouseDown(with: down)
            collection.mouseUp(with: up)
            await ui.settle(0.05)
        }
        if let point = facePoint() {
            let logged = model.ghosttyLog.count
            await press(point, clicks: 1)
            check("a click on a card's face focuses its session, no menu", shown == nil && model.ghosttyLog.count > logged,
                  "\(shown ?? "no menu"), \(model.ghosttyLog.suffix(1))")
            let card = collection.item(at: IndexPath(item: 0, section: 0))?.view as? SessionGrid.CardView
            check("the card tracks the pointer for the hand over its face", card?.handOverFace == true)
        } else {
            check("the first card's face", false)
        }
        FaceMenu.show = showMenu
        model.deleteTasks([task.id])
        await endUndoGroup(model)
    }

    /// A file or a PR dragged onto a task's row links it there.
    static func linkDrops(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator,
              let target = model.addTask(to: .overview, title: "Drop a link here"),
              let file = model.addFile(title: "Dragged note", body: "# Dragged note\n", session: nil, task: nil) else {
            return check("a task and a file to drop on it", false)
        }
        await endUndoGroup(model)
        await ui.settle(0.4)
        let row = coordinator.node(.task(target.id))
        let drag = FakeDrag(item: ModalRoute.file(file.id).selectionKey, source: nil)
        let proposed = coordinator.outlineView(outline, validateDrop: drag, proposedItem: row, proposedChildIndex: NSOutlineViewDropOnItemIndex)
        check("a file dragged onto a task's row proposes a link", proposed == .link)
        _ = coordinator.outlineView(outline, acceptDrop: drag, item: row, childIndex: NSOutlineViewDropOnItemIndex)
        await endUndoGroup(model)
        await ui.settle(0.4)
        check("dropped, it links to that task and shows under its row", model.isLinked(.file(file.id), to: target.id)
              && model.outputs(ofTask: target.id).contains(.file(file.id)))
        check("dragged there again, it's refused", coordinator.outlineView(outline, validateDrop: drag, proposedItem: row,
                                                                          proposedChildIndex: NSOutlineViewDropOnItemIndex) == [])
        model.undoManager?.undo()
        await ui.settle(0.3)
        check("Undo unlinks it", !model.isLinked(.file(file.id), to: target.id))
        // A click on a link's chip under the row shows its menu: Open, Unlink, Delete for a file.
        model.link(.file(file.id), to: target.id)
        await endUndoGroup(model)
        await ui.settle(0.4)
        let menu = model.linkMenu(.file(file.id), task: target.id)
        menu.update()
        let titles = menu.items.map(\.title)
        check("a linked file's menu has Open, Unlink and Delete", titles.contains("Open") && titles.contains("Unlink from T-\(target.id)")
              && titles.contains("Delete"), titles.joined(separator: ", "))
        let chip = ModalRoute.file(file.id).chipKey(task: target.id)
        var shown: String?
        var shownMenu: NSMenu?
        let showMenu = FaceMenu.show
        FaceMenu.show = { menu, id, _, _ in shown = id; shownMenu = menu }
        // The links' SwiftUI view hands a right-click on to the outline, which shows the link's menu.
        if let outline = ui.find(TaskOutlineView.self), let point = ui.anchor(chip),
           let down = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                         windowNumber: ui.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
            outline.rightMouseDown(with: down)
        }
        shownMenu?.update()
        check("a right-click on a link's chip under its task shows the link's menu", shown == chip
                   && shownMenu?.items.contains { $0.title == "Unlink from T-\(target.id)" } == true, shown ?? "no menu")
        // A Control-click on the chip gives the link's menu too; on the title, the task's.
        if let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator,
           let cell = outline.view(atColumn: 1, row: outline.row(forItem: coordinator.node(.task(target.id))), makeIfNecessary: false) as? TaskCell {
            func menu(at point: NSPoint?) -> [String] {
                guard let point, let down = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                                               windowNumber: ui.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
                      let menu = outline.menu(for: down) else { return [] }
                menu.update()
                return menu.items.map(\.title)
            }
            check("a Control-click on a link's chip gives the link's menu", menu(at: ui.anchor(chip)).contains("Unlink from T-\(target.id)"))
            let title = menu(at: cell.title.convert(NSPoint(x: cell.title.bounds.midX, y: cell.title.bounds.midY), to: nil))
            check("on the task's title, the task's menu", !title.isEmpty && !title.contains("Unlink from T-\(target.id)"), title.joined(separator: ", "))
        }
        FaceMenu.show = showMenu
        // A click selects the chip; a double-click opens it.
        model.selectedItem = nil
        await ui.click(ui.anchor(chip))
        tableCheck(ui, "a click on a link's chip selects it", model.selectedItem == chip, model.selectedItem ?? "-")
        await ui.click(ui.anchor(chip), count: 2)
        tableCheck(ui, "a double-click on a link's chip opens it", model.modal == .file(file.id), String(describing: model.modal))
        model.closeModal()
        await ui.settle(0.5)
        // Deleted while the task's modal lists it, the file leaves the list.
        model.open(.task(target.id))
        await ui.settle(0.8)
        let listed = "row:" + ModalRoute.file(file.id).selectionKey
        check("the task's modal lists its linked file", ui.anchor(listed) != nil)
        model.deleteFile(file.id)
        await endUndoGroup(model)
        await ui.settle(0.6)
        check("a file deleted while the task's modal is open leaves its list", ui.anchor(listed) == nil)
        model.undoManager?.undo()
        await ui.settle(0.5)
        // Deleted from its own modal, opened from the task's: the task's modal shows again, without it.
        model.open(.file(file.id), push: true)
        await ui.settle(0.6)
        model.deleteFile(file.id)
        await endUndoGroup(model)
        await ui.settle(0.6)
        check("a file deleted from its modal goes back to the task's", model.modal == .task(target.id) && model.modalStack.isEmpty
              && ui.anchor(listed) == nil, String(describing: model.modal))
        model.closeModal()
        await ui.settle(0.6)
        if let pr = model.ownPullRequests.first {
            let prDrag = FakeDrag(item: ModalRoute.github(pr.url).selectionKey, source: nil)
            _ = coordinator.outlineView(outline, validateDrop: prDrag, proposedItem: row, proposedChildIndex: NSOutlineViewDropOnItemIndex)
            _ = coordinator.outlineView(outline, acceptDrop: prDrag, item: row, childIndex: NSOutlineViewDropOnItemIndex)
            await ui.settle(0.3)
            check("a PR dropped on a task's row links it", model.task(target.id)?.links.map(\.absoluteString).contains(pr.url) == true)
        }
        model.deleteTasks([target.id])
        await endUndoGroup(model)
        await ui.settle(0.3)
    }

    /// Last, as they move the page and the keyboard: a task whose last subtask goes loses its disclosure; Tab scrolls into view.
    static func lateChecks(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator else { return check("the outline is on the page", false) }
        // Every section folds to its header: Tab passes a folded one, Tasks keeps only its header.
        if model.hasRows(.files) {
            model.folded = [.files]
            await ui.settle(0.4)
            check("a folded section has no rows for Tab", !model.hasRows(.files) && model.moveSection(from: .sessions, by: 1) != .files)
            model.folded = []
            await ui.settle(0.3)
        }
        model.folded = [.tasks]
        await ui.settle(0.5)
        let header = coordinator.node(.header(.overview))
        check("folded, Tasks shows its header and no rows", outline.row(forItem: header) >= 0 && outline.numberOfChildren(ofItem: header) == 0)
        model.focusQuickAdd(.overview)
        await ui.settle(0.5)
        check("New Task unfolds Tasks", !model.folded.contains(.tasks) && outline.numberOfChildren(ofItem: header) > 0)
        model.quickAddFocus = nil
        model.selectSection(nil)
        await ui.settle(0.3)
        if let parent = model.addTask(to: .overview, title: "Parent of one"), let child = model.addSubtask(to: parent.id, title: "Only child") {
            await endUndoGroup(model)
            await ui.settle(0.5)
            let had = outline.isExpandable(coordinator.node(.task(parent.id)))
            model.deleteTasks([child.id])
            await endUndoGroup(model)
            await ui.settle(0.5)
            check("a task whose last subtask is deleted loses its disclosure", had && !outline.isExpandable(coordinator.node(.task(parent.id))))
            model.deleteTasks([parent.id])
            await endUndoGroup(model)
        }
        // Tab to Pull Requests from the bottom of the page brings the selected row into view.
        if let scroll = outline.enclosingScrollView {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max((scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height, 0)))
            scroll.reflectScrolledClipView(scroll.contentView)
            await ui.settle(0.3)
            model.parkedItems[.pullRequests] = nil
            model.selectedItem = nil
            model.moveSection(from: .tasks, by: 1)
            await ui.until { model.selectedItem?.hasPrefix("github:") == true }
            await ui.settle(0.5)
            let row = model.selectedItem.flatMap { key in model.githubItem(String(key.dropFirst("github:".count))) }
            let view = row.flatMap { UITest.anchors["pr:\($0.number)", default: []].compactMap(\.view).last }
            check("Tab to Pull Requests from far down the page scrolls its selected row into view", view.map { !$0.visibleRect.isEmpty } == true,
                  model.selectedItem ?? "-")
            // The keyboard goes back to the outline, as the next checks expect.
            model.selectSection(nil)
            ui.window.makeFirstResponder(outline)
            await ui.settle(0.3)
        }
    }

    /// A task folded when the rows load opens from its disclosure with its subtasks and the rows below in the
    /// outline's frame and clickable; so does a task above it.
    static func disclosures(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator else { return check("the outline is on the page", false) }
        model.folded = []
        model.search = ""
        guard let above = model.addTask(to: .overview, title: "Caret above"), let parent = model.addTask(to: .overview, title: "Caret parent") else {
            return check("tasks for the carets", false)
        }
        await endUndoGroup(model)
        await ui.settle(0.5)
        /// The task's disclosure shows, on its title's line, just before its status glyph.
        func caret(_ id: Int) async -> (ok: Bool, detail: String) {
            let row = outline.row(forItem: coordinator.node(.task(id)))
            if row >= 0 { outline.scrollRowToVisible(row) }
            await ui.settle(0.2)
            guard row >= 0, let rowView = outline.rowView(atRow: row, makeIfNecessary: false),
                  let cell = outline.view(atColumn: 1, row: row, makeIfNecessary: false) as? TaskCell else { return (false, "no row") }
            func buttons(_ view: NSView) -> [NSButton] {
                view.subviews.flatMap { ($0 as? NSButton).map { [$0] } ?? [] + buttons($0) }
            }
            guard let button = buttons(rowView).first(where: { $0.identifier?.rawValue.contains("Disclosure") == true }) else { return (false, "no disclosure") }
            let disclosure = button.convert(button.bounds, to: nil)
            let glyph = cell.glyph.convert(cell.glyph.bounds, to: nil)
            let ok = !button.isHidden && button.alphaValue > 0 && abs(disclosure.midY - glyph.midY) < 1.5
                && disclosure.maxX <= glyph.minX + 1 && glyph.minX - disclosure.maxX < Space.md
            return (ok, "disclosure \(disclosure.integral) glyph \(glyph.integral)")
        }
        guard let child = model.addSubtask(to: parent.id, title: "Caret child") else { return check("a subtask", false) }
        await endUndoGroup(model)
        await ui.settle(0.6)
        var result = await caret(parent.id)
        check("a task's first subtask brings its disclosure, on its line", result.ok, result.detail)
        model.indentTasks([parent.id])
        await endUndoGroup(model)
        await ui.settle(0.6)
        result = await caret(parent.id)
        check("indented with its subtasks, its disclosure stays on its line", result.ok, result.detail)
        result = await caret(above.id)
        check("and its new parent gets one on its line", result.ok, result.detail)
        model.outdentTasks([parent.id])
        await endUndoGroup(model)
        await ui.settle(0.6)
        result = await caret(parent.id)
        check("outdented, its disclosure stays on its line", result.ok, result.detail)
        model.toggleList(parent.id)
        await endUndoGroup(model)
        await ui.settle(0.6)
        model.backlogOpen = true
        await ui.settle(0.4)
        result = await caret(parent.id)
        check("moved to the Backlog, it keeps its disclosure on its line", result.ok, result.detail)
        model.toggleList(parent.id)
        await endUndoGroup(model)
        await ui.settle(0.6)
        result = await caret(parent.id)
        check("and back in Tasks too", result.ok, result.detail)
        // Shut in the outline while the model has it open: the outline opens it again, its subtask back.
        let repairs = OutlineCoordinator.repairs
        outline.collapseItem(coordinator.node(.task(parent.id)))
        model.setCollapsed(parent.id, false)
        await ui.settle(0.6)
        check("a task open in the model but shut in the outline opens again with its subtasks",
              OutlineCoordinator.repairs > repairs && outline.isItemExpanded(coordinator.node(.task(parent.id)))
              && outline.row(forItem: coordinator.node(.task(child.id))) >= 0, "\(OutlineCoordinator.repairs - repairs) repairs")
        OutlineCoordinator.repairs = repairs
        // ⇧-arrows held down never take a task out of its parent; a press still does.
        coordinator.select(child.id)
        await ui.settle(0.3)
        await ui.key(.left, .shift, held: true)
        await ui.key(.down, .shift, held: true)
        await ui.settle(0.4)
        check("held ⇧← and ⇧↓ leave a subtask in its parent", model.taskTree.parent(of: child.id) == parent.id,
              "parent \(String(describing: model.taskTree.parent(of: child.id)))")
        await ui.key(.down, .shift)
        await ui.settle(0.4)
        check("a press of ⇧↓ on the last subtask still takes it out", model.taskTree.parent(of: child.id) == nil)
        model.undoManager?.undo()
        await ui.settle(0.4)
        model.deleteTasks([child.id, parent.id, above.id])
        await endUndoGroup(model)
        await ui.settle(0.3)
    }

    /// A click on a PR's face, in Reviews and in Yours, shows its session's menu under the face, an ended session's too.
    static func prFaces(_ model: AppModel, _ ui: Driver) async {
        guard let ended = model.sessions.first(where: { !$0.isRunning }) else { return check("an ended session", false) }
        let show = FaceMenu.show
        defer { FaceMenu.show = show }
        for (group, pr) in [("Reviews", model.reviewRequests.first), ("Yours", model.ownPullRequests.first)] {
            guard let pr else { check("a PR in \(group)", false); continue }
            let before = model.sessions(onPullRequest: pr, includeEnded: true).map(\.id)
            for id in before where id != ended.id { if var item = model.session(id) { item.links.removeAll { $0 == pr.url }; model.put(item) } }
            model.link(pullRequest: pr.url, session: ended.id)
            await ui.settle(0.4)
            let first = model.byImportance(model.sessions(onPullRequest: pr, includeEnded: true)).first?.id
            var shown: (id: String, menu: NSMenu, view: NSView?)?
            FaceMenu.show = { menu, id, _, view in shown = (id, menu, view) }
            let point = ui.anchor("pr-face:\(pr.number)")
            let hit = point.flatMap { ui.hitView($0) }
            await ui.click(point)
            await ui.settle(0.3)
            shown?.menu.update()
            let titles = shown?.menu.items.map(\.title) ?? []
            check("a click on a PR's face in \(group) shows its session's menu under the face, not Start Session",
                  shown?.id == first && shown?.view != nil && model.modal == nil,
                  "shown \(shown?.id ?? "-"), first \(first ?? "-"), hit \(hit.map { String(describing: type(of: $0)) } ?? "-"), \(String(describing: model.modal))")
            check("its menu starts another session on the PR", titles.contains { $0.hasPrefix("Start Another Session on \(pr.reference)") },
                  titles.joined(separator: ", "))
            if model.modal != nil { model.closeModal(); await ui.settle(0.5) }
            if var item = model.session(ended.id) { item.links.removeAll { $0 == pr.url }; model.put(item) }
        }
    }

    /// The bell opens the center; a chip opens its item over it and Back returns; Read acts on a selected row; Remind Me… shows its form.
    static func notificationCenter(_ model: AppModel, _ ui: Driver) async {
        model.closeModal()
        await ui.settle(0.5)
        let bell = ui.anchor("bell")
        check("the toolbar has the bell, breathing while something needs the user", bell != nil && model.bellBreathes)
        // The toolbar's hand is AppKit's: it shows on entering an item and leaves with the pointer.
        func hands(_ view: NSView?) -> [ToolbarHandView] {
            guard let view else { return [] }
            return ((view as? ToolbarHandView).map { [$0] } ?? []) + view.subviews.flatMap(hands)
        }
        let toolbarHands = hands(ui.window.contentView?.superview)
        if let hand = toolbarHands.first, let event = ui.mouseDown(.zero, clicks: 1) {
            hand.mouseEntered(with: event)
            let entered = NSCursor.current == NSCursor.pointingHand
            hand.mouseExited(with: event)
            check("the bell and New show the pointing hand, and leaving them gives the arrow back",
                  toolbarHands.count == 2 && toolbarHands.allSatisfy { $0.trackingAreas.contains { $0.options.contains(.cursorUpdate) } }
                  && entered && NSCursor.current == NSCursor.arrow, "\(toolbarHands.count) hands, entered \(entered)")
        } else {
            check("the toolbar's items track the pointing hand", false, "\(toolbarHands.count) hands")
        }
        await ui.click(bell)
        await ui.until(2) { model.modal == .notifications }
        check("a click on the bell opens the center", model.modal == .notifications, "\(String(describing: model.modal))")
        check("and the bell stops breathing", !model.bellBreathes)
        check("a session that waits shows in Needs You with Focus", model.blockedSessions.allSatisfy { ui.anchor("blocked:\($0.id)") != nil })
        guard let row = model.notices(in: .updates).first(where: { $0.readAt == nil && !$0.links.isEmpty }) else { return check("an update with links", false) }
        let link = row.links[0]
        let chip = await ui.steadyAnchor("notice-chip:\(row.id.uuidString):\(link)")
        check("a row shows its links as chips", chip != nil, link)
        await ui.click(chip, inSheet: true)
        await ui.until(2) { model.modal != .notifications }
        check("a chip opens its item over the center", model.modal == ModalRoute(noticeKey: link) && model.modalStack.last == .notifications,
              "\(String(describing: model.modal)) over \(model.modalStack)")
        check("and reads its row", model.notices.first { $0.id == row.id }?.readAt != nil)
        await ui.back()
        await ui.until(2) { model.modal == .notifications }
        check("Back returns to the center", model.modal == .notifications, "\(String(describing: model.modal))")
        check("where the row read stays in place", model.notices(in: .updates).contains { $0.id == row.id })
        model.noticeSelection = row.id.uuidString
        await ui.settle(0.3)
        check("and keeps its actions: Mark as Unread shows on it", ui.anchor("read:\(row.id.uuidString)") != nil)

        // A long text: two lines at rest, all of it once selected.
        if let long = model.notices(in: .updates).first(where: { $0.text.count > 200 }) {
            model.noticeSelection = nil
            await ui.settle(0.3)
            let rest = ui.anchorFrame("notice:\(long.id.uuidString)")?.height ?? 0
            model.noticeSelection = long.id.uuidString
            await ui.settle(0.3)
            let open = ui.anchorFrame("notice:\(long.id.uuidString)")?.height ?? 0
            check("a selected row shows its whole text", open > rest + Space.sm, "\(rest) → \(open)")
        } else {
            check("an update with a long text", false)
        }
        if let other = model.notices(in: .updates).first(where: { $0.readAt == nil }) {
            // Selected, as a click or the arrows select it: its Read shows.
            model.noticeSelection = other.id.uuidString
            await ui.settle(0.3)
            await ui.click(await ui.steadyAnchor("read:\(other.id.uuidString)"), inSheet: true)
            await ui.settle(0.3)
            check("Read on a selected row reads it", model.notices.first { $0.id == other.id }?.readAt != nil)
        } else {
            check("a second unread update", false)
        }

        // A due reminder: what it links opens over the center and it stays to be done, with its actions.
        let task = model.addTask(to: .overview, title: "Reminder's task")
        let due = model.remind("Check the canary", at: .now.addingTimeInterval(-1), level: .important, links: task.map { ["task:\($0.id)"] } ?? [])
        model.fireDue()
        await ui.settle(0.4)
        if let task {
            await ui.click(await ui.steadyAnchor("notice-chip:\(due.id.uuidString):task:\(task.id)"), inSheet: true)
            await ui.until(2) { model.modal == .task(task.id) }
            check("a reminder's link opens over the center", model.modal == .task(task.id), "\(String(describing: model.modal))")
            check("and leaves the reminder to be done", model.notices.first { $0.id == due.id }?.readAt == nil)
            await ui.back()
            await ui.until(2) { model.modal == .notifications }
        }
        model.noticeSelection = due.id.uuidString
        await ui.settle(0.3)
        check("a due reminder stays in Needs You with Edit, Later and Done", model.notices(in: .needsYou).contains { $0.id == due.id }
              && ["edit", "later", "read"].allSatisfy { ui.anchor("\($0):\(due.id.uuidString)") != nil })
        await ui.click(await ui.steadyAnchor("read:\(due.id.uuidString)"), inSheet: true)
        await ui.settle(0.3)
        check("Done completes it, in place", model.notices.first { $0.id == due.id }?.readAt != nil && model.notices(in: .needsYou).contains { $0.id == due.id })

        // Editing a reminder: its row turns into the editor, filled in; Important and Save change it.
        let waiting = model.remind("Call the bank", at: .now.addingTimeInterval(7200), level: .important)
        await ui.settle(0.4)
        model.noticeSelection = waiting.id.uuidString
        await ui.settle(0.3)
        await ui.click(await ui.steadyAnchor("edit:\(waiting.id.uuidString)"), inSheet: true)
        await ui.settle(0.4)
        func fields(_ view: NSView?) -> [NSTextField] {
            guard let view else { return [] }
            let own: [NSTextField] = (view as? NSTextField).map { [$0] } ?? []
            return own + view.subviews.flatMap(fields)
        }
        let filled = fields(ui.window.attachedSheet?.contentView).first { $0.placeholderString == "Remind me to…" }
        check("Edit turns a reminder into its editor, filled in", ui.anchor("reminder-text") != nil && filled?.stringValue == "Call the bank",
              filled?.stringValue ?? "no field")
        await ui.click(await ui.steadyAnchor("reminder-important"), inSheet: true)
        await ui.click(await ui.steadyAnchor("reminder-add"), inSheet: true)
        await ui.settle(0.4)
        check("and Save keeps what changed", model.notices.first { $0.id == waiting.id }?.level == .update && ui.anchor("reminder-text") == nil)

        // The When picker: the time of a row in Later opens it; a choice sets the time.
        model.noticeSelection = waiting.id.uuidString
        await ui.settle(0.3)
        await ui.click(await ui.steadyAnchor("due:\(waiting.id.uuidString)"), inSheet: true)
        await ui.settle(0.6)
        if await ui.clickInPopover("when:tomorrow") {
            check("a choice in the When picker sets the time", model.notices.first { $0.id == waiting.id }?.dueAt == ReminderTime.date(.tomorrow))
        } else {
            skip("a choice in the When picker sets the time")
        }

        await ui.click(ui.anchor("remind-me"), inSheet: true)
        await ui.settle(0.5)
        check("Remind Me… shows the editor", model.composingReminder && ui.anchor("reminder-text") != nil && ui.anchor("reminder-when") != nil)
        model.composingReminder = false
        model.markAllRead()
        await ui.settle(0.3)
        check("Mark All Read leaves nothing unread but due reminders and the sessions that wait", model.updateCount == 0
              && model.importantCount == model.blockedSessions.count + model.notices.filter { $0.kind == .reminder && $0.level == .important && $0.readAt == nil && $0.dueAt == nil }.count)
        model.closeModal()
        await ui.settle(0.5)
        check("once the center closes, what was read is in Earlier", model.notices(in: .earlier).contains { $0.id == row.id })
        model.openCenter()
        await ui.settle(0.6)
        check("and Earlier shows, open, with the reminder just done", ui.anchor("notice:\(due.id.uuidString)") != nil)
        model.closeModal()
        if let task { model.deleteTasks([task.id]) }
        await ui.settle(0.3)
    }

    /// With one session on the grid, a real click on its face focuses it, its card selected or not.
    static func singleSessionFace(_ model: AppModel, _ ui: Driver) async {
        guard let collection = ui.find(SessionGrid.CardCollection.self), let grid = collection.delegate as? SessionGrid.Coordinator,
              let only = grid.ids.first else { return check("a session card", false) }
        let others = grid.ids.dropFirst()
        // The others closed a moment: one card left.
        func close(_ closed: Bool) { for id in others { if var item = model.session(id) { item.closedAt = closed ? .now : nil; model.put(item) } } }
        close(true)
        await ui.settle(0.6)
        check("one card left on the grid", grid.ids == [only], "\(grid.ids.count) cards")
        func faceClick() async -> Bool {
            guard let card = collection.item(at: IndexPath(item: 0, section: 0))?.view else { return false }
            card.scrollToVisible(card.bounds.insetBy(dx: 0, dy: -Driver.overlayClearance))
            ui.window.layoutIfNeeded()
            let local = NSPoint(x: Space.md + Metric.faceCard / 2, y: Space.md + Metric.faceCard / 2)
            let point = card.convert(card.isFlipped ? local : NSPoint(x: local.x, y: card.bounds.height - local.y), to: nil)
            let logged = model.ghosttyLog.count
            await ui.click(point)
            await ui.settle(0.3)
            return model.ghosttyLog.count > logged
        }
        model.selectSection(nil)
        collection.deselectAll(nil)
        await ui.settle(0.3)
        tableCheck(ui, "the only card's face, unselected, focuses its session", await faceClick(), "\(model.ghosttyLog.suffix(1))")
        grid.collectionView(collection, didSelectItemsAt: [IndexPath(item: 0, section: 0)])
        collection.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
        await ui.settle(0.3)
        tableCheck(ui, "selected, its face still focuses its session", await faceClick(), "\(model.ghosttyLog.suffix(1))")
        close(false)
        model.selectSection(nil)
        await ui.settle(0.4)
    }

    /// A row's description toggle sits after its title, the hover actions don't repeat it; the grip and the dot keep apart.
    static func rowControls(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator else { return check("the outline is on the page", false) }
        model.folded = []
        model.search = ""
        model.allDescriptions = []
        guard let plain = model.addTask(to: .overview, title: "No description"),
              let noted = model.addTask(to: .overview, title: "With a description", body: "Some words.") else { return check("tasks for the toggle", false) }
        await endUndoGroup(model)
        await ui.settle(0.5)
        func row(_ id: Int) async -> (row: OutlineRowView, cell: TaskCell, faces: FacesCell)? {
            let index = outline.row(forItem: coordinator.node(.task(id)))
            guard index >= 0 else { return nil }
            outline.scrollRowToVisible(index)
            await ui.settle(0.2)
            guard let row = outline.rowView(atRow: index, makeIfNecessary: false) as? OutlineRowView,
                  let cell = outline.view(atColumn: 1, row: index, makeIfNecessary: false) as? TaskCell,
                  let faces = outline.view(atColumn: 0, row: index, makeIfNecessary: false) as? FacesCell else { return nil }
            return (row, cell, faces)
        }
        guard let quiet = await row(plain.id), let full = await row(noted.id) else { return check("the rows are on the page", false) }
        check("a task with a description shows its toggle at rest", !full.cell.note.isHidden && full.cell.note.toolTip?.hasPrefix("Show") == true)
        check("a task without one doesn't", quiet.cell.note.isHidden)
        quiet.cell.setHovered(true)
        quiet.faces.setHovered(true)
        quiet.cell.layoutSubtreeIfNeeded()
        quiet.faces.layoutSubtreeIfNeeded()
        let hoverActions = quiet.cell.subviews.compactMap { $0 as? NSButton }.filter { !$0.isHidden && $0 !== quiet.cell.note }
        check("under the pointer it shows, to write one", !quiet.cell.note.isHidden && quiet.cell.note.toolTip?.hasPrefix("Write") == true)
        check("the hover actions don't repeat it", !hoverActions.contains { $0.toolTip?.contains("description") == true },
              hoverActions.compactMap(\.toolTip).joined(separator: ", "))
        quiet.cell.setHovered(false)
        quiet.faces.setHovered(false)
        // A click on the toggle shows the description; it turns accent and hides it again.
        full.cell.note.performClick(nil)
        await ui.settle(0.4)
        check("its toggle shows the description", model.descriptionShownInOutline(noted.id))
        if let again = await row(noted.id) {
            check("shown, its toggle stays, to hide it", !again.cell.note.isHidden && again.cell.note.toolTip?.hasPrefix("Hide") == true)
            again.cell.note.performClick(nil)
            await ui.settle(0.4)
            check("and hides it", !model.descriptionShownInOutline(noted.id))
        }
        // Shown by the list's Descriptions, the toggle hides that one.
        model.allDescriptions = [.overview]
        await ui.settle(0.4)
        if let listed = await row(noted.id) {
            listed.cell.note.performClick(nil)
            await ui.settle(0.4)
            check("with Descriptions on, the toggle hides that one", !model.descriptionShownInOutline(noted.id))
            model.toggleDescription(noted.id)
            check("and shows it again", model.descriptionShownInOutline(noted.id))
        }
        model.allDescriptions = []
        model.deleteTasks([plain.id, noted.id])
        await endUndoGroup(model)
        await ui.settle(0.3)
    }

    static func foldedParentOpens(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator,
              let container = outline.superview as? OutlineContainer else { return check("the outline is on the page", false) }
        model.folded = []
        model.search = ""
        guard let above = model.addTask(to: .overview, title: "Fold above"), let parent = model.addTask(to: .overview, title: "Fold parent") else {
            return check("tasks to fold", false)
        }
        for index in 0..<3 { _ = model.addSubtask(to: above.id, title: "Above \(index)") }
        var subtasks: [Int] = []
        for index in 0..<16 { if let task = model.addSubtask(to: parent.id, title: "Subtask \(index)") { subtasks.append(task.id) } }
        if subtasks.count > 4 { _ = model.addSubtask(to: subtasks[4], title: "Deep") }
        var below: [Int] = []
        for index in 0..<4 { if let task = model.addTask(to: .overview, title: "Below \(index)") { below.append(task.id) } }
        await endUndoGroup(model)
        await ui.settle(0.6)
        // As at launch: the rows load again with both parents folded.
        model.setCollapsed(above.id, true)
        model.setCollapsed(parent.id, true)
        model.folded = [.tasks]
        await ui.settle(0.6)
        model.folded = []
        await ui.settle(0.8)
        var problems: [String] = []
        func fits(_ step: String) async {
            if container.frame.height + 0.5 < container.contentHeight {
                problems.append("\(step): frame \(Int(container.frame.height)) rows \(Int(container.contentHeight))")
            }
            if outline.frame.height + 0.5 < container.contentHeight {
                problems.append("\(step): outline \(Int(outline.frame.height)) rows \(Int(container.contentHeight))")
            }
            for id in [subtasks.last, below.last].compactMap({ $0 }) where outline.row(forItem: coordinator.node(.task(id))) >= 0 {
                // The page takes a moment to follow a scroll.
                _ = ui.titlePoint(id)
                await ui.settle(0.3)
                guard let point = ui.titlePoint(id), let hit = ui.hitView(point), hit.isDescendant(of: outline) else {
                    problems.append("\(step): T-\(id) can't be clicked: \(ui.titlePoint(id).flatMap(ui.hitView).map { String(describing: type(of: $0)) } ?? "nothing")")
                    continue
                }
            }
        }
        await fits("loaded folded")
        func disclose(_ id: Int) async {
            let row = outline.row(forItem: coordinator.node(.task(id)))
            guard row >= 0 else { return problems.append("T-\(id) has no row") }
            let item = coordinator.node(.task(id))
            if ui.canClickTables {
                let rect = outline.frameOfOutlineCell(atRow: row)
                outline.scrollToVisible(rect)
                let frame = outline.convert(rect, to: nil)
                await ui.click(NSPoint(x: frame.midX, y: frame.midY))
            } else {
                NSAnimationContext.runAnimationGroup({ context in
                    context.allowsImplicitAnimation = true
                    if outline.isItemExpanded(item) { outline.animator().collapseItem(item) } else { outline.animator().expandItem(item) }
                }, completionHandler: nil)
            }
            await ui.settle(0.8)
        }
        await disclose(parent.id)
        check("a folded task opens from its disclosure", outline.isItemExpanded(coordinator.node(.task(parent.id))) && !model.collapsed.contains(parent.id))
        await fits("opened")
        await disclose(above.id)
        await fits("above opened")
        await disclose(parent.id)
        await fits("folded again")
        await disclose(parent.id)
        await fits("opened again")
        check("opening folded tasks keeps every row in the outline and clickable", problems.isEmpty, problems.prefix(6).joined(separator: "; "))
        // The Backlog folded, the last tasks of Tasks opened one after the other: its header stays on the page.
        problems = []
        model.backlogOpen = false
        for id in below.suffix(2) { for index in 0..<6 { _ = model.addSubtask(to: id, title: "Late \(index)") } }
        await endUndoGroup(model)
        await ui.settle(0.6)
        for id in below.suffix(2) { model.setCollapsed(id, true) }
        model.folded = [.tasks]
        await ui.settle(0.6)
        model.folded = []
        await ui.settle(0.8)
        for id in below.suffix(2) {
            let item = coordinator.node(.task(id))
            NSAnimationContext.runAnimationGroup({ context in
                context.allowsImplicitAnimation = true
                outline.animator().expandItem(item)
            }, completionHandler: nil)
            await ui.settle(0.1)
        }
        await ui.settle(0.8)
        await fits("bottom tasks opened")
        let header = outline.row(forItem: coordinator.node(.header(.backlog)))
        if header >= 0, let scroll = outline.enclosingScrollView, let page = scroll.documentView {
            let rect = outline.rect(ofRow: header)
            let inPage = outline.convert(rect, to: page)
            if inPage.maxY > page.bounds.maxY + 0.5 || inPage.minY < page.bounds.minY - 0.5 {
                problems.append("the Backlog header at \(Int(inPage.minY))–\(Int(inPage.maxY)) is off the page (\(Int(page.bounds.height)))")
            }
            outline.scrollToVisible(rect)
            await ui.settle(0.3)
            let frame = outline.convert(rect, to: nil)
            let cell = outline.view(atColumn: 0, row: header, makeIfNecessary: false)
            let row = outline.rowView(atRow: header, makeIfNecessary: false)
            if cell == nil || cell?.window == nil || row == nil || cell?.superview !== row {
                problems.append("the Backlog header's row shows no header: cell \(cell.map { String(describing: type(of: $0)) } ?? "none"), in its row \(cell?.superview === row)")
            }
            if let hit = ui.hitView(NSPoint(x: frame.minX + 200, y: frame.midY)), !(cell.map { hit.isDescendant(of: $0) } ?? false) {
                problems.append("a click on the Backlog header lands on \(type(of: hit))")
            }
        } else {
            problems.append("no Backlog header")
        }
        check("with the Backlog folded, opening the last tasks keeps its header on the page", problems.isEmpty, problems.prefix(6).joined(separator: "; "))
        model.backlogOpen = true
        model.deleteTasks([above.id, parent.id] + below)
        await endUndoGroup(model)
        await ui.settle(0.4)
    }

    /// Typing anywhere on the page never leaves the outline shorter than its rows: the rows below stay.
    static func typingKeepsRows(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator,
              let container = outline.superview as? OutlineContainer else { return check("the outline is on the page", false) }
        var short: [String] = []
        func fits(_ step: String) {
            let backlog = outline.row(forItem: coordinator.node(.header(.backlog)))
            let bottom = backlog >= 0 ? outline.rect(ofRow: backlog).maxY : 0
            if container.frame.height + 0.5 < container.contentHeight || container.frame.height + 0.5 < bottom || outline.frame.height + 0.5 < bottom {
                short.append("\(step): frame \(Int(container.frame.height)) rows \(Int(container.contentHeight))")
            }
        }
        model.backlogOpen = true
        await ui.settle(0.6)
        fits("open")
        guard let parent = model.addTask(to: .overview, title: "Typing parent"), let child = model.addSubtask(to: parent.id, title: "First child") else {
            return check("tasks to type in", false)
        }
        await endUndoGroup(model)
        await ui.settle(0.6)
        fits("added")
        // A new subtask's title, as the user types one.
        coordinator.select(child.id)
        ui.window.makeFirstResponder(outline)
        await ui.key("n", code: 45)
        await ui.settle(0.5)
        for (index, letter) in "Everything below stays".enumerated() {
            await ui.key(String(letter))
            if index % 4 == 0 { await ui.settle(0.15) }
            fits("title \(index)")
        }
        await ui.key(.return)
        await ui.settle(0.6)
        fits("title saved")
        await ui.key(.escape)
        await ui.settle(0.4)
        // A description, line after line.
        await ui.editTitle(child.id)
        await ui.key(.return, .shift)
        await ui.settle(0.8)
        for line in 0..<6 {
            await ui.type("Line \(line) of the description")
            await ui.key(.return)
            await ui.settle(0.2)
            fits("description \(line)")
        }
        await ui.key(.escape)
        await ui.settle(0.6)
        fits("description saved")
        // The lists' searches and the toolbar's.
        for (index, text) in ["T", "Ty", "Typ", "Typi", "Typ", "", "zz", ""].enumerated() {
            model.listSearch[.overview] = text.isEmpty ? nil : text
            await ui.settle(0.15)
            fits("list search \(index)")
        }
        for (index, text) in ["c", "cd", "cdn", "cd", "", "x", ""].enumerated() {
            model.search = text
            await ui.settle(0.15)
            fits("search \(index)")
        }
        await ui.settle(0.6)
        fits("end")
        check("typing never leaves the outline shorter than its rows", short.isEmpty, short.prefix(6).joined(separator: "; "))
        check("the outline's rows always matched its snapshot", OutlineCoordinator.repairs == 0, "\(OutlineCoordinator.repairs) repairs")
        model.deleteTasks([parent.id])
        model.backlogOpen = false
        await endUndoGroup(model)
        await ui.settle(0.4)
    }

    /// The menu bar as a Mac user expects it: HQ once in Window, no toolbar items, Help, ⌘W closing the modal first,
    /// the Task menu's move acting on what's selected.
    static func menuBar(_ model: AppModel, _ ui: Driver) async {
        let menus = NSApp.mainMenu?.items.compactMap(\.submenu) ?? []
        func menu(_ title: String) -> NSMenu? { menus.first { $0.title == title } }
        func titles(_ title: String) -> [String] { menu(title)?.items.map(\.title) ?? [] }
        let window = titles("Window")
        check("Window lists HQ once", window.filter { $0 == "HQ" }.count == 1, window.joined(separator: ", "))
        check("View has no toolbar items: the toolbar holds the title and the search", !titles("View").contains { $0.contains("Toolbar") },
              titles("View").joined(separator: ", "))
        check("Help has Keyboard Shortcuts", titles("Help").contains("Keyboard Shortcuts"), titles("Help").joined(separator: ", "))
        // ⌘W closes the modal, not the window.
        if let close = menu("File")?.items.first(where: { $0.keyEquivalent == "w" && $0.keyEquivalentModifierMask == .command }),
           let file = close.menu, let task = model.tasks.first(where: { model.list(of: $0.id) == .overview }) {
            model.open(.task(task.id))
            await ui.settle(0.6)
            ui.window.makeKey()
            file.performActionForItem(at: file.index(of: close))
            await ui.settle(0.6)
            check("⌘W closes the modal and leaves the window", model.modal == nil && ui.window.isVisible, String(describing: model.modal))
            model.closeModal()
            await ui.settle(0.4)
        } else {
            check("File has Close ⌘W", false, titles("File").joined(separator: ", "))
        }
        // Several Backlog rows: Move to Tasks, and it moves them.
        if let a = model.addTask(to: .backlog, title: "Back one"), let b = model.addTask(to: .backlog, title: "Back two") {
            await endUndoGroup(model)
            model.selectedTasks = [a.id, b.id]
            model.syncMenu()
            check("with several Backlog rows selected the Task menu moves them to Tasks", !MenuState.shared.tasksToBacklog)
            model.moveTasks([a.id, b.id], toBacklog: MenuState.shared.tasksToBacklog)
            check("and they go", model.list(of: a.id) == .overview && model.list(of: b.id) == .overview)
            model.selectedTasks = []
            model.deleteTasks([a.id, b.id])
            await endUndoGroup(model)
        }
        // A PR selected on the page: the menu bar's Open on GitHub and Copy Link act on it.
        if let pr = model.reviewRequests.first ?? model.ownPullRequests.first {
            model.selectedItem = ModalRoute.github(pr.url).selectionKey
            check("a PR selected on the page gives the menu bar Open on GitHub", MenuState.shared.outside == "Open on GitHub" && MenuState.shared.link == pr.url,
                  MenuState.shared.outside ?? "none")
            model.selectedItem = nil
            // Its modal's Copy Link copies its address.
            model.open(.github(pr.url))
            await ui.settle(0.8)
            check("its Reload stops turning once the page has loaded", model.loadingPage == nil, model.loadingPage ?? "")
            Pasteboard.copied = nil
            func copyLinkSize() -> CGSize? { UITest.anchors["copy-link", default: []].compactMap(\.view).last?.frame.size }
            let before = copyLinkSize()
            await ui.click(ui.anchor("copy-link"), inSheet: true)
            check("a PR's modal copies its link", Pasteboard.copied == pr.url, Pasteboard.copied ?? "nothing copied")
            check("Copy Link keeps its size while it says Copied", before != nil && copyLinkSize() == before,
                  "\(String(describing: before)) → \(String(describing: copyLinkSize()))")
            model.closeModal()
            await ui.settle(0.5)
        }
    }

    /// The grid's validateDrop, with its in-out arguments kept valid for the call.
    static func validate(_ coordinator: SessionGrid.Coordinator, _ collection: NSCollectionView, _ info: FakeDrag, item: Int,
                         operation: NSCollectionView.DropOperation) -> (NSDragOperation, NSCollectionView.DropOperation) {
        var path = NSIndexPath(forItem: item, inSection: 0)
        var op = operation
        let result = withUnsafeMutablePointer(to: &path) { pathPointer in
            withUnsafeMutablePointer(to: &op) { opPointer in
                coordinator.collectionView(collection, validateDrop: info, proposedIndexPath: AutoreleasingUnsafeMutablePointer(pathPointer),
                                           dropOperation: opPointer)
            }
        }
        return (result, op)
    }

    // MARK: Outline keys

    /// Tasks: A (A1, A2), B, C. Backlog: D, E. The test vault's earlier notes go first, so a rescan can't bring them back.
    static func makeTree(_ model: AppModel) async -> [String: Int] {
        for task in model.tasks { if let path = task.path { try? FileManager.default.removeItem(atPath: path) } }
        model.tasks = []
        var ids: [String: Int] = [:]
        for title in ["A", "B", "C"] { ids[title] = model.addTask(to: .overview, title: title)?.id }
        for title in ["E", "D"] { ids[title] = model.addTask(to: .backlog, title: title)?.id }
        if let a = ids["A"] {
            ids["A1"] = model.addSubtask(to: a, title: "A1")?.id
            ids["A2"] = model.addSubtask(to: a, title: "A2")?.id
        }
        await endUndoGroup(model)
        return ids
    }

    static func outlineKeys(_ model: AppModel, _ ui: Driver) async {
        let ids = await makeTree(model)
        await ui.settle(0.8)
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator,
              let a = ids["A"], let b = ids["B"], let c = ids["C"], let a2 = ids["A2"] else { return check("the outline's tasks", false) }
        let tree = { model.taskTree }
        let rows = { ui.window.firstResponder === outline }
        let state = { "selected \(model.selectedTasks) focused \(String(describing: model.focusedTask)) responder \(ui.responder)" }
        check("the outline shows Tasks with their subtasks", tree().top(.overview) == [a, b, c] && tree().children(of: a).count == 2)

        // A click selects, a double-click edits.
        await ui.click(ui.titlePoint(b))
        tableCheck(ui, "a click on a title selects its row without editing", model.selectedTasks == [b] && !ui.isTyping, state())
        // A click on the selected row's status moves it on; the row stays selected.
        if let cell = outline.view(atColumn: 1, row: outline.row(forItem: coordinator.node(.task(b))), makeIfNecessary: false) as? TaskCell {
            let glyph = cell.glyph.convert(NSPoint(x: cell.glyph.bounds.midX, y: cell.glyph.bounds.midY), to: nil)
            await ui.click(glyph)
            tableCheck(ui, "a click on a selected row's status moves it on and keeps the row selected",
                       model.task(b)?.status == .doing && model.selectedTasks == [b], "\(String(describing: model.task(b)?.status)) \(state())")
            model.setStatus(b, .todo)
            await ui.settle(0.2)
        }
        await ui.click(ui.titlePoint(b), count: 2)
        check("a double-click on a title edits it, its row still selected", ui.isTyping && model.focusedTask == b && model.selectedTasks == [b], state())
        if !ui.isTyping { coordinator.beginEditing(b) }

        // In a title: Return adds below; Tab goes to the description, Shift-Tab back and to the previous title.
        await ui.key(.return)
        await ui.settle(0.5)
        let added = tree().top(.overview)
        check("Return in a title adds a task below and edits it", added.count == 4 && added[2] != c && model.focusedTask == added[2] && ui.isTyping,
              "\(added) \(state())")
        let new = added[2]
        let before = model.tasks.count
        await ui.key(.return)
        await ui.settle(0.3)
        check("Return in an empty title adds nothing", model.tasks.count == before && model.focusedTask == new && ui.isTyping, state())
        await ui.type("Fix push #perf")
        await ui.key(.tab)
        await ui.settle(0.8)
        check("Tab in a title edits its description, and leaves the task where it is", model.editingDescription == new && ui.isTyping
              && tree().parent(of: new) == nil, state())
        check("#word in a typed title becomes a tag", model.task(new)?.title == "Fix push" && model.task(new)?.tags == ["perf"],
              "\(model.task(new)?.title ?? "-") \(model.task(new)?.tags ?? [])")
        await ui.type("Why.")
        await ui.key(.tab, .shift)
        await ui.settle(0.5)
        check("Shift-Tab in a description saves it and edits the task's title", model.task(new)?.body == "Why." && model.editingDescription == nil
              && model.focusedTask == new && ui.isTyping, "\(model.task(new)?.body ?? "-") \(state())")
        await ui.key(.tab)
        await ui.settle(0.8)
        await ui.key(.tab)
        await ui.settle(0.5)
        check("Tab in a description edits the next task's title", model.focusedTask == c && ui.isTyping && model.editingDescription == nil, state())
        await ui.key(.tab, .shift)
        await ui.settle(0.3)
        check("Shift-Tab in a title edits the previous task's title", model.focusedTask == new && ui.isTyping, state())
        await ui.key(.up)
        await ui.settle(0.3)
        check("Up in a title selects the row above, without editing", model.selectedTasks == [b] && rows(), state())

        // On rows: arrows move the selection, Tab goes round the page's sections; Shift with arrows moves the task.
        await ui.key(.down)
        await ui.settle(0.2)
        check("Down on rows selects the next task", model.selectedTasks == [new] && rows(), state())
        let sections = PageSection.allCases.filter { model.hasRows($0) }
        var left = PageSection.tasks
        for section in sections.drop(while: { $0 != .tasks }).dropFirst() + sections.prefix(while: { $0 != .tasks }) {
            await ui.key(.tab)
            // The next section takes the keyboard after an update; a busy run takes longer.
            await ui.until {
                switch section {
                case .pullRequests: model.selectedItem?.hasPrefix("github:") == true
                case .sessions: ui.window.firstResponder is SessionGrid.CardCollection
                case .files: model.selectedItem?.hasPrefix("file:") == true || model.selectedItem?.hasPrefix("artifact:") == true
                case .tasks: rows()
                }
            }
            switch left {
            case .tasks: check("Tab out of the tasks unselects their rows", model.selectedTasks.isEmpty, state())
            case .sessions: check("Tab out of the sessions unselects the card", model.selectedSession == nil, model.selectedSession ?? "-")
            case .pullRequests, .files: break
            }
            left = section
            switch section {
            case .pullRequests:
                let first = model.selectedItem
                check("Tab takes the keyboard to Pull Requests, first row selected", first?.hasPrefix("github:") == true && !rows(), state())
                await ui.key(.down)
                await ui.settle(0.2)
                check("Down selects the next pull request", model.selectedItem != first && model.selectedItem?.hasPrefix("github:") == true,
                      model.selectedItem ?? "-")
            case .sessions:
                check("Tab takes the keyboard to the session cards", ui.window.firstResponder is SessionGrid.CardCollection && model.selectedSession != nil,
                      ui.responder)
            case .files:
                check("Tab takes the keyboard to Files and Artifacts", model.selectedItem?.hasPrefix("file:") == true
                      || model.selectedItem?.hasPrefix("artifact:") == true, model.selectedItem ?? "-")
            case .tasks:
                break
            }
        }
        await ui.key(.tab)
        await ui.settle(0.5)
        check("Tab round the page comes back to the tasks, the row still selected", model.selectedTasks == [new] && rows(), state())
        await ui.key(.tab, .shift)
        await ui.until { !rows() && model.selectedItem != nil }
        check("Shift-Tab goes to the section before", !rows(), state())
        await ui.key(.tab)
        await ui.until { rows() && model.selectedTasks == [new] }
        check("and Tab back to the row", model.selectedTasks == [new] && rows(), state())
        // ⇧Tab goes round the page the other way, through every section.
        func reached(_ section: PageSection) -> Bool {
            switch section {
            case .pullRequests: model.selectedItem?.hasPrefix("github:") == true && model.selectedSection == .pullRequests
            case .sessions: ui.window.firstResponder is SessionGrid.CardCollection && model.selectedSession != nil
            case .files: (model.selectedItem?.hasPrefix("file:") == true || model.selectedItem?.hasPrefix("artifact:") == true) && model.selectedSection == .files
            case .tasks: rows()
            }
        }
        for section in sections.prefix(while: { $0 != .tasks }).reversed() {
            await ui.key(.tab, .shift)
            await ui.until { reached(section) }
            check("Shift-Tab takes the keyboard back to \(section), the section left unselected", reached(section) && model.selectedTasks.isEmpty, state())
        }
        await ui.key(.tab, .shift)
        await ui.until { rows() && model.selectedTasks == [new] }
        check("Shift-Tab round the page comes back to the tasks, the row still selected", model.selectedTasks == [new] && rows()
              && model.selectedSession == nil && model.selectedItem == nil, state())
        await ui.key(.right, .shift)
        await ui.settle(0.5)
        check("Shift-Right indents the row under the task above; it keeps the selection and the keyboard",
              tree().parent(of: new) == b && model.selectedTasks == [new] && rows(), "parent \(String(describing: tree().parent(of: new))) \(state())")
        await ui.key(.left, .shift)
        await ui.settle(0.5)
        check("Shift-Left outdents it", tree().parent(of: new) == nil && tree().top(.overview) == [a, b, new, c] && model.selectedTasks == [new] && rows(),
              "\(tree().top(.overview)) \(state())")
        model.undoManager?.undo()
        await ui.settle(0.4)
        check("Undo Outdent nests it again", tree().parent(of: new) == b)
        model.undoManager?.undo()
        await ui.settle(0.4)
        check("Undo Indent puts it back, still selected", tree().parent(of: new) == nil && model.selectedTasks == [new], state())
        await ui.key(.up, .shift)
        await ui.settle(0.5)
        check("Shift-Up moves the row up among its siblings, still selected", tree().top(.overview) == [a, new, b, c] && model.selectedTasks == [new] && rows(),
              "\(tree().top(.overview)) \(state())")
        await ui.key(.down, .shift)
        await ui.settle(0.5)
        check("Shift-Down moves it back", tree().top(.overview) == [a, b, new, c] && model.selectedTasks == [new], "\(tree().top(.overview))")
        outline.selectRowIndexes(IndexSet([b, new].map { outline.row(forItem: coordinator.node(.task($0))) }), byExtendingSelection: false)
        await ui.key(.up, .shift)
        await ui.settle(0.5)
        check("Shift-Up moves several rows together", tree().top(.overview) == [b, new, a, c] && model.selectedTasks == [b, new],
              "\(tree().top(.overview)) \(state())")
        await ui.key(.up, .shift)
        await ui.settle(0.5)
        check("and they stop whole at the top", tree().top(.overview) == [b, new, a, c], "\(tree().top(.overview))")
        model.undoManager?.undo()
        await ui.settle(0.4)
        check("one Undo puts them back", tree().top(.overview) == [a, b, new, c], "\(tree().top(.overview))")
        let a1 = tree().children(of: a)[0]
        coordinator.select(a1)
        await ui.key(.up, .shift)
        await ui.settle(0.5)
        check("Shift-Up on a first subtask moves it out, above its parent", tree().top(.overview) == [a1, a, b, new, c] && model.selectedTasks == [a1],
              "\(tree().top(.overview)) \(state())")
        await ui.key(.down, .shift)
        await ui.settle(0.5)
        check("Shift-Down then moves it below the task under it, as a sibling", tree().top(.overview) == [a, a1, b, new, c], "\(tree().top(.overview))")
        coordinator.select(a2)
        await ui.key(.down, .shift)
        await ui.settle(0.5)
        check("Shift-Down on a last subtask moves it out, below its parent", tree().parent(of: a2) == nil && tree().top(.overview) == [a, a2, a1, b, new, c],
              "\(tree().top(.overview))")
        model.undoManager?.undo()
        await ui.settle(0.3)
        model.undoManager?.undo()
        await ui.settle(0.3)
        model.undoManager?.undo()
        await ui.settle(0.3)
        check("Undo puts the subtasks back", tree().children(of: a) == [a1, a2] && tree().top(.overview) == [a, b, new, c],
              "\(tree().children(of: a)) \(tree().top(.overview))")

        // In a title: Shift-Right at its end indents, Shift-Left at its start outdents; the title stays edited.
        coordinator.beginEditing(new)
        await ui.settle(0.3)
        await ui.key(.right, .shift)
        await ui.settle(0.6)
        check("Shift-Right at the end of a title indents the task and keeps editing it", tree().parent(of: new) == b && ui.isTyping && model.focusedTask == new,
              "parent \(String(describing: tree().parent(of: new))) \(state())")
        (ui.window.firstResponder as? NSTextView)?.setSelectedRange(NSRange(location: 0, length: 0))
        await ui.key(.left, .shift)
        await ui.settle(0.6)
        check("Shift-Left at the start of a title outdents it, still editing", tree().parent(of: new) == nil && tree().top(.overview) == [a, b, new, c] && ui.isTyping,
              "\(tree().top(.overview)) \(state())")
        await ui.key(.left, .shift)
        await ui.settle(0.3)
        check("a top-level task stays where it is", tree().top(.overview) == [a, b, new, c] && ui.isTyping)
        await ui.key(.escape)
        await ui.settle(0.3)
        // An empty task moved from its title stays, still edited, until the edit ends.
        coordinator.select(new)
        await ui.key("n")
        await ui.settle(0.5)
        let blank = model.focusedTask
        await ui.key(.right, .shift)
        await ui.settle(0.8)
        check("Shift-Right on a new empty task indents it and keeps it", blank.map { tree().parent(of: $0) == new && model.task($0) != nil } == true && ui.isTyping,
              "\(String(describing: blank)) parent \(String(describing: blank.flatMap { tree().parent(of: $0) })) \(state())")
        await ui.key(.escape)
        await ui.settle(0.5)
        check("and Escape drops it, empty", blank.map { model.task($0) == nil } == true && tree().top(.overview) == [a, b, new, c])

        // Return edits, Escape gives the rows back the keyboard; the Task menu's keys work on rows.
        coordinator.select(new)
        await ui.key(.return)
        await ui.settle(0.3)
        check("Return on a row edits its title", ui.isTyping && model.focusedTask == new, state())
        await ui.key(.escape)
        await ui.settle(0.3)
        check("Escape in a title ends editing; the row keeps the selection and the keyboard", !ui.isTyping && rows() && model.selectedTasks == [new], state())
        await ui.key(.return, .command)
        await ui.settle(0.3)
        check("Command-Return on a row moves it to the next status", model.task(new)?.status == .doing && rows())
        for _ in 0..<2 { await ui.key(.return, .command) }
        await ui.settle(0.3)
        check("through Done, then back to Todo, the row still selected", model.task(new)?.status == .todo && model.selectedTasks == [new] && rows(), state())
        model.setStatus(new, .todo)
        let shown = model.descriptionShownInOutline(new)
        await ui.key(.return, .shift)
        await ui.settle(0.4)
        check("Shift-Return on a row shows or hides its description", model.descriptionShownInOutline(new) != shown && model.editingDescription == nil && rows(),
              state())
        await ui.key(.return, .shift)
        await ui.settle(0.4)
        check("and again", model.descriptionShownInOutline(new) == shown)
        model.hideDone = [.overview]
        model.setStatus(new, .doing)
        await ui.key(.return, .command)
        await ui.settle(0.5)
        check("a row that Hide Done hides gives the selection and the keyboard to the row above", model.selectedTasks == [b] && rows(), state())
        model.hideDone = []
        model.toggleDone(new)
        await ui.settle(0.4)

        // N and Shift-N add; a task left empty goes; Delete selects the row above.
        coordinator.select(new)
        let count = model.tasks.count
        await ui.key("n", code: 45)
        await ui.settle(0.5)
        let order = tree().top(.overview)
        check("N on a row adds a task below and edits its title", model.tasks.count == count + 1 && ui.isTyping
              && order.firstIndex(of: model.focusedTask ?? 0) == (order.firstIndex(of: new) ?? 0) + 1, "\(order) \(state())")
        await ui.key(.escape)
        await ui.settle(0.5)
        check("Escape on a task with nothing in it deletes it and selects the row above", model.tasks.count == count && model.selectedTasks == [new] && rows(),
              state())
        await ui.key("N", .shift, code: 45)
        await ui.settle(0.5)
        let sub = model.focusedTask ?? 0
        check("Shift-N adds a subtask and edits its title", tree().parent(of: sub) == new && ui.isTyping, state())
        await ui.type("Sub")
        await ui.key(.escape)
        await ui.settle(0.4)
        check("Escape keeps a task with a title", model.task(sub)?.title == "Sub" && model.selectedTasks == [sub] && rows(), state())
        await ui.key(.delete)
        await ui.settle(0.5)
        check("Delete on a row deletes it and selects the row above", model.task(sub) == nil && model.selectedTasks == [new] && rows(), state())
        await ui.key(.down)
        await ui.key(.up)
        await ui.settle(0.2)
        check("the rows keep the keyboard after a delete", model.selectedTasks == [new] && rows(), state())

        // Backspace at the start of a title stays there: the task and the edit stay.
        let typed = model.task(new)?.title ?? ""
        await ui.editTitle(new)
        for _ in 0..<(typed.count + 2) { await ui.key(.delete) }
        await ui.settle(0.5)
        check("Backspace at the start of a title keeps the task and the edit", model.task(new) != nil && model.focusedTask == new && ui.isTyping,
              state())
        await ui.type(typed)
        await ui.key(.escape)
        await ui.settle(0.4)

        // The description: Escape and Command-Return save and select the row.
        await ui.editTitle(b)
        await ui.key(.return, .shift)
        await ui.settle(0.8)
        check("Shift-Return in a title opens the description's editor", model.editingDescription == b && ui.isTyping, ui.responder)
        check("the description's editor keeps its text keys from the Task menu", model.outlineKeyboard == .none)
        await ui.type("Goal: fewer blobs.")
        if let editor = ui.window.firstResponder as? NSTextView {
            model.focusSearch()
            await ui.settle(0.3)
            check("Find in a description's editor opens its find bar and keeps the edit", editor.enclosingScrollView?.isFindBarVisible == true
                  && model.editingDescription == b, ui.responder)
            let hide = NSMenuItem()
            hide.tag = NSTextFinder.Action.hideFindInterface.rawValue
            editor.performTextFinderAction(hide)
            ui.window.makeFirstResponder(editor)
            await ui.settle(0.2)
        }
        await ui.key(.escape)
        await ui.settle(0.5)
        check("Escape in a description saves it and selects its row with the keyboard", model.task(b)?.body == "Goal: fewer blobs."
              && model.editingDescription == nil && model.selectedTasks == [b] && rows(), "\(model.task(b)?.body ?? "-") \(state())")
        coordinator.editDescription(b)
        await ui.settle(0.8)
        await ui.type(" More.")
        await ui.key(.return, .command)
        await ui.settle(0.5)
        check("Command-Return saves the description", model.task(b)?.body == "Goal: fewer blobs. More." && model.editingDescription == nil && rows(),
              "\(model.task(b)?.body ?? "-") \(state())")
        // Clicks on a description go through the outline's check before the description's own views.
        if let point = ui.descriptionPoint(b), let single = ui.mouseDown(point, clicks: 1), let double = ui.mouseDown(point, clicks: 2) {
            outline.deselectAll(nil)
            let passed = coordinator.descriptionClick(single)
            await ui.settle(0.3)
            check("a click on a description selects its row and still reaches the description", passed != nil && model.selectedTasks == [b] && rows(), state())
            let swallowed = coordinator.descriptionClick(double)
            await ui.settle(0.6)
            check("a double-click on a description edits it", swallowed == nil && model.editingDescription == b && ui.isTyping, state())
            await ui.key(.escape)
            await ui.settle(0.4)
        } else {
            check("the description shows under its row", false)
        }
        if ui.canClickTables, let point = ui.descriptionPoint(b) {
            await ui.click(point, count: 2)
            await ui.settle(0.6)
            check("a real double-click on a description edits it", model.editingDescription == b && ui.isTyping, state())
            await ui.key(.escape)
            await ui.settle(0.4)
        } else {
            skip("a real double-click on a description edits it")
        }

        // To the Backlog and back: the task above takes the selection.
        await ui.editTitle(b)
        await ui.chord("b", [.command, .shift], code: 11)
        await ui.settle(0.5)
        check("Shift-Command-B moves a task to the top of the Backlog", tree().top(.backlog).first == b, "list \(model.list(of: b))")
        check("and the task above it in Tasks takes the selection and the keyboard", model.selectedTasks == [a2] && rows(), state())
        model.toggleList(b)
        await ui.settle(0.4)
        check("and back to the end of Tasks", tree().top(.overview).last == b)

        // Folding a task whose subtask is selected selects the task.
        coordinator.select(a2)
        outline.collapseItem(coordinator.node(.task(a)))
        await ui.settle(0.3)
        check("folding a task whose subtask is selected selects the task", model.selectedTasks == [a] && rows(), state())
        outline.expandItem(coordinator.node(.task(a)))
        await ui.settle(0.3)

        // Quick add: Return keeps the field; Option-Return sends to the Backlog; Escape goes back to the rows.
        model.focusQuickAdd(.overview)
        await ui.settle(0.6)
        check("New Task gives the quick-add line the keyboard", ui.isTyping, ui.responder)
        await ui.type("Quick one")
        await ui.key(.return)
        await ui.settle(0.4)
        let quick = tree().top(.overview).last
        check("the quick-add line adds at the end of Tasks and keeps the keyboard", model.task(quick)?.title == "Quick one" && ui.isTyping)
        await ui.type("Later one")
        await ui.key(.return, .option)
        await ui.settle(0.4)
        check("Option-Return sends it to the Backlog", model.task(tree().top(.backlog).first)?.title == "Later one")
        await ui.key(.escape)
        await ui.settle(0.3)
        check("Escape in the quick-add line selects the task above it", model.selectedTasks == [quick ?? 0] && rows(), state())
        // The Backlog's filter.
        model.backlogOpen = true
        model.listSearch[.backlog] = "Later"
        await ui.settle(0.5)
        check("the Backlog's search shows the tasks that match", OutlineSnapshot.make(model).children(of: .header(.backlog)).filter { if case .task = $0 { true } else { false } }.count == 1)
        model.listSearch = [:]
        model.backlogFilter = BacklogFilter()
        model.backlogOpen = false
    }

    // MARK: Outline drops

    static func outlineDrops(_ model: AppModel, _ ui: Driver) async {
        await linkDrops(model, ui)
        let ids = await makeTree(model)
        model.backlogOpen = true
        await ui.settle(0.8)
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator,
              let a = ids["A"], let a1 = ids["A1"], let b = ids["B"], let c = ids["C"], let d = ids["D"], let e = ids["E"] else {
            return check("the outline for drops", false)
        }
        let tree = { model.taskTree }
        // Several selected rows: the Task menu acts on them all, and they move to the Backlog in order.
        outline.selectRowIndexes(IndexSet([b, c].map { outline.row(forItem: coordinator.node(.task($0))) }), byExtendingSelection: false)
        await ui.settle(0.3)
        check("the Task menu targets every selected row", MenuState.shared.tasks == [b, c], "\(MenuState.shared.tasks)")
        model.moveTasks(MenuState.shared.tasks, toBacklog: true)
        await endUndoGroup(model)
        check("several rows move to the Backlog in their order", Array(tree().top(.backlog).prefix(2)) == [b, c], "\(tree().top(.backlog))")
        model.undoManager?.undo()
        await ui.settle(0.3)
        check("one Undo brings them back", tree().top(.overview) == [a, b, c], "\(tree().top(.overview))")
        let family = [a] + tree().children(of: a)
        outline.selectRowIndexes(IndexSet(family.map { outline.row(forItem: coordinator.node(.task($0))) }), byExtendingSelection: false)
        await ui.settle(0.3)
        model.moveTasks(MenuState.shared.tasks, toBacklog: true)
        await endUndoGroup(model)
        check("a task and its subtasks selected together go to the Backlog together, still nested",
              tree().top(.backlog).first == a && tree().children(of: a) == Array(family.dropFirst()), "\(tree().top(.backlog)) \(tree().children(of: a))")
        model.undoManager?.undo()
        await ui.settle(0.3)
        outline.deselectAll(nil)
        func drop(_ moving: [Int], on item: OutlineNode.Kind?, index: Int) async -> (NSDragOperation, Bool) {
            let info = FakeDrag(tasks: moving, source: outline)
            let parent = item.map { coordinator.node($0) }
            let operation = coordinator.outlineView(outline, validateDrop: info, proposedItem: parent, proposedChildIndex: index)
            guard operation == .move else { return (operation, false) }
            let accepted = coordinator.outlineView(outline, acceptDrop: info, item: parent, childIndex: index)
            coordinator.dragEnded()
            await endUndoGroup(model)
            return (operation, accepted)
        }
        _ = await drop([c], on: .header(.overview), index: 0)
        await ui.settle(0.3)
        check("a drop between rows lands there", tree().top(.overview) == [c, a, b])
        let name = model.undoManager?.undoActionName ?? "-"
        let orders = model.tasks.map { "\($0.id):\($0.order)" }
        model.undoManager?.undo()
        await ui.settle(0.3)
        check("Undo puts it back", tree().top(.overview) == [a, b, c], "undid \(name), \(orders) → \(model.tasks.map { "\($0.id):\($0.order)" }) redo \(model.undoManager?.redoActionName ?? "-")")
        _ = await drop([b], on: .task(a), index: NSOutlineViewDropOnItemIndex)
        await ui.settle(0.3)
        check("a drop on a row makes it the last child", tree().children(of: a).last == b)
        model.undoManager?.undo()
        await ui.settle(0.3)
        _ = await drop([a], on: .header(.backlog), index: NSOutlineViewDropOnItemIndex)
        await ui.settle(0.3)
        check("a drop on the Backlog's header goes to its end, with its subtasks", tree().top(.backlog).last == a && tree().list(of: a1) == .backlog)
        model.undoManager?.undo()
        await ui.settle(0.3)
        _ = await drop([d], on: .header(.overview), index: 1)
        await ui.settle(0.3)
        check("a drop from the Backlog onto Tasks lands between rows", tree().top(.overview) == [a, d, b, c])
        model.undoManager?.undo()
        await ui.settle(0.3)
        let refused = await drop([a], on: .task(a1), index: NSOutlineViewDropOnItemIndex)
        check("a drop into its own subtree is refused", refused.0 == [] && tree().parent(of: a) == nil)
        let two = await drop([e, d], on: .header(.overview), index: 3)
        await ui.settle(0.3)
        check("several rows drop together, in order", two.1 && tree().top(.overview) == [a, b, c, e, d], "\(tree().top(.overview))")
        model.undoManager?.undo()
        await ui.settle(0.3)
        check("Undo moves them all back", tree().top(.backlog) == [d, e] || tree().top(.backlog) == [e, d])
        // A drag that ends outside the window leaves no drop target behind.
        coordinator.dragEnded()
        check("a cancelled drag leaves no row marked as a drop target", (0..<outline.numberOfRows).allSatisfy { !(outline.rowView(atRow: $0, makeIfNecessary: false)?.isTargetForDropOperation ?? false) })
        let writer = coordinator.outlineView(outline, pasteboardWriterForItem: coordinator.node(.task(a))) as? NSPasteboardItem
        check("a dragged task carries its key and its title for other apps",
              writer?.string(forType: DragItem.taskType) == "\(a)" && writer?.string(forType: .string) == "T-\(a) A")
        model.backlogOpen = false
    }

    // MARK: Modal

    /// The row's look: group gaps, a hidden description's first line, the status menu, # completion, the modal's tags.
    static func outlineLooks(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator else { return check("the outline is on the page", false) }
        model.shownDescriptions = []
        model.allDescriptions = []
        // Run alone, the overview has none of the earlier groups' tasks.
        if !model.taskTree.top(.overview).contains(where: { !model.taskTree.children(of: $0).isEmpty }),
           let parent = model.addTask(to: .overview, title: "Looks parent") {
            _ = model.addSubtask(to: parent.id, title: "Looks child")
            _ = model.addTask(to: .overview, title: "Looks after")
            await ui.settle(0.5)
        }
        let top = model.taskTree.top(.overview)
        guard top.count >= 2, let parent = top.first(where: { !model.taskTree.children(of: $0).isEmpty }),
              let child = model.taskTree.children(of: parent).first else { return check("tasks with subtasks on the overview", false) }
        await ui.settle(0.4)
        func height(_ id: Int) -> CGFloat { outline.rect(ofRow: outline.row(forItem: coordinator.node(.task(id)))).height }
        func lineHeight(_ id: Int) -> CGFloat { height(id) - (model.tasksWithOutputs.contains(id) ? Metric.linksLine : 0) }
        check("the Files and Artifacts section lists files", model.listedFiles.first.map { ui.anchor("item:file:\($0.id)") != nil } ?? true)
        let linkedTask = top.first { model.tasksWithOutputs.contains($0) }
        if let linkedTask, !model.descriptionShownInOutline(linkedTask) {
            check("a task's links take a line under its title", height(linkedTask) == coordinator.gap(of: linkedTask) + Metric.outlineRow + Metric.linksLine,
                  "\(height(linkedTask))")
        }
        check("the first task sits under its card's padding, a top-level task after another a gap lower; its subtasks don't",
              lineHeight(top[1]) == Metric.outlineRow + Metric.outlineGroupGap && lineHeight(top[0]) == Metric.outlineRow + Metric.listCardPadding && lineHeight(child) == Metric.outlineRow,
              "\(height(top[0])) \(height(top[1])) \(height(child))")

        // A hidden description shows as a small mark after the title; a click on it shows the description.
        model.setDescription(child, "**Why**: the canary flaps.\n\nMore below.")
        await ui.settle(0.5)
        let row = outline.row(forItem: coordinator.node(.task(child)))
        guard let first = outline.view(atColumn: 1, row: row, makeIfNecessary: true) as? TaskCell else { return check("the subtask's row", false) }
        // The edits below reload the row: always its current cell.
        var cell: TaskCell {
            outline.view(atColumn: 1, row: outline.row(forItem: coordinator.node(.task(child))), makeIfNecessary: true) as? TaskCell ?? first
        }
        cell.layoutSubtreeIfNeeded()
        check("a hidden description shows its mark after the title", !cell.note.isHidden && cell.note.frame.minX >= cell.title.frame.maxX,
              "\(cell.note.isHidden) \(cell.note.frame)")
        cell.note.performClick(nil)
        await ui.settle(0.5)
        check("a click on the mark shows the description", model.descriptionShownInOutline(child))
        model.toggleDescription(child)
        await ui.settle(0.4)

        // The toggle after the title shows and hides it, and stays on the row while it shows.
        if model.descriptionShownInOutline(child) { model.toggleDescription(child) }
        await ui.settle(0.4)
        let toggled = (outline.view(atColumn: 1, row: outline.row(forItem: coordinator.node(.task(child))), makeIfNecessary: true) as? TaskCell)?.note
        toggled?.performClick(nil)
        await ui.settle(0.5)
        check("the description toggle after the title shows the description", model.descriptionShownInOutline(child))
        toggled?.performClick(nil)
        await ui.settle(0.5)
        check("and hides it", !model.descriptionShownInOutline(child))

        // A click on the status glyph steps to the next status, through the outline as AppKit delivers it.
        if let before = model.task(child)?.status {
            cell.layoutSubtreeIfNeeded()
            let glyphFrame = cell.glyph.convert(cell.glyph.bounds, to: nil)
            if let click = ui.mouseDown(NSPoint(x: glyphFrame.midX, y: glyphFrame.midY), clicks: 1) { outline.mouseDown(with: click) }
            await ui.settle(0.3)
            let all = TaskStatus.allCases
            let next = all[((all.firstIndex(of: before) ?? 0) + 1) % all.count]
            check("a click on the status glyph steps to the next status", model.task(child)?.status == next,
                  "\(before) → \(String(describing: model.task(child)?.status))")
            model.setStatus(child, before)
            await ui.settle(0.3)
        }

        // The status glyph picks any status; ⌘-click steps to the next.
        cell.glyph.onPick(.doing)
        await ui.settle(0.3)
        check("the status menu sets the status it picks", model.task(child)?.status == .doing)
        cell.glyph.onNext()
        await ui.settle(0.3)
        check("Command-click on the status moves to the next one", model.task(child)?.status == .done)

        // The task's key shows whole, three digits too.
        cell.key.stringValue = "T-1066"
        cell.setHovered(true)
        cell.needsLayout = true
        cell.layoutSubtreeIfNeeded()
        let keyText = ceil(("T-1066" as NSString).size(withAttributes: [.font: KitType.key.nsFont]).width)
        check("a task's key fits its label", cell.key.frame.width >= keyText + 2 && cell.key.frame.maxX <= cell.bounds.width, "\(cell.key.frame) for \(keyText)")
        cell.setHovered(false)
        coordinator.refresh()

        // Clicks reach the status glyph, not only the row's selection.
        func middle(_ view: NSView) -> NSPoint {
            let frame = view.convert(view.bounds, to: nil)
            return NSPoint(x: frame.midX, y: frame.midY)
        }
        check("a click on the status glyph reaches it", cell.button(at: middle(cell.glyph)) === cell.glyph)
        check("a click on the title doesn't", cell.button(at: middle(cell.title)) == nil)

        // The project sits after the title, a button; a task in no project shows its icon alone.
        model.setProject(child, "Registry")
        await ui.settle(0.4)
        cell.layoutSubtreeIfNeeded()
        check("a task's project shows after its title, and a click reaches it", !cell.project.isHidden && cell.project.project == "Registry"
              && cell.project.frame.minX >= cell.title.frame.maxX && cell.button(at: middle(cell.project)) === cell.project,
              "\(cell.project.frame) \(cell.title.frame)")
        cell.project.onPick(nil)
        await ui.settle(0.4)
        let inherited = model.project(ofTask: child) != nil
        check("with none, its icon alone, unless a parent's project applies", model.task(child)?.project == nil
              && (inherited ? cell.project.labels.isEmpty : cell.project.labels.first?.text == ""), "\(cell.project.labels)")

        // The subtask count counts every level.
        if let grandchild = model.addSubtask(to: child, title: "Grandchild") {
            await ui.settle(0.4)
            let parentCell = outline.view(atColumn: 1, row: outline.row(forItem: coordinator.node(.task(parent))), makeIfNecessary: true) as? TaskCell
            let below = model.taskTree.subtree(of: parent).count - 1
            check("a task's subtask count counts every level under it", parentCell?.progress.total == below,
                  "\(parentCell?.progress.total ?? -1) of \(below)")
            // Its ring has a segment per status.
            model.setStatus(grandchild.id, .doing)
            await ui.settle(0.4)
            let statuses = model.taskTree.subtree(of: parent).filter { $0 != parent }.compactMap { model.task($0)?.status }
            let ring = (outline.view(atColumn: 1, row: outline.row(forItem: coordinator.node(.task(parent))), makeIfNecessary: true) as? TaskCell)?.progress
            check("a task's ring counts what's under it by status", ring?.counts[.doing] == statuses.filter { $0 == .doing }.count
                  && ring?.toolTip?.contains("doing") == true, ring?.toolTip ?? "no ring")
            model.deleteTasks([grandchild.id])
            await ui.settle(0.3)
        }

        // A click on a row's key copies its key and title, through the outline as AppKit delivers it.
        // The edits above reload rows: the row's cell now may be another view.
        let keyRow = outline.row(forItem: coordinator.node(.task(child)))
        if let task = model.task(child), let cell = outline.view(atColumn: 1, row: keyRow, makeIfNecessary: true) as? TaskCell {
            outline.scrollRowToVisible(keyRow)
            cell.scrollToVisible(cell.bounds.insetBy(dx: 0, dy: -Driver.overlayClearance))
            cell.setHovered(true)
            ui.window.layoutIfNeeded()
            cell.layoutSubtreeIfNeeded()
            let point = cell.key.convert(NSPoint(x: cell.key.bounds.midX, y: cell.key.bounds.midY), to: nil)
            Pasteboard.copied = nil
            if let click = ui.mouseDown(point, clicks: 1) { outline.mouseDown(with: click) }
            await ui.settle(0.2)
            let copied = Pasteboard.copied
            check("a click on a task's key copies its key and title", copied == "\(task.key) \(task.title)" && cell.key.tracksHandCursor,
                  "\(copied ?? "nothing"), hand \(cell.key.tracksHandCursor), hits \(cell.button(at: point).map { String(describing: type(of: $0)) } ?? "none"), row \(outline.row(at: outline.convert(point, from: nil))) of \(keyRow), in outline \(cell.superview != nil), key \(cell.key.frame) hidden \(cell.key.isHidden), copies \(cell.key.copied)")
            check("and the key turns the accent color", cell.key.textColor == Ink.accentNS)
            cell.setHovered(false)
        }

        // A click on the faces starts a session on the task, through the outline as AppKit delivers it.
        if let faces = outline.view(atColumn: 0, row: keyRow, makeIfNecessary: true) as? FacesCell {
            faces.layoutSubtreeIfNeeded()
            let point = faces.convert(NSPoint(x: faces.bounds.width - Space.xs - Metric.faceRow / 2, y: faces.gap + Metric.outlineRow / 2), to: nil)
            // The pointing hand: the view under the pointer tracks it, wherever the row scrolled.
            let hit = ui.hitView(point)
            check("the hand shows over a task's faces", (hit as? FaceStackView)?.tracksHandCursor == true, String(describing: hit.map { type(of: $0) }))
            check("and over its status", cell.glyph.tracksHandCursor)
            if let click = ui.mouseDown(point, clicks: 1) { outline.mouseDown(with: click) }
            await ui.settle(0.6)
            check("a click on a task's faces starts a session on it", model.modal == .start, "\(String(describing: model.modal))")
            // Closing keeps the sheet's size and content while it animates out: no jump, no flash.
            let open = ui.window.attachedSheet?.frame.size
            model.closeModal()
            await ui.settle(0.05)
            let closing = ui.window.attachedSheet?.frame.size
            check("a closing sheet keeps its size", closing == nil || closing == open, "\(String(describing: open)) → \(String(describing: closing))")
            await ui.settle(0.5)
            // With a session on it, a click on its face shows that session's menu, once no double-click can come.
            if let session = model.gridSessions.first {
                model.link(task: child, session: session.id)
                await ui.settle(0.4)
                faces.layoutSubtreeIfNeeded()
                var shown: String?
                let show = FaceMenu.show
                FaceMenu.show = { _, id, _, _ in shown = id }
                if let click = ui.mouseDown(point, clicks: 1) { outline.mouseDown(with: click) }
                await ui.settle(0.3)
                check("a click on a task's face shows its session's menu at once, not Start Session", shown == session.id && model.modal == nil,
                      "\(shown ?? "-") \(String(describing: model.modal))")
                FaceMenu.show = show
                model.unlink(task: child, session: session.id)
                await ui.settle(0.3)
            }
        }


        // # in a title lists what it can become.
        let editor = NSTextView()
        editor.string = "Fix #rev"
        editor.setSelectedRange(NSRange(location: 8, length: 0))
        let word = OutlineCoordinator.hashWord(in: editor)
        check("the word after # is completed", word?.text == "rev" && word?.range == NSRange(location: 5, length: 3), "\(String(describing: word))")
        editor.string = "Fix PR#418"
        editor.setSelectedRange(NSRange(location: 10, length: 0))
        check("# inside a word isn't", OutlineCoordinator.hashWord(in: editor) == nil)

        // The modal's tags: + adds one.
        model.open(.task(child))
        await ui.settle(1)
        let plus = ui.anchor("tag-adder")
        check("+ shows after the tags in the modal", plus != nil)
        if let plus, ui.canClickTables {
            await ui.click(plus, inSheet: true)
            await ui.settle(0.5)
            await ui.type("fresh")
            await ui.key(.return)
            await ui.settle(0.5)
            tableCheck(ui, "+ after the tags adds one", model.task(child)?.tags.contains("fresh") == true, "\(model.task(child)?.tags ?? [])")
            await ui.key(.escape)
        } else {
            skip("+ after the tags adds one")
        }
        model.closeModal()
        model.shownDescriptions = []
        await ui.settle(0.6)
    }

    static func modal(_ model: AppModel, _ ui: Driver) async {
        guard let task = model.tasks.first else { return check("a task for the modal", false) }
        model.open(.task(task.id))
        await ui.settle(0.8)
        check("the task's modal opens as a sheet", ui.window.attachedSheet != nil)
        let session = model.gridSessions[0]
        model.open(.session(session.id), push: true)
        model.open(.task(task.id), push: true)
        await ui.settle(0.4)
        check("opening from inside the modal keeps the way back", model.modalStack.count == 2)
        model.back()
        model.back()
        check("Back goes back two levels", model.modal == .task(task.id) && model.modalStack.isEmpty)
        model.closeModal()
        await ui.settle(0.6)
        check("Close ends the sheet", ui.window.attachedSheet == nil && model.modal == nil)
        model.beginStart(task: task.id)
        await ui.settle(1)
        check("Start a Session focuses the first message, caret at the end", ui.sheetIsTyping, ui.sheetResponder)
        model.closeModal()
        await ui.settle(0.5)
    }

    // MARK: Performance

    /// 500 tasks and 30 sessions: the outline builds only what's in view, rows stay true to the
    /// model when scrolled to, and no update or scroll holds the main thread for long.
    /// Working faces sway and cards breathe on the render server: HQ's main thread rests meanwhile.
    static func idle(_ model: AppModel, _ ui: Driver) async {
        model.selectSection(nil)
        await ui.settle(1)
        let faces = ui.findAll(FaceView.self).map(\.face) + ui.findAll(FaceStackView.self).flatMap(\.faceLayers)
        let working = faces.filter(\.isWorking)
        check("working faces are on the page", !working.isEmpty, "\(faces.count) faces")
        check("each working face sways on the render server", working.allSatisfy(\.sways), "\(working.filter { !$0.sways }.count) of \(working.count) still")
        let breathing = ui.findAll(BreathingView.self)
        check("a card that needs the user breathes on the render server", !breathing.isEmpty && breathing.allSatisfy(\.breathes),
              "\(breathing.count) breathing, \(breathing.filter { !$0.breathes }.count) without their animation")
        let before = Self.mainThreadCPU()
        await ui.settle(2)
        let used = Self.mainThreadCPU() - before
        check("the main thread rests while faces sway and cards breathe", used < 0.1, String(format: "%.0f ms of CPU in 2 s", used * 1000))
    }

    /// CPU time the main thread has used, in seconds.
    static func mainThreadCPU() -> Double {
        let thread = pthread_mach_thread_np(pthread_self())
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count) }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.user_time.seconds + info.system_time.seconds) + Double(info.user_time.microseconds + info.system_time.microseconds) / 1_000_000
    }

    static func performance(_ model: AppModel, _ ui: Driver) async {
        // A baseline: the small page scrolled the same way, before the large seed.
        var baseline: Stall.Result?
        if let outline = ui.find(TaskOutlineView.self), let scroll = outline.enclosingScrollView {
            let end = max((scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height, 0)
            let steps = Array(stride(from: 0, through: end, by: 160))
            baseline = await Stall.measure((steps + steps.reversed()).map { y in {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
            } }, gap: 0.03)
            scroll.contentView.scroll(to: .zero)
        }
        SeedData.fillLarge(model, now: .now)
        // Notes for them, so vault rescans keep them.
        if let vault = model.vault {
            var tasks = model.tasks
            for index in tasks.indices where tasks[index].path == nil {
                tasks[index].path = vault.tasksDirectory.appending(path: "T-\(tasks[index].id).md").path
                try? vault.save(tasks[index])
            }
            model.tasks = tasks
        }
        model.backlogOpen = false
        await ui.settle(3)
        guard let outline = ui.find(TaskOutlineView.self), let scroll = outline.enclosingScrollView else {
            return check("the outline with the large seed", false)
        }
        func scrollPage(to y: CGFloat) {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        var bottom: CGFloat { max((scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height, 0) }
        func visibleRowsDrawn() -> Bool {
            let rows = outline.rows(in: outline.visibleRect)
            return rows.length > 0 && (rows.location..<rows.location + rows.length)
                .allSatisfy { (outline.rowView(atRow: $0, makeIfNecessary: false)?.alphaValue ?? 0) > 0.99 }
        }

        // The Backlog opened below the fold, then scrolled to.
        scrollPage(to: bottom)
        await ui.settle(0.3)
        model.backlogOpen = true
        await ui.settle(0.1)
        scrollPage(to: bottom)
        await ui.settle(1.2)
        check("the Backlog opened below the fold draws its rows when scrolled to", visibleRowsDrawn(), "\(outline.visibleRect)")
        scrollPage(to: 6000)
        await ui.settle(0.5)
        var built = 0
        outline.enumerateAvailableRowViews { _, _ in built += 1 }
        check("the outline builds only the rows in view", built > 0 && built < 120, "\(built) row views for \(outline.numberOfRows) rows")
        scrollPage(to: 0)

        // Descriptions on, scrolled, off, back to the top: no row keeps a description it no longer shows.
        let descriptions = await Stall.measure([{ model.allDescriptions = [.overview, .backlog] }], gap: 1)
        scrollPage(to: 3000)
        await ui.settle(0.5)
        model.allDescriptions = []
        await ui.settle(0.8)
        scrollPage(to: 0)
        await ui.settle(0.5)
        var stale = 0
        outline.enumerateAvailableRowViews { rowView, _ in
            if let cell = rowView.view(atColumn: 1) as? TaskCell, cell.descriptionHost != nil { stale += 1 }
        }
        check("rows out of view drop the descriptions that were hidden", stale == 0, "\(stale) rows")

        let search = await Stall.measure(["r", "re", "reg", "regi", "reg", "re", "r", ""].map { text in { model.search = text } })
        let folded = model.taskTree.top(.overview).filter { !model.taskTree.children(of: $0).isEmpty }.prefix(8)
        let fold = await Stall.measure(folded.map { id in { model.setCollapsed(id, true) } } + folded.map { id in { model.setCollapsed(id, false) } })
        let move = await Stall.measure(model.taskTree.top(.overview).prefix(8).map { id in {
            if let index = model.tasks.firstIndex(where: { $0.id == id }) { model.tasks[index].order += 2.5 }
        } })
        print("  perf: scrolling")
        // A fast trackpad scroll through the outline: 48 pt a frame, down 4000 pt and back.
        let start = outline.convert(NSPoint.zero, to: scroll.documentView).y
        let down = Array(stride(from: start, through: min(start + 4000, bottom), by: 48))
        scrollPage(to: start)
        await ui.settle(0.5)
        let scrolls = await Stall.measure((down + down.reversed()).map { y in { scrollPage(to: y) } }, gap: 0.016)
        scrollPage(to: bottom)
        await ui.settle(0.5)
        check("rows scrolled into view are drawn, to the last one", visibleRowsDrawn()
              && outline.rowView(atRow: outline.numberOfRows - 1, makeIfNecessary: false) != nil, "\(outline.visibleRect)")
        scrollPage(to: 0)

        print("  perf: baseline scroll of the small page \(baseline?.description ?? "-")")
        print("  perf: show all descriptions \(descriptions); search \(search); fold \(fold); move \(move); scroll \(scrolls); \(built) row views")
        check("Show Descriptions with 500 tasks holds the main thread under 150 ms", descriptions.worst < 150, "\(descriptions)")
        check("a search keystroke with 500 tasks holds it under 100 ms", search.worst < 100, "\(search)")
        check("folding a task with 500 tasks holds it under 50 ms", fold.worst < 50, "\(fold)")
        check("a move with 500 tasks takes under two frames, none over 100 ms", move.median < 34 && move.worst < 100, "\(move)")
        check("scrolling the page with 500 tasks stays within a frame, rare steps at two, none at three",
              scrolls.median < 17 && scrolls.hitches <= scrolls.steps.count / 100 && scrolls.worst < 50, "\(scrolls)")
    }
}

/// How long the main thread went without a turn of its run loop after each step, in ms.
final class Stall {
    private var last = CACurrentMediaTime()
    private var worst = 0.0

    struct Result: CustomStringConvertible {
        let steps: [Int]
        var worst: Int { steps.max() ?? 0 }
        var median: Int { steps.sorted()[steps.count / 2] }
        /// Steps that held the main thread longer than two frames.
        var hitches: Int { steps.filter { $0 > 34 }.count }
        var description: String { "worst \(worst), median \(median), \(hitches) of \(steps.count) over 34 ms" }
    }

    static func measure(_ steps: [() -> Void], gap: Double = 0.08) async -> Result {
        let stall = Stall()
        let timer = Timer(timeInterval: 0.002, repeats: true) { _ in MainActor.assumeIsolated { stall.tick() } }
        RunLoop.main.add(timer, forMode: .common)
        try? await Task.sleep(for: .seconds(0.05))
        var results: [Int] = []
        for step in steps {
            stall.worst = 0
            stall.last = CACurrentMediaTime()
            step()
            try? await Task.sleep(for: .seconds(gap))
            results.append(Int(stall.worst * 1000))
        }
        timer.invalidate()
        return Result(steps: results)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        worst = max(worst, now - last)
        last = now
    }
}

/// A drag that never left HQ: the drop code reads only its pasteboard and source.
final class FakeDrag: NSObject, NSDraggingInfo {
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("HQ-uitest-\(UUID().uuidString)"))
    private let source: Any?

    init(tasks: [Int] = [], session: String? = nil, item key: String? = nil, source: Any?) {
        self.source = source
        super.init()
        pasteboard.clearContents()
        var items: [NSPasteboardItem] = tasks.map { id in
            let item = NSPasteboardItem()
            item.setString("\(id)", forType: DragItem.taskType)
            return item
        }
        if let key {
            let item = NSPasteboardItem()
            item.setData(Data(key.utf8), forType: DragItem.itemType)
            items.append(item)
        }
        if let session {
            let item = NSPasteboardItem()
            item.setString(session, forType: DragItem.sessionType)
            items.append(item)
        }
        pasteboard.writeObjects(items)
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { source }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

extension Driver {
    /// A command-key chord: an active app gets it from the system as a key equivalent; a background
    /// run hands it to the window the same way.
    func chord(_ characters: String, _ flags: NSEvent.ModifierFlags, code: UInt16) async {
        guard !NSApp.isActive else { return await key(characters, flags, code: code) }
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil, characters: characters,
                                        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) {
            _ = window.performKeyEquivalent(with: event)
        }
        await settle(0.05)
    }

    func find<T: NSView>(_ type: T.Type) -> T? {
        func search(_ view: NSView) -> T? {
            if let match = view as? T { return match }
            for child in view.subviews { if let match = search(child) { return match } }
            return nil
        }
        return window.contentView.flatMap(search)
    }

    func findAll<T: NSView>(_ type: T.Type) -> [T] {
        func search(_ view: NSView) -> [T] {
            ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap(search)
        }
        return window.contentView.map(search) ?? []
    }

    /// The middle of a card, in window coordinates, scrolled into view.
    func cardPoint(_ id: String) -> NSPoint? {
        guard let collection = find(SessionGrid.CardCollection.self),
              let coordinator = collection.delegate as? SessionGrid.Coordinator,
              let index = coordinator.ids.firstIndex(of: id),
              let item = collection.item(at: IndexPath(item: index, section: 0)) else { return nil }
        item.view.scrollToVisible(item.view.bounds)
        let frame = item.view.convert(item.view.bounds, to: nil)
        return NSPoint(x: frame.minX + frame.width * 0.4, y: frame.midY)
    }

    func cardLocal(_ collection: NSCollectionView, _ index: Int) -> NSPoint {
        guard let item = collection.item(at: IndexPath(item: index, section: 0)) else { return .zero }
        return NSPoint(x: item.view.frame.midX, y: item.view.frame.midY)
    }

    /// A click on a task's title; a background run, whose tables take no synthetic clicks, gives it the keyboard.
    /// Edits a task's title as Return on its row does.
    func editTitle(_ id: Int) async {
        find(TaskOutlineView.self)?.coordinator?.beginEditing(id)
        await settle()
    }

    /// The middle of a task's title, in window coordinates, scrolled into view.
    func titlePoint(_ id: Int) -> NSPoint? {
        guard let outline = find(TaskOutlineView.self), let coordinator = outline.coordinator else { return nil }
        let row = outline.row(forItem: coordinator.node(.task(id)))
        guard row >= 0, let cell = outline.view(atColumn: 1, row: row, makeIfNecessary: true) as? TaskCell else { return nil }
        cell.title.scrollToVisible(cell.title.bounds.insetBy(dx: 0, dy: -Driver.overlayClearance))
        window.layoutIfNeeded()
        let frame = cell.title.convert(cell.title.bounds, to: nil)
        return NSPoint(x: frame.minX + min(frame.width / 2, 20), y: frame.midY)
    }

    /// A mouse-down as the window would get it.
    func mouseDown(_ point: NSPoint, clicks: Int) -> NSEvent? {
        NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)
    }

    /// The left of a task's shown description, in window coordinates.
    func descriptionPoint(_ id: Int) -> NSPoint? {
        guard let outline = find(TaskOutlineView.self), let coordinator = outline.coordinator else { return nil }
        let row = outline.row(forItem: coordinator.node(.task(id)))
        guard row >= 0, let host = (outline.view(atColumn: 1, row: row, makeIfNecessary: true) as? TaskCell)?.descriptionHost else { return nil }
        host.scrollToVisible(host.bounds)
        let frame = host.convert(host.bounds, to: nil)
        return NSPoint(x: frame.minX + 40, y: frame.maxY - 14)
    }

    var sheetIsTyping: Bool { window.attachedSheet?.firstResponder is NSTextView }
    var sheetResponder: String { window.attachedSheet?.firstResponder.map { String(describing: Swift.type(of: $0)) } ?? "none" }
}
