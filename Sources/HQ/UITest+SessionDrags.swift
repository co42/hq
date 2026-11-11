import AppKit
import HQKit
import SwiftUI

/// Sessions drag and move as tasks do (T-437, T-438): over a card's or a row's middle, its ring and the drop menu; over an
/// edge or a gap, the line, and it lands there at once, one Undo; a cancelled drag leaves all as it was; ⇧ with the arrows
/// and the Session menu's moves; a drag image is the card alone, and a ring shows whole on every side.
extension UITest {
    static func sessionDrags(_ model: AppModel, _ ui: Driver) async {
        guard let collection = ui.find(SessionGrid.CardCollection.self), let grid = collection.delegate as? SessionGrid.Coordinator,
              let lead = model.gridRoots.first(where: { model.team(of: $0.id).count == 4 })?.id else {
            return await check("the seed's team on the grid", false)
        }
        let picked = SessionGrid.pickDropChoice
        await gridLines(model, ui, collection, grid, lead)
        await scenario(model, ui)
        await rowLines(model, ui, collection, grid, lead)
        await scenario(model, ui)
        await dropMenus(model, ui, collection, grid, lead)
        await scenario(model, ui)
        await moveKeys(model, ui, collection, grid, lead)
        await scenario(model, ui)
        await toggleClicks(model, ui, collection, grid, lead)
        await scenario(model, ui)
        await wholeRings(model, ui, collection, grid, lead)
        SessionGrid.pickDropChoice = picked
    }

    /// A point on a card's edge, in window coordinates: its leading or far edge as the grid reads it (DESIGN.md §5).
    static func cardEdge(_ index: Int, after: Bool, _ collection: NSCollectionView, _ grid: SessionGrid.Coordinator) -> NSPoint {
        let frame = SessionGrid.frame(of: index, width: collection.bounds.width)
        let point = grid.columns > 1 ? NSPoint(x: after ? frame.maxX - Space.xs : frame.minX + Space.xs, y: frame.midY)
            : NSPoint(x: frame.midX, y: after ? frame.maxY - Space.xs : frame.minY + Space.xs)
        return collection.convert(point, to: nil)
    }

    /// The drop menu's titles once it asks, and the item picked: the first that starts with `choice`, none for nil.
    private final class DropPicks {
        var titles: [String] = []
        var choice: String?

        init(_ choice: String? = nil) {
            self.choice = choice
            SessionGrid.pickDropChoice = { [self] menu in
                titles = menu.items.map(\.title)
                return self.choice.flatMap { choice in menu.items.first { $0.title.hasPrefix(choice) } }
            }
        }
    }

    private static func undoName(_ model: AppModel) -> String { model.undoManager?.undoActionName ?? "-" }

    // MARK: Lines

    /// A card over another's far edge: the line where it lands, no ring, the cards still; let go, it lands there at once,
    /// selected, one Undo. A cancelled drag leaves all as it was. A team's session between cards: top-level there.
    private static func gridLines(_ model: AppModel, _ ui: Driver, _ collection: SessionGrid.CardCollection, _ grid: SessionGrid.Coordinator,
                                  _ lead: String) async {
        let roots = grid.ids
        guard roots.count > 3 else { return await check("four cards on the grid", false) }
        let picks = DropPicks()
        let moving = roots[0]
        await endUndoGroup(model)
        let drag = FakeDrag(session: moving, source: collection, at: cardEdge(2, after: true, collection, grid))
        let proposed = propose(grid, collection, drag, item: 2, operation: .before)
        let after: Bool = if case .place(let place, _)? = grid.drop { place.parent == nil && place.after == roots[2] } else { false }
        await check("a card over another's far edge: the line where it lands, right after it, and no card takes the ring",
                    after && grid.dropTarget == nil && grid.grid?.lineView.line != nil, String(describing: grid.drop))
        await check("the cards hold still: AppKit is told it drops onto a card, never into a gap", proposed.0 == .move && proposed.1 == .on, "\(proposed)")
        let expected = Array(roots[1...2]) + [moving] + Array(roots[3...])
        _ = grid.collectionView(collection, acceptDrop: drag, indexPath: IndexPath(item: proposed.2, section: 0), dropOperation: .on)
        record("let go, it takes that place at once, where the line was", grid.ids == expected, "\(grid.ids.map { $0.prefix(4) })")
        grid.dragEnded()
        await check("it's there, selected, no menu asked, one Undo step", model.gridRoots.map(\.id) == expected && model.selectedSession == moving
                    && picks.titles.isEmpty && undoName(model) == "Move Session", "\(undoName(model)), \(picks.titles)")
        await check("the line goes with the drag", grid.grid?.lineView.line == nil && grid.drop == nil)
        await endUndoGroup(model)
        model.undoManager?.undo()
        await ui.until { grid.ids == roots }
        await check("Undo puts it back", model.gridRoots.map(\.id) == roots && grid.ids == roots)

        // Escape ends the drag where it is: AppKit tells the grid the drag left it.
        let held = FakeDrag(session: moving, source: collection, at: cardEdge(2, after: true, collection, grid))
        _ = propose(grid, collection, held, item: 2, operation: .before)
        collection.draggingExited(held)
        await ui.settle()
        await check("a cancelled drag leaves no line or ring, every card where it was", grid.grid?.lineView.line == nil && grid.dropTarget == nil
                    && grid.ids == roots && model.gridRoots.map(\.id) == roots)

        // A team's session let go after the first card: top-level right there.
        model.openTeam = lead
        guard let open = await openCard(ui), let worker = model.team(of: lead).last?.session.id, let parent = model.session(worker)?.parent else {
            return await check("the open team", false)
        }
        await endUndoGroup(model)
        let row = FakeDrag(session: worker, source: open, at: cardEdge(0, after: true, collection, grid))
        _ = propose(grid, collection, row, item: 0, operation: .before)
        _ = grid.collectionView(collection, acceptDrop: row, indexPath: IndexPath(item: 0, section: 0), dropOperation: .on)
        grid.dragEnded()
        await check("a team's session let go between cards is top-level there, no menu asked, one Undo step (Make Root)",
                    model.session(worker)?.parent == nil && model.gridRoots.map(\.id).firstIndex(of: worker) == 1 && picks.titles.isEmpty
                    && undoName(model) == "Make Root", "\(undoName(model)), \(model.gridRoots.map { $0.name.prefix(8) })")
        await endUndoGroup(model)
        model.undoManager?.undo()
        await check("Undo puts it back in its team", model.session(worker)?.parent == parent && model.gridRoots.map(\.id) == roots)
    }

    /// Over an open team's rows: a row's top shows the line at its level and lands there under its session's parent; the
    /// open card's own bottom edge, first under it; a row moves among its siblings the same way.
    private static func rowLines(_ model: AppModel, _ ui: Driver, _ collection: SessionGrid.CardCollection, _ grid: SessionGrid.Coordinator,
                                 _ lead: String) async {
        model.openTeam = lead
        let roots = grid.ids
        let rows = model.team(of: lead).map(\.session.id)
        guard let open = await openCard(ui), rows.count == 4, model.sessionTree.parent(of: rows[2]) == lead, model.sessionTree.parent(of: rows[3]) == lead,
              let loose = roots.first(where: { $0 != lead && model.session($0)?.isRunning == true && model.team(of: $0).isEmpty }),
              let third = open.rowFrame(rows[2]), let first = open.rowFrame(rows[0]) else {
            return await check("the open team and a loose card", false)
        }
        let picks = DropPicks()
        await endUndoGroup(model)
        let top = FakeDrag(session: loose, source: collection, at: center(NSRect(x: third.midX, y: third.minY + 2, width: 0, height: 0), in: open))
        let operation = open.dropOperation(top)
        let before: Bool = if case .place(let place, _)? = open.drop { place.parent == lead && place.before == rows[2] } else { false }
        await check("a card over a row's top: the line among the rows, at its level, and no ring", operation == .move && before
                    && open.dropOn == nil && open.lineView.line != nil, String(describing: open.drop))
        _ = open.performDragOperation(top)
        grid.dragEnded()
        await check("let go, it lands there under that row's parent, selected, no menu asked, one Undo step (Move Under)",
                    model.team(of: lead).map(\.session.id) == [rows[0], rows[1], loose, rows[2], rows[3]] && model.selectedSession == loose
                    && picks.titles.isEmpty && undoName(model) == "Move Under" && open.lineView.line == nil,
                    "\(undoName(model)), \(model.team(of: lead).map { $0.session.name.prefix(8) })")
        await endUndoGroup(model)
        model.undoManager?.undo()
        await ui.until { model.session(loose)?.parent == nil && grid.ids == roots }
        await check("Undo puts it back on the grid, in its place", model.session(loose)?.parent == nil && model.gridRoots.map(\.id) == roots)

        // The open card's own bottom edge: first under its session.
        model.openTeam = lead
        guard let again = await openCard(ui) else { return }
        let under = FakeDrag(session: loose, source: collection, at: center(NSRect(x: again.bounds.midX, y: Metric.card - 2, width: 0, height: 0), in: again))
        _ = again.dropOperation(under)
        let firstUnder: Bool = if case .place(let place, _)? = again.drop { place.parent == lead && place.before == rows[0] } else { false }
        await check("over the open card's own bottom edge: first under its session", firstUnder, String(describing: again.drop))
        again.draggingExited(under)
        await check("the drag gone, no line stays", again.lineView.line == nil && again.drop == nil)

        // A row over the first row's top: first among its siblings.
        await endUndoGroup(model)
        await ui.settle()
        let last = FakeDrag(session: rows[3], source: again, at: center(NSRect(x: first.midX, y: first.minY + 2, width: 0, height: 0), in: again))
        _ = again.dropOperation(last)
        let lastFirst: Bool = if case .place(let place, _)? = again.drop { place.parent == lead && place.before == rows[0] } else { false }
        await check("a row over the first row's top: the line before it", lastFirst, String(describing: again.drop))
        _ = again.performDragOperation(last)
        grid.dragEnded()
        await check("a row let go over the first row's top goes first among them, one Undo step (Move Session)",
                    model.team(of: lead).map(\.session.id) == [rows[3], rows[0], rows[1], rows[2]] && undoName(model) == "Move Session",
                    "\(undoName(model)), \(model.team(of: lead).map { $0.session.name.prefix(8) })")
        await endUndoGroup(model)
        model.undoManager?.undo()
        await check("Undo puts the rows back", model.team(of: lead).map(\.session.id) == rows)
    }

    // MARK: Drop menus

    /// Over a card's or a row's middle: its ring, and the drop menu, as a task's: Move Under, Move Above, Move Below, Make
    /// Root (when it has a parent), Cancel.
    private static func dropMenus(_ model: AppModel, _ ui: Driver, _ collection: SessionGrid.CardCollection, _ grid: SessionGrid.Coordinator,
                                  _ lead: String) async {
        let roots = grid.ids
        let loose = roots.filter { $0 != lead && model.session($0)?.isRunning == true && model.team(of: $0).isEmpty }
        guard loose.count >= 2, let index = roots.firstIndex(of: loose[1]), let target = card(loose[1], collection, grid) else {
            return await check("two loose cards", false)
        }
        let picks = DropPicks("Move Below")
        await endUndoGroup(model)
        let onto = FakeDrag(session: loose[0], source: collection, at: center(target.bounds, in: target))
        _ = propose(grid, collection, onto, item: index, operation: .on)
        await check("a card over another's middle: that card's ring, no line", grid.dropTarget?.item == index && grid.grid?.lineView.line == nil)
        _ = grid.collectionView(collection, acceptDrop: onto, indexPath: IndexPath(item: index, section: 0), dropOperation: .on)
        grid.dragEnded()
        var expected = roots.filter { $0 != loose[0] }
        expected.insert(loose[0], at: (expected.firstIndex(of: loose[1]) ?? 0) + 1)
        await check("dropped, the menu asks as a task's: Move Under, Move Above, Move Below, Cancel (no Make Root at the top)",
                    ["Move Under “", "Move Above “", "Move Below “", "Cancel"].allSatisfy { title in picks.titles.contains { $0.hasPrefix(title) } }
                    && !picks.titles.contains("Make Root"), picks.titles.joined(separator: " | "))
        await check("Move Below puts it right after that card, one Undo step", model.gridRoots.map(\.id) == expected && undoName(model) == "Move Session",
                    "\(undoName(model)), \(model.gridRoots.map { $0.name.prefix(8) })")
        await endUndoGroup(model)
        model.undoManager?.undo()
        await ui.until { grid.ids == roots }

        // A row over another row's middle: Move Above, among that row's siblings.
        model.openTeam = lead
        let rows = model.team(of: lead).map(\.session.id)
        guard let open = await openCard(ui), rows.count == 4, let third = open.rowFrame(rows[2]) else { return await check("the open team", false) }
        picks.choice = "Move Above"
        await endUndoGroup(model)
        let row = FakeDrag(session: rows[3], source: open, at: center(third, in: open))
        _ = open.dropOperation(row)
        await check("a row over another row's middle: that row's ring, no line", open.dropOn == rows[2] && open.lineView.line == nil)
        _ = open.performDragOperation(row)
        await check("dropped, Make Root is there too for a team's session", picks.titles.contains("Make Root"), picks.titles.joined(separator: " | "))
        await check("Move Above puts it right before that row, one Undo step", model.team(of: lead).map(\.session.id) == [rows[0], rows[1], rows[3], rows[2]]
                    && undoName(model) == "Move Session", "\(undoName(model)), \(model.team(of: lead).map { $0.session.name.prefix(8) })")
        await endUndoGroup(model)
        model.undoManager?.undo()
        await ui.until { model.team(of: lead).map(\.session.id) == rows }

        // Cancel leaves everything as it was.
        picks.choice = "Cancel"
        guard let again = await openCard(ui), let second = again.rowFrame(rows[2]) else { return }
        let cancelled = FakeDrag(session: rows[3], source: again, at: center(second, in: again))
        _ = again.dropOperation(cancelled)
        _ = again.performDragOperation(cancelled)
        await ui.settle()
        await check("Cancel in the drop menu leaves every session where it was", model.team(of: lead).map(\.session.id) == rows && grid.ids == roots
                    && again.dropOn == nil)
    }

    // MARK: Keys

    /// The ⇧ arrows on one column, as a task's keys; on two, a card moves on screen (T-440).
    private static func moveKeys(_ model: AppModel, _ ui: Driver, _ collection: SessionGrid.CardCollection, _ grid: SessionGrid.Coordinator,
                                 _ lead: String) async {
        if !(await onColumns(1, model, ui, grid, { await oneColumnKeys(model, ui, collection, grid, lead) })) {
            skip("⇧ arrows on one column", because: "the window couldn't be made one column wide")
        }
        await scenario(model, ui)
        if !(await onColumns(2, model, ui, grid, { await twoColumnKeys(model, ui, collection, grid, lead) })) {
            skip("⇧ arrows on two columns", because: "the screen isn't wide enough for two columns")
        }
    }

    /// The window as wide as `columns` of cards need while `body` runs, then as it was. False, with nothing run, when the
    /// screen can't hold them.
    private static func onColumns(_ columns: Int, _ model: AppModel, _ ui: Driver, _ grid: SessionGrid.Coordinator, _ body: () async -> Void) async -> Bool {
        let original = ui.window.frame
        guard let screen = ui.window.screen?.visibleFrame else { return false }
        if grid.columns != columns {
            let frame = columns > 1 ? NSRect(x: screen.minX, y: original.minY, width: screen.width, height: original.height)
                : NSRect(x: original.minX, y: original.minY, width: min(original.width, screen.width / 2), height: original.height)
            ui.window.setFrame(frame, display: true)
            await ui.until(2) { grid.columns == columns && model.gridColumns == columns }
        }
        let ran = grid.columns == columns && model.gridColumns == columns
        if ran { await body() }
        if ui.window.frame != original {
            ui.window.setFrame(original, display: true)
            await ui.until(2) { model.gridColumns == grid.columns }
            await ui.settle(0.3)
        }
        return ran
    }

    /// ⇧ and an arrow as the key window takes it: the cards' own keys before the menu bar's. A background run's window is
    /// never key, so the key goes to the window's views the same way.
    private static func shift(_ key: Driver.Key, held: Bool = false, _ ui: Driver) async {
        guard !NSApp.isActive else { return await ui.key(key, .shift, held: held) }
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift, .numericPad, .function], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: ui.window.windowNumber, context: nil, characters: key.characters,
                                        charactersIgnoringModifiers: key.characters, isARepeat: held, keyCode: key.code) {
            _ = ui.window.performKeyEquivalent(with: event)
        }
        await ui.settle(0.05)
    }

    /// The Session menu, brought up to date as when the user opens it.
    private static func sessionMenu() -> NSMenu? {
        guard let menu = NSApp.mainMenu?.items.first(where: { $0.title == "Session" })?.submenu else { return nil }
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.update()
        return menu
    }

    /// The moves the Session menu lacks, by title, with ⇧ and their arrow.
    private static func menuMissing(_ moves: [(String, Int)]) -> [String] {
        let items = sessionMenu()?.items ?? []
        return moves.filter { title, key in
            !items.contains { $0.title == title && $0.keyEquivalent == String(UnicodeScalar(UInt16(key))!) && $0.keyEquivalentModifierMask == .shift }
        }.map(\.0)
    }

    /// On one column, ⇧↑ ⇧↓ ⇧→ ⇧← on the selected card or row act as a task's keys; a held key stays among siblings; the
    /// Session menu has them.
    private static func oneColumnKeys(_ model: AppModel, _ ui: Driver, _ collection: SessionGrid.CardCollection, _ grid: SessionGrid.Coordinator,
                                      _ lead: String) async {
        let roots = grid.ids
        guard let index = roots.indices.first(where: { $0 > 0 && $0 < roots.count - 1 && model.team(of: roots[$0]).isEmpty
                                                    && model.session(roots[$0])?.isRunning == true && model.session(roots[$0 - 1])?.isRunning == true
                                                    && model.team(of: roots[$0 - 1]).isEmpty }) else {
            return await check("a loose card after a running one", false)
        }
        let id = roots[index], previous = roots[index - 1]
        ui.window.makeFirstResponder(collection)
        grid.select(id)
        await endUndoGroup(model)
        await shift(.down, ui)
        await check("⇧↓ moves the selected card one place later, still selected, one Undo step (Move Down)",
                    model.gridRoots.map(\.id).firstIndex(of: id) == index + 1 && model.selectedSession == id && undoName(model) == "Move Down",
                    "\(undoName(model)), at \(model.gridRoots.map(\.id).firstIndex(of: id) ?? -1)")
        await endUndoGroup(model)
        await shift(.up, ui)
        await check("⇧↑ moves it back (Move Up)", model.gridRoots.map(\.id) == roots && undoName(model) == "Move Up")
        await endUndoGroup(model)
        await shift(.right, held: true, ui)
        await ui.settle()
        await check("a held ⇧→ does nothing more", model.session(id)?.parent == nil)
        await shift(.right, ui)
        await check("⇧→ puts it under the card before it, last of its sessions, that team open, it selected (Indent)",
                    model.session(id)?.parent == previous && model.team(of: previous).last?.session.id == id && model.openTeam == previous
                    && model.selectedSession == id && undoName(model) == "Indent", "\(undoName(model)), open \(model.openTeam?.prefix(4) ?? "none")")
        await endUndoGroup(model)
        await shift(.left, ui)
        await check("⇧← takes it one level out, right after that card (Outdent)", model.session(id)?.parent == nil
                    && model.gridRoots.map(\.id) == roots && undoName(model) == "Outdent", "\(undoName(model)), \(model.gridRoots.map { $0.name.prefix(8) })")

        // In a team: a held ⇧↑ on its first row stays first; pressed, it leaves the team, right above its card.
        let rows = model.team(of: lead).map(\.session.id)
        grid.select(rows[0])
        await ui.until { model.openTeam == lead }
        await shift(.up, held: true, ui)
        await ui.settle()
        await check("a held ⇧↑ on a team's first row keeps it there", model.session(rows[0])?.parent == lead && model.team(of: lead).first?.session.id == rows[0])
        await endUndoGroup(model)
        await shift(.up, ui)
        func order() -> [String] { model.gridRoots.map(\.id) }
        await check("pressed, ⇧↑ takes it out of the team, right above its card (Move Up)", model.session(rows[0])?.parent == nil
                    && order().firstIndex(of: rows[0]).map { order().indices.contains($0 + 1) && order()[$0 + 1] == lead } == true && undoName(model) == "Move Up",
                    "\(undoName(model)), \(order().map { $0.prefix(4) })")
        await endUndoGroup(model)
        model.undoManager?.undo()
        await ui.until { model.session(rows[0])?.parent == lead }

        // The Session menu: the moves with their keys while the cards have the keyboard, and acting on the selected card.
        ui.window.makeFirstResponder(collection)
        grid.select(id)
        let moves = [("Move Up", NSUpArrowFunctionKey), ("Move Down", NSDownArrowFunctionKey), ("Indent", NSRightArrowFunctionKey), ("Outdent", NSLeftArrowFunctionKey)]
        await check("the Session menu has Move Up ⇧↑, Move Down ⇧↓, Indent ⇧→ and Outdent ⇧← while the cards have the keyboard",
                    menuMissing(moves).isEmpty, menuMissing(moves).joined(separator: ", "))
        await endUndoGroup(model)
        if let menu = sessionMenu(), let down = menu.items.firstIndex(where: { $0.title == "Move Down" }) { menu.performActionForItem(at: down) }
        await check("its Move Down moves the selected card", model.gridRoots.map(\.id).firstIndex(of: id) == index + 1 && undoName(model) == "Move Down")
    }

    /// On two columns a card's ⇧ arrows move it on screen and never put it under another; the menu says Move Right and Move
    /// Left; a team's rows keep the task keys (T-440).
    private static func twoColumnKeys(_ model: AppModel, _ ui: Driver, _ collection: SessionGrid.CardCollection, _ grid: SessionGrid.Coordinator,
                                      _ lead: String) async {
        let roots = grid.ids
        let rows = model.team(of: lead).map(\.session.id)
        guard let index = roots.indices.first(where: { $0 % 2 == 0 && $0 + 2 < roots.count && model.team(of: roots[$0]).isEmpty }), rows.count == 4,
              model.sessionTree.parent(of: rows[2]) == lead, model.sessionTree.parent(of: rows[0]) == lead else {
            return await check("a card in the left column with cards right of and below it, and the seed's team", false)
        }
        let id = roots[index]
        func at() -> Int { model.gridRoots.map(\.id).firstIndex(of: id) ?? -1 }
        ui.window.makeFirstResponder(collection)
        grid.select(id)
        await endUndoGroup(model)
        await shift(.left, ui)
        await ui.settle()
        await check("on two columns, ⇧← on a card in the left column does nothing", model.gridRoots.map(\.id) == roots && model.session(id)?.parent == nil)
        await shift(.right, ui)
        await check("⇧→ moves it one place right in its row, never under another (Move Right)", at() == index + 1 && model.session(id)?.parent == nil
                    && model.selectedSession == id && undoName(model) == "Move Right", "\(undoName(model)), at \(at()), parent \(model.session(id)?.parent?.prefix(4) ?? "none")")
        await endUndoGroup(model)
        await shift(.right, ui)
        await ui.settle()
        await check("⇧→ in the right column does nothing: it never wraps to the next row", at() == index + 1 && model.session(id)?.parent == nil)
        await shift(.left, ui)
        await check("⇧← moves it back left, not out of anything (Move Left)", model.gridRoots.map(\.id) == roots && undoName(model) == "Move Left")
        await endUndoGroup(model)
        await shift(.down, ui)
        await check("⇧↓ moves it to the place of the card below it (Move Down)", at() == index + 2 && model.session(id)?.parent == nil
                    && undoName(model) == "Move Down", "\(undoName(model)), at \(at())")
        await endUndoGroup(model)
        await shift(.up, ui)
        await check("⇧↑ moves it back up (Move Up)", model.gridRoots.map(\.id) == roots && undoName(model) == "Move Up")
        let moves = [("Move Right", NSRightArrowFunctionKey), ("Move Left", NSLeftArrowFunctionKey)]
        await check("the Session menu says what ⇧→ and ⇧← do to a card on two columns: Move Right, Move Left",
                    menuMissing(moves).isEmpty && !(sessionMenu()?.items.contains { $0.title == "Indent" || $0.title == "Outdent" } ?? true),
                    menuMissing(moves).joined(separator: ", "))

        // A team's rows are a list at any width: ⇧→ puts a row under the row before it.
        grid.select(rows[2])
        await ui.until { model.openTeam == lead }
        await endUndoGroup(model)
        await shift(.right, ui)
        await check("an open team's row keeps the task keys on two columns: ⇧→ puts it under the row before (Indent)",
                    model.session(rows[2])?.parent == rows[0] && undoName(model) == "Indent", "\(undoName(model))")
        await check("and the menu says Indent and Outdent for a row", menuMissing([("Indent", NSRightArrowFunctionKey), ("Outdent", NSLeftArrowFunctionKey)]).isEmpty)
    }

    /// A team's toggle takes the next click at once: a double-click's second click hides what the first showed (T-441).
    private static func toggleClicks(_ model: AppModel, _ ui: Driver, _ collection: SessionGrid.CardCollection, _ grid: SessionGrid.Coordinator,
                                     _ lead: String) async {
        guard let leadCard = card(lead, collection, grid) else { return await check("the team's card", false) }
        await ui.until { leadCard.tray != .zero }
        guard let content = leadCard.content else { return await check("the team's card content", false) }
        let toggle = center(SessionCard.traySpots(content, in: leadCard.tray).toggle, in: leadCard)
        await click(toggle, count: 1, ui, collection)
        await check("a click on a team's toggle shows its sessions", model.openTeam == lead, model.openTeam ?? "none")
        await click(toggle, count: 2, ui, collection)
        await check("the next click, a double-click's second, hides them at once", model.openTeam == nil, model.openTeam ?? "none")
        await click(toggle, count: 3, ui, collection)
        await check("and the one after shows them again", model.openTeam == lead, model.openTeam ?? "none")
    }

    /// A press and release on the view the window would hand them to: the open team's card, else the grid under a card.
    private static func click(_ point: NSPoint, count: Int, _ ui: Driver, _ collection: NSCollectionView) async {
        guard let hit = ui.hitView(point), let down = ui.mouseDown(point, clicks: count),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: ui.window.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 0) else { return }
        let view: NSView = hit is TeamCardView ? hit : collection
        // A collection view tracks the press up to its release: the release waits in the queue.
        NSApp.postEvent(up, atStart: false)
        view.mouseDown(with: down)
        view.mouseUp(with: up)
        await ui.settle(0.2)
    }

    // MARK: Rings and drag images

    /// The ring shows whole on every side, on a card under the pointer and on a row (T-438); a drag image is the card or the
    /// row alone, at its own size.
    private static func wholeRings(_ model: AppModel, _ ui: Driver, _ collection: SessionGrid.CardCollection, _ grid: SessionGrid.Coordinator,
                                   _ lead: String) async {
        let roots = grid.ids
        guard let id = roots.first(where: { $0 != lead && model.session($0)?.isRunning == true }), let session = model.session(id),
              let index = roots.firstIndex(of: id), let view = card(id, collection, grid), let page = grid.grid else {
            return await check("a running card", false)
        }
        let size = view.frame.size
        // Selected under the pointer, as when a drag starts on it, then dropped onto: drawn alone at its size, as a drag image is.
        var content = model.cardContent(session, open: nil, selected: id, width: size.width)
        var sides: [String] = []
        for dropTarget in [false, true] {
            content.dropTarget = dropTarget ? id : nil
            let hovered = SessionGrid.image(of: SessionCard(content, now: model.now).environment(\.forcedPartState, .hover), size: size, in: page)
            sides += ringMissing(hovered, NSRect(origin: .zero, size: size), page.effectiveAppearance).map { "\($0)\(dropTarget ? " (drop)" : "")" }
        }
        await check("a card's ring shows whole on every side under the pointer: the card never grows past its edges", sides.isEmpty,
                    "missing on its \(sides.joined(separator: ", "))")
        await check("a card sits inside the grid on every side", collection.bounds.contains(view.frame), "\(view.frame) in \(collection.bounds)")
        let image = grid.dragImage(of: index, size: size)
        await check("a card's drag image is the card alone: its size, drawn, no ring", image?.size == size && image.map(isDrawn) == true
                    && image.map { ringMissing($0, NSRect(origin: .zero, size: size), page.effectiveAppearance).count == 4 } == true,
                    "\(String(describing: image?.size)) for \(size)")

        // An open team's row it drops onto: the ring whole, inside the card; its drag image the row alone.
        model.openTeam = lead
        guard let open = await openCard(ui), let row = model.team(of: lead).first?.session.id, let frame = open.rowFrame(row),
              let loose = roots.first(where: { $0 != lead && $0 != row && model.session($0)?.isRunning == true && model.team(of: $0).isEmpty }) else {
            return await check("the open team", false)
        }
        _ = open.dropOperation(FakeDrag(session: loose, source: collection, at: center(frame, in: open)))
        await ui.settle()
        var rowSides = ["all"]
        if let bitmap = open.bitmapImageRepForCachingDisplay(in: open.bounds) {
            open.cacheDisplay(in: open.bounds, to: bitmap)
            let shot = NSImage(size: open.bounds.size)
            shot.addRepresentation(bitmap)
            rowSides = ringMissing(shot, frame, open.effectiveAppearance)
        }
        await check("a row's drop ring shows whole on every side, inside its card", open.dropOn == row && rowSides.isEmpty && open.bounds.contains(frame),
                    "missing on its \(rowSides.joined(separator: ", "))")
        open.draggingExited(nil)
        let rowImage = open.dragImage(of: row)
        await check("a row's drag image is the row alone, at its size, drawn", rowImage?.size == frame.size && rowImage.map(isDrawn) == true)
    }

    /// The sides of `rect` (points, from the top left) where the accent doesn't show within 3 pt in from the side's middle.
    static func ringMissing(_ image: NSImage, _ rect: NSRect, _ appearance: NSAppearance) -> [String] {
        guard let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first, image.size.width > 0 else { return ["all"] }
        let scale = CGFloat(bitmap.pixelsWide) / image.size.width
        var accent = NSColor.black
        appearance.performAsCurrentDrawingAppearance { accent = Ink.accentNS.usingColorSpace(.sRGB) ?? .black }
        func accentAt(_ x: CGFloat, _ y: CGFloat) -> Bool {
            guard let color = bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB) else { return false }
            return abs(color.redComponent - accent.redComponent) + abs(color.greenComponent - accent.greenComponent)
                + abs(color.blueComponent - accent.blueComponent) < 0.5
        }
        let pixel = 1 / scale
        let steps = Array(stride(from: 0, through: 3, by: pixel))
        var missing: [String] = []
        if !steps.contains(where: { accentAt(rect.minX + $0, rect.midY) }) { missing.append("left") }
        if !steps.contains(where: { accentAt(rect.maxX - pixel - $0, rect.midY) }) { missing.append("right") }
        if !steps.contains(where: { accentAt(rect.midX, rect.minY + $0) }) { missing.append("top") }
        if !steps.contains(where: { accentAt(rect.midX, rect.maxY - pixel - $0) }) { missing.append("bottom") }
        return missing
    }

    /// An image with something drawn in it: more than a few colors.
    static func isDrawn(_ image: NSImage) -> Bool {
        guard let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first else { return false }
        var seen = Set<Int>()
        for x in stride(from: 0, to: bitmap.pixelsWide, by: max(bitmap.pixelsWide / 60, 1)) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: max(bitmap.pixelsHigh / 12, 1)) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                seen.insert(Int(color.redComponent * 15) << 8 | Int(color.greenComponent * 15) << 4 | Int(color.blueComponent * 15))
            }
        }
        return seen.count > 3
    }
}
