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
              let coordinator = collection.delegate as? SessionGrid.Coordinator else { return await check("the session grid is on the page", false) }
        let first = model.gridSessions[0]
        // The cards sit in the page's column, not across the page's scroll view.
        let grid = collection.superview?.bounds ?? .zero
        let frames = (0..<collection.numberOfItems(inSection: 0)).compactMap { collection.item(at: IndexPath(item: $0, section: 0))?.view.frame }
        await check("the cards stay inside the grid's column", collection.frame.size == grid.size && !frames.isEmpty && frames.allSatisfy { $0.maxX <= grid.width + 0.5 },
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
        await check("every card's face takes its click", missed.isEmpty, "missed cards \(missed)")
        await check("cards take the click that brings HQ forward", ui.takesFirstClick(ui.cardPoint(first.id)))
        await ui.click(ui.cardPoint(first.id))
        await ui.settle(0.5)
        await tableCheck(ui, "a click on a card selects it and opens nothing", model.modal == nil && model.selectedSession == first.id,
                   "\(String(describing: model.modal))")
        let running = model.gridSessions.first { $0.tty != nil && $0.isRunning }!
        let before = model.ghosttyLog.count
        await ui.click(ui.cardPoint(running.id), count: 2)
        await ui.settle(0.6)
        await tableCheck(ui, "a double-click on a card opens its modal, not Ghostty", model.modal == .session(running.id) && model.ghosttyLog.count == before,
                   "\(model.ghosttyLog.count - before) calls, modal \(String(describing: model.modal))")
        model.closeModal()

        // Reorder: the card dropped before the first one goes first, the others keep their order.
        let order = model.gridRoots.map(\.id)
        let moving = order[3]
        let info = FakeDrag(session: moving, source: collection, at: cardEdge(0, after: false, collection, coordinator))
        let accepted = validate(coordinator, collection, info, item: 0, operation: .before)
        await check("a card dragged over the grid is a move", accepted.0 == .move)
        await endUndoGroup(model)
        _ = coordinator.collectionView(collection, acceptDrop: info, indexPath: IndexPath(item: 0, section: 0), dropOperation: .on)
        await endUndoGroup(model)
        await ui.settle(0.4)
        await check("a dropped card lands where it was dropped", model.gridRoots.map(\.id) == [moving] + order.filter { $0 != moving },
              "\(model.gridRoots.map { $0.id.prefix(4) })")
        await check("the grid shows the new order without a reload", coordinator.ids == model.gridRoots.map(\.id))
        model.undoManager?.undo()
        await ui.settle(0.4)
        await check("Undo Move Session puts it back", model.gridRoots.map(\.id) == order)

        // A task dropped on a card links to that session.
        guard let task = model.addTask(to: .overview, title: "Link me") else { return await check("a task to drop", false) }
        await endUndoGroup(model)
        await ui.settle(0.3)
        let taskDrag = FakeDrag(tasks: [task.id], source: nil)
        let link = validate(coordinator, collection, taskDrag, item: 1, operation: .before)
        await check("a task over a card proposes a link onto it", link.0 == .link && link.1 == .on)
        collection.draggingExited(taskDrag)
        await check("a task dragged off the grid leaves no card highlighted", coordinator.dropTarget == nil)
        _ = validate(coordinator, collection, taskDrag, item: 1, operation: .before)
        _ = coordinator.collectionView(collection, acceptDrop: taskDrag, indexPath: IndexPath(item: 1, section: 0), dropOperation: .on)
        await endUndoGroup(model)
        await check("a task dropped on a card works on its session", model.task(task.id)?.sessions == [model.gridRoots[1].id])
        let action = model.undoManager?.undoActionName ?? "-"
        model.undoManager?.undo()
        await ui.settle(0.2)
        await check("Undo unlinks it", model.task(task.id)?.sessions.isEmpty == true, "undid \(action)")
        coordinator.dragEnded()

        // A running session stays on the grid: its menu has no Hide.
        let cardMenu = coordinator.menu(at: ui.cardLocal(collection, 0))
        cardMenu?.update()
        let titles = cardMenu?.items.map(\.title) ?? []
        await check("a card has a context menu, with no Hide", titles.contains("Show Details") && !titles.contains { $0.hasPrefix("Hide") }, titles.joined(separator: ", "))
        model.deleteTasks([task.id])
    }

    /// One selection on the page: a click in a section unselects the others, a click on nothing unselects all;
    /// a click on a card's face shows the card's menu.
    static func pageSelection(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator,
              let collection = ui.find(SessionGrid.CardCollection.self), let grid = collection.delegate as? SessionGrid.Coordinator,
              let pr = model.reviewRequests.first ?? model.ownPullRequests.first,
              let task = model.addTask(to: .overview, title: "Select me") else { return await check("a task, a card and a PR to select", false) }
        await endUndoGroup(model)
        await ui.settle(0.4)
        coordinator.select(task.id)
        await ui.settle(0.3)
        await check("a selected row gives the tasks the page's selection", model.selectedSection == .tasks && model.selectedTasks == [task.id],
              "\(String(describing: model.selectedSection))")
        let prKey = ModalRoute.github(pr.url).selectionKey
        await ui.click(ui.anchor("pr:\(pr.number)"))
        await ui.until { model.selectedItem == prKey && outline.selectedRowIndexes.isEmpty }
        await tableCheck(ui, "a click on a PR selects it, and the task's row unselects", model.selectedItem == prKey && model.selectedSection == .pullRequests
                   && outline.selectedRowIndexes.isEmpty, "\(model.selectedItem ?? "-"), \(outline.selectedRowIndexes.count) rows")
        // What the click does, for a background run, whose SwiftUI rows take no synthetic clicks.
        model.selectedItem = prKey
        model.selectSection(.pullRequests)
        await ui.until { outline.selectedRowIndexes.isEmpty }
        await check("a PR taking the selection unselects the task's row", outline.selectedRowIndexes.isEmpty && model.selectedTasks.isEmpty,
              "\(outline.selectedRowIndexes.count) rows")
        _ = ui.cardPoint(grid.ids[0])
        grid.collectionView(collection, didSelectItemsAt: [IndexPath(item: 0, section: 0)])
        await ui.settle(0.3)
        await check("a card selected unselects the PR", model.selectedSession == grid.ids[0] && model.selectedItem == nil && model.selectedSection == .sessions,
              model.selectedItem ?? "-")
        // The Sessions header, between its title and its buttons: nothing there.
        let gridFrame = collection.convert(collection.bounds, to: nil)
        await ui.click(NSPoint(x: gridFrame.midX, y: gridFrame.maxY + Space.md + 12))
        await ui.until { model.selectedSession == nil }
        await tableCheck(ui, "a click on nothing unselects everything", model.selectedSession == nil && model.selectedItem == nil && model.selectedSection == nil
                   && collection.selectionIndexPaths.isEmpty, "\(model.selectedSession ?? "-") \(String(describing: model.selectedSection))")
        model.selectSection(nil)
        await ui.settle(0.3)
        await check("with nothing selected, no card stays selected", model.selectedSession == nil && collection.selectionIndexPaths.isEmpty)
        model.selectedItem = ModalRoute.github(pr.url).chipKey(task: task.id)
        await check("a link chip under a task is selected apart from its row in Pull Requests", model.selectedItem != prKey
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
            await check("a click on a card's face focuses its session, no menu", shown == nil && model.ghosttyLog.count > logged,
                  "\(shown ?? "no menu"), \(model.ghosttyLog.suffix(1))")
            let card = collection.item(at: IndexPath(item: 0, section: 0))?.view as? SessionGrid.CardView
            await check("the card tracks the pointer for the hand over its face", card?.handOverFace == true)
            // In every state, needs-you ones first: their glow and badge must not take the click (T-327).
            if let grid = collection.delegate as? SessionGrid.Coordinator, let id = grid.ids.first, let original = model.session(id) {
                let states: [SessionState] = [.waiting(.question), .waiting(.permission), .waiting(.plan), .failed, .working, .idle, .done]
                var missed: [String] = []
                for state in states {
                    var item = original
                    item.status = SessionStatus(state: state, unread: state == .done, since: .now)
                    model.put(item)
                    await ui.settle(0.4)
                    guard let point = facePoint() else { missed.append("\(state): no face"); continue }
                    // What the window would hand a real click: the grid, not something drawn over the card.
                    if let hit = ui.window.contentView?.hitTest(point), !hit.isDescendant(of: collection) {
                        missed.append("\(state): \(type(of: hit)) takes the click")
                        continue
                    }
                    let logged = model.ghosttyLog.count
                    // In front, a real click through the window, as the user's; in the background, straight to the grid.
                    if ui.canClickTables { await ui.click(point) } else { await press(point, clicks: 1) }
                    await ui.settle(0.3)
                    if model.ghosttyLog.count == logged { missed.append("\(state)") }
                }
                model.put(original)
                await check("a click on a card's face focuses its session in every state", missed.isEmpty, "missed: \(missed.joined(separator: ", "))")
            }
        } else {
            await check("the first card's face", false)
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
            return await check("a task and a file to drop on it", false)
        }
        await endUndoGroup(model)
        await ui.settle(0.4)
        let row = coordinator.node(.task(target.id))
        let drag = FakeDrag(item: ModalRoute.file(file.id).selectionKey, source: nil)
        let proposed = coordinator.outlineView(outline, validateDrop: drag, proposedItem: row, proposedChildIndex: NSOutlineViewDropOnItemIndex)
        await check("a file dragged onto a task's row proposes a link", proposed == .link)
        _ = coordinator.outlineView(outline, acceptDrop: drag, item: row, childIndex: NSOutlineViewDropOnItemIndex)
        await endUndoGroup(model)
        await ui.settle(0.4)
        await check("dropped, it links to that task and shows under its row", model.isLinked(.file(file.id), to: target.id)
              && model.outputs(ofTask: target.id).contains(.file(file.id)))
        await check("dragged there again, it's refused", coordinator.outlineView(outline, validateDrop: drag, proposedItem: row,
                                                                          proposedChildIndex: NSOutlineViewDropOnItemIndex) == [])
        model.undoManager?.undo()
        await ui.settle(0.3)
        await check("Undo unlinks it", !model.isLinked(.file(file.id), to: target.id))
        // A click on a link's chip under the row shows its menu: Open, Unlink, Delete for a file.
        model.link(.file(file.id), to: target.id)
        await endUndoGroup(model)
        await ui.settle(0.4)
        let menu = model.linkMenu(.file(file.id), task: target.id)
        menu.update()
        let titles = menu.items.map(\.title)
        await check("a linked file's menu has Open, Unlink and Delete", titles.contains("Open") && titles.contains("Unlink from T-\(target.id)")
              && titles.contains("Delete"), titles.joined(separator: ", "))
        let chip = ModalRoute.file(file.id).chipKey(task: target.id)
        var shown: String?
        var shownMenu: NSMenu?
        let showMenu = FaceMenu.show
        FaceMenu.show = { menu, id, _, _ in shown = id; shownMenu = menu }
        // A right-click on the file's link on the card shows the link's menu.
        func linkPoint() -> NSPoint? {
            guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator,
                  let cell = outline.view(atColumn: 1, row: outline.row(forItem: coordinator.node(.task(target.id))), makeIfNecessary: false) as? TaskCell else { return nil }
            return cell.links.windowPoint(of: .file(file.id))
        }
        if let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator {
            outline.scrollRowToVisible(outline.row(forItem: coordinator.node(.task(target.id))))
            await ui.settle(0.3)
        }
        if let outline = ui.find(TaskOutlineView.self), let point = linkPoint(),
           let down = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                         windowNumber: ui.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
            outline.rightMouseDown(with: down)
        }
        shownMenu?.update()
        await check("a right-click on a link on its task's card shows the link's menu", shown == chip
                   && shownMenu?.items.contains { $0.title == "Unlink from T-\(target.id)" } == true,
              shown ?? "no menu at \(String(describing: linkPoint()))")
        // A Control-click on the link gives the link's menu too; on the title, the task's.
        if let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator,
           let cell = outline.view(atColumn: 1, row: outline.row(forItem: coordinator.node(.task(target.id))), makeIfNecessary: false) as? TaskCell {
            func menu(at point: NSPoint?) -> [String] {
                guard let point, let down = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                                               windowNumber: ui.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
                      let menu = outline.menu(for: down) else { return [] }
                menu.update()
                return menu.items.map(\.title)
            }
            await check("a Control-click on a link gives the link's menu", menu(at: linkPoint()).contains("Unlink from T-\(target.id)"))
            let title = menu(at: cell.title.convert(NSPoint(x: cell.title.bounds.midX, y: cell.title.bounds.midY), to: nil))
            await check("on the task's title, the task's menu", !title.isEmpty && !title.contains("Unlink from T-\(target.id)"), title.joined(separator: ", "))
        }
        FaceMenu.show = showMenu
        // A click opens it, on the press (2026-11-10).
        await ui.click(linkPoint())
        await tableCheck(ui, "a click on a link on the card opens it", model.modal == .file(file.id), String(describing: model.modal))
        model.closeModal()
        await ui.settle(0.5)
        // Deleted while the task's modal lists it, the file leaves the list.
        model.open(.task(target.id))
        await ui.settle(0.8)
        let listed = "row:" + ModalRoute.file(file.id).selectionKey
        await check("the task's modal lists its linked file", ui.anchor(listed) != nil)
        model.deleteFile(file.id)
        await endUndoGroup(model)
        await ui.settle(0.6)
        await check("a file deleted while the task's modal is open leaves its list", ui.anchor(listed) == nil)
        model.undoManager?.undo()
        await ui.settle(0.5)
        // Deleted from its own modal, opened from the task's: the task's modal shows again, without it.
        model.open(.file(file.id), push: true)
        await ui.settle(0.6)
        model.deleteFile(file.id)
        await endUndoGroup(model)
        await ui.settle(0.6)
        await check("a file deleted from its modal goes back to the task's", model.modal == .task(target.id) && model.modalStack.isEmpty
              && ui.anchor(listed) == nil, String(describing: model.modal))
        model.closeModal()
        await ui.settle(0.6)
        if let pr = model.ownPullRequests.first {
            let prDrag = FakeDrag(item: ModalRoute.github(pr.url).selectionKey, source: nil)
            _ = coordinator.outlineView(outline, validateDrop: prDrag, proposedItem: row, proposedChildIndex: NSOutlineViewDropOnItemIndex)
            _ = coordinator.outlineView(outline, acceptDrop: prDrag, item: row, childIndex: NSOutlineViewDropOnItemIndex)
            await ui.settle(0.3)
            await check("a PR dropped on a task's row links it", model.task(target.id)?.links.map(\.absoluteString).contains(pr.url) == true)
        }
        model.deleteTasks([target.id])
        await endUndoGroup(model)
        await ui.settle(0.3)
    }

    /// Last, as they move the page and the keyboard: a task whose last subtask goes loses its chevron; Tab scrolls into view.
    static func lateChecks(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator else { return await check("the outline is on the page", false) }
        // Every section folds to its header: Tab passes a folded one, Tasks keeps only its header.
        if model.hasRows(.files) {
            model.folded = [.files]
            await ui.settle(0.4)
            await check("a folded section has no rows for Tab", !model.hasRows(.files) && model.moveSection(from: .sessions, by: 1) != .files)
            model.folded = []
            await ui.settle(0.3)
        }
        model.folded = [.tasks]
        await ui.settle(0.5)
        let header = coordinator.node(.header(.overview))
        await check("folded, Tasks shows its header and no rows", outline.row(forItem: header) >= 0 && outline.numberOfChildren(ofItem: header) == 0)
        model.focusQuickAdd(.overview)
        await ui.settle(0.5)
        await check("New Task unfolds Tasks", !model.folded.contains(.tasks) && outline.numberOfChildren(ofItem: header) > 0)
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
            await check("a task whose last subtask is deleted loses its chevron", had && !outline.isExpandable(coordinator.node(.task(parent.id))) && coordinator.snapshot.foldable.contains(parent.id) == false)
            model.deleteTasks([parent.id])
            await endUndoGroup(model)
        }
        // As wide as the screen and back: every card's line stays at its card's left (once seen in its middle at full screen).
        func offCards() -> [String] {
            var off: [String] = []
            outline.enumerateAvailableRowViews { _, row in
                guard let cell = outline.view(atColumn: 1, row: row, makeIfNecessary: false) as? TaskCell, let superview = cell.superview else { return }
                let shown = outline.convert(cell.frame, from: superview), wanted = outline.frameOfCell(atColumn: 1, row: row)
                if abs(shown.minX - wanted.minX) > 1 || abs(shown.width - wanted.width) > 1 { off.append("row \(row): \(Int(shown.minX)) for \(Int(wanted.minX))") }
            }
            return off
        }
        let original = ui.window.frame
        if let screen = ui.window.screen?.visibleFrame {
            ui.window.setFrame(NSRect(x: screen.minX, y: original.minY, width: screen.width, height: original.height), display: true, animate: true)
            await ui.settle(0.8)
            let wide = offCards()
            ui.window.setFrame(original, display: true, animate: true)
            await ui.settle(0.8)
            let back = offCards()
            await check("as wide as the screen and back, every card's line stays at its card's left", wide.isEmpty && back.isEmpty,
                  (wide + back).prefix(4).joined(separator: "; "))
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
            func view() -> NSView? {
                let row = model.selectedItem.flatMap { key in model.githubItem(String(key.dropFirst("github:".count))) }
                return row.flatMap { UITest.anchors["pr:\($0.number)", default: []].compactMap(\.view).last }
            }
            await check("Tab to Pull Requests from far down the page scrolls its selected row into view", view().map { !$0.visibleRect.isEmpty } == true,
                  model.selectedItem ?? "-")
            // The keyboard goes back to the outline, as the next checks expect.
            model.selectSection(nil)
            ui.window.makeFirstResponder(outline)
            await ui.settle(0.3)
        }
    }

    /// A task's fold chevron sits on its first line as it gets subtasks, moves in and out of a parent and between lists.
    static func disclosures(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator else { return await check("the outline is on the page", false) }
        model.folded = []
        model.search = ""
        guard let above = model.addTask(to: .overview, title: "Caret above"), let parent = model.addTask(to: .overview, title: "Caret parent") else {
            return await check("tasks for the carets", false)
        }
        await endUndoGroup(model)
        await ui.settle(0.5)
        /// The task's fold chevron shows, on its first line, at its card's top right (2026-11-10).
        func caret(_ id: Int) async -> (ok: Bool, detail: String) {
            let row = outline.row(forItem: coordinator.node(.task(id)))
            if row >= 0 { outline.scrollRowToVisible(row) }
            await ui.settle(0.2)
            guard row >= 0, let cell = outline.view(atColumn: 1, row: row, makeIfNecessary: false) as? TaskCell else { return (false, "no row") }
            let button = cell.fold
            let chevron = button.convert(button.bounds, to: nil)
            let glyph = cell.glyph.convert(cell.glyph.bounds, to: nil)
            let card = cell.convert(cell.bounds, to: nil)
            let ok = !button.isHidden && button.alphaValue > 0 && abs(chevron.midY - glyph.midY) < 1.5
                && chevron.minX > card.maxX - Metric.cardEndControl - Space.sm && chevron.maxX <= card.maxX + 0.5
            return (ok, "chevron \(chevron.integral) glyph \(glyph.integral) hidden \(button.isHidden)")
        }
        guard let child = model.addSubtask(to: parent.id, title: "Caret child") else { return await check("a subtask", false) }
        await endUndoGroup(model)
        await ui.settle(0.6)
        var result = await caret(parent.id)
        await check("a task's first subtask brings its chevron, on its line", result.ok, result.detail)
        // No AppKit disclosure on a row: the card's own chevron folds (2026-11-10).
        func parentRow() -> Int { outline.row(forItem: coordinator.node(.task(parent.id))) }
        func disclosures() -> [NSView] {
            let row = parentRow()
            return row < 0 ? [] : (outline.rowView(atRow: row, makeIfNecessary: false)?.subviews ?? [])
                .filter { $0.identifier == NSOutlineView.disclosureButtonIdentifier && !$0.isHidden && !$0.frame.isEmpty }
        }
        await check("no AppKit disclosure on a task's row", parentRow() >= 0 && disclosures().isEmpty, "\(disclosures().count)")
        // The pointing hand over the chevron, as the window would hit it, and over every AppKit button a task row
        // shows (T-350).
        if parentRow() >= 0, let button = (outline.view(atColumn: 1, row: parentRow(), makeIfNecessary: false) as? TaskCell)?.fold {
            func hit() -> NSView? { ui.hitView(button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)) }
            await check("the pointing hand over a task's chevron", hit() === button && button.tracksHandCursor,
                  "hit \(hit().map { String(describing: type(of: $0)) } ?? "none"), tracks \(button.tracksHandCursor)")
        } else {
            await check("the pointing hand over a task's chevron", false, "no chevron")
        }
        var bare: [String] = []
        for row in 0..<outline.numberOfRows {
            guard outline.item(atRow: row) is OutlineNode, let rowView = outline.rowView(atRow: row, makeIfNecessary: false) else { continue }
            // AppKit's views only: SwiftUI's give the hand themselves (clickable()). Buttons, and every other view a click acts on.
            func shown(_ view: NSView) -> [NSView] {
                let name = String(reflecting: type(of: view))
                guard !view.isHidden, !name.hasPrefix("_"), !name.hasPrefix("SwiftUI."), !name.contains("HostingView") else { return [] }
                let acts = (view as? NSButton)?.isEnabled == true || view is NoSessionFace || view is GlyphButton || view is ProjectButton
                    || (view as? FaceStackView)?.clickable == true || view is KeyField
                return (acts ? [view] : []) + view.subviews.flatMap(shown)
            }
            for view in shown(rowView) where !view.tracksHandCursor {
                bare.append("row \(row): \(type(of: view)) \(view.identifier?.rawValue ?? view.toolTip ?? "-")")
            }
        }
        await check("every AppKit view a click acts on in a row shows the pointing hand", bare.isEmpty, bare.prefix(5).joined(separator: "; "))
        // Every part a click acts on shows the hand as the window gives it, the page scrolled: a card's links and
        // blocking tasks too, whose clicks go to the outline (T-453).
        model.link(.github("https://github.com/acme/registry/pull/9101"), to: parent.id)
        model.link(.web("https://example.com/hand"), to: parent.id)
        model.addLink(parent.id, .blockedBy, above.id)
        await endUndoGroup(model)
        if parentRow() >= 0 { outline.scrollRowToVisible(parentRow()) }
        await ui.settle(0.5)
        let card = (outline.view(atColumn: 1, row: parentRow(), makeIfNecessary: false) as? TaskCell)
        var bareParts = ui.partsWithoutHand()
        if let grid = ui.find(SessionGrid.CardCollection.self) {
            grid.scrollToVisible(grid.bounds)
            await ui.settle(0.4)
            bareParts += ui.partsWithoutHand()
        }
        await check("every AppKit part a click acts on shows the pointing hand, as the window gives it, links and blockers too (T-453)",
                    bareParts.isEmpty && card?.links.handParts.count == 2 && card?.blockers.handParts.count == 1,
                    "links \(card?.links.handParts.count ?? -1), blockers \(card?.blockers.handParts.count ?? -1); " + bareParts.prefix(6).joined(separator: "; "))
        model.indentTasks([parent.id])
        await endUndoGroup(model)
        await ui.settle(0.6)
        result = await caret(parent.id)
        await check("indented with its subtasks, its chevron stays on its line", result.ok, result.detail)
        result = await caret(above.id)
        await check("and its new parent gets one on its line", result.ok, result.detail)
        model.outdentTasks([parent.id])
        await endUndoGroup(model)
        await ui.settle(0.6)
        result = await caret(parent.id)
        await check("outdented, its chevron stays on its line", result.ok, result.detail)
        model.toggleList(parent.id)
        await endUndoGroup(model)
        await ui.settle(0.6)
        model.backlogOpen = true
        await ui.settle(0.4)
        result = await caret(parent.id)
        await check("moved to the Backlog, it keeps its chevron on its line", result.ok, result.detail)
        model.toggleList(parent.id)
        await endUndoGroup(model)
        await ui.settle(0.6)
        result = await caret(parent.id)
        await check("and back in Tasks too", result.ok, result.detail)
        // Shut in the outline while the model has it open: the outline opens it again, its subtask back.
        let repairs = OutlineCoordinator.repairs
        AppLog.expected.append("T-\(parent.id) open in the model, shut in the outline")
        outline.collapseItem(coordinator.node(.task(parent.id)))
        model.setFold(parent.id, .all)
        await ui.settle(0.6)
        await check("a task open in the model but shut in the outline opens again with its subtasks",
              OutlineCoordinator.repairs > repairs && outline.isItemExpanded(coordinator.node(.task(parent.id)))
              && outline.row(forItem: coordinator.node(.task(child.id))) >= 0 && AppLog.expected.isEmpty, "\(OutlineCoordinator.repairs - repairs) repairs")
        AppLog.expected = []
        OutlineCoordinator.repairs = repairs
        // ⇧-arrows held down never take a task out of its parent; a press still does.
        coordinator.select(child.id)
        await ui.settle(0.3)
        await ui.key(.left, .shift, held: true)
        await ui.key(.down, .shift, held: true)
        await ui.settle(0.4)
        await check("held ⇧← and ⇧↓ leave a subtask in its parent", model.taskTree.parent(of: child.id) == parent.id,
              "parent \(String(describing: model.taskTree.parent(of: child.id)))")
        await ui.key(.down, .shift)
        await ui.settle(0.4)
        await check("a press of ⇧↓ on the last subtask still takes it out", model.taskTree.parent(of: child.id) == nil)
        model.undoManager?.undo()
        await ui.settle(0.4)
        model.deleteTasks([child.id, parent.id, above.id])
        await endUndoGroup(model)
        await ui.settle(0.3)
    }

    /// A click on a PR's face, in Reviews and in Yours, shows its session's menu under the face, an ended session's too.
    static func prFaces(_ model: AppModel, _ ui: Driver) async {
        guard let ended = model.sessions.first(where: { !$0.isRunning }) else { return await check("an ended session", false) }
        let show = FaceMenu.show
        defer { FaceMenu.show = show }
        for (group, pr) in [("Reviews", model.reviewRequests.first), ("Yours", model.ownPullRequests.first)] {
            guard let pr else { await check("a PR in \(group)", false); continue }
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
            await check("a click on a PR's face in \(group) shows its session's menu under the face, not Start Session",
                  shown?.id == first && shown?.view != nil && model.modal == nil,
                  "shown \(shown?.id ?? "-"), first \(first ?? "-"), hit \(hit.map { String(describing: type(of: $0)) } ?? "-"), \(String(describing: model.modal))")
            await check("its menu starts another session on the PR", titles.contains { $0.hasPrefix("Start Another Session on \(pr.reference)") },
                  titles.joined(separator: ", "))
            if model.modal != nil { model.closeModal(); await ui.settle(0.5) }
            if var item = model.session(ended.id) { item.links.removeAll { $0 == pr.url }; model.put(item) }
        }
    }

    /// The bell opens the center; a chip opens its item over it and Back returns; Read acts on a selected row; Remind Me… shows its form.
    static func notificationCenter(_ model: AppModel, _ ui: Driver) async {
        model.closeModal()
        await ui.settle(0.5)
        await check("the toolbar has the bell, breathing while something needs the user", ui.anchor("bell") != nil && model.bellBreathes)
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
            await check("the bell and New show the pointing hand, and leaving them gives the arrow back",
                  toolbarHands.count == 2 && toolbarHands.allSatisfy { $0.trackingAreas.contains { $0.options.contains(.cursorUpdate) } }
                  && entered && NSCursor.current == NSCursor.arrow, "\(toolbarHands.count) hands, entered \(entered)")
        } else {
            await check("the toolbar's items track the pointing hand", false, "\(toolbarHands.count) hands")
        }
        await ui.click(ui.anchor("bell"))
        await ui.until(2) { model.modal == .notifications }
        await check("a click on the bell opens the center", model.modal == .notifications, "\(String(describing: model.modal))")
        await check("and the bell stops breathing", !model.bellBreathes)
        await check("a session that waits shows in Needs You with Focus", model.blockedSessions.allSatisfy { ui.anchor("blocked:\($0.id)") != nil })
        await check("a PR that waits for the user's review stands in Needs You, with Later (T-319)", !model.waitingReviews.isEmpty
              && model.waitingReviews.allSatisfy { ui.anchor("review:\($0.url)") != nil && ui.anchor("review-later:\($0.url)") != nil },
              "\(model.waitingReviews.count) waiting")
        guard let row = model.notices(in: .updates).first(where: { $0.readAt == nil && !$0.links.isEmpty }) else { return await check("an update with links", false) }
        if let frame = ui.anchorFrame("notice:\(row.id.uuidString)"), let face = ui.anchorFrame("notice-avatar:\(row.id.uuidString)") {
            await check("a card's face or tile starts at its padding, as on a task's card (no unread dot)",
                  abs(face.minX - frame.minX - Metric.cardPadding) < 1, "\(face.minX - frame.minX) pt in")
        } else {
            await check("a row's face or tile has its anchor", false)
        }
        let link = row.links[0]
        let chip = await ui.steadyAnchor("notice-chip:\(row.id.uuidString):\(link)")
        await check("a row shows its links as chips", chip != nil, link)
        await ui.click(chip, inSheet: true)
        await ui.until(2) { model.modal != .notifications }
        await check("a chip opens its item over the center", model.modal == ModalRoute(noticeKey: link) && model.modalStack.last == .notifications,
              "\(String(describing: model.modal)) over \(model.modalStack)")
        await check("and reads its row", model.notices.first { $0.id == row.id }?.readAt != nil)
        await ui.back()
        await ui.until(2) { model.modal == .notifications }
        await check("Back returns to the center", model.modal == .notifications, "\(String(describing: model.modal))")
        await check("where the row read went to Earlier at once (T-365)", model.notices(in: .earlier).contains { $0.id == row.id }
              && !model.notices(in: .updates).contains { $0.id == row.id })

        // A long text: three lines at rest, its toggle shows all of it; selecting it doesn't (T-458). Many links: one line.
        let long = model.notify(String(repeating: "A notification with a long text that needs more than three lines. ", count: 12), level: .update,
                                source: "uitest-long", links: (40...47).map { "task:\($0)" } + ["github:https://github.com/acme/registry/pull/418"])
        await ui.settle(0.4)
        func height() -> CGFloat { ui.anchorFrame("notice:\(long.id.uuidString)")?.height ?? 0 }
        /// Cards that overlap the one under them, in the center.
        func overlaps() -> [String] {
            let cards = (model.notices.map { "notice:\($0.id.uuidString)" } + model.blockedSessions.map { "blocked:\($0.id)" })
                .compactMap { ui.anchorFrame($0) }.sorted { $0.minY < $1.minY }
            return zip(cards, cards.dropFirst()).filter { $0.maxY > $1.minY + 0.5 && $0.minX < $1.maxX && $1.minX < $0.maxX }.map { "\($0.integral) over \($1.integral)" }
        }
        let rest = height()
        model.noticeSelection = long.id.uuidString
        await ui.settle(0.3)
        await check("a long notification shows three lines, its links on one line, and its toggle; selecting it shows no more (T-458)",
                    ui.anchor("more:\(long.id.uuidString)") != nil && rest > 0 && rest < 200 && abs(height() - rest) < 1, "\(rest) → \(height())")
        await ui.click(await ui.steadyAnchor("more:\(long.id.uuidString)"), inSheet: true)
        await check("its toggle shows all of it, and no card runs over the next", height() > rest + Space.xl && overlaps().isEmpty,
                    "\(rest) → \(height()); \(overlaps().prefix(2))")
        await ui.click(await ui.steadyAnchor("more:\(long.id.uuidString)"), inSheet: true)
        await check("and three lines again", abs(height() - rest) < 1, "\(rest) → \(height())")
        model.notices.removeAll { $0.id == long.id }
        model.noticeSelection = nil
        if let other = model.notices(in: .updates).first(where: { $0.readAt == nil }) {
            // Selected, as a click or the arrows select it: its Read shows.
            model.noticeSelection = other.id.uuidString
            await ui.settle(0.3)
            await ui.click(await ui.steadyAnchor("read:\(other.id.uuidString)"), inSheet: true)
            await ui.settle(0.3)
            await check("Read on a selected row reads it", model.notices.first { $0.id == other.id }?.readAt != nil)
        } else {
            await check("a second unread update", false)
        }

        // A due reminder: what it links opens over the center and it stays to be done, with its actions.
        let task = model.addTask(to: .overview, title: "Reminder's task")
        let due = model.remind("Check the canary", at: .now.addingTimeInterval(-1), level: .important, links: task.map { ["task:\($0.id)"] } ?? [])
        model.fireDue()
        await ui.settle(0.4)
        if let task {
            await ui.click(await ui.steadyAnchor("notice-chip:\(due.id.uuidString):task:\(task.id)"), inSheet: true)
            await ui.until(2) { model.modal == .task(task.id) }
            await check("a reminder's link opens over the center", model.modal == .task(task.id), "\(String(describing: model.modal))")
            await check("and leaves the reminder to be done", model.notices.first { $0.id == due.id }?.readAt == nil)
            await ui.back()
            await ui.until(2) { model.modal == .notifications }
        }
        model.noticeSelection = due.id.uuidString
        await ui.settle(0.3)
        await check("a due reminder stays in Needs You with Edit, Later and Done", model.notices(in: .needsYou).contains { $0.id == due.id }
              && ["edit", "later", "read"].allSatisfy { ui.anchor("\($0):\(due.id.uuidString)") != nil })
        let after = (model.notices(in: .needsYou) + model.notices(in: .updates) + model.notices(in: .later))
            .drop { $0.id != due.id }.dropFirst().first?.id
        await ui.click(await ui.steadyAnchor("read:\(due.id.uuidString)"), inSheet: true)
        await ui.settle(0.3)
        await check("Done completes it and it goes to Earlier at once (T-365)", model.notices.first { $0.id == due.id }?.readAt != nil
              && !model.notices(in: .needsYou).contains { $0.id == due.id } && model.notices(in: .earlier).contains { $0.id == due.id })
        await check("the selection goes on to the row after it", after == nil || model.noticeSelection == after?.uuidString,
              "\(String(describing: model.noticeSelection)) for \(String(describing: after))")

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
        func filled() -> NSTextField? { fields(ui.window.attachedSheet?.contentView).first { $0.placeholderString == "Remind me to…" } }
        await check("Edit turns a reminder into its editor, filled in", ui.anchor("reminder-text") != nil && filled()?.stringValue == "Call the bank",
              filled()?.stringValue ?? "no field")
        await ui.click(await ui.steadyAnchor("reminder-important"), inSheet: true)
        await ui.click(await ui.steadyAnchor("reminder-add"), inSheet: true)
        await ui.settle(0.4)
        await check("and Save keeps what changed", model.notices.first { $0.id == waiting.id }?.level == .update && ui.anchor("reminder-text") == nil)

        // The When picker: the time of a row in Later opens it; a choice sets the time.
        model.noticeSelection = waiting.id.uuidString
        await ui.settle(0.3)
        await ui.click(await ui.steadyAnchor("due:\(waiting.id.uuidString)"), inSheet: true)
        await ui.settle(0.6)
        if await ui.clickInPopover("when:tomorrow") {
            await check("a choice in the When picker sets the time", model.notices.first { $0.id == waiting.id }?.dueAt == ReminderTime.date(.tomorrow))
        } else {
            skip("a choice in the When picker sets the time")
        }

        // New Reminder… is its own sheet, the keyboard in its text; over the center, Back returns there.
        model.beginReminder()
        await ui.until(2) { model.modal == .newReminder }
        await ui.settle(0.6)
        await check("New Reminder… opens its sheet with the keyboard in the text", model.modal == .newReminder
              && ui.anchor("new-reminder-text") != nil && ui.window.attachedSheet?.firstResponder is NSText,
              "\(String(describing: model.modal)), \(ui.sheetResponder)")
        let sheet = ui.window.attachedSheet
        if let editor = sheet?.firstResponder as? NSTextView {
            editor.insertText("Look at the canary again", replacementRange: editor.selectedRange())
            await ui.settle(0.2)
        }
        let before = model.notices.count
        await ui.click(await ui.steadyAnchor("new-reminder-add"), inSheet: true)
        await ui.until(2) { model.modal == .notifications }
        await check("Add Reminder puts it in Later and goes back to the center", model.notices.count == before + 1
              && model.notices(in: .later).contains { $0.text == "Look at the canary again" } && model.modal == .notifications,
              "\(model.notices.count - before) added, \(String(describing: model.modal))")
        model.closeModal()
        await ui.settle(0.5)
        await check("once the center closes, what was read is in Earlier", model.notices(in: .earlier).contains { $0.id == row.id })
        // Earlier folds as a page section does, folded until the user opens it (the setting is the user's: set here, never saved).
        model.earlierOpen = false
        model.openCenter()
        await ui.settle(0.6)
        await check("Earlier shows folded: its rows stay out of sight", ui.anchor("notice:\(due.id.uuidString)") == nil)
        model.earlierOpen = true
        await ui.settle(0.5)
        await check("opened, it shows the reminder just done", ui.anchor("notice:\(due.id.uuidString)") != nil)
        model.earlierOpen = false
        model.closeModal()
        if let task { model.deleteTasks([task.id]) }
        await ui.settle(0.3)
    }

    /// With one session on the grid, a real click on its face focuses it, its card selected or not.
    static func singleSessionFace(_ model: AppModel, _ ui: Driver) async {
        guard let collection = ui.find(SessionGrid.CardCollection.self), let grid = collection.delegate as? SessionGrid.Coordinator,
              let only = grid.ids.first else { return await check("a session card", false) }
        // The others closed a moment, teams too: one card left.
        let others = model.sessions.filter { $0.id != only && $0.closedAt == nil }.map(\.id)
        func close(_ closed: Bool) { for id in others { if var item = model.session(id) { item.closedAt = closed ? .now : nil; model.put(item) } } }
        close(true)
        await ui.settle(0.6)
        await check("one card left on the grid", grid.ids == [only], "\(grid.ids.count) cards")
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
        let unselected = await faceClick()
        await tableCheck(ui, "the only card's face, unselected, focuses its session", unselected, "\(model.ghosttyLog.suffix(1))")
        grid.collectionView(collection, didSelectItemsAt: [IndexPath(item: 0, section: 0)])
        collection.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
        await ui.settle(0.3)
        let selected = await faceClick()
        await tableCheck(ui, "selected, its face still focuses its session", selected, "\(model.ghosttyLog.suffix(1))")
        close(false)
        model.selectSection(nil)
        await ui.settle(0.4)
    }

    /// A row's description toggle sits after its title, the hover actions don't repeat it; the grip and the dot keep apart.
    static func rowControls(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator else { return await check("the outline is on the page", false) }
        model.folded = []
        model.search = ""
        model.allDescriptions = []
        guard let plain = model.addTask(to: .overview, title: "No description"),
              let noted = model.addTask(to: .overview, title: "With a description", body: "Some words.") else { return await check("tasks for the toggle", false) }
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
        guard let quiet = await row(plain.id), let full = await row(noted.id) else { return await check("the rows are on the page", false) }
        // Nothing under the pointer (2026-11-10); a card with a description has its button in the corner (after the fourth preview).
        func shown(_ cell: TaskCell) -> [String] {
            cell.subviews.filter { !$0.isHidden && $0.frame.width > 0 }.map { "\(type(of: $0))" }.sorted()
        }
        func buttons(_ cell: TaskCell) -> [NSButton] { cell.subviews.compactMap { $0 as? NSButton }.filter { !$0.isHidden } }
        await check("a card's only button at rest is its description button, when it has a description",
              buttons(full.cell).map { $0 === full.cell.note } == [true] && buttons(quiet.cell).isEmpty,
              (buttons(full.cell) + buttons(quiet.cell)).compactMap(\.toolTip).joined(separator: ", "))
        let atRest = shown(quiet.cell)
        let facesAtRest = quiet.faces.subviews.filter { !$0.isHidden }.count
        quiet.row.onHover(true)
        quiet.cell.layoutSubtreeIfNeeded()
        quiet.faces.layoutSubtreeIfNeeded()
        await check("nothing shows under the pointer", shown(quiet.cell) == atRest && quiet.faces.subviews.filter { !$0.isHidden }.count == facesAtRest,
              "\(atRest) → \(shown(quiet.cell))")
        quiet.row.onHover(false)
        model.toggleDescription(noted.id)
        await ui.settle(0.4)
        _ = await row(noted.id)
        func described() -> TaskCell? {
            let index = outline.row(forItem: coordinator.node(.task(noted.id)))
            return index < 0 ? nil : outline.view(atColumn: 1, row: index, makeIfNecessary: false) as? TaskCell
        }
        await check("Show Description shows it in the card", model.descriptionShownInOutline(noted.id) && described()?.descriptionHost != nil)
        model.toggleDescription(noted.id)
        await ui.settle(0.4)
        await check("and hides it", !model.descriptionShownInOutline(noted.id))
        // Shown by the list's Descriptions, Hide Description hides that one.
        model.allDescriptions = [.overview]
        await ui.settle(0.4)
        model.toggleDescription(noted.id)
        await ui.settle(0.4)
        await check("with Descriptions on, Hide Description hides that one", !model.descriptionShownInOutline(noted.id))
        model.toggleDescription(noted.id)
        await check("and shows it again", model.descriptionShownInOutline(noted.id))
        model.allDescriptions = []
        // One face per row, the same open or folded: the task's own session, never a subtask's (T-346).
        let ranked = model.byImportance(model.gridSessions)
        if let top = ranked.first, let low = ranked.last, top.id != low.id, let sub = model.addSubtask(to: plain.id, title: "Under it") {
            model.link(task: plain.id, session: low.id)
            model.link(task: sub.id, session: top.id)
            model.setFold(plain.id, .all)
            await endUndoGroup(model)
            await ui.settle(0.5)
            let openRow = await row(plain.id)
            let open = openRow?.faces.shownSession
            model.setFold(plain.id, .hidden)
            await ui.settle(0.5)
            let foldedRow = await row(plain.id)
            let folded = foldedRow?.faces.shownSession
            await check("a task shows its own session's face, open or folded", open == low.id && folded == low.id, "open \(open ?? "-"), folded \(folded ?? "-")")
            // Its parent's session too: every card shows its face (T-452).
            model.setFold(plain.id, .all)
            model.unlink(task: sub.id, session: top.id)
            model.link(task: sub.id, session: low.id)
            await endUndoGroup(model)
            await ui.settle(0.5)
            let subFace = await row(sub.id)?.faces.shownSession
            await check("a subtask shows its session's face when it's its parent's too (T-452)", subFace == low.id, subFace ?? "none")
            model.unlink(task: sub.id, session: low.id)
            model.unlink(task: plain.id, session: low.id)
            model.deleteTasks([sub.id])
            await endUndoGroup(model)
            await ui.settle(0.4)
        } else {
            await check("two sessions and a subtask for the face check", false)
        }
        // Rows hold still until AppKit ends a drag, also once the button is up: a drop elsewhere changes the model before the
        // drag's end, and AppKit then closes its drop gap on the rows it had (T-353, a crash).
        // The button as the test says, never the user's own mouse beside the run.
        OutlineCoordinator.buttonDown = { false }
        let rowsBefore = outline.numberOfRows
        coordinator.dragBegan([plain.id])
        let added = model.addTask(to: .overview, title: "Added mid-drag")
        await ui.settle(0.8)
        await check("rows hold still while a drag ends, the button up", outline.numberOfRows == rowsBefore && coordinator.dragged == [plain.id],
              "\(rowsBefore) → \(outline.numberOfRows) rows, dragged \(coordinator.dragged)")
        coordinator.dragEnded()
        await ui.settle(0.6)
        await check("and move once it ended", outline.numberOfRows > rowsBefore && added.map { outline.row(forItem: coordinator.node(.task($0.id))) >= 0 } == true)
        // A drag whose end never comes lets the rows go 3 s after the button is up.
        coordinator.dragBegan([plain.id])
        AppLog.expected.append("a drag of [\(plain.id)] never ended")
        if let late = model.addTask(to: .overview, title: "Added after a lost drag") {
            await ui.wait(1)
            let held = !coordinator.dragged.isEmpty
            await ui.until(4) { coordinator.dragged.isEmpty }
            await check("a drag that never ends holds the rows 3 s, no more",
                        held && coordinator.dragged.isEmpty && outline.row(forItem: coordinator.node(.task(late.id))) >= 0 && AppLog.expected.isEmpty)
            AppLog.expected = []
            model.deleteTasks([late.id])
        }
        OutlineCoordinator.buttonDown = { NSEvent.pressedMouseButtons & 1 != 0 }
        if let added { model.deleteTasks([added.id]) }
        await endUndoGroup(model)
        await ui.settle(0.4)
        // A title being edited takes the row's width at once, also when the keyboard goes straight from another title (T-351).
        coordinator.beginEditing(noted.id)
        await ui.settle(0.3)
        if let target = await row(plain.id) {
            ui.window.makeFirstResponder(target.cell.title)
            await ui.settle(0.3)
            if let edited = await row(plain.id) {
                let room = edited.cell.bounds.width - TaskCell.titleX
                await check("a title edited straight after another takes the row's width", edited.cell.title.currentEditor() != nil
                      && edited.cell.title.frame.width > room / 2, "\(edited.cell.title.frame.width) of \(room)")
            }
        }
        ui.window.makeFirstResponder(outline)
        await ui.settle(0.3)
        // Link… on a row: the link picker opens under it, in its own popover (T-298). The row is on screen, as when right-clicked.
        _ = await row(plain.id)
        model.showLinkPicker(plain.id)
        await ui.settle(0.6)
        func picker() -> NSView? { UITest.anchors["link-picker", default: []].compactMap(\.view).last { $0.window != nil && $0.window !== ui.window } }
        await check("Link… on a task's row opens the link picker under it", picker() != nil && outline.selectedRowIndexes.count == 1,
              "row \(outline.row(forItem: coordinator.node(.task(plain.id)))), \(UITest.anchors["link-picker", default: []].compactMap(\.view).count) pickers, selected \(outline.selectedRowIndexes.count), modal \(String(describing: model.modal))")
        picker()?.window?.close()
        await ui.settle(0.3)
        // A reminder that links the task: its mark before the title, the title after it (T-311).
        let reminder = model.remind("Look at it again", at: .now.addingTimeInterval(3600), level: .important, links: [ModalRoute.task(plain.id).selectionKey])
        await ui.until(3) {
            let index = outline.row(forItem: coordinator.node(.task(plain.id)))
            return index >= 0 && (outline.view(atColumn: 1, row: index, makeIfNecessary: false) as? TaskCell)?.reminderMark.isHidden == false
        }
        if let listed = await row(plain.id) {
            let mark = listed.cell.reminderMark
            // After the key, on the first line: before the title on a card, before the project on a big card.
            let cell = listed.cell
            let placed = cell.stack.big ? abs(mark.frame.midY - cell.glyph.frame.midY) < 1 && (cell.project.isHidden || cell.project.frame.minX >= mark.frame.maxX)
                : cell.title.frame.minX >= mark.frame.maxX
            await check("a reminder that links a task shows after its key, on its first line", !mark.isHidden && mark.frame.minX >= cell.key.frame.maxX && placed
                  && (mark.toolTip ?? "").contains("Look at it again"), "\(mark.isHidden) \(mark.frame) key \(cell.key.frame) title \(cell.title.frame)")
        } else {
            await check("the task's row for its reminder", false)
        }
        model.removeNotice(reminder.id)
        await ui.settle(0.4)
        if let listed = await row(plain.id) { await check("and leaves with the reminder", listed.cell.reminderMark.isHidden) }
        model.deleteTasks([plain.id, noted.id])
        await endUndoGroup(model)
        await ui.settle(0.3)
    }

    static func foldedParentOpens(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator,
              let container = outline.superview as? OutlineContainer else { return await check("the outline is on the page", false) }
        model.folded = []
        model.search = ""
        guard let above = model.addTask(to: .overview, title: "Fold above"), let parent = model.addTask(to: .overview, title: "Fold parent") else {
            return await check("tasks to fold", false)
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
        model.setFold(above.id, .hidden)
        model.setFold(parent.id, .hidden)
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
                    problems.append("\(step): T-\(id) can't be clicked: \(ui.titlePoint(id).flatMap { ui.hitView($0) }.map { String(describing: type(of: $0)) } ?? "nothing")")
                    continue
                }
            }
        }
        await fits("loaded folded")
        await check("a task that hides its subtasks shows none", subtasks.allSatisfy { outline.row(forItem: coordinator.node(.task($0))) < 0 })
        func disclose(_ id: Int) async {
            let row = outline.row(forItem: coordinator.node(.task(id)))
            guard row >= 0 else { return problems.append("T-\(id) has no row") }
            outline.scrollRowToVisible(row)
            await ui.settle(0.2)
            if ui.canClickTables, let fold = (outline.view(atColumn: 1, row: row, makeIfNecessary: false) as? TaskCell)?.fold {
                await ui.click(fold.convert(NSPoint(x: fold.bounds.midX, y: fold.bounds.midY), to: nil))
            } else {
                coordinator.fold([id], model.fold[id] == .hidden ? .all : .hidden)
            }
            await ui.settle(0.8)
        }
        await disclose(parent.id)
        await check("a folded task opens from its chevron", outline.isItemExpanded(coordinator.node(.task(parent.id))) && model.fold[parent.id] == .all
              && subtasks.allSatisfy { outline.row(forItem: coordinator.node(.task($0))) >= 0 })
        await fits("opened")
        await disclose(above.id)
        await fits("above opened")
        await disclose(parent.id)
        await fits("folded again")
        await disclose(parent.id)
        await fits("opened again")
        await check("opening folded tasks keeps every row in the outline and clickable", problems.isEmpty, problems.prefix(6).joined(separator: "; "))
        // The chevron toggles: subtasks shown, hidden, shown again; a story's filter keeps only its Blocked and doing tasks,
        // with the tasks above them; not one only blocked by another task (T-442, 2026-11-12).
        if subtasks.count > 15, let deep = model.taskTree.children(of: subtasks[4]).first,
           let inner = model.addSubtask(to: subtasks[13], title: "Inner, doing") {
            problems = []
            for id in subtasks.prefix(7) + [inner.id] { model.setStatus(id, .doing) }
            model.addLink(subtasks[10], .blockedBy, subtasks[9])
            model.addLink(subtasks[11], .blockedBy, deep)
            model.block(subtasks[12])
            model.setFold(subtasks[13], .hidden)
            await endUndoGroup(model)
            await ui.settle(0.8)
            func cell(_ id: Int) -> TaskCell? {
                let row = outline.row(forItem: coordinator.node(.task(id)))
                return row < 0 ? nil : outline.view(atColumn: 1, row: row, makeIfNecessary: true) as? TaskCell
            }
            func shown() -> Set<Int> { Set((subtasks + [deep, inner.id]).filter { outline.row(forItem: coordinator.node(.task($0))) >= 0 }) }
            // Looked up again after the scroll, which can give its cell to another row (T-436).
            func press(_ find: @autoclosure () -> NSButton?) async {
                guard let first = find() else { return problems.append("no button") }
                outline.scrollRowToVisible(outline.row(for: first))
                await ui.settle(0.2)
                guard let button = find() else { return problems.append("no button after the scroll") }
                if ui.canClickTables { await ui.click(button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)) } else { button.performClick(nil) }
                await ui.settle(0.6)
            }
            // A click on the chevron hides them all, the next shows them all: no third state.
            await press(cell(parent.id)?.fold)
            let hidden = subtasks.allSatisfy { outline.row(forItem: coordinator.node(.task($0))) < 0 }
            await press(cell(parent.id)?.fold)
            await check("a task's chevron hides its subtasks, and its next click shows them all again",
                  hidden && subtasks.allSatisfy { outline.row(forItem: coordinator.node(.task($0))) >= 0 } && model.fold[parent.id] == .all,
                  "hidden \(hidden), \(String(describing: model.fold[parent.id])), \(problems)")
            await check("its tooltip says what a click does", cell(parent.id)?.fold.toolTip == "Hide its subtasks (←)", cell(parent.id)?.fold.toolTip ?? "-")
            // The filter button: on a story with subtasks only.
            await check("a story with subtasks has the filter button, a subtask with its own has none",
                  cell(parent.id)?.filter.isHidden == false && cell(subtasks[13])?.filter.isHidden == true && cell(subtasks[13])?.fold.isHidden == false)
            model.setDescription(parent.id, "Why the story exists.")
            await endUndoGroup(model)
            await ui.settle(0.4)
            func order() -> (note: NSRect, filter: NSRect, fold: NSRect)? {
                guard let story = cell(parent.id), !story.note.isHidden, !story.filter.isHidden else { return nil }
                return (story.note.frame, story.filter.frame, story.fold.frame)
            }
            await check("on a story's card, right to left: the chevron, the filter button, the description button",
                  order().map { $0.filter.maxX <= $0.fold.minX + 0.5 && $0.note.maxX <= $0.filter.minX + 0.5 && abs($0.note.midY - $0.filter.midY) < 0.5 } == true,
                  String(describing: order()))
            model.setDescription(parent.id, "")
            await endUndoGroup(model)
            coordinator.select(subtasks[15])
            await ui.settle(0.3)
            await press(cell(parent.id)?.filter)
            let expected = Set(subtasks.prefix(7) + [subtasks[12], subtasks[13], inner.id])
            await check("the story's filter keeps its doing and Blocked tasks with the tasks above them, opened; none only blocked by another or todo",
                  shown() == expected && model.storyFilter == [parent.id], "shown \(shown().sorted()) expected \(expected.sorted())")
            await check("its button turns the accent, its tooltip says so", cell(parent.id)?.filter.contentTintColor == Ink.accentNS
                  && cell(parent.id)?.filter.toolTip?.hasPrefix("Showing only") == true, cell(parent.id)?.filter.toolTip ?? "-")
            await check("a selected task the filter hides gives the selection to its story", model.selectedTasks == [parent.id], "\(model.selectedTasks)")
            await fits("filtered")
            await press(cell(parent.id)?.filter)
            await check("off, the story shows all its tasks again", model.storyFilter.isEmpty
                  && subtasks.allSatisfy { outline.row(forItem: coordinator.node(.task($0))) >= 0 }, "shown \(shown().count) of \(subtasks.count + 2)")
            await check("and every row stays in the outline and clickable", problems.isEmpty, problems.prefix(6).joined(separator: "; "))
            model.deleteTasks([inner.id])
            await endUndoGroup(model)
            model.setFold(subtasks[13], nil)
            await ui.settle(0.4)
        } else {
            await check("a story with over 15 subtasks, one of them with its own", false)
        }
        // The Backlog folded, the last tasks of Tasks opened one after the other: its header stays on the page.
        problems = []
        model.backlogOpen = false
        for id in below.suffix(2) { for index in 0..<6 { _ = model.addSubtask(to: id, title: "Late \(index)") } }
        await endUndoGroup(model)
        await ui.settle(0.6)
        for id in below.suffix(2) { model.setFold(id, .hidden) }
        model.folded = [.tasks]
        await ui.settle(0.6)
        model.folded = []
        await ui.settle(0.8)
        for id in below.suffix(2) {
            coordinator.fold([id], .all)
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
        await check("with the Backlog folded, opening the last tasks keeps its header on the page", problems.isEmpty, problems.prefix(6).joined(separator: "; "))
        model.backlogOpen = true
        model.deleteTasks([above.id, parent.id] + below)
        await endUndoGroup(model)
        await ui.settle(0.4)
    }

    /// Typing anywhere on the page never leaves the outline shorter than its rows: the rows below stay.
    /// The large seed (500 tasks, 30 sessions), with notes so vault rescans keep its tasks.
    static func seedLarge(_ model: AppModel) {
        SeedData.fillLarge(model, now: .now)
        guard let vault = model.vault else { return }
        var tasks = model.tasks
        for index in tasks.indices where tasks[index].path == nil {
            tasks[index].path = vault.tasksDirectory.appending(path: "T-\(tasks[index].id).md").path
            try? vault.save(tasks[index])
        }
        model.tasks = tasks
    }

    static func typingKeepsRows(_ model: AppModel, _ ui: Driver) async {
        // On the large seed, where the page once gave the outline half its rows' height after a search.
        seedLarge(model)
        await ui.settle(3)
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator,
              let container = outline.superview as? OutlineContainer else { return await check("the outline is on the page", false) }
        var short: [String] = []
        func holds() -> Bool {
            let backlog = outline.row(forItem: coordinator.node(.header(.backlog)))
            let bottom = backlog >= 0 ? outline.rect(ofRow: backlog).maxY : 0
            return container.frame.height + 0.5 >= container.contentHeight && container.frame.height + 0.5 >= bottom && outline.frame.height + 0.5 >= bottom
        }
        // The page takes the rows' new height on its next layout, which a settle at its limit can come before: judged once it did.
        func fits(_ step: String) async {
            await ui.until(2) { holds() }
            if !holds() { short.append("\(step): frame \(Int(container.frame.height)) outline \(Int(outline.frame.height)) rows \(Int(container.contentHeight)), 2 s on") }
        }
        model.backlogOpen = true
        await ui.settle(0.6)
        await fits("open")
        guard let parent = model.addTask(to: .overview, title: "Typing parent"), let child = model.addSubtask(to: parent.id, title: "First child") else {
            return await check("tasks to type in", false)
        }
        await endUndoGroup(model)
        await ui.settle(0.6)
        await fits("added")
        // A new subtask's title, as the user types one.
        coordinator.select(child.id)
        ui.window.makeFirstResponder(outline)
        await ui.key("n", code: 45)
        await ui.settle(0.5)
        for (index, letter) in "Everything below stays".enumerated() {
            await ui.key(String(letter))
            if index % 4 == 0 { await ui.settle(0.15) }
            await fits("title \(index)")
        }
        await ui.key(.return)
        await ui.settle(0.6)
        await fits("title saved")
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
            await fits("description \(line)")
        }
        await ui.key(.escape)
        await ui.settle(0.6)
        await fits("description saved")
        // The lists' searches and the toolbar's.
        for (index, text) in ["T", "Ty", "Typ", "Typi", "Typ", "", "zz", ""].enumerated() {
            model.listSearch[.overview] = text.isEmpty ? nil : text
            await ui.settle(0.15)
            await fits("list search \(index)")
        }
        for (index, text) in ["c", "cd", "cdn", "cd", "", "x", ""].enumerated() {
            model.search = text
            await ui.settle(0.15)
            await fits("search \(index)")
        }
        await ui.settle(0.6)
        await fits("end")
        await check("typing never leaves the outline shorter than its rows", short.isEmpty, short.prefix(6).joined(separator: "; "))
        await check("the outline's rows always matched its snapshot", OutlineCoordinator.repairs == 0, "\(OutlineCoordinator.repairs) repairs")
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
        await check("Window lists HQ once", window.filter { $0 == "HQ" }.count == 1, window.joined(separator: ", "))
        await check("View has no toolbar items: the toolbar holds the title and the search", !titles("View").contains { $0.contains("Toolbar") },
              titles("View").joined(separator: ", "))
        await check("Help has Keyboard Shortcuts", titles("Help").contains("Keyboard Shortcuts"), titles("Help").joined(separator: ", "))
        // ⌘W closes the modal, not the window.
        if let close = menu("File")?.items.first(where: { $0.keyEquivalent == "w" && $0.keyEquivalentModifierMask == .command }),
           let file = close.menu, let task = model.addTask(to: .overview, title: "Close me") {
            model.open(.task(task.id))
            await ui.settle(0.6)
            ui.window.makeKey()
            file.performActionForItem(at: file.index(of: close))
            await ui.settle(0.6)
            await check("⌘W closes the modal and leaves the window", model.modal == nil && ui.window.isVisible, String(describing: model.modal))
            model.closeModal()
            await ui.settle(0.4)
        } else {
            await check("File has Close ⌘W", false, titles("File").joined(separator: ", "))
        }
        // Several Backlog rows: Move to Tasks, and it moves them.
        if let a = model.addTask(to: .backlog, title: "Back one"), let b = model.addTask(to: .backlog, title: "Back two") {
            await endUndoGroup(model)
            model.selectedTasks = [a.id, b.id]
            model.syncMenu()
            await check("with several Backlog rows selected the Task menu moves them to Tasks", !MenuState.shared.tasksToBacklog)
            model.moveTasks([a.id, b.id], toBacklog: MenuState.shared.tasksToBacklog)
            await check("and they go", model.list(of: a.id) == .overview && model.list(of: b.id) == .overview)
            model.selectedTasks = []
            model.deleteTasks([a.id, b.id])
            await endUndoGroup(model)
        }
        // A PR selected on the page: the menu bar's Open on GitHub and Copy Link act on it.
        if let pr = model.reviewRequests.first ?? model.ownPullRequests.first {
            model.selectedItem = ModalRoute.github(pr.url).selectionKey
            await check("a PR selected on the page gives the menu bar Open on GitHub", MenuState.shared.outside == "Open on GitHub" && MenuState.shared.link == pr.url,
                  MenuState.shared.outside ?? "none")
            model.selectedItem = nil
            // Its modal's Copy Link copies its address.
            model.open(.github(pr.url))
            await ui.settle(0.8)
            await check("its Reload stops turning once the page has loaded", model.loadingPage == nil, model.loadingPage ?? "")
            Pasteboard.copied = nil
            func copyLinkSize() -> CGSize? { UITest.anchors["copy-link", default: []].compactMap(\.view).last?.frame.size }
            let before = copyLinkSize()
            await ui.click(ui.anchor("copy-link"), inSheet: true)
            await check("a PR's modal copies its link", Pasteboard.copied == pr.url, Pasteboard.copied ?? "nothing copied")
            await check("Copy Link keeps its size while it says Copied", before != nil && copyLinkSize() == before,
                  "\(String(describing: before)) → \(String(describing: copyLinkSize()))")
            model.closeModal()
            await ui.settle(0.5)
        }
    }

    /// Slack links and the new sheets (T-312, T-313, T-331, T-332, T-333): New Task… and New Reminder… come with the
    /// copied Slack link until × drops that copy, named after its message; Link… adds anything, by keyboard too; the chips
    /// under a task's row take the hand; a Slack link pasted in a list's New Task line becomes its link.
    static func slackLinks(_ model: AppModel, _ ui: Driver) async {
        let url = SlackService.fixtureLink
        let route = ModalRoute.slack(url)
        let line = "Can you check the eu-west upload retries before Monday?"
        func copy(_ text: String?) {
            SlackClipboard.testText = text
            SlackClipboard.testChange += 1
        }
        func editor() -> NSTextView? { (ui.window.attachedSheet ?? ui.window).firstResponder as? NSTextView }
        func open(_ sheet: ModalRoute) async {
            model.closeModal()
            await ui.settle(0.3)
            if case .newTask(let list) = sheet { model.beginTask(list) } else { model.beginReminder() }
            await ui.until(2) { model.modal == sheet }
            await ui.settle(0.8)
        }
        model.slackMessages = SlackService.fixtures
        model.closeModal()
        model.folded = []
        await ui.settle(0.4)

        // New Task… with a Slack link copied: its own sheet, the link, the message's words.
        copy("look: \(url)")
        await open(.newTask(.overview))
        await check("New Task… opens its own sheet with the keyboard in the title", model.modal == .newTask(.overview)
              && ui.anchor("new-task-title") != nil && editor() != nil, ui.responder)
        await check("a Slack link copied comes as a link, and names the task", ui.anchor("new-task-link:\(route.selectionKey)") != nil
              && editor()?.string == line, editor()?.string ?? ui.responder)
        let before = Set(model.tasks.map(\.id))
        await ui.click(await ui.steadyAnchor("new-task-add"), inSheet: true)
        await ui.until(2) { model.modal == nil }
        await ui.settle(0.6)
        func addedTask() -> TaskItem? { model.tasks.first { !before.contains($0.id) } }
        await check("Add Task puts it at the end of Tasks with the link, and selects its row", addedTask()?.title == line
              && addedTask()?.links == [URL(string: url)!] && model.list(of: addedTask()?.id ?? 0) == .overview && model.selectedTasks == [addedTask()?.id ?? 0],
              "\(addedTask()?.title ?? "none") \(addedTask()?.links ?? []) selected \(model.selectedTasks)")
        let added = addedTask()

        // The links on its card: the hand over each, the arrow beside; a click opens it (2026-11-10).
        model.selectSection(nil)
        await ui.settle(0.5)
        if let added, let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator,
           let cell = outline.view(atColumn: 1, row: outline.row(forItem: coordinator.node(.task(added.id))), makeIfNecessary: false) as? TaskCell,
           let token = cell.links.windowPoint(of: route) {
            let past = cell.links.convert(NSPoint(x: -Space.sm, y: cell.links.bounds.midY), to: nil)
            await check("the hand over a link on a task's card, as the window gives it, the arrow beside", ui.cursorShown(at: token) == .pointingHand && ui.cursorShown(at: past) != .pointingHand)
            let opened = model.slackLog.count
            await ui.click(token)
            await ui.settle(0.4)
            await tableCheck(ui, "a click on the Slack link opens it in Slack", model.slackLog.count == opened + 1 && model.slackLog.last == url
                       && model.modal == nil, "\(model.slackLog)")
        } else {
            await check("the hand over a link on a task's card, the arrow beside", false, "no link on the card")
        }

        // A link added from the CLI shows under the task's row at once, every kind (T-352): through the socket, as `hq` does it.
        if let parent = model.addTask(to: .overview, title: "Parent of linked ones"), let other = model.addTask(to: .overview, title: "Related"),
           let target = model.addSubtask(to: parent.id, title: "Linked from the CLI"),
           let shut = model.addSubtask(to: parent.id, title: "Linked while folded") {
            model.setFold(parent.id, .all)
            await endUndoGroup(model)
            await ui.settle(0.4)
            let routes: [(String, ModalRoute)] = [(url, route), ("https://example.com/notes", .web("https://example.com/notes")),
                                                  ("https://github.com/acme/registry/pull/431", .github("https://github.com/acme/registry/pull/431")),
                                                  (other.key, .task(other.id))]
            func link(_ id: Int, _ key: String, _ item: String) -> String {
                String(decoding: AgentRouter.handle(JSON.data(["command": "task link", "args": ["task": key, "item": item, "not-mine": "true"]])), as: UTF8.self)
            }
            /// The link on the task's card, once the card shows it.
            func onCard(_ id: Int, _ route: ModalRoute) async -> Bool {
                // The card on screen, as the user would look at it.
                func shown() -> Bool {
                    guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator else { return false }
                    let row = outline.row(forItem: coordinator.node(.task(id)))
                    guard row >= 0 else { return false }
                    outline.scrollRowToVisible(row)
                    guard let cell = outline.view(atColumn: 1, row: row, makeIfNecessary: true) as? TaskCell else { return false }
                    return cell.links.tokens.contains { $0.routes.contains(route) }
                }
                await ui.until(2) { shown() }
                return shown()
            }
            var missing: [String] = []
            for (item, shown) in routes {
                let reply = link(target.id, target.key, item)
                // A linked task isn't drawn on the card: the task's window lists it (2026-11-10).
                if case .task = shown {
                    if await onCard(target.id, shown) || !model.outputs(ofTask: target.id).contains(shown) { missing.append("\(item): drawn, or not linked") }
                } else if await !onCard(target.id, shown) {
                    missing.append("\(item): \(reply.prefix(80))")
                }
            }
            await check("a link added from the CLI shows on a subtask's card at once, every kind but a task", missing.isEmpty, missing.joined(separator: "; "))
            // Linked while its parent is folded: there when the parent opens.
            model.setFold(parent.id, .hidden)
            await ui.settle(0.4)
            _ = link(shut.id, shut.key, url)
            model.setFold(parent.id, .all)
            await ui.settle(0.5)
            let shows = await onCard(shut.id, route)
            await check("a link added while its parent is folded shows once it opens", shows)
            model.deleteTasks([parent.id, target.id, shut.id, other.id])
            await endUndoGroup(model)
            await ui.settle(0.3)
        }

        // The same copy comes to New Reminder… too, until its × drops it.
        await open(.newReminder)
        await check("New Reminder… gets the same copied link, and the message's words", ui.anchor("new-reminder-link:\(route.selectionKey)") != nil
              && editor()?.string == line, editor()?.string ?? ui.responder)
        await ui.click(await ui.steadyAnchor("new-reminder-unlink:\(route.selectionKey)"), inSheet: true)
        await ui.settle(0.4)
        await check("its × drops the link", ui.anchor("new-reminder-link:\(route.selectionKey)") == nil)
        model.dropCopiedLink(url)
        await open(.newReminder)
        await check("a copy dropped with × comes no more", ui.anchor("new-reminder-link:\(route.selectionKey)") == nil)

        // Link… finds anything: typed words, ↓ to the next match, Return links it; the chip shows in the sheet.
        guard let target = model.addTask(to: .backlog, title: "Slack link target"), let second = model.addTask(to: .backlog, title: "Slack link second") else {
            return await check("tasks to link", false)
        }
        await endUndoGroup(model)
        await ui.settle(0.3)
        if let field = editor() {
            field.insertText("Answer Julien", replacementRange: NSRange(location: 0, length: field.string.utf16.count))
        }
        await ui.click(await ui.steadyAnchor("new-reminder-link-button"), inSheet: true)
        await ui.settle(0.6)
        if let picker = ui.popoverWindow("link-picker"), let search = picker.firstResponder as? NSTextView {
            search.insertText("Slack link", replacementRange: NSRange(location: 0, length: 0))
            await ui.settle(0.4)
            let first = UITest.anchors["link-match:\(ModalRoute.task(second.id).selectionKey)"] != nil
            await ui.key(.down, inPopover: "link-picker")
            await ui.key(.return, inPopover: "link-picker")
            await ui.settle(0.5)
            await check("Link… lists the matches as the user types; ↓ and Return link the next one", first
                  && ui.anchor("new-reminder-link:\(ModalRoute.task(target.id).selectionKey)") != nil,
                  "\(UITest.anchors.keys.filter { $0.hasPrefix("new-reminder-link:") })")
        } else {
            await tableCheck(ui, "Link… lists the matches as the user types; ↓ and Return link the next one", false, "no popover")
        }
        let count = model.notices.count
        await ui.click(await ui.steadyAnchor("new-reminder-add"), inSheet: true)
        await ui.until(2) { model.modal != .newReminder }
        await check("Add Reminder keeps what Link… linked", model.notices.count == count + 1 && model.notices.last?.text == "Answer Julien"
                   && model.notices.last?.links == [ModalRoute.task(target.id).selectionKey], "\(model.notices.last?.text ?? "none") \(model.notices.last?.links ?? [])")
        if let reminder = model.notices.last, model.notices.count == count + 1 { model.removeNotice(reminder.id) }

        // A Slack link pasted in the words of New Task… becomes its link; the Backlog's New Task… lands there.
        copy(nil)
        await open(.newTask(.backlog))
        editor()?.insertText("Ping Julien \(url)", replacementRange: NSRange(location: 0, length: 0))
        await ui.settle(0.5)
        await check("a Slack link pasted in the title becomes the link, out of the words", ui.anchor("new-task-link:\(route.selectionKey)") != nil
              && editor()?.string == "Ping Julien", editor()?.string ?? ui.responder)
        let beforeBacklog = Set(model.tasks.map(\.id))
        await ui.click(await ui.steadyAnchor("new-task-add"), inSheet: true)
        await ui.until(2) { model.modal == nil }
        await ui.settle(0.4)
        func pinged() -> TaskItem? { model.tasks.first { !beforeBacklog.contains($0.id) } }
        await check("New Backlog Task… adds it to the Backlog", pinged()?.title == "Ping Julien" && pinged().map { model.list(of: $0.id) } == .backlog
              && pinged()?.links == [URL(string: url)!], "\(pinged()?.title ?? "none")")

        // The lists' own New Task lines stay: a Slack link pasted there becomes the task's link; Escape drops it.
        model.focusQuickAdd(.overview)
        await ui.settle(0.6)
        if let field = editor() {
            field.string = ""
            field.insertText("Ping again \(url)", replacementRange: NSRange(location: 0, length: 0))
            await ui.settle(0.5)
            await check("a Slack link pasted in a list's New Task line becomes its link, out of the title", model.pendingTaskLink?.url == url
                  && ui.anchor("quick-add-link") != nil && editor()?.string == "Ping again", editor()?.string ?? ui.responder)
        } else {
            await check("a Slack link pasted in a list's New Task line becomes its link, out of the title", false, ui.responder)
        }
        await ui.key(.escape)
        await ui.settle(0.3)
        await check("Escape drops the link with the title", model.pendingTaskLink == nil)
        model.closeModal()
        model.deleteTasks([added?.id, pinged()?.id, target.id, second.id].compactMap(\.self))
        await endUndoGroup(model)
        await ui.settle(0.3)
    }

    /// T-368: the editor looks like the rendered text and grows with it, continues lists, marks words, ticks checkboxes; a
    /// double-click edits at the spot, in the outline, the task's window and a note.
    static func markdownEditing(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator else { return await check("the outline is on the page", false) }
        model.closeModal()
        model.folded = []
        model.search = ""
        let body = "# Plan\n\nFirst line.\n\nSecond line.\n\n- one\n- [ ] two\n\n```\ncode\n```\n\nLast line."
        guard let task = model.addTask(to: .overview, title: "Write it down", body: body) else { return await check("a task to describe", false) }
        await endUndoGroup(model)
        model.shownDescriptions.insert(task.id)
        await ui.settle(0.6)
        func row() -> Int { outline.row(forItem: coordinator.node(.task(task.id))) }
        outline.scrollRowToVisible(row())
        let rowAtRest = outline.rect(ofRow: row()).height
        coordinator.editDescription(task.id)
        await ui.inEditor()
        guard let editor = ui.window.firstResponder as? MarkdownEditor.EditorTextView, let storage = editor.textStorage else {
            return await check("the description's editor takes the keyboard", false, ui.responder)
        }
        func at(_ needle: String) -> Int { (editor.string as NSString).range(of: needle).location }
        func font(_ needle: String) -> NSFont? { at(needle) == NSNotFound ? nil : storage.attribute(.font, at: at(needle), effectiveRange: nil) as? NSFont }
        let plain = font("First line")
        await check("the editor writes in the rendered text's font and size, headings at theirs, mono only in code, marks dimmed",
              plain?.isFixedPitch == false && plain?.pointSize == KitType.body.nsFont.pointSize
                && font("Plan")?.pointSize == KitType.heading1.nsFont.pointSize && font("code")?.isFixedPitch == true
                && storage.attribute(.foregroundColor, at: at("# Plan"), effectiveRange: nil) as? NSColor == Ink.syntaxQuietNS,
              "\(plain?.fontName ?? "-") \(font("Plan")?.pointSize ?? 0) \(font("code")?.fontName ?? "-")")
        // The rendered text sat at the description's top-left, below its top padding.
        var editorOrigin: CGPoint?
        if let scroll = editor.enclosingScrollView, let host = (outline.view(atColumn: 1, row: row(), makeIfNecessary: false) as? TaskCell)?.descriptionHost {
            let frame = scroll.convert(scroll.bounds, to: host)
            editorOrigin = CGPoint(x: frame.minX, y: host.isFlipped ? frame.minY : host.bounds.height - frame.maxY)
        }
        await check("the editor opens where the rendered text was, as tall: its row doesn't move (T-368)", abs(outline.rect(ofRow: row()).height - rowAtRest) <= 1
              && editorOrigin.map { abs($0.x) <= 0.5 && abs($0.y - Space.xs) <= 0.5 } == true,
              "row \(rowAtRest) → \(outline.rect(ofRow: row()).height), editor at \(String(describing: editorOrigin))")
        // It grows with its text, and its row with it.
        let box = { editor.enclosingScrollView?.frame.height ?? 0 }
        let boxBefore = box(), rowBefore = outline.rect(ofRow: row()).height
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        for line in ["More.", "And more.", "And more again."] {
            await ui.key(.return)
            await ui.key(.return)
            await ui.type(line)
        }
        await ui.settle(0.6)
        await check("the box grows with its text, and its row with it", box() > boxBefore + Space.lg && outline.rect(ofRow: row()).height > rowBefore + Space.lg,
              "box \(boxBefore) → \(box()), row \(rowBefore) → \(outline.rect(ofRow: row()).height)")
        // Lists.
        func caret(after needle: String) { editor.setSelectedRange(NSRange(location: at(needle) + (needle as NSString).length, length: 0)) }
        caret(after: "- one")
        await ui.key(.return)
        await ui.type("half")
        await check("Return on a list item starts the next one", editor.string.contains("- one\n- half\n- [ ] two"), editor.string)
        caret(after: "- [ ] two")
        await ui.key(.return)
        await check("a checkbox item's next one has a checkbox", editor.string.contains("- [ ] two\n- [ ] \n"), editor.string)
        await ui.key(.return)
        await check("Return on an empty item ends the list", editor.string.contains("- [ ] two\n\n\n```") && model.editingDescription == task.id, editor.string)
        caret(after: "- half")
        await ui.key(.tab)
        await check("Tab nests a list item, the editor keeping the keyboard", editor.string.contains("\n  - half") && model.editingDescription == task.id, editor.string)
        await ui.key(.tab, .shift)
        await check("Shift-Tab takes it back out", editor.string.contains("\n- half") && model.editingDescription == task.id, editor.string)
        // ⌘B, ⌘I, ⌘K, a pasted address.
        editor.setSelectedRange((editor.string as NSString).range(of: "Second"))
        await ui.chord("b", .command, code: 11)
        await check("Command-B marks the selection bold", editor.string.contains("**Second** line."), editor.string)
        await ui.chord("b", .command, code: 11)
        await check("Command-B again takes the marks off", editor.string.contains("\nSecond line."), editor.string)
        await ui.chord("i", .command, code: 34)
        await check("Command-I marks it italic, and doesn't open the task", editor.string.contains("_Second_ line.") && model.modal == nil, editor.string)
        await ui.chord("i", .command, code: 34)
        Pasteboard.copy("https://example.com/plan")
        editor.setSelectedRange((editor.string as NSString).range(of: "Second"))
        await ui.chord("k", .command, code: 40)
        await check("Command-K links the selection to a copied address", editor.string.contains("[Second](https://example.com/plan) line."), editor.string)
        editor.setSelectedRange((editor.string as NSString).range(of: "Last"))
        editor.paste(nil)
        await check("an address pasted over words links them", editor.string.contains("[Last](https://example.com/plan) line."), editor.string)
        // A checkbox ticks on a click, with the pointing hand over it.
        if let layout = editor.layoutManager, let container = editor.textContainer {
            let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: at("[ ] two"), length: 3), actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            let point = editor.convert(NSPoint(x: rect.midX + editor.textContainerOrigin.x, y: rect.midY + editor.textContainerOrigin.y), to: nil)
            if let click = ui.mouseDown(point, clicks: 1) {
                NSCursor.arrow.set()
                editor.cursorUpdate(with: click)
                let hand = NSCursor.current == NSCursor.pointingHand
                editor.mouseDown(with: click)
                await check("a click on a checkbox in the editor ticks it, the pointing hand over it", editor.string.contains("- [x] two") && hand, editor.string)
                editor.mouseDown(with: click)
                await check("and another unticks it", editor.string.contains("- [ ] two"), editor.string)
            }
        } else {
            await check("the editor's text layout", false)
        }
        await ui.key(.escape)
        await ui.settle(0.6)
        await check("Escape saves what the editor wrote", model.task(task.id)?.body.contains("[Second](https://example.com/plan) line.") == true
              && model.editingDescription == nil, model.task(task.id)?.body ?? "-")

        // A double-click edits at the spot: six lines, the fourth double-clicked.
        let lines = "Line one.\n\nLine two.\n\nLine three.\n\nLine four.\n\nLine five.\n\nLine six."
        let four = (lines as NSString).range(of: "Line four.")
        func onFour(_ responder: NSResponder?) -> Bool {
            guard let text = responder as? NSTextView else { return false }
            return NSLocationInRange(text.selectedRange().location, NSRange(location: four.location, length: four.length + 1))
        }
        model.setDescription(task.id, lines)
        await ui.settle(0.6)
        outline.scrollRowToVisible(row())
        if let host = (outline.view(atColumn: 1, row: row(), makeIfNecessary: true) as? TaskCell)?.descriptionHost {
            host.scrollToVisible(host.bounds)
            let height = host.bounds.height - Space.xs - Space.md
            let point = host.convert(NSPoint(x: Space.xl, y: host.isFlipped ? Space.xs + height * 3.5 / 6 : host.bounds.height - Space.xs - height * 3.5 / 6), to: nil)
            if let double = ui.mouseDown(point, clicks: 2) {
                let swallowed = coordinator.descriptionClick(double) == nil
                await ui.settle(0.8)
                await check("a double-click on a description edits it at the spot (T-368)", swallowed && model.editingDescription == task.id && onFour(ui.window.firstResponder),
                      "caret \((ui.window.firstResponder as? NSTextView)?.selectedRange().location ?? -1) for \(four)")
                await ui.key(.escape)
                await ui.settle(0.5)
            }
        } else {
            await check("the description shows under its row", false)
        }
        // In the task's window and in a note, the same.
        func catcher(_ view: NSView?) -> EditOnDoubleClick.CatcherView? {
            guard let view else { return nil }
            return (view as? EditOnDoubleClick.CatcherView) ?? view.subviews.lazy.compactMap(catcher).first
        }
        func doubleClick(fourthOf area: EditOnDoubleClick.CatcherView, in sheet: NSWindow) -> Bool {
            let point = area.convert(NSPoint(x: Space.xl, y: area.bounds.height * 3.5 / 6), to: nil)
            guard let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: sheet.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 1) else { return false }
            return area.take(event) == nil
        }
        func frame(_ anchor: String) -> NSRect? {
            UITest.anchors[anchor, default: []].compactMap(\.view).last(where: { $0.window != nil }).map { $0.convert($0.bounds, to: nil) }
        }
        func same(_ a: NSRect?, _ b: NSRect?) -> Bool {
            guard let a, let b else { return false }
            return abs(a.minX - b.minX) <= 0.5 && abs(a.maxY - b.maxY) <= 0.5 && abs(a.width - b.width) <= 0.5 && abs(a.height - b.height) <= 1
        }
        model.open(.task(task.id))
        await ui.settle(1)
        if let sheet = ui.window.attachedSheet, let area = catcher(sheet.contentView) {
            let rendered = frame("modal-description"), button = frame("modal-edit-description")
            let swallowed = doubleClick(fourthOf: area, in: sheet)
            await ui.settle(0.8)
            await check("a double-click on the description in the task's window edits it at the spot", swallowed && model.modalEditingDescription && onFour(sheet.firstResponder),
                  "caret \((sheet.firstResponder as? NSTextView)?.selectedRange().location ?? -1) for \(four)")
            await check("in the task's window only the text turns into the editor: same place, same size, Edit becomes Done where it was",
                  same(rendered, frame("modal-description-editor")) && same(button, frame("modal-edit-description")),
                  "\(String(describing: rendered)) → \(String(describing: frame("modal-description-editor"))), button \(String(describing: button)) → \(String(describing: frame("modal-edit-description")))")
            model.saveModalEdits()
        } else {
            await check("the task's window shows its description", false)
        }
        model.closeModal()
        await ui.settle(0.5)
        if let file = model.addFile(title: "Notes to edit", body: lines) {
            model.open(.file(file.id))
            await ui.settle(1)
            if let sheet = ui.window.attachedSheet, let area = catcher(sheet.contentView) {
                let rendered = frame("file-text")
                let swallowed = doubleClick(fourthOf: area, in: sheet)
                await ui.settle(0.8)
                await check("a double-click on a note edits it at the spot", swallowed && model.editingFile == file.id && onFour(sheet.firstResponder),
                      "caret \((sheet.firstResponder as? NSTextView)?.selectedRange().location ?? -1) for \(four)")
                await check("in a note only the text turns into the editor: its byline and title stay, the text in the same place and size",
                      same(rendered, frame("file-editor")) && frame("file-page") != nil,
                      "\(String(describing: rendered)) → \(String(describing: frame("file-editor")))")
                model.editingFile = nil
            } else {
                await check("a note's window shows its text", false)
            }
            model.closeModal()
            model.deleteFile(file.id)
        }
        await ui.settle(0.4)
        model.deleteTasks([task.id])
    }

    /// T-348, T-359, T-358, T-343: the grip moves a task, the rest of its row carries it (onto a task or a card it links;
    /// other apps get its line); Copy, ⌘C and the modals' Copy give items' lines; Remind Me… opens New Reminder about the item.
    static func copyAndRemind(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator,
              let collection = ui.find(SessionGrid.CardCollection.self),
              let cards = collection.delegate as? SessionGrid.Coordinator else { return await check("the outline and the grid are on the page", false) }
        model.folded = []
        model.search = ""
        guard let carried = model.addTask(to: .overview, title: "Carry me"),
              let target = model.addTask(to: .overview, title: "Link it here") else { return await check("tasks to drag", false) }
        await endUndoGroup(model)
        await ui.settle(0.5)
        let index = outline.row(forItem: coordinator.node(.task(carried.id)))
        outline.scrollRowToVisible(index)
        await ui.settle(0.2)
        guard let faces = outline.view(atColumn: 0, row: index, makeIfNecessary: true) as? FacesCell,
              let cell = outline.view(atColumn: 1, row: index, makeIfNecessary: true) as? TaskCell else { return await check("the row's cells", false) }
        faces.layoutSubtreeIfNeeded()
        let line = "Task \(carried.key): Carry me"
        func writer() -> NSPasteboardItem? { coordinator.outlineView(outline, pasteboardWriterForItem: coordinator.node(.task(carried.id))) as? NSPasteboardItem }
        // The whole card drags (2026-11-10): no grip, from its title or anywhere on it the task moves, and other apps get its line.
        _ = outline.canDragRows(with: IndexSet(integer: index), at: cell.title.convert(NSPoint(x: cell.title.bounds.midX, y: cell.title.bounds.midY), to: outline))
        let moved = writer()
        await check("a drag from anywhere on the card moves the task, and gives other apps its line", moved?.string(forType: DragItem.taskType) == "\(carried.id)"
              && moved?.data(forType: DragItem.itemType) == nil && moved?.string(forType: .string) == line, moved?.string(forType: .string) ?? "no line")
        await check("no grip: no open hand over the outline", !outline.trackingAreas.contains { $0.owner === outline && $0.options.contains(.cursorUpdate) })
        // Onto another task: the drop menu (Link to among its choices), never onto itself.
        let drag = FakeDrag(tasks: [carried.id], source: outline)
        let onto = coordinator.node(.task(target.id))
        await check("a task dragged onto another task's card is taken (the drop menu asks)",
              coordinator.outlineView(outline, validateDrop: drag, proposedItem: onto, proposedChildIndex: NSOutlineViewDropOnItemIndex) == .move)
        await check("never onto itself", coordinator.outlineView(outline, validateDrop: drag, proposedItem: coordinator.node(.task(carried.id)),
                                                           proposedChildIndex: NSOutlineViewDropOnItemIndex) == [])
        let pick = OutlineCoordinator.pickDropChoice
        OutlineCoordinator.pickDropChoice = { menu, _ in menu.items.first { $0.title.hasPrefix("Link to") } }
        _ = coordinator.outlineView(outline, acceptDrop: drag, item: onto, childIndex: NSOutlineViewDropOnItemIndex)
        await ui.settle(0.4)
        OutlineCoordinator.pickDropChoice = pick
        await endUndoGroup(model)
        await check("Link to: the task links to the target only, and neither moved", model.isLinked(.task(carried.id), to: target.id)
              && model.taskTree.parent(of: carried.id) == nil && model.outputs(ofTask: target.id).contains(.task(carried.id))
              && !model.outputs(ofTask: carried.id).contains(.task(target.id)))
        model.undoManager?.undo()
        await ui.settle(0.3)
        await check("Undo unlinks them", !model.isLinked(.task(carried.id), to: target.id))
        // Onto a session's card it links to that session.
        if let session = model.gridSessions.first {
            await check("a task carried onto a card proposes a link onto it", validate(cards, collection, drag, item: 0, operation: .before).0 == .link)
            _ = cards.collectionView(collection, acceptDrop: drag, indexPath: IndexPath(item: 0, section: 0), dropOperation: .on)
            await endUndoGroup(model)
            await check("dropped, the task is linked to that session", model.task(carried.id)?.sessions.contains(session.id) == true)
            model.undoManager?.undo()
            await ui.settle(0.3)
        }

        // Copy and ⌘C (T-358): the rows', the card's and the open item's lines.
        Pasteboard.copied = nil
        outline.selectRowIndexes([index], byExtendingSelection: false)
        outline.copy(nil)
        await check("⌘C on a selected row copies its line", Pasteboard.copied == line, Pasteboard.copied ?? "nothing")
        if let press = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: ui.window.windowNumber,
                                          context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { cell.key.mouseDown(with: press) }
        await check("a click on the key copies the same line", Pasteboard.copied == line, Pasteboard.copied ?? "nothing")
        if let session = model.gridSessions.first {
            model.selectedSession = session.id
            collection.copy(nil)
            await check("⌘C on a card copies its session's line", Pasteboard.copied == "Session \(session.id): \(session.name)", Pasteboard.copied ?? "nothing")
        }
        var routes: [ModalRoute] = [.task(target.id)]
        routes += model.gridSessions.prefix(1).map { .session($0.id) }
        routes += model.files.prefix(1).map { .file($0.id) }
        routes += model.artifacts.prefix(1).map { .artifact($0.id) }
        routes += (model.github?.items ?? []).filter { $0.kind == .pullRequest }.prefix(1).map { .github($0.url) }
        for route in routes {
            model.open(route)
            await ui.until(2) { ui.window.attachedSheet != nil }
            await ui.settle(0.6)
            Pasteboard.copied = nil
            await ui.click(await ui.steadyAnchor("copy-item"), inSheet: true)
            await check("the modal's Copy copies the item's line: \(route.selectionKey.prefix(12))", Pasteboard.copied == model.line(of: route),
                  Pasteboard.copied ?? "nothing")
            if case .session = route {
                await ui.settle()
                await check("a session's modal has no Remind Me…", ui.anchor("item-remind-me") == nil)
            } else {
                await check("and Remind Me…", ui.anchor("item-remind-me") != nil)
            }
            model.closeModal()
            await ui.settle(0.3)
        }

        // Remind Me… (T-343): the card's menu (no button on the card since 2026-11-10), then the PR modal's.
        let targetRow = outline.row(forItem: coordinator.node(.task(target.id)))
        // The task selected: the menu acts on it.
        outline.selectRowIndexes([targetRow], byExtendingSelection: false)
        guard let row = outline.view(atColumn: 1, row: targetRow, makeIfNecessary: true) as? TaskCell, let taskMenu = coordinator.menu(forRow: targetRow) else {
            return await check("the task's card and its menu", false)
        }
        taskMenu.update()
        guard let remindItem = taskMenu.items.firstIndex(where: { $0.title == "Remind Me…" }) else {
            return await check("the card's menu has Remind Me…", false, taskMenu.items.map(\.title).joined(separator: ", "))
        }
        await check("no Remind Me… button on the card", !row.subviews.contains { ($0 as? NSButton)?.toolTip?.hasPrefix("Remind me") == true })
        taskMenu.performActionForItem(at: remindItem)
        await ui.until(2) { model.modal == .newReminder }
        await ui.settle(0.6)
        row.setHovered(false)
        await check("it opens New Reminder with the task linked", model.modal == .newReminder && ui.anchor("new-reminder-link:task:\(target.id)") != nil)
        let before = model.notices.count
        await ui.click(await ui.steadyAnchor("new-reminder-add"), inSheet: true)
        await ui.until(2) { model.modal == nil }
        await check("Add Reminder with no words of the user's: the task's title, linked to it", model.notices.count == before + 1
              && model.notices.last?.text == "Link it here" && model.notices.last?.links == ["task:\(target.id)"], "\(String(describing: model.notices.last))")
        if model.notices.count == before + 1, let added = model.notices.last { model.removeNotice(added.id) }
        if let pr = (model.github?.items ?? []).first(where: { $0.kind == .pullRequest }) {
            model.open(.github(pr.url))
            await ui.settle(0.6)
            await ui.click(await ui.steadyAnchor("item-remind-me"), inSheet: true)
            await ui.until(2) { model.modal == .newReminder }
            await ui.settle(0.4)
            await check("a PR's modal opens it over the PR, linked to it", model.modalStack.last == .github(pr.url)
                  && ui.anchor("new-reminder-link:github:\(pr.url)") != nil)
            model.back()
            await ui.until(2) { model.modal == .github(pr.url) }
            await check("Cancel goes back to the PR", model.modal == .github(pr.url))
            model.closeModal()
            await ui.settle(0.3)
        }
        // The two tasks stay: deleted here, in a test window behind the user's, their rows' slide-out never ends and leaves
        // their views below the outline for the sweep to find (2026-11-09).
        func outside() -> [NSView] {
            outline.subviews.filter { $0 is NSTableRowView && !$0.isHidden
                && !outline.bounds.insetBy(dx: -1, dy: -1).contains(NSPoint(x: $0.frame.midX, y: $0.frame.midY)) }
        }
        await check("the outline fits its rows after the drops, the copies and the reminders", outside().isEmpty,
              "outline \(Int(outline.bounds.height)), outside at \(outside().map { Int($0.frame.minY) })")
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
              let a = ids["A"], let b = ids["B"], let c = ids["C"], let a2 = ids["A2"] else { return await check("the outline's tasks", false) }
        let tree = { model.taskTree }
        let rows = { ui.window.firstResponder === outline }
        let state = { "selected \(model.selectedTasks) focused \(String(describing: model.focusedTask)) responder \(ui.responder)" }
        await check("the outline shows Tasks with their subtasks", tree().top(.overview) == [a, b, c] && tree().children(of: a).count == 2)

        // A click selects, a double-click edits.
        await ui.click(ui.titlePoint(b))
        await tableCheck(ui, "a click on a title selects its row without editing", model.selectedTasks == [b] && !ui.isTyping, state())
        // A click on the selected row's status moves it on; the row stays selected.
        if let cell = outline.view(atColumn: 1, row: outline.row(forItem: coordinator.node(.task(b))), makeIfNecessary: false) as? TaskCell {
            let glyph = cell.glyph.convert(NSPoint(x: cell.glyph.bounds.midX, y: cell.glyph.bounds.midY), to: nil)
            await ui.click(glyph)
            await tableCheck(ui, "a click on a selected row's status moves it on and keeps the row selected",
                       model.task(b)?.status == .doing && model.selectedTasks == [b], "\(String(describing: model.task(b)?.status)) \(state())")
            model.setStatus(b, .todo)
            await ui.settle(0.2)
        }
        await ui.click(ui.titlePoint(b), count: 2)
        await check("a double-click on a title edits it, its row still selected", ui.isTyping && model.focusedTask == b && model.selectedTasks == [b], state())
        if !ui.isTyping { coordinator.beginEditing(b) }

        // In a title: Return adds below; Tab goes to the description, Shift-Tab back and to the previous title.
        await ui.key(.return)
        await ui.settle(0.5)
        let added = tree().top(.overview)
        await check("Return in a title adds a task below and edits it", added.count == 4 && added[2] != c && model.focusedTask == added[2] && ui.isTyping,
              "\(added) \(state())")
        let new = added[2]
        let before = model.tasks.count
        await ui.key(.return)
        await ui.settle(0.3)
        await check("Return in an empty title adds nothing", model.tasks.count == before && model.focusedTask == new && ui.isTyping, state())
        await ui.type("Fix push #perf")
        await ui.key(.tab)
        await ui.inEditor()
        await check("Tab in a title edits its description, and leaves the task where it is", model.editingDescription == new && ui.isTyping
              && tree().parent(of: new) == nil, state())
        await check("#word in a typed title becomes a tag", model.task(new)?.title == "Fix push" && model.task(new)?.tags == ["perf"],
              "\(model.task(new)?.title ?? "-") \(model.task(new)?.tags ?? [])")
        await ui.type("Why.")
        await ui.key(.tab, .shift)
        await ui.settle(0.5)
        await check("Shift-Tab in a description saves it and edits the task's title", model.task(new)?.body == "Why." && model.editingDescription == nil
              && model.focusedTask == new && ui.isTyping, "\(model.task(new)?.body ?? "-") \(state())")
        await ui.key(.tab)
        await ui.inEditor()
        await ui.key(.tab)
        await ui.settle(0.5)
        await check("Tab in a description edits the next task's title", model.focusedTask == c && ui.isTyping && model.editingDescription == nil, state())
        await ui.key(.tab, .shift)
        await ui.settle(0.3)
        await check("Shift-Tab in a title edits the previous task's title", model.focusedTask == new && ui.isTyping, state())
        await ui.key(.up)
        await ui.settle(0.3)
        await check("Up in a title selects the row above, without editing", model.selectedTasks == [b] && rows(), state())

        // On rows: arrows move the selection, Tab goes round the page's sections; Shift with arrows moves the task.
        await ui.key(.down)
        await ui.settle(0.2)
        await check("Down on rows selects the next task", model.selectedTasks == [new] && rows(), state())
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
            case .tasks: await check("Tab out of the tasks unselects their rows", model.selectedTasks.isEmpty, state())
            case .sessions: await check("Tab out of the sessions unselects the card", model.selectedSession == nil, model.selectedSession ?? "-")
            case .pullRequests, .files: break
            }
            left = section
            switch section {
            case .pullRequests:
                await check("Tab takes the keyboard to Pull Requests, first row selected", model.selectedItem?.hasPrefix("github:") == true && !rows(), state())
                let first = model.selectedItem
                await ui.key(.down)
                await ui.settle(0.2)
                await check("Down selects the next pull request", model.selectedItem != first && model.selectedItem?.hasPrefix("github:") == true,
                      model.selectedItem ?? "-")
            case .sessions:
                await check("Tab takes the keyboard to the session cards", ui.window.firstResponder is SessionGrid.CardCollection && model.selectedSession != nil,
                      ui.responder)
            case .files:
                await check("Tab takes the keyboard to Files and Artifacts", model.selectedItem?.hasPrefix("file:") == true
                      || model.selectedItem?.hasPrefix("artifact:") == true, model.selectedItem ?? "-")
            case .tasks:
                break
            }
        }
        await ui.key(.tab)
        await ui.settle(0.5)
        await check("Tab round the page comes back to the tasks, the row still selected", model.selectedTasks == [new] && rows(), state())
        await ui.key(.tab, .shift)
        await ui.until { !rows() && model.selectedItem != nil }
        await check("Shift-Tab goes to the section before", !rows(), state())
        await ui.key(.tab)
        await ui.until { rows() && model.selectedTasks == [new] }
        await check("and Tab back to the row", model.selectedTasks == [new] && rows(), state())
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
            await check("Shift-Tab takes the keyboard back to \(section), the section left unselected", reached(section) && model.selectedTasks.isEmpty, state())
        }
        await ui.key(.tab, .shift)
        await ui.until { rows() && model.selectedTasks == [new] }
        await check("Shift-Tab round the page comes back to the tasks, the row still selected", model.selectedTasks == [new] && rows()
              && model.selectedSession == nil && model.selectedItem == nil, state())
        await ui.key(.right, .shift)
        await ui.settle(0.5)
        await check("Shift-Right indents the row under the task above; it keeps the selection and the keyboard",
              tree().parent(of: new) == b && model.selectedTasks == [new] && rows(), "parent \(String(describing: tree().parent(of: new))) \(state())")
        await ui.key(.left, .shift)
        await ui.settle(0.5)
        await check("Shift-Left outdents it", tree().parent(of: new) == nil && tree().top(.overview) == [a, b, new, c] && model.selectedTasks == [new] && rows(),
              "\(tree().top(.overview)) \(state())")
        model.undoManager?.undo()
        await ui.settle(0.4)
        await check("Undo Outdent nests it again", tree().parent(of: new) == b)
        model.undoManager?.undo()
        await ui.settle(0.4)
        await check("Undo Indent puts it back, still selected", tree().parent(of: new) == nil && model.selectedTasks == [new], "parent \(String(describing: tree().parent(of: new))) list \(String(describing: model.task(new)?.list)) \(state())")
        await ui.key(.up, .shift)
        await ui.settle(0.5)
        await check("Shift-Up moves the row up among its siblings, still selected", tree().top(.overview) == [a, new, b, c] && model.selectedTasks == [new] && rows(),
              "\(tree().top(.overview)) \(state())")
        await ui.key(.down, .shift)
        await ui.settle(0.5)
        await check("Shift-Down moves it back", tree().top(.overview) == [a, b, new, c] && model.selectedTasks == [new], "\(tree().top(.overview))")
        let a1 = tree().children(of: a)[0]
        coordinator.select(a1)
        await ui.key(.up, .shift)
        await ui.settle(0.5)
        await check("Shift-Up on a first subtask moves it out, above its parent", tree().top(.overview) == [a1, a, b, new, c] && model.selectedTasks == [a1],
              "\(tree().top(.overview)) \(state())")
        await ui.key(.down, .shift)
        await ui.settle(0.5)
        await check("Shift-Down then moves it below the task under it, as a sibling", tree().top(.overview) == [a, a1, b, new, c], "\(tree().top(.overview))")
        coordinator.select(a2)
        await ui.key(.down, .shift)
        await ui.settle(0.5)
        await check("Shift-Down on a last subtask moves it out, below its parent", tree().parent(of: a2) == nil && tree().top(.overview) == [a, a2, a1, b, new, c],
              "\(tree().top(.overview))")
        model.undoManager?.undo()
        await ui.settle(0.3)
        model.undoManager?.undo()
        await ui.settle(0.3)
        model.undoManager?.undo()
        await ui.settle(0.3)
        await check("Undo puts the subtasks back", tree().children(of: a) == [a1, a2] && tree().top(.overview) == [a, b, new, c],
              "\(tree().children(of: a)) \(tree().top(.overview))")

        // In a title: Shift-Right at its end indents, Shift-Left at its start outdents; the title stays edited.
        coordinator.beginEditing(new)
        await ui.settle(0.3)
        await ui.key(.right, .shift)
        await ui.settle(0.6)
        await check("Shift-Right at the end of a title indents the task and keeps editing it", tree().parent(of: new) == b && ui.isTyping && model.focusedTask == new,
              "parent \(String(describing: tree().parent(of: new))) \(state())")
        (ui.window.firstResponder as? NSTextView)?.setSelectedRange(NSRange(location: 0, length: 0))
        await ui.key(.left, .shift)
        await ui.settle(0.6)
        await check("Shift-Left at the start of a title outdents it, still editing", tree().parent(of: new) == nil && tree().top(.overview) == [a, b, new, c] && ui.isTyping,
              "\(tree().top(.overview)) \(state())")
        await ui.key(.left, .shift)
        await ui.settle(0.3)
        await check("a top-level task stays where it is", tree().top(.overview) == [a, b, new, c] && ui.isTyping)
        await ui.key(.escape)
        await ui.settle(0.3)
        // An empty task moved from its title stays, still edited, until the edit ends.
        coordinator.select(new)
        await ui.key("n")
        await ui.settle(0.5)
        let blank = model.focusedTask
        await ui.key(.right, .shift)
        await ui.settle(0.8)
        await check("Shift-Right on a new empty task indents it and keeps it", blank.map { tree().parent(of: $0) == new && model.task($0) != nil } == true && ui.isTyping,
              "\(String(describing: blank)) parent \(String(describing: blank.flatMap { tree().parent(of: $0) })) \(state())")
        await ui.key(.escape)
        await ui.settle(0.5)
        await check("and Escape drops it, empty", blank.map { model.task($0) == nil } == true && tree().top(.overview) == [a, b, new, c])
        // The same keys at once, no pause for the rows to settle: an empty task moved and left while its rows still move
        // (T-372, a crash placing the cards).
        for leave in [Driver.Key.escape, .down, .up] {
            coordinator.select(new)
            await ui.key("n")
            await ui.settle(0.3)
            let quick = model.focusedTask
            await ui.key(.right, .shift)
            await ui.key(.left, .shift)
            await ui.key(.right, .shift)
            await ui.key(leave)
            await ui.settle(0.6)
            await check("an empty task moved by keys and left at once (\(leave)) goes, the outline whole",
                  quick.map { model.task($0) == nil } == true && tree().top(.overview) == [a, b, new, c] && rows(), "\(tree().top(.overview)) \(state())")
        }

        // Return edits, Escape gives the rows back the keyboard; the Task menu's keys work on rows.
        coordinator.select(new)
        await ui.key(.return)
        await ui.settle(0.3)
        await check("Return on a row edits its title", ui.isTyping && model.focusedTask == new, state())
        await ui.key(.escape)
        await ui.settle(0.3)
        await check("Escape in a title ends editing; the row keeps the selection and the keyboard", !ui.isTyping && rows() && model.selectedTasks == [new], state())
        await ui.key(.return, .command)
        await ui.settle(0.3)
        await check("Command-Return on a row moves it to the next status", model.task(new)?.status == .doing && rows())
        for _ in 0..<2 { await ui.key(.return, .command) }
        await ui.settle(0.3)
        await check("through Done, then back to Todo, the row still selected", model.task(new)?.status == .todo && model.selectedTasks == [new] && rows(), state())
        model.setStatus(new, .todo)
        let shown = model.descriptionShownInOutline(new)
        await ui.key(.return, .shift)
        await ui.settle(0.4)
        await check("Shift-Return on a row shows or hides its description", model.descriptionShownInOutline(new) != shown && model.editingDescription == nil && rows(),
              state())
        await ui.key(.return, .shift)
        await ui.settle(0.4)
        await check("and again", model.descriptionShownInOutline(new) == shown)
        model.hideDone = [.overview]
        model.setStatus(new, .doing)
        await ui.key(.return, .command)
        await ui.settle(0.5)
        await check("a row that Hide Done hides gives the selection and the keyboard to the row above", model.selectedTasks == [b] && rows(), state())
        model.hideDone = []
        model.toggleDone(new)
        await ui.settle(0.4)

        // N and Shift-N add; a task left empty goes; Delete selects the row above.
        coordinator.select(new)
        let count = model.tasks.count
        await ui.key("n", code: 45)
        await ui.settle(0.5)
        let order = tree().top(.overview)
        await check("N on a row adds a task below and edits its title", model.tasks.count == count + 1 && ui.isTyping
              && order.firstIndex(of: model.focusedTask ?? 0) == (order.firstIndex(of: new) ?? 0) + 1, "\(order) \(state())")
        await ui.key(.escape)
        await ui.settle(0.5)
        await check("Escape on a task with nothing in it deletes it and selects the row above", model.tasks.count == count && model.selectedTasks == [new] && rows(),
              state())
        await ui.key("N", .shift, code: 45)
        await ui.settle(0.5)
        await check("Shift-N adds a subtask and edits its title", tree().parent(of: model.focusedTask ?? 0) == new && ui.isTyping, state())
        let sub = model.focusedTask ?? 0
        await ui.type("Sub")
        await ui.key(.escape)
        await ui.settle(0.4)
        await check("Escape keeps a task with a title", model.task(sub)?.title == "Sub" && model.selectedTasks == [sub] && rows(), state())
        await ui.key(.delete)
        await ui.settle(0.5)
        await check("Delete on a row deletes it and selects the row above", model.task(sub) == nil && model.selectedTasks == [new] && rows(), state())
        await ui.key(.down)
        await ui.key(.up)
        await ui.settle(0.2)
        await check("the rows keep the keyboard after a delete", model.selectedTasks == [new] && rows(), state())

        // Backspace at the start of a title stays there: the task and the edit stay.
        let typed = model.task(new)?.title ?? ""
        await ui.editTitle(new)
        for _ in 0..<(typed.count + 2) { await ui.key(.delete) }
        await ui.settle(0.5)
        await check("Backspace at the start of a title keeps the task and the edit", model.task(new) != nil && model.focusedTask == new && ui.isTyping,
              state())
        await ui.type(typed)
        await ui.key(.escape)
        await ui.settle(0.4)

        // The description: Escape and Command-Return save and select the row.
        await ui.editTitle(b)
        await ui.key(.return, .shift)
        await ui.settle(0.8)
        await check("Shift-Return in a title opens the description's editor", model.editingDescription == b && ui.isTyping, ui.responder)
        await check("the description's editor keeps its text keys from the Task menu", model.outlineKeyboard == .none)
        await ui.type("Goal: fewer blobs.")
        if let editor = ui.window.firstResponder as? NSTextView {
            model.focusSearch()
            await ui.settle(0.3)
            await check("Find in a description's editor opens its find bar and keeps the edit", editor.enclosingScrollView?.isFindBarVisible == true
                  && model.editingDescription == b, ui.responder)
            let hide = NSMenuItem()
            hide.tag = NSTextFinder.Action.hideFindInterface.rawValue
            editor.performTextFinderAction(hide)
            ui.window.makeFirstResponder(editor)
            await ui.settle(0.2)
        }
        await ui.key(.escape)
        await ui.settle(0.5)
        await check("Escape in a description saves it and selects its row with the keyboard", model.task(b)?.body == "Goal: fewer blobs."
              && model.editingDescription == nil && model.selectedTasks == [b] && rows(), "\(model.task(b)?.body ?? "-") \(state())")
        coordinator.editDescription(b)
        await ui.inEditor()
        await ui.type(" More.")
        await ui.key(.return, .command)
        await ui.settle(0.5)
        await check("Command-Return saves the description", model.task(b)?.body == "Goal: fewer blobs. More." && model.editingDescription == nil && rows(),
              "\(model.task(b)?.body ?? "-") \(state())")
        // Clicks on a description go through the outline's check before the description's own views.
        if let point = ui.descriptionPoint(b), let single = ui.mouseDown(point, clicks: 1), let double = ui.mouseDown(point, clicks: 2) {
            outline.deselectAll(nil)
            let passed = coordinator.descriptionClick(single)
            await ui.settle(0.3)
            await check("a click on a description selects its row and still reaches the description", passed != nil && model.selectedTasks == [b] && rows(), state())
            let swallowed = coordinator.descriptionClick(double)
            await ui.settle(0.6)
            await check("a double-click on a description edits it", swallowed == nil && model.editingDescription == b && ui.isTyping, state())
            await ui.key(.escape)
            await ui.settle(0.4)
        } else {
            await check("the description shows under its row", false)
        }
        if ui.canClickTables, let point = ui.descriptionPoint(b) {
            await ui.click(point, count: 2)
            await ui.settle(0.6)
            await check("a real double-click on a description edits it", model.editingDescription == b && ui.isTyping, state())
            await ui.key(.escape)
            await ui.settle(0.4)
        } else {
            skip("a real double-click on a description edits it")
        }

        // To the Backlog and back: the task above takes the selection.
        await ui.editTitle(b)
        await ui.chord("b", [.command, .shift], code: 11)
        await ui.settle(0.5)
        await check("Shift-Command-B moves a task to the top of the Backlog", tree().top(.backlog).first == b, "list \(model.list(of: b))")
        await check("and the task above it in Tasks takes the selection and the keyboard", model.selectedTasks == [a2] && rows(), state())
        model.toggleList(b)
        await ui.settle(0.4)
        await check("and back to the end of Tasks", tree().top(.overview).last == b)

        // Folding a task whose subtask is selected selects the task.
        coordinator.select(a2)
        coordinator.fold([a], .hidden)
        await ui.settle(0.3)
        await check("folding a task whose subtask is selected selects the task", model.selectedTasks == [a] && rows(), state())
        // ← folds the selected task, → shows all its subtasks again; ← on a subtask without any selects its parent.
        coordinator.fold([a], .all)
        await ui.settle(0.3)
        await ui.key(.left)
        await ui.settle(0.3)
        await check("← hides the selected task's subtasks", model.fold[a] == .hidden && model.selectedTasks == [a], state())
        await ui.key(.right)
        await ui.settle(0.3)
        await check("→ shows all its subtasks", model.fold[a] == .all && outline.row(forItem: coordinator.node(.task(a2))) >= 0, state())
        await ui.key(.right)
        await ui.settle(0.3)
        let firstChild = tree().children(of: a).first
        await check("→ on an open task selects its first subtask", firstChild.map { model.selectedTasks == [$0] } == true, state())
        await ui.key(.left)
        await ui.settle(0.3)
        await check("← on a subtask without subtasks selects its parent", model.selectedTasks == [a] && model.fold[a] == .all, state())

        // Quick add: Return keeps the field; Option-Return sends to the Backlog; Escape goes back to the rows.
        model.focusQuickAdd(.overview)
        await ui.settle(0.6)
        await check("New Task gives the quick-add line the keyboard", ui.isTyping, ui.responder)
        await ui.type("Quick one")
        await ui.key(.return)
        await ui.settle(0.4)
        let quick = tree().top(.overview).last
        await check("the quick-add line adds at the end of Tasks and keeps the keyboard", model.task(quick)?.title == "Quick one" && ui.isTyping)
        await ui.type("Later one")
        await ui.key(.return, .option)
        await ui.settle(0.4)
        await check("Option-Return sends it to the Backlog", model.task(tree().top(.backlog).first)?.title == "Later one")
        await ui.key(.escape)
        await ui.settle(0.3)
        await check("Escape in the quick-add line selects the task above it", model.selectedTasks == [quick ?? 0] && rows(), state())
        // The Backlog's filter.
        model.backlogOpen = true
        model.listSearch[.backlog] = "Later"
        await ui.settle(0.5)
        await check("the Backlog's search shows the tasks that match", OutlineSnapshot.make(model).children(of: .header(.backlog)).filter { if case .task = $0 { true } else { false } }.count == 1)
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
              let a = ids["A"], let a1 = ids["A1"], let b = ids["B"], let c = ids["C"], let d = ids["D"] else {
            return await check("the outline for drops", false)
        }
        let tree = { model.taskTree }
        // One row at a time (2026-11-10): the Task menu acts on it; a task goes to the Backlog with its subtasks, still nested.
        outline.selectRowIndexes(IndexSet([outline.row(forItem: coordinator.node(.task(b))), outline.row(forItem: coordinator.node(.task(c)))]),
                                 byExtendingSelection: false)
        await ui.settle(0.3)
        await check("only one row can be selected", outline.selectedRowIndexes.count <= 1 && !outline.allowsMultipleSelection, "\(outline.selectedRowIndexes.count)")
        coordinator.select(a)
        await ui.settle(0.3)
        await check("the Task menu targets the selected row", MenuState.shared.tasks == [a], "\(MenuState.shared.tasks)")
        let family = tree().children(of: a)
        model.moveTasks(MenuState.shared.tasks, toBacklog: true)
        await endUndoGroup(model)
        await check("a task goes to the Backlog with its subtasks, still nested", tree().top(.backlog).first == a && tree().children(of: a) == family,
              "\(tree().top(.backlog)) \(tree().children(of: a))")
        model.undoManager?.undo()
        await ui.settle(0.3)
        await check("one Undo brings it back", tree().top(.overview) == [a, b, c], "\(tree().top(.overview))")
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
        await check("a drop between rows lands there", tree().top(.overview) == [c, a, b])
        let name = model.undoManager?.undoActionName ?? "-"
        let orders = model.tasks.map { "\($0.id):\($0.order)" }
        model.undoManager?.undo()
        await ui.settle(0.3)
        await check("Undo puts it back", tree().top(.overview) == [a, b, c], "undid \(name), \(orders) → \(model.tasks.map { "\($0.id):\($0.order)" }) redo \(model.undoManager?.redoActionName ?? "-")")
        _ = await drop([b], on: .task(a), index: NSOutlineViewDropOnItemIndex)
        await ui.settle(0.3)
        await check("a drop on a row makes it the last child", tree().children(of: a).last == b)
        model.undoManager?.undo()
        await ui.settle(0.3)
        _ = await drop([a], on: .header(.backlog), index: NSOutlineViewDropOnItemIndex)
        await ui.settle(0.3)
        await check("a drop on the Backlog's header goes to its end, with its subtasks", tree().top(.backlog).last == a && tree().list(of: a1) == .backlog)
        model.undoManager?.undo()
        await ui.settle(0.3)
        _ = await drop([d], on: .header(.overview), index: 1)
        await ui.settle(0.3)
        await check("a drop from the Backlog onto Tasks lands between rows", tree().top(.overview) == [a, d, b, c])
        model.undoManager?.undo()
        await ui.settle(0.3)
        let refused = await drop([a], on: .task(a1), index: NSOutlineViewDropOnItemIndex)
        await check("a drop into its own subtree is refused", refused.0 == [] && tree().parent(of: a) == nil)
        // A drag that ends outside the window leaves no drop target behind.
        coordinator.dragEnded()
        await check("a cancelled drag leaves no row marked as a drop target", (0..<outline.numberOfRows).allSatisfy { !(outline.rowView(atRow: $0, makeIfNecessary: false)?.isTargetForDropOperation ?? false) })
        model.backlogOpen = false
    }

    // MARK: Modal

    /// The row's look: group gaps, a hidden description's first line, the status menu, # completion, the modal's tags.
    static func outlineLooks(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator else { return await check("the outline is on the page", false) }
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
              let child = model.taskTree.children(of: parent).first else { return await check("tasks with subtasks on the overview", false) }
        await ui.settle(0.4)
        func height(_ id: Int) -> CGFloat { outline.rect(ofRow: outline.row(forItem: coordinator.node(.task(id)))).height }
        func lineHeight(_ id: Int) -> CGFloat { height(id) - (model.tasksWithOutputs.contains(id) ? Metric.linksLine : 0) }
        await check("the Files and Artifacts section lists files", model.listedFiles.first.map { ui.anchor("item:file:\($0.id)") != nil } ?? true)
        // A task with a link: one of the seed's, else the last top-level task gets a PR for these checks.
        var lent: (task: Int, route: ModalRoute)?
        if !top.contains(where: { model.tasksWithOutputs.contains($0) }), let last = top.last, let pr = model.github?.items.first {
            lent = (last, .github(pr.url))
            model.link(.github(pr.url), to: last)
            await ui.settle(0.5)
        }
        let linkedTask = top.first { model.tasksWithOutputs.contains($0) }
        await check("a task with a link on the overview", linkedTask != nil)
        if let linkedTask, !model.descriptionShownInOutline(linkedTask) {
            // On the card's first line, at its end: no line of their own (2026-11-10).
            let stack = TaskCell.stack(model, linkedTask, big: coordinator.isBig(linkedTask), description: false)
            await check("a task's links take no line of their own", height(linkedTask) == coordinator.gap(of: linkedTask) + stack.height, "\(height(linkedTask))")
            let linkedRow = outline.row(forItem: coordinator.node(.task(linkedTask)))
            if let linkedCell = outline.view(atColumn: 1, row: linkedRow, makeIfNecessary: true) as? TaskCell {
                linkedCell.layoutSubtreeIfNeeded()
                await check("they sit at the end of its first line", !linkedCell.links.isHidden && !linkedCell.links.tokens.isEmpty
                      && abs(linkedCell.links.frame.midY - linkedCell.glyph.frame.midY) < 1 && linkedCell.links.frame.minX > linkedCell.key.frame.maxX,
                      "\(linkedCell.links.frame) glyph \(linkedCell.glyph.frame)")
            }
        }
        if let lent { model.unlink(lent.route, from: lent.task); await ui.settle(0.4) }
        let blockPad = { (id: Int) in coordinator.plan.blocks.contains(id) ? (coordinator.plan.depth[id] == 0 ? Metric.storyTrayPadding : Metric.trayPadding) : 0 }
        await check("the first task sits at the list's top, a top-level task after another a story's gap lower, a subtask a card's gap",
              coordinator.gap(of: top[0]) == blockPad(top[0]) && coordinator.gap(of: top[1]) >= Metric.storyGap + blockPad(top[1])
              && coordinator.gap(of: child) >= Metric.taskGap && coordinator.gap(of: child) < Metric.storyGap,
              "\(height(top[0])) \(height(top[1])) \(height(child))")

        // A description, hidden: the card's button says it has one; Show Description shows it.
        model.setDescription(child, "**Why**: the canary flaps.\n\nMore below.")
        await ui.settle(0.5)
        let row = outline.row(forItem: coordinator.node(.task(child)))
        guard let first = outline.view(atColumn: 1, row: row, makeIfNecessary: true) as? TaskCell else { return await check("the subtask's row", false) }
        // The edits below reload the row: always its current cell.
        var cell: TaskCell {
            outline.view(atColumn: 1, row: outline.row(forItem: coordinator.node(.task(child))), makeIfNecessary: true) as? TaskCell ?? first
        }
        cell.layoutSubtreeIfNeeded()
        // A subtask's card: its description button in the corner, nothing on the title's line (2026-11-10); Show Description
        // shows it in the card, under its line.
        await check("a hidden description shows as the card's description button, no other mark", !cell.note.isHidden
              && !cell.subviews.contains { $0 is NSButton && !$0.isHidden && $0 !== cell.note })
        model.toggleDescription(child)
        await ui.settle(0.5)
        await check("Show Description shows it", model.descriptionShownInOutline(child))
        if let shownHost = cell.descriptionHost {
            await check("under the card's first line, from where the lines under it start", shownHost.frame.minY >= cell.glyph.frame.maxY
                  && shownHost.frame.minX == TaskCell.titleX, "\(shownHost.frame)")
        }
        model.toggleDescription(child)
        await ui.settle(0.5)
        await check("and hides it", !model.descriptionShownInOutline(child))

        // A click on the status glyph steps to the next status, through the outline as AppKit delivers it.
        if let before = model.task(child)?.status {
            cell.layoutSubtreeIfNeeded()
            let glyphFrame = cell.glyph.convert(cell.glyph.bounds, to: nil)
            if let click = ui.mouseDown(NSPoint(x: glyphFrame.midX, y: glyphFrame.midY), clicks: 1) { outline.mouseDown(with: click) }
            await ui.settle(0.3)
            let all = TaskStatus.allCases
            let next = all[((all.firstIndex(of: before) ?? 0) + 1) % all.count]
            await check("a click on the status glyph steps to the next status", model.task(child)?.status == next,
                  "\(before) → \(String(describing: model.task(child)?.status))")
            model.setStatus(child, before)
            await ui.settle(0.3)
        } else {
            await check("the subtask's status", false)
        }

        // The status glyph picks any status; ⌘-click steps to the next.
        cell.glyph.onPick(.doing)
        await ui.settle(0.3)
        await check("the status menu sets the status it picks", model.task(child)?.status == .doing)
        cell.glyph.onNext()
        await ui.settle(0.3)
        await check("Command-click on the status moves to the next one", model.task(child)?.status == .done)

        // The task's key shows whole, three digits too.
        cell.key.stringValue = "T-1066"
        cell.setHovered(true)
        cell.needsLayout = true
        cell.layoutSubtreeIfNeeded()
        let keyText = ceil(("T-1066" as NSString).size(withAttributes: [.font: KitType.key.nsFont]).width)
        await check("a task's key fits its label", cell.key.frame.width >= keyText + 2 && cell.key.frame.maxX <= cell.bounds.width, "\(cell.key.frame) for \(keyText)")
        cell.setHovered(false)
        coordinator.refresh()

        // Clicks reach the status glyph, not only the row's selection.
        func middle(_ view: NSView) -> NSPoint {
            let frame = view.convert(view.bounds, to: nil)
            return NSPoint(x: frame.midX, y: frame.midY)
        }
        await check("a click on the status glyph reaches it", cell.button(at: middle(cell.glyph)) === cell.glyph)
        await check("a click on the title doesn't", cell.button(at: middle(cell.title)) == nil)

        // The project sits after the title, a button; a task in no project shows its icon alone.
        model.setProject(child, "Registry")
        await ui.settle(0.4)
        cell.layoutSubtreeIfNeeded()
        await check("a task's project shows after its title, and a click reaches it", !cell.project.isHidden && cell.project.project == "Registry"
              && cell.project.frame.minX >= cell.title.frame.maxX && cell.button(at: middle(cell.project)) === cell.project,
              "\(cell.project.frame) \(cell.title.frame)")
        cell.project.onPick(nil)
        await ui.settle(0.4)
        cell.layoutSubtreeIfNeeded()
        await check("with none, nothing: no icon on a card (2026-11-10)", model.task(child)?.project == nil && (cell.project.isHidden || cell.project.project == nil),
              "\(cell.project.labels)")

        // A block's progress, on its header's line: every level under it, by state.
        if let grandchild = model.addSubtask(to: child, title: "Grandchild"), model.addSubtask(to: grandchild.id, title: "Great-grandchild") != nil {
            await ui.settle(0.4)
            func childCell() -> TaskCell? { outline.view(atColumn: 1, row: outline.row(forItem: coordinator.node(.task(child))), makeIfNecessary: true) as? TaskCell }
            let leaves = model.taskFlow.tally(of: child).total
            await check("a block's progress counts what's under it, every level", childCell()?.progress.tally.total == leaves && leaves >= 1,
                  "\(childCell()?.progress.tally.total ?? -1) of \(leaves)")
            model.setStatus(model.taskTree.children(of: grandchild.id).first ?? grandchild.id, .doing)
            await ui.settle(0.4)
            let bar = childCell()?.progress
            await check("by state: what's doing shows as doing", bar?.tally.doing == 1 && bar?.toolTip?.contains("1 doing") == true, bar?.toolTip ?? "no bar")
            model.deleteTasks([grandchild.id])
            await ui.settle(0.3)
        } else {
            await check("a grandchild and a great-grandchild", false)
        }

        // A click on a row's key copies its key and title, through the outline as AppKit delivers it.
        // The edits above reload rows: the row's cell now may be another view.
        let keyRow = outline.row(forItem: coordinator.node(.task(child)))
        if keyRow >= 0 { outline.scrollRowToVisible(keyRow) }
        if let task = model.task(child), let cell = outline.view(atColumn: 1, row: keyRow, makeIfNecessary: true) as? TaskCell {
            cell.scrollToVisible(cell.bounds.insetBy(dx: 0, dy: -Driver.overlayClearance))
            cell.setHovered(true)
            ui.window.layoutIfNeeded()
            cell.layoutSubtreeIfNeeded()
            let point = cell.key.convert(NSPoint(x: cell.key.bounds.midX, y: cell.key.bounds.midY), to: nil)
            Pasteboard.copied = nil
            if let click = ui.mouseDown(point, clicks: 1) { outline.mouseDown(with: click) }
            await ui.settle(0.2)
            let copied = Pasteboard.copied
            await check("a click on a task's key copies its line, as Copy does (T-358)", copied == "Task \(task.key): \(task.title)" && cell.key.tracksHandCursor,
                  "\(copied ?? "nothing"), hand \(cell.key.tracksHandCursor), hits \(cell.button(at: point).map { String(describing: type(of: $0)) } ?? "none"), row \(outline.row(at: outline.convert(point, from: nil))) of \(keyRow), in outline \(cell.superview != nil), key \(cell.key.frame) hidden \(cell.key.isHidden), copies \(cell.key.copied)")
            await check("and the key turns the accent color", cell.key.textColor == Ink.accentNS)
            cell.setHovered(false)
        } else {
            await check("the subtask's row", false)
        }

        // The face sits in its slot at the card's start; with nobody on the task, the plain avatar, a click offering Start Session….
        if let faces = outline.view(atColumn: 0, row: keyRow, makeIfNecessary: true) as? FacesCell {
            faces.layoutSubtreeIfNeeded()
            let nobody = model.sessions(on: child, includeEnded: true).isEmpty
            await check("the plain avatar when nobody is on the task, before its status", nobody ? !faces.noSession.isHidden
                  && faces.convert(faces.noSession.frame, to: outline).maxX <= cell.convert(cell.glyph.frame, to: outline).minX : faces.noSession.isHidden)
            if nobody {
                var offered: String?
                let show = FaceMenu.show
                FaceMenu.show = { menu, id, _, _ in offered = id + ": " + menu.items.map(\.title).joined(separator: ", ") }
                let avatar = faces.noSession.convert(NSPoint(x: faces.noSession.bounds.midX, y: faces.noSession.bounds.midY), to: nil)
                if let click = ui.mouseDown(avatar, clicks: 1) { outline.mouseDown(with: click) }
                await ui.settle(0.3)
                FaceMenu.show = show
                await check("a click on it offers Start Session…", offered == "no-session: Start Session…", offered ?? "nothing")
            }
            await check("the hand over its status", cell.glyph.tracksHandCursor)
            model.beginStart(task: child)
            await ui.settle(0.6)
            // Closing keeps the sheet's size and content while it animates out: no jump, no flash.
            let open = ui.window.attachedSheet?.frame.size
            model.closeModal()
            await ui.settle(0.05)
            let closing = ui.window.attachedSheet?.frame.size
            await check("a closing sheet keeps its size", closing == nil || closing == open, "\(String(describing: open)) → \(String(describing: closing))")
            await ui.settle(0.5)
            // With a session on it, a click on its face shows that session's menu, once no double-click can come.
            if let session = model.gridSessions.first {
                model.link(task: child, session: session.id)
                await ui.settle(0.4)
                faces.layoutSubtreeIfNeeded()
                func face() -> NSView? { faces.subviews.first { $0 is FaceStackView } }
                func facePoint() -> NSPoint { face().map { $0.convert(NSPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: nil) } ?? .zero }
                await check("the face shows at the card's start, before its status, the hand over it", (ui.hitView(facePoint()) as? FaceStackView)?.tracksHandCursor == true
                      && (face().map { faces.convert($0.frame, to: outline).maxX <= cell.convert(cell.glyph.frame, to: outline).minX } ?? false),
                      String(describing: ui.hitView(facePoint()).map { type(of: $0) }))
                let point = facePoint()
                var shown: String?
                let show = FaceMenu.show
                FaceMenu.show = { _, id, _, _ in shown = id }
                if let click = ui.mouseDown(point, clicks: 1) { outline.mouseDown(with: click) }
                await ui.settle(0.3)
                await check("a click on a task's face shows its session's menu at once, not Start Session", shown == session.id && model.modal == nil,
                      "\(shown ?? "-") \(String(describing: model.modal))")
                FaceMenu.show = show
                model.unlink(task: child, session: session.id)
                await ui.settle(0.3)
            }
        } else {
            await check("the subtask's faces", false)
        }


        // # in a title lists what it can become.
        let editor = NSTextView()
        editor.string = "Fix #rev"
        editor.setSelectedRange(NSRange(location: 8, length: 0))
        let word = OutlineCoordinator.hashWord(in: editor)
        await check("the word after # is completed", word?.text == "rev" && word?.range == NSRange(location: 5, length: 3), "\(String(describing: word))")
        editor.string = "Fix PR#418"
        editor.setSelectedRange(NSRange(location: 10, length: 0))
        await check("# inside a word isn't", OutlineCoordinator.hashWord(in: editor) == nil)

        // The modal's tags: + adds one.
        model.open(.task(child))
        await ui.settle(1)
        await check("+ shows after the tags in the modal", ui.anchor("tag-adder") != nil)
        if let plus = ui.anchor("tag-adder"), ui.canClickTables {
            await ui.click(plus, inSheet: true)
            await ui.settle(0.5)
            await ui.type("fresh")
            await ui.key(.return)
            await ui.settle(0.5)
            await tableCheck(ui, "+ after the tags adds one", model.task(child)?.tags.contains("fresh") == true, "\(model.task(child)?.tags ?? [])")
            await ui.key(.escape)
        } else {
            skip("+ after the tags adds one")
        }
        model.closeModal()
        model.shownDescriptions = []
        await ui.settle(0.6)
        // A ring with nothing started is only a grey track: hidden until something under it starts (2026-11-07).
        // On a block's header: a top-level task shows its progress line instead.
        if let holder = model.addTask(to: .overview, title: "Holds a block"), let fresh = model.addSubtask(to: holder.id, title: "Nothing started yet"),
           let first = model.addSubtask(to: fresh.id, title: "First part"),
           model.addSubtask(to: fresh.id, title: "Second part") != nil {
            await ui.settle(0.4)
            // Laid out on screen: a cell made off screen keeps its defaults.
            func bar() -> BlockProgressView? {
                let row = outline.row(forItem: coordinator.node(.task(fresh.id)))
                guard let cell = outline.view(atColumn: 1, row: row, makeIfNecessary: true) as? TaskCell else { return nil }
                cell.scrollToVisible(cell.bounds.insetBy(dx: 0, dy: -Driver.overlayClearance))
                ui.window.layoutIfNeeded()
                cell.layoutSubtreeIfNeeded()
                return cell.progress
            }
            let resting = bar()
            let shownAtRest = resting?.isHidden == false && resting?.tally.total == 2
            model.setStatus(first.id, .doing)
            await ui.settle(0.4)
            await check("a block's progress shows on its header, 0/2 with nothing started, and counts one doing once it starts", shownAtRest && bar()?.tally.doing == 1,
                  "\(String(describing: resting?.tally)) → \(String(describing: bar()?.tally))")
            model.deleteTasks([holder.id])
            await ui.settle(0.3)
        } else {
            await check("a task that holds a block, and its subtask", false)
        }

    }

    static func modal(_ model: AppModel, _ ui: Driver) async {
        guard let task = model.addTask(to: .overview, title: "Open me") else { return await check("a task for the modal", false) }
        model.open(.task(task.id))
        await ui.settle(0.8)
        await check("the task's modal opens as a sheet", ui.window.attachedSheet != nil)
        let session = model.gridSessions[0]
        model.open(.session(session.id), push: true)
        model.open(.task(task.id), push: true)
        await ui.settle(0.4)
        await check("opening from inside the modal keeps the way back", model.modalStack.count == 2)
        model.back()
        model.back()
        await check("Back goes back two levels", model.modal == .task(task.id) && model.modalStack.isEmpty)
        model.closeModal()
        await ui.settle(0.6)
        await check("Close ends the sheet", ui.window.attachedSheet == nil && model.modal == nil)
        model.beginStart(task: task.id)
        await ui.settle(1)
        await check("Start a Session focuses the first message, caret at the end", ui.sheetIsTyping, ui.sheetResponder)
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
        let wide = model.windowSize.width >= Metric.sectionBarWindow
        await check("the section bar is in the toolbar when the window has room for it, and gone when it hasn't",
              (ui.anchorFrame("section-bar") != nil) == wide && ui.anchorFrame("section-bar").map { $0.midY > ui.window.contentLayoutRect.maxY } ?? true, "\(Int(model.windowSize.width)) pt")
        func faces() -> [FaceLayer] { ui.findAll(FaceView.self).map(\.face) + ui.findAll(FaceStackView.self).flatMap(\.faceLayers) }
        func working() -> [FaceLayer] { faces().filter(\.isWorking) }
        await check("working faces are on the page", !working().isEmpty, "\(faces().count) faces")
        await check("each working face sways on the render server", working().allSatisfy(\.sways), "\(working().filter { !$0.sways }.count) of \(working().count) still")
        func breathing() -> [BreathingView] { ui.findAll(BreathingView.self) }
        await check("a card that needs the user breathes on the render server", !breathing().isEmpty && breathing().allSatisfy(\.breathes),
              "\(breathing().count) breathing, \(breathing().filter { !$0.breathes }.count) without their animation")
        let before = Self.mainThreadCPU()
        await ui.wait(2)
        let used = Self.mainThreadCPU() - before
        await check("the main thread rests while faces sway and cards breathe", used < 0.1, String(format: "%.0f ms of CPU in 2 s", used * 1000))
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
        seedLarge(model)
        model.backlogOpen = false
        await ui.settle(3)
        guard let outline = ui.find(TaskOutlineView.self), let scroll = outline.enclosingScrollView else {
            return await check("the outline with the large seed", false)
        }
        func scrollPage(to y: CGFloat) {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        var bottom: CGFloat { max((scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height, 0) }
        func visibleRowsDrawn() -> Bool {
            // Drawn: at full opacity, or faded with its card when the selection doesn't light it.
            let rows = outline.rows(in: outline.visibleRect)
            return rows.length > 0 && (rows.location..<rows.location + rows.length).allSatisfy { row in
                let task = (outline.item(atRow: row) as? OutlineNode)?.task
                let expected: CGFloat = task.map { outline.lit?.contains($0) == false } == true ? Motion.dimmedOpacity : 1
                return abs((outline.rowView(atRow: row, makeIfNecessary: false)?.alphaValue ?? 0) - expected) < 0.01
            }
        }

        // The Backlog opened below the fold, then scrolled to.
        scrollPage(to: bottom)
        await ui.settle(0.3)
        model.backlogOpen = true
        await ui.settle(0.1)
        scrollPage(to: bottom)
        await ui.settle(1.2)
        await check("the Backlog opened below the fold draws its rows when scrolled to", visibleRowsDrawn(), "\(outline.visibleRect)")
        scrollPage(to: 6000)
        await ui.settle(0.5)
        var built = 0
        outline.enumerateAvailableRowViews { _, _ in built += 1 }
        await check("the outline builds only the rows in view", built > 0 && built < 120, "\(built) row views for \(outline.numberOfRows) rows")
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
        await check("rows out of view drop the descriptions that were hidden", stale == 0, "\(stale) rows")

        let search = await Stall.measure(["r", "re", "reg", "regi", "reg", "re", "r", ""].map { text in { model.search = text } })
        let folded = model.taskTree.top(.overview).filter { !model.taskTree.children(of: $0).isEmpty }.prefix(8)
        let fold = await Stall.measure(folded.map { id in { model.setFold(id, .hidden) } } + folded.map { id in { model.setFold(id, .all) } })
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
        await check("rows scrolled into view are drawn, to the last one", visibleRowsDrawn()
              && outline.rowView(atRow: outline.numberOfRows - 1, makeIfNecessary: false) != nil, "\(outline.visibleRect)")
        // The lists' cards are layers under the rows, the GPU's to draw: a scroll redraws nothing for them (T-337).
        func bodies() -> [CALayer] { (outline.cardsView.layer?.sublayers ?? []).filter { !($0 is CAShapeLayer) } }
        func shapes() -> Int { outline.cardsView.shapes.count }
        await check("the cards and trays are layers under the rows, a body and a far shadow each", outline.subviews.first === outline.cardsView
              && shapes() > 0 && bodies().count == 2 * shapes() && bodies().allSatisfy { $0.shadowPath != nil },
              "\(bodies().count) layers for \(shapes()) cards and trays, first subview \(outline.subviews.first.map { String(describing: type(of: $0)) } ?? "none")")
        scrollPage(to: 0)

        print("  perf: baseline scroll of the small page \(baseline?.description ?? "-")")
        print("  perf: show all descriptions \(descriptions); search \(search); fold \(fold); move \(move); scroll \(scrolls); \(built) row views")
        await check("Show Descriptions with 500 tasks holds the main thread under 150 ms", descriptions.worst < 150, "\(descriptions)")
        await check("a search keystroke with 500 tasks holds it under 100 ms", search.worst < 100, "\(search)")
        await check("folding a task with 500 tasks holds it under 50 ms", fold.worst < 50, "\(fold)")
        await check("a move with 500 tasks takes under two frames, none over 100 ms", move.median < 34 && move.worst < 100, "\(move)")
        await check("scrolling the page with 500 tasks stays within a frame, rare steps at two, none at three",
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
        var description: String { "worst \(worst) at step \(steps.firstIndex(of: worst).map { $0 + 1 } ?? 0), median \(median), \(hitches) of \(steps.count) over 34 ms" }
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
    /// Where the pointer is, in window coordinates.
    private let location: NSPoint

    init(tasks: [Int] = [], session: String? = nil, item key: String? = nil, source: Any?, at location: NSPoint = .zero) {
        self.source = source
        self.location = location
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
    var draggingLocation: NSPoint { location }
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
        await until { isTyping && model.focusedTask == id }
        await settle()
    }

    /// Waits until a description's editor, on the page or in a sheet, takes the keys.
    func inEditor() async {
        await until { window.firstResponder is MarkdownEditor.EditorTextView || window.attachedSheet?.firstResponder is MarkdownEditor.EditorTextView }
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

extension UITest {
    // MARK: Stories: cards, blocks, Blocked and its links (T-372)

    static func storyFlow(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator else { return await check("the outline is on the page", false) }
        model.folded = []
        model.search = ""
        model.allDescriptions = []
        guard let goal = model.addTask(to: .overview, title: "Ship the story"),
              let first = model.addSubtask(to: goal.id, title: "First step"),
              let second = model.addSubtask(to: goal.id, title: "Second step"),
              let third = model.addSubtask(to: goal.id, title: "Third step"),
              let part = model.addSubtask(to: second.id, title: "A part of the second") else { return await check("a story to look at", false) }
        await endUndoGroup(model)
        await ui.settle(0.6)
        func index(_ id: Int) -> Int { outline.row(forItem: coordinator.node(.task(id))) }
        func cell(_ id: Int) -> TaskCell? {
            let row = index(id)
            return row >= 0 ? outline.view(atColumn: 1, row: row, makeIfNecessary: true) as? TaskCell : nil
        }
        // The goal heads a tray, on its big card; the second step heads a tray inside it; the steps are cards in it.
        await check("a top-level task with subtasks heads a block, a subtask with subtasks a block inside it",
              coordinator.plan.blocks.isSuperset(of: [goal.id, second.id]) && coordinator.plan.depth[goal.id] == 0 && coordinator.plan.depth[part.id] == 2)
        func storyCard(_ id: Int) -> NSRect? { outline.cardFrame(ofRow: index(id)) }
        func placed() -> Bool {
            guard let goalCard = storyCard(goal.id), let firstCard = storyCard(first.id), let partCard = storyCard(part.id) else { return false }
            return firstCard.minX == goalCard.minX && partCard.minX >= firstCard.minX + Metric.subtaskIndent
                && abs(goalCard.maxX - (outline.bounds.width - Metric.storyTrayPadding)) < 0.5
        }
        await check("a story's own subtasks sit full width under its big card, a block's subtasks a level in; the cards reach the section's edge",
              placed(), "\(String(describing: storyCard(goal.id))) \(String(describing: storyCard(first.id))) \(String(describing: storyCard(part.id)))")
        await check("two trays and a raised card per task show behind the rows", outline.cardsView.shapes.filter { $0.kind == .tray }.count >= 2
              && outline.cardsView.shapes.contains { $0.kind == .card && abs($0.rect.minY - (storyCard(first.id)?.minY ?? -1)) < 0.5 })
        await check("the goal's big card shows its progress line", cell(goal.id)?.storyHost != nil && cell(first.id)?.storyHost == nil)
        // A block in a block: each card and tray sits its tray's padding inside it, on the right as on the left (T-445).
        if let piece = model.addSubtask(to: part.id, title: "A piece of the part") {
            await endUndoGroup(model)
            await ui.settle(0.6)
            func misplaced() -> [String] {
                let shapes = outline.cardsView.shapes
                func tray(_ id: Int) -> NSRect? { shapes.first { $0.key == "tray:\(id)" }?.rect }
                return model.taskTree.subtree(of: goal.id).dropFirst().compactMap { id -> String? in
                    guard let parent = model.taskTree.parent(of: id), let outer = tray(parent),
                          let own = coordinator.plan.blocks.contains(id) ? tray(id) : outline.cardFrame(ofRow: index(id)) else { return "T-\(id) not drawn" }
                    let pad = coordinator.plan.depth[parent] == 0 ? Metric.storyTrayPadding : Metric.trayPadding
                    guard abs(outer.maxX - pad - own.maxX) > 0.5 || own.minX + 0.5 < outer.minX + pad else { return nil }
                    return "T-\(id) \(Int(own.minX))–\(Int(own.maxX)) in T-\(parent)'s tray \(Int(outer.minX))–\(Int(outer.maxX))"
                }
            }
            await check("every card and tray in a story sits its tray's padding inside it, right and left, at each level",
                  coordinator.plan.depth[piece.id] == 3 && misplaced().isEmpty, misplaced().joined(separator: "; "))
            model.deleteTasks([piece.id])
            await endUndoGroup(model)
            await ui.settle(0.4)
        } else {
            await check("a block in a block to look at", false)
        }
        // Blocked, with a reason: the glyph stays the status (2026-11-10), the red edge and the reason under the title.
        model.block(third.id, reason: "Waiting on a decision")
        await endUndoGroup(model)
        await ui.until(2) { cell(third.id)?.reason.isHidden == false }
        await check("a Blocked task keeps its status glyph and shows its reason under its title", cell(third.id)?.glyph.hold == nil
              && cell(third.id)?.reason.stringValue == "Waiting on a decision" && cell(third.id)?.reason.isHidden == false)
        await check("its card takes the red edge; no card takes a yellow one", outline.cardsView.shapes.contains { $0.ring == .blocked })
        model.unblock(third.id)
        await endUndoGroup(model)
        // Blocked by a task: a chip per blocking task; no lines (2026-11-10).
        await check("a link the tree already says, or a circle, is refused",
              model.addLink(second.id, .blockedBy, part.id) == .partOf && model.addLink(first.id, .blockedBy, goal.id) == .circle)
        await check("a task can be blocked by another", model.addLink(third.id, .blockedBy, first.id) == nil)
        await endUndoGroup(model)
        // The chip shows once the card is laid out again, a frame after its key.
        await ui.until(2) { cell(third.id).map { $0.blockers.keys == "T-\(first.id)" && !$0.blockers.isHidden } ?? false }
        await check("a task blocked by another shows the other's key in a chip, its glyph still its status",
              cell(third.id)?.glyph.hold == nil && cell(third.id)?.blockers.keys == "T-\(first.id)" && cell(third.id)?.blockers.isHidden == false,
              cell(third.id).map { "keys \($0.blockers.keys) hidden \($0.blockers.isHidden) hold \(String(describing: $0.glyph.hold)) cell \($0.frame.integral) chip \($0.blockers.frame.integral)" } ?? "no cell")
        // After: no arrow; selected, what it comes after stays lit and the rest fades.
        model.addLink(second.id, .after, first.id)
        await endUndoGroup(model)
        outline.deselectAll(nil)
        await ui.settle(0.2)
        // What fades is a card's content, its row; the cards' surfaces never fade (2026-11-11).
        func dimmed(_ id: Int) -> Bool? {
            let row = outline.row(forItem: coordinator.node(.task(id)))
            guard row >= 0, let view = outline.rowView(atRow: row, makeIfNecessary: false) else { return nil }
            return view.alphaValue < 1
        }
        let restAtRest = [first.id, second.id, third.id].allSatisfy { dimmed($0) != true }
        coordinator.select(second.id)
        ui.window.makeFirstResponder(outline)
        await ui.settle(0.3)
        if ui.window.isKeyWindow {
            func lit() -> Set<Int> { coordinator.lit() ?? [] }
            await check("selected, a task lights what it comes after, its parent and its subtasks; the rest fades",
                  restAtRest && lit().isSuperset(of: [second.id, first.id, goal.id, part.id]) && dimmed(first.id) == false && dimmed(third.id) == true,
                  "lit \(lit().sorted()), first \(String(describing: dimmed(first.id))), third \(String(describing: dimmed(third.id)))")
            coordinator.select(third.id)
            await ui.settle(0.3)
            await check("selected, a blocked task lights what blocks it", coordinator.lit()?.contains(first.id) == true)
        } else {
            // A background run's window is never key: as when the user is in another app, nothing fades.
            await check("while HQ's window isn't key, a selection fades nothing", restAtRest && coordinator.lit() == nil
                        && [first.id, second.id, third.id].allSatisfy { dimmed($0) != true },
                        "rest \(restAtRest) lit \(String(describing: coordinator.lit())) dimmed \([first.id, second.id, third.id].map(dimmed)) key \(ui.window.isKeyWindow) keyboard \(outline.hasKeyboard)")
            skip("selected, a task lights what it comes after, its parent and its subtasks; the rest fades")
            coordinator.select(third.id)
            await ui.settle(0.3)
        }
        // A click on a blocking task's chip selects that task.
        if let point = cell(third.id)?.blockers.windowPoint(of: first.id), let click = ui.mouseDown(point, clicks: 1) {
            outline.mouseDown(with: click)
            await ui.settle(0.4)
            await check("a click on a blocking task's chip selects it", model.selectedTasks == [first.id], "\(model.selectedTasks)")
        } else {
            await check("a click on a blocking task's chip selects it", false, "no chip")
        }
        await check("the order stays the user's: neither link moved a task",
              model.taskTree.children(of: goal.id) == [first.id, second.id, third.id])
        // Keys: B asks for a reason, Return blocks; B again unblocks.
        coordinator.select(first.id)
        await ui.settle(0.2)
        await ui.key("b")
        await ui.settle(0.6)
        if let picker = ui.popoverWindow("hold-reason"), let field = picker.firstResponder as? NSTextView {
            field.insertText("Needs an answer", replacementRange: NSRange(location: 0, length: 0))
            await ui.key(.return, inPopover: "hold-reason")
            await ui.until(2) { model.task(first.id)?.blocked == true }
            await check("B on a row asks why, and Return blocks it", model.task(first.id)?.blockedReason == "Needs an answer")
            await ui.key("b")
            await ui.until(2) { model.task(first.id)?.blocked == false }
            await check("B on a Blocked row unblocks it", model.task(first.id)?.blocked == false)
        } else {
            await tableCheck(ui, "B on a row asks why, and Return blocks it", false, "no popover")
        }
        // A task dropped on a task: the menu, then Add Below.
        let saved = OutlineCoordinator.pickDropChoice
        var offered: [String] = []
        OutlineCoordinator.pickDropChoice = { menu, _ in
            offered = menu.items.map(\.title).filter { !$0.isEmpty }
            return menu.items.first { $0.title == "Add Below T-\(first.id)" }
        }
        let drag = FakeDrag(tasks: [part.id], source: outline)
        _ = coordinator.outlineView(outline, acceptDrop: drag, item: coordinator.node(.task(first.id)), childIndex: NSOutlineViewDropOnItemIndex)
        await ui.until(2) { model.taskTree.parent(of: part.id) == goal.id }
        OutlineCoordinator.pickDropChoice = saved
        await check("a task dropped on a task asks: Subtask, Above, Below, then the links",
              offered.starts(with: ["Add as Subtask of T-\(first.id)", "Add Above T-\(first.id)", "Add Below T-\(first.id)", "Link to T-\(first.id)"])
              && offered.contains("T-\(first.id) Is Blocked by T-\(part.id)") && offered.contains("T-\(part.id) Comes After T-\(first.id)"),
              offered.joined(separator: " | "))
        await check("Add Below puts it right under the task it was dropped on",
              model.taskTree.children(of: goal.id).prefix(2) == [first.id, part.id], "\(model.taskTree.children(of: goal.id))")
        model.undoManager?.undo()
        await ui.until(2) { model.taskTree.parent(of: part.id) == second.id }
        await check("one Undo puts it back", model.taskTree.parent(of: part.id) == second.id)
        // Siblings move together in the model (the outline selects one row at a time since 2026-11-10).
        model.shiftTasks([second.id, third.id], by: -1)
        await endUndoGroup(model)
        await ui.settle(0.3)
        await check("siblings moved up together keep their order", model.taskTree.children(of: goal.id) == [second.id, third.id, first.id],
              "\(model.taskTree.children(of: goal.id))")
        // The cards hold still under a drag (2026-11-10): the middle of a card takes a dragged task, ringed (its menu
        // asks); its top edge shows a line in the gap above it, where the task would go.
        let targetRow = index(second.id)
        if let card = outline.cardFrame(ofRow: targetRow) {
            let rects = (0..<outline.numberOfRows).map { outline.rect(ofRow: $0) }
            func proposal(at y: CGFloat, item: Any?, index: Int) -> (operation: NSDragOperation, onto: Bool, ring: Bool, line: CGRect?) {
                let probe = FakeDrag(tasks: [first.id], source: outline, at: outline.convert(NSPoint(x: card.midX, y: y), to: nil))
                let operation = coordinator.outlineView(outline, validateDrop: probe, proposedItem: item, proposedChildIndex: index)
                return (operation, coordinator.proposedOnto == second.id, outline.dropOnto == second.id, outline.cardsView.dropLine)
            }
            let at = model.taskTree.children(of: goal.id).firstIndex(of: second.id) ?? 0
            let middle = proposal(at: card.midY, item: coordinator.node(.task(goal.id)), index: at)
            let edge = proposal(at: card.minY + 2, item: coordinator.node(.task(goal.id)), index: at)
            // AppKit proposing the row itself, near its bottom: below the card, not refused.
            let below = proposal(at: card.maxY - 2, item: coordinator.node(.task(second.id)), index: NSOutlineViewDropOnItemIndex)
            await check("a task dragged over the middle of a card goes onto it, the card ringed", middle.operation == .move && middle.onto && middle.ring && middle.line == nil,
                  "\(middle)")
            await check("over its top edge, between cards, a line in the gap above it", edge.operation == .move && !edge.onto && !edge.ring
                  && edge.line.map { $0.midY < card.minY && $0.midY > card.minY - Metric.taskGap && abs($0.minX - card.minX) < 1 } == true, "\(edge) card \(card)")
            await check("AppKit proposing the card near its bottom moves the task below it", below.operation == .move && !below.onto
                  && below.line.map { $0.midY > card.maxY } == true, "\(below)")
            await check("and no card moves while dragging", rects == (0..<outline.numberOfRows).map { outline.rect(ofRow: $0) }
                  && outline.draggingDestinationFeedbackStyle == .none)
            coordinator.dragEnded()
            await ui.settle(0.2)
            await check("the drag's end clears the ring and the line", outline.dropOnto == nil && outline.cardsView.dropLine == nil)
            let image = outline.cardImage(ofRow: targetRow)
            await check("a dragged task's image is its card alone", image?.size == card.size, "\(String(describing: image?.size)) card \(card.size)")
        }
        func keyDown(_ code: UInt16, _ characters: String = "") -> NSEvent? {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: code >= 123 && code <= 126 ? [.numericPad, .function] : [],
                             timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: ui.window.windowNumber, context: nil,
                             characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
        }
        // Space opens the selected task's window, as before (2026-11-10: no Quick Look).
        coordinator.select(second.id)
        await ui.settle(0.3)
        await ui.key(" ")
        await ui.until(2) { model.modal == .task(second.id) }
        await check("Space opens the selected task", model.modal == .task(second.id), String(describing: model.modal))
        model.closeModal()
        await ui.settle(0.5)
        // ↓ on the list's last task: the new task's card, solid with its ring; ↑ goes back to the task.
        let quickRow = outline.row(forItem: coordinator.node(.quickAdd(.overview)))
        if quickRow > 0, let lastTask = (outline.item(atRow: quickRow - 1) as? OutlineNode)?.task {
            coordinator.select(lastTask)
            await ui.settle(0.3)
            await ui.key(.down)
            await ui.settle(0.4)
            func typing() -> Bool { (ui.window.firstResponder as? NSTextView)?.delegate is QuickAddField }
            func newCard() -> CardShape? { outline.cardsView.shapes.first { $0.key == "new:\(TaskList.overview)" } }
            await check("↓ on the last task goes to the new task's card, solid with its ring", typing() && outline.selectedRowIndexes.isEmpty
                  && newCard()?.kind == .card && newCard()?.ring == .selected,
                  "typing \(typing()), selected \(outline.selectedRowIndexes.count), card \(String(describing: newCard()))")
            await ui.key(.up)
            await ui.settle(0.4)
            await check("↑ from it selects the last task again, its card dashed again", model.selectedTasks == [lastTask]
                  && outline.cardsView.shapes.first { $0.key == "new:\(TaskList.overview)" }?.kind == .newTask, "\(model.selectedTasks)")
        } else {
            await check("the list's new task card under its last task", false, "row \(quickRow)")
        }
        // The description button: a click selects its task and shows its description.
        model.setDescription(second.id, "What the second step is about.")
        await ui.settle(0.4)
        outline.deselectAll(nil)
        if let note = cell(second.id)?.note, !note.isHidden {
            note.performClick(nil)
            await ui.settle(0.4)
            await check("a click on a card's description button selects its task and shows its description",
                  model.selectedTasks == [second.id] && model.descriptionShownInOutline(second.id), "\(model.selectedTasks)")
            model.toggleDescription(second.id)
            await ui.settle(0.3)
        } else {
            await check("a card with a description shows its button", false)
        }
        // N beside a doing subtask of a filtered story: the filter goes off, the new task shows, its title edited (it was
        // added out of sight and left empty in the vault).
        model.setStatus(third.id, .doing)
        model.setStoryFilter(goal.id, true)
        await endUndoGroup(model)
        await ui.settle(0.6)
        coordinator.select(third.id)
        await ui.settle(0.3)
        await ui.key("n")
        await ui.settle(0.6)
        await check("N beside a doing subtask of a filtered story: its filter goes off, the new task shows, its title edited",
              model.focusedTask.map { $0 != third.id && index($0) >= 0 } == true && ui.isTyping && model.storyFilter.isEmpty,
              "\(String(describing: model.focusedTask)) \(model.storyFilter)")
        let besides = model.focusedTask
        await ui.key(.escape)
        await ui.until(2) { besides.map { model.task($0) == nil } ?? true }
        await check("and Escape drops it, empty", besides.map { model.task($0) == nil } == true,
              besides.flatMap { model.task($0) }.map { "left: title \"\($0.title)\" empty \(model.isEmptyTask($0.id)) shown \(index($0.id)) typing \(ui.isTyping) responder \(String(describing: ui.window.firstResponder)) selected \(model.selectedTasks)" } ?? "-")
        model.setStoryFilter(goal.id, false)
        model.setStatus(third.id, .todo)
        await endUndoGroup(model)
        await ui.settle(0.4)
        // In a task's window, moves keep a subtask in it; Add Subtask from a card's menu edits the new one there, not on the page.
        model.open(.task(goal.id))
        await ui.until(2) { ui.window.attachedSheet != nil }
        await ui.settle(0.8)
        if let sheet = ui.window.attachedSheet, let top = model.taskTree.children(of: goal.id).first {
            model.outdentTasks([top])
            model.shiftTasks([top], by: -1)
            await endUndoGroup(model)
            await ui.settle(0.4)
            await check("in a task's window, ⇧← and ⇧↑ never take a subtask out of it", model.taskTree.parent(of: top) == goal.id && model.modal == .task(goal.id),
                  "parent \(String(describing: model.taskTree.parent(of: top)))")
            if let added = model.addSubtask(to: third.id) {
                model.outlineFocus = .title(added.id, by: 0)
                await ui.until(2) { (sheet.firstResponder as? NSTextView)?.editedTitle?.task == added.id }
                await check("Add Subtask in a task's window edits the new subtask there, not on the page",
                      (sheet.firstResponder as? NSTextView)?.editedTitle?.task == added.id && (ui.window.firstResponder as? NSTextView)?.editedTitle == nil
                      && model.outlineFocus == nil, "\(String(describing: sheet.firstResponder))")
                model.deleteTasks([added.id])
                await endUndoGroup(model)
            }
        }
        model.closeModal()
        await ui.settle(0.5)
        // The task's window: ↓ on its last subtask goes to the new subtask's card, ↑ back; a double-click on a subtask's
        // title isn't the description's; Escape in the new subtask closes the window.
        model.open(.task(goal.id))
        await ui.until(2) { ui.window.attachedSheet != nil }
        await ui.settle(0.8)
        if let sheet = ui.window.attachedSheet, let scoped = OutlineCoordinator.scoped(goal.id), let inner = ui.find(TaskOutlineView.self, in: sheet.contentView) {
            scoped.selectLast()
            await ui.settle(0.3)
            let lastSub = inner.selectedRow >= 0 ? (inner.item(atRow: inner.selectedRow) as? OutlineNode)?.task : nil
            if let down = keyDown(125) { _ = scoped.key(down) }
            await ui.until(2) { sheet.firstResponder is NSTextView }
            let field = (sheet.firstResponder as? NSTextView)?.delegate as? NSTextField
            await check("↓ on the window's last subtask goes to the new subtask's card", field?.identifier?.rawValue == "new-subtask-field"
                  && inner.selectedRowIndexes.isEmpty, "\(String(describing: sheet.firstResponder))")
            if let field, let editor = sheet.firstResponder as? NSTextView {
                _ = field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:)))
                await ui.settle(0.3)
                await check("↑ from it selects the last subtask", lastSub != nil && inner.selectedRow >= 0
                      && (inner.item(atRow: inner.selectedRow) as? OutlineNode)?.task == lastSub && sheet.firstResponder === inner)
            }
            // A double-click on a subtask's title, as the window's description would see it: not its.
            let firstRow = inner.row(forItem: scoped.node(.task(first.id)))
            if firstRow >= 0, let title = (inner.view(atColumn: 1, row: firstRow, makeIfNecessary: true) as? TaskCell)?.title,
               let area = ui.find(EditOnDoubleClick.CatcherView.self, in: sheet.contentView),
               let event = NSEvent.mouseEvent(with: .leftMouseDown, location: title.convert(NSPoint(x: 4, y: title.bounds.midY), to: nil), modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sheet.windowNumber, context: nil,
                                              eventNumber: 0, clickCount: 2, pressure: 1) {
                let point = area.convert(event.locationInWindow, from: nil)
                await check("a double-click on a subtask's title isn't taken by the window's description", area.take(event) != nil && !model.modalEditingDescription,
                      "catcher visible \(area.visibleRect.integral) has the point \(area.visibleRect.contains(point))")
            } else {
                await check("a subtask's title and the window's description", false)
            }
            if let fieldView = ui.find(FocusField.self, in: sheet.contentView) {
                sheet.makeFirstResponder(fieldView)
                await ui.settle(0.3)
                if let editor = sheet.firstResponder as? NSTextView {
                    _ = fieldView.delegate?.control?(fieldView, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
                }
                await ui.until(2) { model.modal == nil }
                await check("Escape in the new subtask closes the window", model.modal == nil, String(describing: model.modal))
            }
        } else {
            await check("the task's window and its subtasks", false)
        }
        model.closeModal()
        await ui.settle(0.5)
        // The task's window: Blocked, what it's blocked by and comes after, each removable, Blocked By… and After….
        model.open(.task(third.id))
        await ui.until(2) { ui.window.attachedSheet != nil }
        await ui.settle(0.8)
        await check("the task's window shows what it's blocked by, with Block…, Blocked By… and After… on the label line, and no Blocked line",
              ui.anchor("blocked-property") == nil && ui.anchor("relation:\(first.id)") != nil && ui.anchor("relation-add:Block…") != nil
              && ui.anchor("relation-add:Blocked By…") != nil && ui.anchor("relation-add:After…") != nil)
        await check("the task's window has More and one main action, Start Session… with no session on it",
                    ui.anchor("task-more") != nil && ui.anchor("task-main-action") != nil)
        model.block(third.id, reason: "Waiting on a decision")
        await check("a Blocked task's window says why, with Unblock, and no Block…", ui.anchor("blocked-property") != nil && ui.anchor("relation-add:Block…") == nil)
        model.unblock(third.id)
        model.closeModal()
        await ui.settle(0.5)
        // The story's window: its subtasks as the list shows them, the same cards, above its related tasks (2026-11-11).
        model.open(.task(goal.id))
        await ui.until(2) { ui.window.attachedSheet != nil }
        await ui.settle(1)
        func rows() -> [Int] {
            let scoped = OutlineCoordinator.live.compactMap(\.coordinator).first { $0.root == goal.id }
            return [first.id, second.id, third.id].map { scoped?.row(of: $0) ?? -1 }
        }
        func anchors() -> (NSPoint?, NSPoint?) { (ui.anchor("subtask-outline"), ui.anchor("relation-add:After…")) }
        await check("the task's window shows its subtasks as the list's cards, above its related tasks",
              rows().allSatisfy { $0 >= 0 } && anchors().0 != nil && anchors().1.map { relation in anchors().0.map { $0.y > relation.y } ?? false } == true,
              "rows \(rows()), outline \(String(describing: anchors().0)), relations \(String(describing: anchors().1))")
        // Its cards act as the list's: a row's menu goes through the window's outline.
        await check("a subtask in the window belongs to the window's outline", OutlineCoordinator.owner(of: second.id)?.root == goal.id)
        model.closeModal()
        await ui.settle(0.5)
        await check("closed, the page's outline has its rows again", OutlineCoordinator.owner(of: second.id)?.root == nil)
        model.deleteTasks([goal.id])
        await endUndoGroup(model)
        await ui.settle(0.3)
    }
}
