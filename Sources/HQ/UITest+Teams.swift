import AppKit
import HQKit
import SwiftUI

/// Teams on the grid (T-409, T-410): a team's faces and toggle; its card open over the cards below and the next section,
/// one at a time, folded by a click outside, Escape or ⌘↑; the arrows through its rows; its menus; a session dropped on
/// another asks Move Under or Make Root, with Undo.
extension UITest {
    static func teams(_ model: AppModel, _ ui: Driver) async {
        guard let collection = ui.find(SessionGrid.CardCollection.self), let grid = collection.delegate as? SessionGrid.Coordinator,
              let lead = model.gridRoots.first(where: { model.team(of: $0.id).count == 4 })?.id else {
            return await check("the seed's team on the grid", false)
        }
        await cardsFollowRoots(model, ui, collection, grid, lead)
        await scenario(model, ui)
        await teamCard(model, ui, collection, grid, lead)
        await scenario(model, ui)
        await teamKeys(model, ui, collection, grid, lead)
        await scenario(model, ui)
        await teamMenus(model, ui, lead)
        await scenario(model, ui)
        await teamDrops(model, ui, collection, grid, lead)
        await scenario(model, ui)
        await openCardFits(model, ui, lead)
    }

    /// A card's view on the grid, scrolled into view.
    static func card(_ id: String, _ collection: NSCollectionView, _ grid: SessionGrid.Coordinator) -> SessionGrid.CardView? {
        guard let index = grid.ids.firstIndex(of: id), let card = collection.item(at: IndexPath(item: index, section: 0))?.view as? SessionGrid.CardView else { return nil }
        card.scrollToVisible(card.bounds.insetBy(dx: 0, dy: -Driver.overlayClearance))
        return card
    }

    /// A press and release on a view, as the window hands them to it: a background run takes them too.
    private static func press(_ view: NSView, at point: NSPoint, _ ui: Driver, clicks: Int = 1) async {
        for click in 1...clicks {
            guard let down = ui.mouseDown(point, clicks: click),
                  let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: ui.window.windowNumber, context: nil, eventNumber: 0, clickCount: click, pressure: 0) else { return }
            // A collection view tracks the press up to its release: the release waits in the queue.
            NSApp.postEvent(up, atStart: false)
            view.mouseDown(with: down)
            view.mouseUp(with: up)
        }
        await ui.settle(0.2)
    }

    /// The middle of a rect of a view, in window coordinates.
    static func center(_ rect: NSRect, in view: NSView) -> NSPoint {
        let frame = view.convert(rect, to: nil)
        return NSPoint(x: frame.midX, y: frame.midY)
    }

    static func openCard(_ ui: Driver) async -> TeamCardView? {
        await ui.until { ui.find(TeamCardView.self)?.window != nil }
        return ui.find(TeamCardView.self)
    }

    /// The card views on the grid: one per top-level session, each inside the grid.
    private static func cardViews(_ collection: NSCollectionView) -> [NSView] {
        collection.subviews.filter { $0 is SessionGrid.CardView && !$0.isHiddenOrHasHiddenAncestor }
    }

    /// Top-level sessions that move into a team leave the grid with their card views, whatever happens in between.
    private static func cardsFollowRoots(_ model: AppModel, _ ui: Driver, _ collection: SessionGrid.CardCollection, _ grid: SessionGrid.Coordinator, _ lead: String) async {
        for round in 1...3 {
            let loose = model.gridRoots.filter { $0.isRunning && $0.id != lead && model.team(of: $0.id).isEmpty }.map(\.id)
            guard loose.count >= 2 else { return await check("two top-level sessions to move", false) }
            model.setParent(loose[0], to: lead)
            model.setParent(loose[1], to: lead)
            await ui.settle(0.3)
            await endUndoGroup(model)
            model.undoManager?.undo()
            await ui.settle(0.3)
            model.setParent(loose[0], to: lead)
            model.setParent(loose[1], to: lead)
            // A sheet at once, and a new card while it shows (Start a Session from it).
            model.beginStart(parent: round == 2 ? lead : nil)
            await ui.until { ui.window.attachedSheet != nil }
            model.startDraft?.name = "Round \(round)"
            model.startFromDraft()
            await ui.until { ui.window.attachedSheet == nil }
            await ui.settle(0.6)
            let views = cardViews(collection), bounds = collection.bounds.insetBy(dx: -1, dy: -1)
            await check("round \(round): cards moved into a team leave with their views, the others inside the grid",
                        grid.ids == model.gridRoots.map(\.id) && views.count == grid.ids.count && views.allSatisfy { $0.alphaValue == 1 }
                            && views.allSatisfy { bounds.contains(NSPoint(x: $0.frame.midX, y: $0.frame.midY)) },
                        "\(views.count) card views for \(grid.ids.count) cards, \(views.filter { !bounds.contains(NSPoint(x: $0.frame.midX, y: $0.frame.midY)) }.count) outside")
            await scenario(model, ui)
        }
    }

    // MARK: The card

    private static func teamCard(_ model: AppModel, _ ui: Driver, _ collection: SessionGrid.CardCollection, _ grid: SessionGrid.Coordinator, _ lead: String) async {
        let team = model.team(of: lead).map(\.session.id)
        guard let rollout = model.gridRoots.first(where: { !$0.isRunning })?.id, let first = grid.ids.first else { return await check("the closed leader", false) }
        await check("the grid shows the top-level sessions, a closed leader whose team runs among them",
                    grid.ids == model.gridRoots.map(\.id) && grid.ids.contains(rollout) && !team.contains { grid.ids.contains($0) },
                    "\(grid.ids.count) cards")
        guard let leadCard = card(lead, collection, grid) else { return await check("the team's card", false) }
        await check("VoiceOver reads a team's card with its sessions and who needs the user",
                    leadCard.accessibilityLabel() == "registry: ready for more customers, idle, 4 sessions, 1 wants permission",
                    leadCard.accessibilityLabel() ?? "-")
        await ui.until { leadCard.tray != .zero }
        guard let content = leadCard.content else { return await check("the team card's content", false) }
        let spots = SessionCard.traySpots(content, in: leadCard.tray)
        await check("at rest, the team's faces in their order and its toggle", spots.faces.map(\.id) == team && spots.toggle.minX > spots.faces.last?.rect.maxX ?? 0,
                    "\(spots.faces.count) faces")

        // A small face focuses its terminal, as every face does; nothing is selected.
        let asking = team[2]
        model.selectSection(nil)
        let logged = model.ghosttyLog.count
        await press(collection, at: center(spots.faces[2].rect, in: leadCard), ui)
        await check("a click on a team's face focuses that session's terminal, and selects nothing",
                    model.ghosttyLog.count == logged + 1 && model.ghosttyLog.last == "focus \(model.session(asking)?.tty ?? "-")" && model.selectedSession == nil,
                    "\(model.ghosttyLog.suffix(1))")

        // A hook event on one session draws its own card again, none other.
        let renders = SessionGrid.CardItem.renders, minute = model.now
        if var item = model.session(team[3]) {
            item.status = SessionStatus(state: .working, since: .now)
            model.put(item)
        }
        await ui.settle(0.4)
        await check("a session's new state redraws its team's card only", SessionGrid.CardItem.renders - renders == 1 || model.now != minute,
                    "\(SessionGrid.CardItem.renders - renders) cards")

        // The toggle opens the card itself, over the cards below: nothing on the page moves.
        let gridFrame = collection.convert(collection.bounds, to: nil)
        let frames = (0..<collection.numberOfItems(inSection: 0)).compactMap { collection.item(at: IndexPath(item: $0, section: 0))?.view.frame }
        await press(collection, at: center(spots.toggle, in: leadCard), ui)
        await check("the toggle opens the team", model.openTeam == lead)
        guard let open = await openCard(ui) else { return await check("the open team's card", false) }
        let cardFrame = leadCard.convert(leadCard.bounds, to: nil), openFrame = open.convert(open.bounds, to: nil)
        await check("the open card starts where its card is, a row per session", abs(openFrame.minX - cardFrame.minX) < 1 && abs(openFrame.maxY - cardFrame.maxY) < 1
                    && abs(openFrame.width - cardFrame.width) < 1 && abs(openFrame.height - SessionCard.openHeight(rows: 4)) < 1, "\(openFrame) over \(cardFrame)")
        await check("nothing on the page moves", collection.convert(collection.bounds, to: nil) == gridFrame
                    && (0..<collection.numberOfItems(inSection: 0)).compactMap { collection.item(at: IndexPath(item: $0, section: 0))?.view.frame } == frames)
        if let index = grid.ids.firstIndex(of: lead), grid.ids.indices.contains(index + grid.columns),
           let below = collection.item(at: IndexPath(item: index + grid.columns, section: 0))?.view {
            let overlap = below.convert(below.bounds, to: nil).intersection(openFrame)
            await check("it floats over the card below and takes its clicks", !overlap.isEmpty && ui.hitView(NSPoint(x: overlap.midX, y: overlap.midY)) === open,
                        "\(overlap)")
        }

        // Its rows: a click selects, a double-click opens, a face focuses.
        guard let row = open.rowFrame(team[0]), let deep = open.rowFrame(team[1]) else { return await check("the open card's rows", false) }
        await press(open, at: center(row, in: open), ui)
        await check("a click on a row selects its session", model.selectedSession == team[0] && model.selectedSection == .sessions,
                    model.selectedSession ?? "-")
        await press(open, at: center(row, in: open), ui, clicks: 2)
        await check("a double-click on a row opens its session", model.modal == .session(team[0]), "\(String(describing: model.modal))")
        model.closeModal()
        await ui.until { ui.window.attachedSheet == nil }
        let face = SessionCard.rowFace(depth: 2).offsetBy(dx: 0, dy: deep.minY)
        let focused = model.ghosttyLog.count
        await press(open, at: center(face, in: open), ui)
        await check("a click on a row's face focuses that session", model.ghosttyLog.count == focused + 1
                    && model.ghosttyLog.last == "focus \(model.session(team[1])?.tty ?? "-")", "\(model.ghosttyLog.suffix(1))")

        // One open at a time: another team's toggle folds the first.
        if let other = card(rollout, collection, grid) {
            await ui.until { other.tray != .zero }
            if let rest = other.content {
                await press(collection, at: center(SessionCard.traySpots(rest, in: other.tray).toggle, in: other), ui)
            }
            await check("opening another team folds the first: one open at a time", model.openTeam == rollout && open.content?.session.id != lead,
                        "\(model.openTeam ?? "none")")
        }

        // A click anywhere outside folds it, and does what it does there in the same click.
        model.toggleTeam(lead)
        await ui.settle(0.3)
        guard let firstCard = card(first, collection, grid) else { return }
        await ui.click(center(firstCard.bounds, in: firstCard))
        await check("a click outside the open card folds it", model.openTeam == nil, model.openTeam ?? "none")
        await tableCheck(ui, "and the card clicked is selected in the same click", model.selectedSession == first, model.selectedSession ?? "-")

        // At the grid's end, it floats over the next section.
        model.moveSession(lead, to: model.gridRoots.count)
        model.toggleTeam(lead)
        await ui.settle(0.4)
        guard let last = await openCard(ui) else { return }
        last.scrollToVisible(last.bounds)
        ui.window.layoutIfNeeded()
        let lastFrame = last.convert(last.bounds, to: nil), bottom = collection.convert(collection.bounds, to: nil).minY
        let past = NSPoint(x: lastFrame.midX, y: (lastFrame.minY + bottom) / 2)
        await check("at the grid's end, the open card floats over the next section and takes its clicks",
                    lastFrame.minY < bottom - Space.lg && ui.hitView(past) === last, "card bottom \(Int(lastFrame.minY)), grid bottom \(Int(bottom))")
    }

    /// With the sections below folded, the page makes room past its end for the open card: its last row scrolls into view.
    private static func openCardFits(_ model: AppModel, _ ui: Driver, _ lead: String) async {
        model.folded = [.files, .tasks]
        model.moveSession(lead, to: model.gridRoots.count)
        // A big team, last on the grid: its card reaches past the page's end, and past the window's.
        for index in 0..<12 {
            model.put(SessionItem(id: String(format: "7ea70000-0000-4000-8000-%012d", index), customName: "Team row \(index + 1)",
                                  status: SessionStatus(state: .idle, since: .now), cwd: NSTemporaryDirectory(), repo: "team", branch: "row-\(index + 1)",
                                  started: .now, tty: "/dev/ttys2\(index + 10)", order: Double(index + 10), parent: lead))
        }
        model.openTeam = lead
        guard let open = await openCard(ui), let last = model.team(of: lead).last?.session.id, let row = open.rowFrame(last),
              let scroll = open.enclosingScrollView, let document = scroll.documentView else { return await check("the open card in the page", false) }
        await ui.until { document.bounds.contains(open.convert(row, to: document)) }
        open.scrollToVisible(row)
        ui.window.layoutIfNeeded()
        let inDocument = open.convert(row, to: document), shown = open.convert(row, to: scroll.contentView)
        await check("with the sections below folded, the page makes room for the open card, and its last row scrolls into view",
                    document.bounds.contains(inDocument) && scroll.contentView.bounds.contains(shown),
                    "row \(Int(inDocument.minY))–\(Int(inDocument.maxY)) in a page of \(Int(document.bounds.height))")
        let opened = document.bounds.height
        model.openTeam = nil
        await check("folded, the room goes: the page ends where its content does", ui.find(TeamCardView.self)?.window == nil && document.bounds.height < opened,
                    "\(Int(document.bounds.height)) after \(Int(opened))")
        model.folded = []
    }

    // MARK: Keys

    private static func teamKeys(_ model: AppModel, _ ui: Driver, _ collection: SessionGrid.CardCollection, _ grid: SessionGrid.Coordinator, _ lead: String) async {
        let team = model.team(of: lead).map(\.session.id)
        grid.select(lead)
        grid.takeKeys()
        await ui.key(.down, .command)
        await check("⌘↓ shows the selected team's sessions", model.openTeam == lead)
        var walked: [String] = []
        for _ in team {
            await ui.key(.down)
            walked.append(model.selectedSession ?? "-")
        }
        await check("↓ walks the open team's rows", walked == team, "\(walked.map { $0.prefix(8) })")
        let index = grid.ids.firstIndex(of: lead) ?? 0
        let below = grid.ids.indices.contains(index + grid.columns) ? grid.ids[index + grid.columns] : team.last
        await ui.key(.down)
        await check("↓ on its last row goes to the card below, and the team folds", model.selectedSession == below && model.openTeam == (below == team.last ? lead : nil),
                    "\(model.selectedSession ?? "-"), open \(model.openTeam ?? "none")")
        grid.select(lead)
        await ui.key(.down, .command)
        await ui.key(.down)
        await ui.key(" ")
        await check("Space opens the selected row's session", model.modal == .session(team[0]), "\(String(describing: model.modal))")
        model.closeModal()
        await ui.until { ui.window.attachedSheet == nil }
        grid.takeKeys()
        let logged = model.ghosttyLog.count
        await ui.key(.return)
        await check("Return focuses it in Ghostty", model.ghosttyLog.count == logged + 1 && model.ghosttyLog.last == "focus \(model.session(team[0])?.tty ?? "-")",
                    "\(model.ghosttyLog.suffix(1))")
        await ui.key(.up, .command)
        await check("⌘↑ hides them, and its top card takes the selection", model.openTeam == nil && model.selectedSession == lead)
        await ui.key(.down, .command)
        await ui.key(.down)
        await ui.key(.escape)
        await check("Escape folds it too", model.openTeam == nil && model.selectedSession == lead)
        await ui.key(.right)
        await check("→ walks to the next card", model.selectedSession == grid.ids[min(index + 1, grid.ids.count - 1)], model.selectedSession ?? "-")
    }

    // MARK: Menus

    private static func teamMenus(_ model: AppModel, _ ui: Driver, _ lead: String) async {
        let team = model.team(of: lead).map(\.session)
        guard let top = model.session(lead), let worker = team.first, let other = model.gridRoots.first(where: { $0.id != lead && $0.isRunning }) else {
            return await check("a team and another session", false)
        }
        func menu(_ session: SessionItem) -> NSMenu {
            let menu = NSHostingMenu(rootView: SessionMenu(session: session).environment(model))
            menu.update()
            return menu
        }
        let titles = menu(top).items.map(\.title)
        await check("a team's top card's menu: its sessions, a child, its history, Move Under, Close Team with its count; no Fork Session",
                    ["Show Its Sessions", "Start Child Session…", "Start Session from Its History…", "Move Under", "Make Root", "Close Team (5 sessions)…"]
                        .allSatisfy(titles.contains) && !titles.contains("Fork Session"), titles.joined(separator: ", "))
        await check("Make Root is off on a top-level session", menu(top).items.first { $0.title == "Make Root" }?.isEnabled == false)
        let rowMenu = menu(worker)
        await check("a team's session can be made top-level, and shows no team of its own",
                    rowMenu.items.first { $0.title == "Make Root" }?.isEnabled == true && !rowMenu.items.contains { $0.title.hasSuffix("Its Sessions") },
                    rowMenu.items.map(\.title).joined(separator: ", "))
        let under = menu(other).items.first { $0.title == "Move Under" }?.submenu?.items.map(\.title) ?? []
        await check("Move Under lists the open sessions on the page, not itself", under.contains(MenuAction.short(top.name)) && under.contains(MenuAction.short(worker.name))
                    && !under.contains(MenuAction.short(other.name)), under.joined(separator: ", "))

        // Show Its Sessions, then Start Child Session… from the menu.
        let topMenu = menu(top)
        if let index = topMenu.items.firstIndex(where: { $0.title == "Show Its Sessions" }) { topMenu.performActionForItem(at: index) }
        await check("Show Its Sessions opens the team", model.openTeam == lead)
        let child = menu(top)
        if let index = child.items.firstIndex(where: { $0.title == "Start Child Session…" }) { child.performActionForItem(at: index) }
        await check("Start Child Session… opens Start a Session under it", model.modal == .start && model.startDraft?.parent == lead,
                    "\(String(describing: model.modal))")
        model.closeModal()
        await ui.until { ui.window.attachedSheet == nil }

        // Close Team (5 sessions)…: asked, then /exit in each terminal; the one waiting on the user is left for them.
        for id in [lead] + team.map(\.id) {
            guard var item = model.session(id) else { continue }
            item.transcriptPath = "/tmp/HQ-team-\(id).jsonl"
            model.put(item)
        }
        let logged = model.ghosttyLog.count
        model.closeTeam(lead)
        await ui.settle(0.2)
        func closing() -> [String] { Array(model.ghosttyLog.dropFirst(logged)) }
        let ttys = ([top] + team).filter { !$0.status.needsYou }.compactMap(\.tty)
        let asking = team.first { $0.status.needsYou }?.tty ?? "-"
        await check("Close Team asks with the count, then closes each of its sessions but the one that waits on the user",
                    closing().first == "confirm close team \(lead), 5 sessions" && ttys.allSatisfy { tty in closing().contains { $0.hasSuffix("/exit in \(tty)") } }
                    && !closing().contains { $0.hasSuffix(asking) }, closing().joined(separator: " | "))
    }

    // MARK: Drops

    /// The grid's validateDrop, with the place it settles on.
    static func propose(_ grid: SessionGrid.Coordinator, _ collection: NSCollectionView, _ info: FakeDrag, item: Int,
                                operation: NSCollectionView.DropOperation) -> (NSDragOperation, NSCollectionView.DropOperation, Int) {
        var path = NSIndexPath(forItem: item, inSection: 0)
        var op = operation
        let result = withUnsafeMutablePointer(to: &path) { pathPointer in
            withUnsafeMutablePointer(to: &op) { opPointer in
                grid.collectionView(collection, validateDrop: info, proposedIndexPath: AutoreleasingUnsafeMutablePointer(pathPointer), dropOperation: opPointer)
            }
        }
        return (result, op, path.item)
    }

    private static func teamDrops(_ model: AppModel, _ ui: Driver, _ collection: SessionGrid.CardCollection, _ grid: SessionGrid.Coordinator, _ lead: String) async {
        let team = model.team(of: lead).map(\.session.id)
        let roots = grid.ids
        guard let index = roots.firstIndex(of: lead), let leadCard = card(lead, collection, grid),
              let loose = roots.first(where: { $0 != lead && model.session($0)?.isRunning == true && model.team(of: $0).isEmpty }) else {
            return await check("a team and a session to drop", false)
        }
        var titles: [String] = []
        var choice = ""
        let picked = SessionGrid.pickDropChoice
        SessionGrid.pickDropChoice = { menu in
            titles = menu.items.map(\.title)
            return menu.items.first { $0.title.hasPrefix(choice) }
        }
        defer { SessionGrid.pickDropChoice = picked }

        // A card dropped on the middle of another: Move Under it, with Undo.
        let middle = center(leadCard.bounds, in: leadCard)
        let onto = FakeDrag(session: loose, source: collection, at: middle)
        let proposed = propose(grid, collection, onto, item: index, operation: .on)
        await check("a session over the middle of another card drops onto it", proposed.0 == .move && proposed.1 == .on && grid.dropTarget?.item == index,
                    "\(proposed)")
        choice = "Move Under"
        await endUndoGroup(model)
        _ = grid.collectionView(collection, acceptDrop: onto, indexPath: IndexPath(item: index, section: 0), dropOperation: .on)
        grid.dragEnded()
        await ui.until { model.session(loose)?.parent == lead }
        await check("dropped, a menu asks: Move Under it, or Cancel (a top-level one has no Make Root)",
                    titles.contains { $0.hasPrefix("Move Under “registry: ready") } && titles.contains("Cancel") && !titles.contains("Make Root"),
                    titles.joined(separator: " | "))
        await check("Move Under puts it in that team, selected, its team open", model.session(loose)?.parent == lead && model.selectedSession == loose
                    && !grid.ids.contains(loose) && model.openTeam == lead, "\(model.openTeam ?? "none")")
        await endUndoGroup(model)
        model.undoManager?.undo()
        await ui.until { grid.ids == roots }
        await check("Undo puts it back on the grid, in its place", model.session(loose)?.parent == nil && grid.ids == roots)

        // Its edge: a place in the order, right before it, its line shown (T-437). Its left edge on two columns, its top on one.
        let edge = FakeDrag(session: loose, source: collection, at: cardEdge(index, after: false, collection, grid))
        let between = propose(grid, collection, edge, item: index, operation: .on)
        let before: Bool = if case .place(let place, _)? = grid.drop { place.parent == nil && place.before == lead } else { false }
        await check("over a card's edge, it takes a place right before it", between.0 == .move && before && grid.dropTarget == nil,
                    "\(between), \(String(describing: grid.drop))")
        grid.dragEnded()

        // A team's row dropped on another card: Move Under it, or Make Root.
        model.openTeam = lead
        guard let open = await openCard(ui), let worker = team.last, let target = card(loose, collection, grid) else { return await check("the open team", false) }
        let row = FakeDrag(session: worker, source: open, at: center(target.bounds, in: target))
        _ = propose(grid, collection, row, item: grid.ids.firstIndex(of: loose) ?? 0, operation: .on)
        choice = "Make Root"
        await endUndoGroup(model)
        _ = grid.collectionView(collection, acceptDrop: row, indexPath: IndexPath(item: grid.ids.firstIndex(of: loose) ?? 0, section: 0), dropOperation: .on)
        grid.dragEnded()
        await ui.until { model.session(worker)?.parent == nil }
        await check("a team's session dropped on a card is asked Move Under it or Make Root", titles.contains { $0.hasPrefix("Move Under") } && titles.contains("Make Root"),
                    titles.joined(separator: " | "))
        await check("Make Root puts it on the grid", model.session(worker)?.parent == nil && model.gridRoots.contains { $0.id == worker })
        await endUndoGroup(model)
        model.undoManager?.undo()
        await ui.until { model.session(worker)?.parent == lead }
        await check("Undo puts it back in its team", model.session(worker)?.parent == lead && grid.ids == roots)

        // A card dropped on an open row: Move Under that session.
        model.openTeam = lead
        guard let open = await openCard(ui), let rowFrame = open.rowFrame(team[0]) else { return }
        let onRow = FakeDrag(session: loose, source: collection, at: center(rowFrame, in: open))
        await check("a session over an open row drops onto it", open.dropOperation(onRow) == .move && open.dropOn == team[0])
        choice = "Move Under"
        await endUndoGroup(model)
        _ = open.performDragOperation(onRow)
        await ui.until { model.session(loose)?.parent == team[0] }
        await check("dropped there, Move Under puts it under that row's session", model.session(loose)?.parent == team[0]
                    && model.team(of: lead).first { $0.session.id == loose }?.depth == 2)
        await endUndoGroup(model)
        model.undoManager?.undo()
        await ui.until { model.session(loose)?.parent == nil && grid.ids == roots }

        // A team's session let go before the first card: top-level there, no question (T-437).
        model.openTeam = lead
        guard let again = await openCard(ui) else { return }
        let first = FakeDrag(session: worker, source: again, at: cardEdge(0, after: false, collection, grid))
        let place = propose(grid, collection, first, item: 0, operation: .before)
        await check("a team's session between cards takes a place there", place.0 == .move && grid.grid?.lineView.line != nil)
        titles = []
        choice = "Cancel"
        await endUndoGroup(model)
        _ = grid.collectionView(collection, acceptDrop: first, indexPath: IndexPath(item: 0, section: 0), dropOperation: .on)
        grid.dragEnded()
        await ui.until { model.gridRoots.first?.id == worker }
        await check("let go there, it's first on the grid, no menu asked, one Undo step", model.gridRoots.first?.id == worker && titles.isEmpty
                    && model.undoManager?.undoActionName == "Make Root",
                    "\(model.undoManager?.undoActionName ?? "-"), first \(model.gridRoots.first?.name ?? "-"), parent \(model.session(worker)?.parent?.prefix(8) ?? "none"), titles \(titles)")
        await endUndoGroup(model)
        model.undoManager?.undo()
        await ui.until { model.session(worker)?.parent == lead }
        await check("and Undo puts it back under its leader, the grid as it was", model.session(worker)?.parent == lead && grid.ids == roots,
                    "\(grid.ids.map { $0.prefix(4) })")
        grid.dragEnded()
    }
}
