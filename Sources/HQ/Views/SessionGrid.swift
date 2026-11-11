import AppKit
import HQKit
import SwiftUI

/// The Sessions section's cards (DESIGN.md §5): the grid of top-level sessions, and the one team open, its card floating
/// over the cards under it and the next section, so nothing on the page moves.
struct SessionCards: View {
    let width: CGFloat
    @Environment(AppModel.self) private var model
    @State private var link = GridLink()

    var body: some View {
        let roots = model.shownRoots
        SessionGrid(sessions: roots, width: width, link: link)
            .overlay(alignment: .topLeading) {
                if let open = model.openTeam, let index = roots.firstIndex(where: { $0.id == open }) {
                    let content = model.cardContent(roots[index], open: open, selected: model.selectedSession, width: SessionGrid.itemWidth(width))
                    if content.open {
                        let frame = SessionGrid.frame(of: index, width: width)
                        OpenTeam(content: content, now: model.now, link: link)
                            .frame(width: frame.width, height: SessionCard.openHeight(rows: content.team.count))
                            // Where it ends on the page, which makes room past its end for it.
                            .background { GeometryReader { Color.clear.preference(key: OpenTeamBottom.self, value: $0.frame(in: .named(PageEnd.space)).maxY) } }
                            .padding(.leading, frame.minX)
                            .padding(.top, frame.minY)
                    }
                }
            }
    }
}

/// The open team card's bottom in the page's content; 0 while no team is open.
struct OpenTeamBottom: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// What the grid and its open team share: the keyboard, the drop menu, the rows to scroll to.
final class GridLink {
    weak var coordinator: SessionGrid.Coordinator?
    weak var team: TeamCardView?
}

/// What a dragged session would do where it is (DESIGN.md §5): drop onto a session, whose ring shows and whose menu asks;
/// or land at a place, which a line shows.
enum SessionDrop: Equatable {
    case onto(String)
    case place(SessionPlace, line: DropLine)
}

/// The session cards (DESIGN.md §5): an `NSCollectionView` with no scroll view of its own, inside the page's. Cards reorder
/// by drag, an accent bar where one lands; a session dropped on a card asks Move Under or Make Root; a task dropped on a card
/// links it.
struct SessionGrid: NSViewRepresentable {
    let sessions: [SessionItem]
    let width: CGFloat
    var link = GridLink()
    @Environment(AppModel.self) private var model

    /// Two columns from 1060 pt of content, one below (2026-11-10).
    static func columns(for width: CGFloat) -> Int { width >= Metric.twoColumns ? 2 : 1 }

    static func itemWidth(_ width: CGFloat) -> CGFloat {
        let columns = CGFloat(columns(for: width))
        return max(((width - Metric.cardGap * (columns - 1)) / columns).rounded(.down), 1)
    }

    /// Where the card at `index` sits, as the flow layout places it: a full row's last card against the right edge.
    static func frame(of index: Int, width: CGFloat) -> CGRect {
        let columns = columns(for: width), item = itemWidth(width)
        let column = index % columns, row = index / columns
        let x = columns > 1 && column == columns - 1 ? width - item : CGFloat(column) * (item + Metric.cardGap)
        return CGRect(x: x, y: CGFloat(row) * (Metric.card + Metric.cardGap), width: item, height: Metric.card)
    }

    static func height(count: Int, width: CGFloat) -> CGFloat {
        let rows = (count + columns(for: width) - 1) / columns(for: width)
        return CGFloat(rows) * Metric.card + CGFloat(max(rows - 1, 0)) * Metric.cardGap
    }

    /// The UI test picks from the drop menu instead of opening it.
    static var pickDropChoice: ((NSMenu) -> NSMenuItem?)?

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> GridView {
        let grid = GridView()
        grid.coordinator = context.coordinator
        context.coordinator.grid = grid
        context.coordinator.link = link
        link.coordinator = context.coordinator
        context.coordinator.apply(sessions, width: width, now: model.now, selected: model.selectedSession, open: model.openTeam)
        return grid
    }

    func updateNSView(_ grid: GridView, context: Context) {
        context.coordinator.model = model
        context.coordinator.link = link
        link.coordinator = context.coordinator
        // Blinking follows what the user acknowledged.
        _ = model.seen
        context.coordinator.apply(sessions, width: width, now: model.now, selected: model.selectedSession, open: model.openTeam)
        if model.sectionFocus == .sessions {
            model.sectionFocus = nil
            DispatchQueue.main.async { context.coordinator.takeKeyboard() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GridView, context: Context) -> CGSize? {
        CGSize(width: width, height: Self.height(count: sessions.count, width: width))
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var model: AppModel
        weak var grid: GridView?
        weak var link: GridLink?
        /// The cards: top-level sessions, in their order.
        private(set) var ids: [String] = []
        private var contents: [String: CardContent] = [:]
        private var now = Date.now
        private var width: CGFloat = 0
        /// The card a dragged task or session hovers.
        private(set) var dropTarget: IndexPath?
        /// What a dragged session would do where it is on the grid: its ring, or its line.
        private(set) var drop: SessionDrop?
        /// A session landed where it was let go: the cards it moved take their places at once, nothing slides.
        private var landing = false
        /// A drag from or over the grid, since then: the cards hold still until it ends, so AppKit's indexes stay true.
        private(set) var heldSince: Date?
        /// The last cards asked for, shown once a drag ends.
        private var latest: (sessions: [SessionItem], width: CGFloat, selected: String?, open: String?)?

        var columns: Int { SessionGrid.columns(for: width) }

        init(model: AppModel) {
            self.model = model
        }

        /// New or removed cards reload; a change inside cards only redraws them. Under a drag, no card comes or goes.
        func apply(_ sessions: [SessionItem], width: CGFloat, now: Date, selected: String?, open: String?) {
            guard let grid else { return }
            self.now = now
            latest = (sessions, width, selected, open)
            let newIDs = sessions.map(\.id)
            // A drag whose end never came lets the cards go 3 s after the button is up.
            if let since = heldSince, Date.now.timeIntervalSince(since) > 3, !OutlineCoordinator.buttonDown() {
                AppLog.write("grid: a drag never ended; cards move again", to: "clicks.log")
                heldSince = nil
            }
            let tree = model.sessionTree
            let item = SessionGrid.itemWidth(width)
            let built = Dictionary(sessions.map { ($0.id, model.cardContent($0, tree: tree, open: open, selected: selected, width: item)) },
                                   uniquingKeysWith: { first, _ in first })
            reveal(selected, among: newIDs, tree: tree, open: open)
            if heldSince != nil, newIDs != ids {
                for (id, content) in built where contents[id] != nil { contents[id] = content }
                refreshVisible()
                return
            }
            contents = built
            if width != self.width {
                self.width = width
                grid.layout(width: width)
                // The menu's moves follow the columns, after SwiftUI's update.
                let columns = self.columns
                DispatchQueue.main.async { [weak self] in if self?.model.gridColumns != columns { self?.model.gridColumns = columns } }
            }
            if newIDs != ids {
                let old = ids
                let oldSet = Set(old), newSet = Set(newIDs)
                ids = newIDs
                let removed = Set(old.indices.filter { !newSet.contains(old[$0]) }.map { IndexPath(item: $0, section: 0) })
                let inserted = Set(newIDs.indices.filter { !oldSet.contains(newIDs[$0]) }.map { IndexPath(item: $0, section: 0) })
                // A few cards that join or leave, the others keeping their order: the gap opens or closes. Anything else, or
                // no motion, reloads: the animator's zero-length fades left cards at 0%, never removed or shown (2026-11-11).
                if !Motion.still, !landing, removed.count + inserted.count <= 6, old.filter(newSet.contains) == newIDs.filter(oldSet.contains) {
                    Motion.appKit {
                        grid.collection.animator().performBatchUpdates {
                            grid.collection.deleteItems(at: removed)
                            grid.collection.insertItems(at: inserted)
                        } completionHandler: { [weak grid] _ in grid?.settleCards() }
                    }
                } else {
                    grid.collection.reloadData()
                    grid.settleCards()
                }
            }
            landing = false
            refreshVisible()
            let wanted: Set<IndexPath> = selected.flatMap { ids.firstIndex(of: $0) }.map { [IndexPath(item: $0, section: 0)] } ?? []
            if grid.collection.selectionIndexPaths != wanted {
                grid.collection.selectionIndexPaths = wanted
                refreshVisible()
            }
        }

        /// A session of a folded team selected (Tab back to it, a drop, a click on it elsewhere in HQ): its team opens.
        private func reveal(_ selected: String?, among cards: [String], tree: SessionTree, open: String?) {
            guard let selected, !cards.contains(selected), case let root = tree.root(of: selected), root != selected, cards.contains(root), open != root else { return }
            DispatchQueue.main.async { [weak self] in
                guard let model = self?.model, model.selectedSession == selected else { return }
                model.openTeam = root
            }
        }

        private func refreshVisible() {
            guard let grid else { return }
            for case let item as CardItem in grid.collection.visibleItems() { refresh(item) }
        }

        private func refresh(_ item: CardItem) {
            guard let path = grid?.collection.indexPath(for: item), ids.indices.contains(path.item),
                  var content = contents[ids[path.item]] else { return }
            if dropTarget == path { content.dropTarget = content.session.id }
            item.show(content, now: now, model: model)
        }

        /// A card's session, or a row of the open team: what the keys reach.
        private func reaches(_ id: String) -> Bool {
            ids.contains(id) || (model.openTeam.map { open in ids.contains(open) && model.team(of: open).contains { $0.session.id == id } } ?? false)
        }

        // MARK: Data

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { ids.count }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: CardItem.id, for: indexPath)
            if let card = item as? CardItem, var content = contents[ids[indexPath.item]] {
                if dropTarget == indexPath { content.dropTarget = content.session.id }
                card.show(content, now: now, model: model)
            }
            return item
        }

        /// AppKit's gap between cards: never shown, a session's drop is always onto a card (its line shows where it lands).
        func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                            at indexPath: IndexPath) -> NSView {
            collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: NoGap.id, for: indexPath)
        }

        // MARK: Clicks and keys

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            guard let path = indexPaths.first, ids.indices.contains(path.item) else { return }
            select(ids[path.item], scroll: false)
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            refreshVisible()
        }

        /// A card or an open team's row selected; a selection that leaves the open team folds it.
        func select(_ id: String, scroll: Bool = true) {
            if let open = model.openTeam, model.sessionTree.root(of: id) != open { model.foldTeam() }
            model.selectedSession = id
            model.selectSection(.sessions)
            model.acknowledge(id)
            if scroll { scrollToVisible(id) }
            refreshVisible()
        }

        /// The page scrolls, not the grid: it has no scroll view of its own.
        private func scrollToVisible(_ id: String) {
            if let index = ids.firstIndex(of: id), let card = grid?.collection.item(at: IndexPath(item: index, section: 0))?.view {
                card.scrollToVisible(card.bounds)
            } else {
                link?.team?.scrollToVisible(row: id)
            }
        }

        /// Tab brought the keyboard here: the selected card or row, else the one selected when Tab left, else the first.
        func takeKeyboard() {
            guard let collection = grid?.collection, !ids.isEmpty else { return }
            let tree = model.sessionTree
            let id = [model.selectedSession, model.parkedItems[.sessions]].compactMap { $0 }.first { ids.contains(tree.root(of: $0)) } ?? ids[0]
            collection.window?.makeFirstResponder(collection)
            select(id)
        }

        /// A click on the open team's card: the keys go to the grid.
        func takeKeys() {
            guard let collection = grid?.collection else { return }
            collection.window?.makeFirstResponder(collection)
        }

        /// A double-click outside the face shows the session.
        func doubleClicked(at path: IndexPath) {
            guard ids.indices.contains(path.item) else { return }
            model.open(.session(ids[path.item]))
        }

        /// The arrows walk the cards, ↓ an open team's rows first; ⌘↓ ⌘↑ show and hide the selected team's sessions; Escape
        /// folds it; Return opens the selected session in Ghostty, Space shows its details (DESIGN.md §18).
        func key(_ event: NSEvent) -> Bool {
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if event.keyCode == 48, flags.subtracting(.shift).isEmpty {
                // The card unselects, kept aside by the model for when Tab comes back.
                model.moveSection(from: .sessions, by: flags.contains(.shift) ? -1 : 1)
                return true
            }
            switch (event.keyCode, flags) {
            case (53, []):
                guard model.openTeam != nil else { return false }
                model.foldTeam()
                return true
            case (125, [.command]), (126, [.command]):
                guard let id = model.selectedSession, reaches(id) else { return false }
                let root = model.sessionTree.root(of: id)
                if event.keyCode == 125 {
                    if model.openTeam != root { model.toggleTeam(root) }
                } else if model.openTeam == root {
                    model.foldTeam()
                }
                return true
            case (123...126, [.shift]):
                guard let id = model.selectedSession, reaches(id) else { return false }
                move(id, event.keyCode, held: event.isARepeat)
                return true
            case (123...126, []):
                walk(event.keyCode)
                return true
            default: break
            }
            guard let id = model.selectedSession, reaches(id), flags.isEmpty else { return false }
            switch event.keyCode {
            case 36, 76: model.open(id)
            case 49: model.open(.session(id))
            default: return false
            }
            return true
        }

        /// ⇧↑ ⇧↓ move a session among its siblings, ⇧→ under the previous one, ⇧← one level out, as a task's keys do; a held
        /// key moves among siblings only; a card on two columns moves on screen. It stays selected, its team open (DESIGN.md §5).
        func move(_ id: String, _ code: UInt16, held: Bool = false) {
            let move: SessionMove = switch code {
            case 126: .up
            case 125: .down
            case 124: .right
            default: .left
            }
            model.move(session: id, move, held: held)
            select(id)
        }

        /// ↓ on an open team walks its rows, and from its last row goes to the card below; the other arrows walk the cards.
        private func walk(_ code: UInt16) {
            guard !ids.isEmpty else { return }
            guard let current = model.selectedSession, reaches(current) else { return select(ids[0]) }
            let tree = model.sessionTree
            let root = tree.root(of: current)
            guard let index = ids.firstIndex(of: root) else { return select(ids[0]) }
            let rows = model.openTeam == root ? model.team(of: root, in: tree).map(\.session.id) : []
            let row = current == root ? -1 : rows.firstIndex(of: current) ?? -1
            func card(_ offset: Int) -> String { ids.indices.contains(index + offset) ? ids[index + offset] : current }
            let next = switch code {
            case 125: !rows.isEmpty && row < rows.count - 1 ? rows[row + 1] : card(columns)
            case 126: row > 0 ? rows[row - 1] : row == 0 ? root : card(-columns)
            case 124: card(1)
            default: card(-1)
            }
            select(next)
        }

        func menu(at point: NSPoint) -> NSMenu? {
            guard let grid, let path = grid.collection.indexPathForItem(at: point) else { return nil }
            return menu(for: path)
        }

        func menu(for path: IndexPath) -> NSMenu? {
            guard ids.indices.contains(path.item), let session = contents[ids[path.item]]?.session else { return nil }
            return NSHostingMenu(rootView: SessionMenu(session: session).environment(model))
        }

        /// A card's face focuses its session's terminal, or offers to resume it; the card's menu is a right-click.
        func faceClicked(at path: IndexPath) {
            guard ids.indices.contains(path.item) else { return }
            AppLog.write("face click on card \(path.item): \(contents[ids[path.item]].map { "\($0.session.name), \($0.session.status.state)" } ?? "gone")", to: "clicks.log")
            model.openFace(ids[path.item])
        }

        /// A team's toggle shows or hides its rows; one of its faces focuses that session's terminal. Both act on the press.
        func spotClicked(at path: IndexPath, _ spot: CardView.Spot) {
            guard ids.indices.contains(path.item) else { return }
            AppLog.write("\(spot) on card \(path.item)", to: "clicks.log")
            switch spot {
            case .toggle:
                model.toggleTeam(ids[path.item])
                takeKeys()
            case .face(let id): model.openFace(id)
            }
        }

        // MARK: Drag and drop

        func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool { true }

        func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint,
                            forItemsAt indexPaths: Set<IndexPath>) {
            hold()
            // As a task's (DESIGN.md §5): the card alone, in a list formation.
            session.draggingFormation = .list
            let paths = indexPaths.sorted()
            session.enumerateDraggingItems(options: [], for: collectionView, classes: [NSPasteboardItem.self], searchOptions: [:]) { [weak self] item, index, _ in
                guard let self, paths.indices.contains(index), let frame = collectionView.item(at: paths[index])?.view.frame,
                      let image = self.dragImage(of: paths[index].item, size: frame.size) else { return }
                item.setDraggingFrame(frame, contents: image)
            }
        }

        /// A card as it drags: alone, at its own size, no ring, tint or glow.
        func dragImage(of index: Int, size: CGSize) -> NSImage? {
            guard ids.indices.contains(index), let content = contents[ids[index]], let grid else { return nil }
            return SessionGrid.image(of: SessionCard.dragged(content, now: now), size: size, in: grid)
        }

        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            guard ids.indices.contains(indexPath.item) else { return nil }
            return DragItem.session(ids[indexPath.item], line: model.line(of: .session(ids[indexPath.item])))
        }

        /// A session over a card's middle drops onto it (its ring); over its edge or a gap it lands there (the line). AppKit is
        /// told it drops onto a card whatever lands, so the cards hold still.
        func collectionView(_ collectionView: NSCollectionView, validateDrop info: NSDraggingInfo,
                            proposedIndexPath path: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                            dropOperation operation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
            let pasteboard = info.draggingPasteboard
            hold()
            if !DragItem.tasks(on: pasteboard).isEmpty {
                // A task links to the card it's dropped on.
                show(nil)
                let index = path.pointee.item
                guard ids.indices.contains(index) else { return setDropTarget(nil) }
                operation.pointee = .on
                setDropTarget(IndexPath(item: index, section: 0))
                return .link
            }
            guard let id = DragItem.session(on: pasteboard), fromHQ(info, collectionView), !ids.isEmpty,
                  let drop = drop(of: id, at: collectionView.convert(info.draggingLocation, from: nil)) else {
                show(nil)
                return []
            }
            show(drop)
            path.pointee = IndexPath(item: min(max(path.pointee.item, 0), ids.count - 1), section: 0) as NSIndexPath
            operation.pointee = .on
            return .move
        }

        /// A drag from the grid or from the open team's card: HQ's own sessions.
        private func fromHQ(_ info: NSDraggingInfo, _ collectionView: NSCollectionView) -> Bool {
            info.draggingSource as? NSCollectionView === collectionView || info.draggingSource is TeamCardView
        }

        /// Where a session dragged to a point of the grid lands (DESIGN.md §5): a card's middle drops onto it; its edge (its
        /// outer sixth on two columns, its top or bottom quarter on one) or the gap nearest, right before or after it.
        func drop(of id: String, at point: NSPoint) -> SessionDrop? {
            guard !ids.isEmpty, width > 0 else { return nil }
            let frames = ids.indices.map { SessionGrid.frame(of: $0, width: width) }
            let index = frames.indices.min { Self.distance(frames[$0], point) < Self.distance(frames[$1], point) } ?? 0
            let frame = frames[index]
            let after: Bool
            if columns > 1 {
                let side = frame.width / 6
                if point.x < frame.minX + side {
                    after = false
                } else if point.x > frame.maxX - side {
                    after = true
                } else if point.y >= frame.minY, point.y <= frame.maxY {
                    return model.canDrop(id, on: ids[index]) ? .onto(ids[index]) : nil
                } else {
                    after = point.x > frame.midX
                }
            } else {
                let edge = min(Metric.dropEdge, frame.height / 4)
                if point.y < frame.minY + edge {
                    after = false
                } else if point.y > frame.maxY - edge {
                    after = true
                } else {
                    return model.canDrop(id, on: ids[index]) ? .onto(ids[index]) : nil
                }
            }
            return gridPlace(beside: index, after: after)
        }

        /// The place right before or after a card on the grid, and its line in the gap beside it: upright on two columns,
        /// across on one, its ring at its start.
        func gridPlace(beside index: Int, after: Bool) -> SessionDrop {
            let frame = SessionGrid.frame(of: index, width: width)
            let card = ids[index]
            let place = after ? SessionPlace(parent: nil, before: ids.indices.contains(index + 1) ? ids[index + 1] : nil, after: card)
                : SessionPlace(parent: nil, before: card, after: index > 0 ? ids[index - 1] : nil)
            let half = Metric.cardGap / 2
            if columns > 1 {
                let x = after ? frame.maxX + half : frame.minX - half
                return .place(place, line: DropLine(from: CGPoint(x: x, y: frame.minY), to: CGPoint(x: x, y: frame.maxY)))
            }
            let y = after ? frame.maxY + half : frame.minY - half
            return .place(place, line: DropLine(from: CGPoint(x: frame.minX, y: y), to: CGPoint(x: frame.maxX, y: y)))
        }

        private static func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
            hypot(max(rect.minX - point.x, 0, point.x - rect.maxX), max(rect.minY - point.y, 0, point.y - rect.maxY))
        }

        /// The card it drops onto takes the ring; a place shows its line.
        private func show(_ drop: SessionDrop?) {
            self.drop = drop
            if case .onto(let target)? = drop, let index = ids.firstIndex(of: target) {
                setDropTarget(IndexPath(item: index, section: 0))
            } else {
                setDropTarget(nil)
            }
            if case .place(_, let line)? = drop { grid?.lineView.show(line) } else { grid?.lineView.show(nil) }
        }

        @discardableResult
        private func setDropTarget(_ path: IndexPath?) -> NSDragOperation {
            guard dropTarget != path else { return [] }
            dropTarget = path
            refreshVisible()
            return []
        }

        func collectionView(_ collectionView: NSCollectionView, acceptDrop info: NSDraggingInfo, indexPath: IndexPath,
                            dropOperation: NSCollectionView.DropOperation) -> Bool {
            let pasteboard = info.draggingPasteboard
            defer { show(nil) }
            if case let tasks = DragItem.tasks(on: pasteboard), !tasks.isEmpty {
                guard ids.indices.contains(indexPath.item), model.session(ids[indexPath.item]) != nil else { return false }
                let session = ids[indexPath.item]
                for task in tasks { model.link(task: task, session: session) }
                return true
            }
            let point = collectionView.convert(info.draggingLocation, from: nil)
            guard let id = DragItem.session(on: pasteboard), fromHQ(info, collectionView), let drop = drop(of: id, at: point) else { return false }
            switch drop {
            case .onto(let target):
                // After AppKit is done with the drag session.
                DispatchQueue.main.async { [weak self] in self?.showDropMenu(id, onto: target, at: point, in: collectionView) }
            case .place(let place, _):
                land(id, at: place)
            }
            return true
        }

        /// A session let go between cards or rows lands there at once, selected; one Undo step (DESIGN.md §5).
        func land(_ id: String, at place: SessionPlace) {
            let from = ids.firstIndex(of: id)
            landing = true
            guard model.placeSession(id, at: place) else { return }
            // A card moved among the cards takes its new place now: the update that follows finds the grid in order.
            let shown = model.shownRoots.map(\.id)
            if let from, let to = shown.firstIndex(of: id), Set(shown) == Set(ids), let collection = grid?.collection {
                ids = shown
                collection.moveItem(at: IndexPath(item: from, section: 0), to: IndexPath(item: to, section: 0))
            }
            select(id, scroll: false)
        }

        /// A session dropped onto another (DESIGN.md §5), as a task's drop menu: Move Under it, Move Above or Below it, Make
        /// Root (when it has a parent), Cancel.
        func showDropMenu(_ id: String, onto target: String, at point: NSPoint, in view: NSView) {
            guard let moving = model.session(id), let over = model.session(target) else { return }
            let tree = model.sessionTree
            let parent = tree.parent(of: id)
            let beside = tree.parent(of: target)
            let name = "“\(MenuAction.short(over.name))”"
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(.sectionHeader(title: "Drop “\(MenuAction.short(moving.name))”"))
            menu.addItem(MenuAction.item("Move Under \(name)", enabled: parent != target && model.canDrop(id, on: target)) { [weak self] in
                self?.landing = true
                self?.model.setParent(id, to: target)
                self?.select(id)
            })
            for after in [false, true] {
                let place = after ? SessionPlace(parent: beside, after: target) : SessionPlace(parent: beside, before: target)
                menu.addItem(MenuAction.item("Move \(after ? "Below" : "Above") \(name)", enabled: model.canPlace(id, place)) { [weak self] in
                    self?.land(id, at: place)
                })
            }
            if parent != nil {
                menu.addItem(MenuAction.item("Make Root") { [weak self] in
                    self?.landing = true
                    self?.model.setParent(id, to: nil)
                    self?.select(id)
                })
            }
            menu.addItem(.separator())
            menu.addItem(MenuAction.item("Cancel") {})
            if let pick = SessionGrid.pickDropChoice {
                if let item = pick(menu) { (item.representedObject as? MenuAction)?.run() }
                return
            }
            menu.popUp(positioning: nil, at: point, in: view)
        }

        func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
            DragItem.logEnd("card", operation: operation)
            dragEnded()
        }

        /// A drag starts over the grid: what came or went since the last one shows first, then the cards hold still.
        private func hold() {
            guard heldSince == nil else { return }
            if let latest, latest.sessions.map(\.id) != ids {
                apply(latest.sessions, width: latest.width, now: now, selected: latest.selected, open: latest.open)
            }
            heldSince = .now
        }

        /// A drag ended, dropped or not: no card stays marked, and the cards that came or went while it lasted show.
        func dragEnded() {
            show(nil)
            guard heldSince != nil else { return }
            heldSince = nil
            // After AppKit is done with the drag session.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.heldSince == nil, let latest = self.latest else { return }
                self.apply(latest.sessions, width: latest.width, now: self.now, selected: self.model.selectedSession, open: self.model.openTeam)
            }
        }

        func copySelection() {
            if let id = model.selectedSession { model.copy([.session(id)]) }
        }
    }

    // MARK: Views

    /// The collection view in a plain view that reports its height to SwiftUI.
    final class GridView: NSView {
        let collection = CardCollection()
        private let flow = NSCollectionViewFlowLayout()
        weak var coordinator: Coordinator? {
            didSet {
                collection.dataSource = coordinator
                collection.delegate = coordinator
            }
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
            flow.minimumInteritemSpacing = Metric.cardGap
            flow.minimumLineSpacing = Metric.cardGap
            flow.sectionInset = NSEdgeInsetsZero
            collection.collectionViewLayout = flow
            collection.backgroundColors = [.clear]
            collection.isSelectable = true
            collection.allowsEmptySelection = true
            collection.register(CardItem.self, forItemWithIdentifier: CardItem.id)
            collection.registerForDraggedTypes([DragItem.sessionType, DragItem.taskType])
            collection.setDraggingSourceOperationMask(.move, forLocal: true)
            collection.setDraggingSourceOperationMask(.copy, forLocal: false)  // Into another app (Ghostty): its line, as a task gives (T-348)
            collection.register(NoGap.self, forSupplementaryViewOfKind: NSCollectionView.elementKindInterItemGapIndicator, withIdentifier: NoGap.id)
            collection.setAccessibilityLabel("Sessions")
            collection.onKey = { [weak self] event in self?.coordinator?.key(event) ?? false }
            collection.onMenu = { [weak self] point in self?.coordinator?.menu(at: point) }
            collection.onDoubleClick = { [weak self] path in self?.coordinator?.doubleClicked(at: path) }
            collection.onFaceClick = { [weak self] path in self?.coordinator?.faceClicked(at: path) }
            collection.onSpot = { [weak self] path, spot in self?.coordinator?.spotClicked(at: path, spot) }
            collection.onEmptyClick = { [weak self] in self?.coordinator?.model.selectSection(nil) }
            collection.onDragLeft = { [weak self] in self?.coordinator?.dragEnded() }
            collection.onCopy = { [weak self] in self?.coordinator?.copySelection() }
            collection.onKeyboard = { [weak self] has in self?.coordinator?.model.cardsKeyboard = has }
            addSubview(collection)
            addSubview(lineView)
        }

        /// Where a dragged session lands between cards, over them.
        let lineView = DropLineView()

        required init?(coder: NSCoder) { fatalError() }

        // The cards fill the view whatever size their layout gave them: cards outside its frame take no clicks.
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            if collection.frame != bounds { collection.frame = bounds }
            if lineView.frame != bounds { lineView.frame = bounds }
        }

        override func layout() {
            super.layout()
            if collection.frame != bounds { collection.frame = bounds }
            if lineView.frame != bounds { lineView.frame = bounds }
        }

        func layout(width: CGFloat) {
            flow.itemSize = NSSize(width: SessionGrid.itemWidth(width), height: Metric.card)
            flow.invalidateLayout()
        }

        /// After cards came or went: each card shows whole, and a view AppKit faded out but left behind goes, so nothing
        /// unseen takes a click.
        func settleCards() {
            let items = (0..<collection.numberOfItems(inSection: 0)).compactMap { collection.item(at: IndexPath(item: $0, section: 0))?.view }
            for view in items where view.alphaValue < 1 { view.alphaValue = 1 }
            for case let card as CardView in collection.subviews where !items.contains(card) && card.alphaValue == 0 {
                card.removeFromSuperview()
            }
        }
    }

    /// Takes the first click, Return and Space, double-clicks, and asks for each card's menu.
    final class CardCollection: NSCollectionView {
        var onKey: ((NSEvent) -> Bool)?
        var onMenu: ((NSPoint) -> NSMenu?)?
        var onDoubleClick: ((IndexPath) -> Void)?
        var onFaceClick: ((IndexPath) -> Void)?
        /// A team's toggle or one of its faces, pressed.
        var onSpot: ((IndexPath, CardView.Spot) -> Void)?
        var onEmptyClick: (() -> Void)?
        /// The cards took or gave up the keyboard.
        var onKeyboard: ((Bool) -> Void)?
        /// A press on a face: its card and where it started.
        private var facePress: (path: IndexPath, at: NSPoint)?
        /// A drag left the grid or ended, wherever it started.
        var onDragLeft: (() -> Void)?
        /// ⌘C, Edit › Copy: the selected card's session line (T-358).
        var onCopy: (() -> Void)?

        @objc func copy(_ sender: Any?) { onCopy?() }

        /// AppKit sizes a collection view and lays out its cards to its enclosing scroll view, the page's, wider than the
        /// grid: cards past the grid's edge show but take no clicks. The grid has no scroll view, and stays its own size.
        override var enclosingScrollView: NSScrollView? { nil }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(superview?.bounds.size ?? newSize)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func becomeFirstResponder() -> Bool {
            let took = super.becomeFirstResponder()
            if took { onKeyboard?(true) }
            return took
        }

        override func resignFirstResponder() -> Bool {
            let gave = super.resignFirstResponder()
            if gave { onKeyboard?(false) }
            return gave
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            super.draggingExited(sender)
            onDragLeft?()
        }

        override func draggingEnded(_ sender: NSDraggingInfo) {
            super.draggingEnded(sender)
            onDragLeft?()
        }

        override func keyDown(with event: NSEvent) {
            if onKey?(event) != true { super.keyDown(with: event) }
        }

        /// The cards' keys come before the menu bar's, as the outline's rows' do: a held ⇧ arrow stays among siblings.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if window?.firstResponder === self, onKey?(event) == true { return true }
            return super.performKeyEquivalent(with: event)
        }

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            let path = indexPathForItem(at: point)
            window?.makeFirstResponder(self)
            facePress = nil
            guard let path else {
                // A click between cards: nothing on the page stays selected.
                onEmptyClick?()
                return super.mouseDown(with: event)
            }
            // A team's toggle and faces act on the press, and select nothing; the toggle on every click, a face on the first.
            if let card = item(at: path)?.view as? CardView, let spot = card.spot(at: card.convert(event.locationInWindow, from: nil)) {
                if spot == .toggle || event.clickCount == 1 { onSpot?(path, spot) }
                return
            }
            let face = onFace(path, event)
            if event.clickCount == 2, !face {
                onDoubleClick?(path)
                return
            }
            // A face acts on its first click only: a double-click focuses once.
            facePress = face && event.clickCount == 1 ? (path, event.locationInWindow) : nil
            if face { AppLog.write("face press on card \(path.item)", to: "clicks.log") }
            super.mouseDown(with: event)
            // The collection view may track the press itself, up to its release.
            if let up = NSApp.currentEvent, up.type == .leftMouseUp, up.timestamp >= event.timestamp { faceReleased(up) }
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            faceReleased(event)
        }

        /// A click, not a drag, on a face: its session's terminal, at once.
        private func faceReleased(_ event: NSEvent) {
            guard let press = facePress else { return }
            facePress = nil
            guard hypot(event.locationInWindow.x - press.at.x, event.locationInWindow.y - press.at.y) < 4 else {
                return AppLog.write("face press on card \(press.path.item) moved: a drag, not a click", to: "clicks.log")
            }
            onFaceClick?(press.path)
        }

        private func onFace(_ path: IndexPath, _ event: NSEvent) -> Bool {
            guard let card = item(at: path)?.view else { return false }
            let local = card.convert(event.locationInWindow, from: nil)
            return CardView.face.contains(card.isFlipped ? local : NSPoint(x: local.x, y: card.bounds.height - local.y))
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            onMenu?(convert(event.locationInWindow, from: nil))
        }
    }

    /// One card: SwiftUI in an AppKit item. Clicks land on the collection view.
    final class CardItem: NSCollectionViewItem {
        static let id = NSUserInterfaceItemIdentifier("session-card")
        private let host = NSHostingView(rootView: AnyView(EmptyView()))

        override func loadView() {
            let root = CardView()
            host.sizingOptions = []
            host.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                host.topAnchor.constraint(equalTo: root.topAnchor),
                host.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            ])
            view = root
        }

        /// What the card shows, so an update that changes none of it leaves the card alone.
        private var shown: (content: CardContent, now: Date)?
        /// Cards drawn again since launch: a hook event redraws its own card only.
        static var renders = 0

        func show(_ content: CardContent, now: Date, model: AppModel) {
            if let shown, shown.content == content, shown.now == now { return }
            shown = (content, now)
            Self.renders += 1
            let id = content.session.id
            guard let card = view as? CardView else { return }
            card.content = content
            // Open, the team's card floats over this one, which shows nothing.
            var resting = content
            resting.open = false
            host.isHidden = content.open
            host.rootView = AnyView(SessionCard(resting, now: now) { [weak card] in card?.tray = $0 }
                .accessibilityHidden(true)
                .uiTestAnchor("card:\(id)"))
            card.setAccessibilityLabel(SessionCard.spoken(content))
            card.selected = content.selected == id
            card.press = { [weak model] in model?.open(.session(id)) }
            var actions: [(name: String, run: () -> Void)] = [(content.session.isRunning ? "Focus" : "Resume", { [weak model] in model?.open(id) })]
            if !content.team.isEmpty {
                actions.append((content.open ? "Hide Its Sessions" : "Show Its Sessions", { [weak model] in model?.toggleTeam(id) }))
            }
            card.actions = actions
        }
    }

    /// AppKit's gap between cards, empty: the cards hold still and a line shows where a session lands.
    final class NoGap: NSView, NSCollectionViewElement {
        static let id = NSUserInterfaceItemIdentifier("no-gap")
    }

    /// A SwiftUI view drawn once at a size, in a view's window and appearance: a drag image.
    static func image(of view: some View, size: CGSize, in parent: NSView) -> NSImage {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        parent.addSubview(host, positioned: .below, relativeTo: nil)
        defer { host.removeFromSuperview() }
        host.layoutSubtreeIfNeeded()
        let image = NSImage(size: size)
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            image.addRepresentation(bitmap)
        }
        return image
    }

    /// The card's root: clicks go to the collection view.
    final class CardView: NSView {
        /// What a press on a team's tray reaches.
        enum Spot: Equatable, CustomStringConvertible {
            case toggle
            case face(String)

            var description: String {
                switch self {
                case .toggle: "team toggle"
                case .face(let id): "team face \(id.prefix(8))"
                }
            }
        }

        var press: () -> Void = {}
        var actions: [(name: String, run: () -> Void)] = []
        var selected = false
        var content: CardContent?
        /// Where the team's tray sits in the card, as SwiftUI laid it out.
        var tray: CGRect = .zero

        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .button }
        override func isAccessibilitySelected() -> Bool { selected }
        override func accessibilityPerformPress() -> Bool { press(); return true }
        override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
            actions.map { action in NSAccessibilityCustomAction(name: action.name) { action.run(); return true } }
        }

        nonisolated override var isFlipped: Bool { true }

        /// The face, at the card's top left inside its padding.
        static var face: NSRect { NSRect(x: Space.md, y: Space.md, width: Metric.faceCard, height: Metric.faceCard) }
        private var pointerArea: NSTrackingArea?

        /// The team's toggle or one of its faces under a point of the card.
        func spot(at point: NSPoint) -> Spot? {
            guard let content, !content.team.isEmpty, tray.insetBy(dx: -Metric.lineGap, dy: -Metric.lineGap).contains(point) else { return nil }
            let spots = SessionCard.traySpots(content, in: tray)
            if spots.toggle.insetBy(dx: -Metric.lineGap, dy: -Metric.lineGap).contains(point) { return .toggle }
            return spots.faces.first { $0.rect.contains(point) }.map { .face($0.id) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

        // The pointing hand over the faces and the toggle, which SwiftUI can't give: the card takes their clicks.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackPointer()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            trackPointer()
        }

        private func trackPointer() {
            guard pointerArea == nil, window != nil else { return }
            let area = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
            addTrackingArea(area)
            pointerArea = area
        }

        override func cursorUpdate(with event: NSEvent) { pointer(event) }
        override func mouseMoved(with event: NSEvent) { pointer(event) }

        private func pointer(_ event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            (Self.face.contains(point) || spot(at: point) != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
        }

        /// Over the face, as the pointer sees it.
        var handOverFace: Bool { pointerArea != nil }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

// MARK: The open team

/// The open team's card in SwiftUI's overlay over the grid.
struct OpenTeam: NSViewRepresentable {
    let content: CardContent
    let now: Date
    let link: GridLink
    @Environment(AppModel.self) private var model

    func makeNSView(context: Context) -> TeamCardView { TeamCardView() }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TeamCardView, context: Context) -> CGSize? { proposal.replacingUnspecifiedDimensions() }

    func updateNSView(_ view: TeamCardView, context: Context) {
        view.link = link
        view.show(content, now: now, model: model)
    }
}

/// The open team's card (DESIGN.md §5): the card's row and a row per session, over the cards below. A click selects, a
/// double-click opens, a face focuses, a right-click shows the menu, a drag moves a session, a drop asks; a press anywhere
/// outside it folds it.
final class TeamCardView: NSView, NSDraggingSource {
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    weak var link: GridLink? { didSet { link?.team = self } }
    private weak var model: AppModel?
    private(set) var content: CardContent?
    private var now = Date.distantPast
    /// Where its tray sits, as SwiftUI laid it out.
    private var tray: CGRect = .zero
    /// The session a dragged item hovers.
    private(set) var dropOn: String? { didSet { if dropOn != oldValue { redraw() } } }
    /// What a dragged session would do where it is over the card: its ring, or its line.
    private(set) var drop: SessionDrop?
    /// Where a dragged session lands among the rows, or beside the card on the grid.
    let lineView = DropLineView()
    /// A press on a session: a click, or a drag once it moves.
    private var press: (id: String, at: NSPoint, face: Bool)?
    private var outside: Any?
    private var pointerArea: NSTrackingArea?

    nonisolated override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        lineView.autoresizingMask = [.width, .height]
        addSubview(lineView)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        registerForDraggedTypes([DragItem.sessionType, DragItem.taskType, DragItem.itemType])
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ content: CardContent, now: Date, model: AppModel) {
        self.model = model
        guard content != self.content || now != self.now else { return }
        self.content = content
        self.now = now
        redraw()
    }

    private func redraw() {
        guard var content else { return }
        if let dropOn { content.dropTarget = dropOn }
        host.rootView = AnyView(SessionCard(content, now: now) { [weak self] in self?.tray = $0 }
            .uiTestAnchor("team:\(content.session.id)"))
    }

    // MARK: Where

    /// The session under a point, and whether the point is on its face.
    func spot(at point: NSPoint) -> (id: String, face: Bool)? {
        guard let content, bounds.contains(point) else { return nil }
        if point.y < Metric.card { return (content.session.id, SessionGrid.CardView.face.contains(point)) }
        let top = Metric.card + SessionCard.rowsTop
        let index = Int(((point.y - top) / Metric.teamRow).rounded(.down))
        guard point.y >= top, content.team.indices.contains(index) else { return nil }
        let member = content.team[index]
        let face = SessionCard.rowFace(depth: member.depth).offsetBy(dx: 0, dy: top + CGFloat(index) * Metric.teamRow)
        return (member.id, face.insetBy(dx: -Metric.lineGap, dy: -Metric.lineGap).contains(point))
    }

    /// A session's row in this view; the card's own row for its top session.
    func rowFrame(_ id: String) -> NSRect? {
        guard let content else { return nil }
        if id == content.session.id { return NSRect(x: 0, y: 0, width: bounds.width, height: Metric.card) }
        guard let index = content.team.firstIndex(where: { $0.id == id }) else { return nil }
        let inset = Space.xs + 2
        return NSRect(x: inset, y: Metric.card + SessionCard.rowsTop + CGFloat(index) * Metric.teamRow, width: bounds.width - inset * 2, height: Metric.teamRow)
    }

    func scrollToVisible(row id: String) {
        if let rect = rowFrame(id) { scrollToVisible(rect) }
    }

    /// The toggle, as SwiftUI laid it out.
    var toggle: NSRect? { content.map { SessionCard.traySpots($0, in: tray).toggle } }

    // MARK: Clicks

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let model else { return }
        link?.coordinator?.takeKeys()
        let point = convert(event.locationInWindow, from: nil)
        press = nil
        // The toggle takes every click: the second of a double-click hides what the first showed.
        if let toggle, toggle.insetBy(dx: -Metric.lineGap, dy: -Metric.lineGap).contains(point) {
            model.foldTeam()
            return
        }
        guard let (id, face) = spot(at: point) else { return }
        if event.clickCount == 2 {
            if !face { model.open(.session(id)) }
            return
        }
        link?.coordinator?.select(id, scroll: false)
        press = (id, event.locationInWindow, face)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let press, hypot(event.locationInWindow.x - press.at.x, event.locationInWindow.y - press.at.y) >= 4 else { return }
        self.press = nil
        beginDrag(press.id, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { press = nil }
        guard let press, press.face, hypot(event.locationInWindow.x - press.at.x, event.locationInWindow.y - press.at.y) < 4 else { return }
        AppLog.write("face click on an open team's row: \(press.id.prefix(8))", to: "clicks.log")
        model?.openFace(press.id)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model, let id = spot(at: convert(event.locationInWindow, from: nil))?.id, let session = model.session(id) else { return nil }
        return NSHostingMenu(rootView: SessionMenu(session: session).environment(model))
    }

    /// A press anywhere outside the card folds it; a menu opened from it isn't outside.
    private func clicked(_ event: NSEvent) {
        guard let window, event.window === window, let model, let content, model.openTeam == content.session.id else { return }
        if !bounds.contains(convert(event.locationInWindow, from: nil)) { model.foldTeam() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let outside {
            NSEvent.removeMonitor(outside)
            self.outside = nil
        }
        guard window != nil else { return }
        outside = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.clicked(event)
            return event
        }
        if pointerArea == nil {
            let area = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
            addTrackingArea(area)
            pointerArea = area
        }
    }

    // The pointing hand over the faces and the toggle.
    override func cursorUpdate(with event: NSEvent) { pointer(event) }
    override func mouseMoved(with event: NSEvent) { pointer(event) }

    private func pointer(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        (toggle?.contains(point) == true || spot(at: point)?.face == true ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    // MARK: Drag

    private func beginDrag(_ id: String, event: NSEvent) {
        guard let model, let rect = rowFrame(id), let image = dragImage(of: id) else { return }
        let item = NSDraggingItem(pasteboardWriter: DragItem.session(id, line: model.line(of: .session(id))))
        item.setDraggingFrame(rect, contents: image)
        // As a task's (DESIGN.md §5): alone, in a list formation.
        beginDraggingSession(with: [item], event: event, source: self).draggingFormation = .list
    }

    /// A session of the card as it drags: the card alone for its top session, a row on a small card of its own for the others.
    func dragImage(of id: String) -> NSImage? {
        guard let content, let rect = rowFrame(id) else { return nil }
        if id == content.session.id { return SessionGrid.image(of: SessionCard.dragged(content, now: now), size: rect.size, in: self) }
        guard let member = content.team.first(where: { $0.id == id }) else { return nil }
        return SessionGrid.image(of: SessionCard.draggedRow(member, now: now), size: rect.size, in: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        DragItem.logEnd("team row", operation: operation)
        link?.coordinator?.dragEnded()
    }

    // MARK: Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dropOperation(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dropOperation(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { show(nil) }
    override func draggingEnded(_ sender: NSDraggingInfo) { show(nil) }

    /// A task links to the session it's dropped on; a session over a row's middle drops onto it (the menu asks), over its
    /// edge or between rows it lands there.
    func dropOperation(_ info: NSDraggingInfo) -> NSDragOperation {
        let point = convert(info.draggingLocation, from: nil)
        let pasteboard = info.draggingPasteboard
        if !DragItem.tasks(on: pasteboard).isEmpty {
            show(nil)
            dropOn = spot(at: point)?.id
            return dropOn == nil ? [] : .link
        }
        guard let id = DragItem.session(on: pasteboard), let drop = drop(of: id, at: point) else {
            show(nil)
            return []
        }
        show(drop)
        return .move
    }

    /// Where a session dragged to a point of the card lands (DESIGN.md §5). On its own row: the middle drops onto its
    /// session, the bottom quarter puts it first under it, the edges place it on the grid as any card's do. On a row: the
    /// middle drops onto it, the top or bottom quarter puts it right before or after it, at its level.
    func drop(of id: String, at point: NSPoint) -> SessionDrop? {
        guard let model, let content, bounds.contains(point) else { return nil }
        let top = content.session.id
        if point.y < Metric.card {
            let edge = min(Metric.dropEdge, Metric.card / 4)
            if point.y > Metric.card - edge, !content.team.isEmpty { return rowPlace(of: id, 0, after: false) }
            if let grid = link?.coordinator, let index = grid.ids.firstIndex(of: top) {
                let side = bounds.width / 6
                let beside: Bool? = grid.columns > 1 ? (point.x < side ? false : point.x > bounds.width - side ? true : nil) : (point.y < edge ? false : nil)
                if let after = beside, case .place(let place, let line) = grid.gridPlace(beside: index, after: after) {
                    let collection = grid.grid?.collection
                    return .place(place, line: DropLine(from: convert(line.from, from: collection), to: convert(line.to, from: collection)))
                }
            }
            return model.canDrop(id, on: top) ? .onto(top) : nil
        }
        let rows = content.team
        guard !rows.isEmpty else { return nil }
        let y = point.y - Metric.card - SessionCard.rowsTop
        let index = min(max(Int((y / Metric.teamRow).rounded(.down)), 0), rows.count - 1)
        let within = y - CGFloat(index) * Metric.teamRow
        let edge = min(Metric.dropEdge, Metric.teamRow / 4)
        if within < edge { return rowPlace(of: id, index, after: false) }
        if within > Metric.teamRow - edge {
            return rows.indices.contains(index + 1) ? rowPlace(of: id, index + 1, after: false) : rowPlace(of: id, index, after: true)
        }
        return model.canDrop(id, on: rows[index].id) ? .onto(rows[index].id) : nil
    }

    /// Right before or after a row, beside its session: the line across the row's top or bottom, from its face's left.
    private func rowPlace(of id: String, _ index: Int, after: Bool) -> SessionDrop? {
        guard let model, let content, content.team.indices.contains(index) else { return nil }
        let member = content.team[index]
        let parent = model.sessionTree.parent(of: member.id)
        let place = after ? SessionPlace(parent: parent, after: member.id) : SessionPlace(parent: parent, before: member.id)
        guard model.canPlace(id, place), let row = rowFrame(member.id) else { return nil }
        let y = after ? row.maxY : row.minY
        return .place(place, line: DropLine(from: CGPoint(x: SessionCard.rowFace(depth: member.depth).minX, y: y), to: CGPoint(x: row.maxX, y: y)))
    }

    /// The row it drops onto takes the ring; a place shows its line.
    private func show(_ drop: SessionDrop?) {
        self.drop = drop
        if case .onto(let target)? = drop { dropOn = target } else { dropOn = nil }
        if case .place(_, let line)? = drop { lineView.show(line) } else { lineView.show(nil) }
    }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        let point = convert(info.draggingLocation, from: nil)
        let target = spot(at: point)?.id
        defer { show(nil) }
        guard let model else { return false }
        let pasteboard = info.draggingPasteboard
        if case let tasks = DragItem.tasks(on: pasteboard), !tasks.isEmpty {
            guard let target else { return false }
            for task in tasks { model.link(task: task, session: target) }
            return true
        }
        guard let id = DragItem.session(on: pasteboard), let drop = drop(of: id, at: point) else { return false }
        switch drop {
        case .onto(let target):
            // After AppKit is done with the drag session.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.link?.coordinator?.showDropMenu(id, onto: target, at: point, in: self)
            }
        case .place(let place, _):
            link?.coordinator?.land(id, at: place)
        }
        return true
    }
}

/// A menu item that runs a closure.
final class MenuAction: NSObject {
    let run: () -> Void

    init(_ run: @escaping () -> Void) {
        self.run = run
    }

    @objc func perform(_ sender: Any?) { run() }

    static func item(_ title: String, enabled: Bool = true, _ run: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(perform(_:)), keyEquivalent: "")
        item.target = action
        // The item keeps its action alive: a target is weak.
        item.representedObject = action
        item.isEnabled = enabled
        return item
    }

    /// A session's name in a menu, cut at 30 characters so the menu stays narrow.
    static func short(_ name: String) -> String {
        name.count > MenuBarMenu.nameLimit ? name.prefix(MenuBarMenu.nameLimit - 1).trimmingCharacters(in: .whitespaces) + "…" : name
    }
}

/// A session's menu, from a click on its face anywhere (DESIGN.md §10).
enum FaceMenu {
    /// Shows it at a point in a view, or at the pointer with no view; the UI test records it instead.
    static var show: (NSMenu, String, NSPoint, NSView?) -> Void = { menu, _, point, view in
        if let view { menu.popUp(positioning: nil, at: point, in: view) } else { menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
    }

    /// Under the face clicked, its left edges lined up, as a task's faces show it; at the pointer without a view.
    static func showUnder(_ view: NSView?, _ menu: NSMenu, _ id: String) {
        let point = view.map { NSPoint(x: 0, y: $0.isFlipped ? $0.bounds.maxY + Space.xs : -Space.xs) } ?? .zero
        show(menu, id, point, view)
    }
}

extension DragItem {
    /// A session on a drag: its id for HQ, its line for other apps.
    static func session(_ id: String, line: String) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(id, forType: sessionType)
        item.setString(line, forType: .string)
        return item
    }

    /// The session a drag carries.
    static func session(on pasteboard: NSPasteboard) -> String? {
        pasteboard.pasteboardItems?.first?.string(forType: sessionType)
    }
}

extension AppModel {
    /// The cards the grid shows: the top-level sessions; while the search filters, those with a match in their team.
    var shownRoots: [SessionItem] {
        let roots = gridRoots
        guard !search.isEmpty else { return roots }
        let matches = Set(filteredGrid.map(\.id))
        let tree = sessionTree
        return roots.filter { root in matches.contains(root.id) || tree.rows(under: root.id).contains { matches.contains($0.id) } }
    }

    /// What a card shows: its session and role, its team, and the selection, the open team and blinking among them.
    func cardContent(_ session: SessionItem, tree: SessionTree? = nil, open: SessionItem.ID?, selected: SessionItem.ID?, width: CGFloat) -> CardContent {
        let tree = tree ?? sessionTree
        let team = self.team(of: session.id, in: tree).map { TeamMember(session: $0.session, depth: $0.depth, role: role(named: $0.session.role)) }
        let everyone = [session] + team.map(\.session)
        return CardContent(session: session, role: role(named: session.role), team: team, open: open == session.id && !team.isEmpty,
                           selected: everyone.contains { $0.id == selected } ? selected : nil,
                           blinking: everyone.contains(where: blinks), trayRoom: SessionCard.trayRoom(width))
    }

    /// Show or hide a team's sessions in its card: one team open at a time.
    func toggleTeam(_ id: SessionItem.ID) {
        if openTeam == id { return foldTeam() }
        guard !team(of: id).isEmpty else { return }
        foldTeam()
        openTeam = id
    }

    /// The open team folds; one of its sessions that was selected hands the selection to its top card.
    func foldTeam() {
        guard let open = openTeam else { return }
        if let selected = selectedSession, selected != open, sessionTree.root(of: selected) == open { selectedSession = open }
        openTeam = nil
    }

    /// A session can go under `target`: another running one, not of its own team below it.
    func canDrop(_ id: SessionItem.ID, on target: SessionItem.ID) -> Bool {
        id != target && session(target)?.isRunning == true && sessionTree.canMove(id, under: target)
    }

    /// A team's open sessions: its top card's, then the ones under it, depth first.
    func openSessions(ofTeam id: SessionItem.ID) -> [SessionItem] {
        ([session(id)].compactMap { $0 } + team(of: id).map(\.session)).filter(\.isRunning)
    }

    /// Close Team (N sessions)…: asks with the count, then closes each one as Close Session does. One that waits on the
    /// user is left for them to answer, and the alert says so.
    func closeTeam(_ id: SessionItem.ID) {
        let open = openSessions(ofTeam: id)
        guard let top = session(id), !open.isEmpty else { return }
        let waiting = open.filter { if case .waiting = $0.status.state { true } else { false } }
        let close = { [weak self] in
            for item in open.reversed() where !waiting.contains(where: { $0.id == item.id }) { self?.closeSession(item.id) }
        }
        if Store.isOverridden {
            ghosttyLog.append("confirm close team \(id), \(open.count) sessions")
            return close()
        }
        let alert = NSAlert()
        alert.messageText = "Close “\(top.name)” and its team, \(open.count) session\(open.count == 1 ? "" : "s")?"
        alert.informativeText = "Each one quits its Claude and closes its terminal; they go to Closed Sessions, where Resume brings each back."
            + (waiting.isEmpty ? "" : " \(waiting.count == 1 ? "One waits" : "\(waiting.count) wait") on you and stay\(waiting.count == 1 ? "s" : "") open: answer \(waiting.count == 1 ? "it" : "them") first.")
        alert.addButton(withTitle: "Close \(open.count) Session\(open.count == 1 ? "" : "s")")
        alert.addButton(withTitle: "Cancel")
        let finish = { (response: NSApplication.ModalResponse) in
            if response == .alertFirstButtonReturn { close() }
        }
        if let window = window.map({ $0.attachedSheet ?? $0 }) {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    /// A session's menu; from a task's or a PR's faces, with a new session on it too.
    func faceMenu(_ id: String, task: Int? = nil, pullRequest: GitHubItem? = nil) -> NSMenu? {
        guard let session = session(id) else { return nil }
        return NSHostingMenu(rootView: SessionMenu(session: session, task: task, pullRequest: pullRequest).environment(self))
    }
}

/// A session's menu: a card's or a team row's context menu, and a click on its face anywhere (DESIGN.md §5, §10).
struct SessionMenu: View {
    let session: SessionItem
    /// From a task's faces: Start Session… on that task.
    var task: Int?
    /// From a PR's face: a session on that PR.
    var pullRequest: GitHubItem?
    @Environment(AppModel.self) private var model

    var body: some View {
        let tree = model.sessionTree
        let top = tree.parent(of: session.id) == nil
        let team = model.team(of: session.id, in: tree)
        Button(session.isRunning ? "Focus" : "Resume") { model.open(session.id) }
        Button("Show Details") { model.open(.session(session.id)) }
        if top && !team.isEmpty {
            let open = model.openTeam == session.id
            Button(open ? "Hide Its Sessions" : "Show Its Sessions") { model.toggleTeam(session.id) }
                .keyboardShortcut(open ? .upArrow : .downArrow, modifiers: .command)
        }
        if let task, let item = model.task(task) {
            Button("Start Another Session on \(item.key)…") { model.beginStart(task: task) }
        }
        if let pullRequest {
            Button("Start Another Session on \(pullRequest.reference)…") { model.beginStart(pullRequest: pullRequest) }
        }
        Divider()
        Button("Start Child Session…") { model.beginStart(parent: session.id) }
            .disabled(!session.isRunning)
        Button("Start Session from Its History…") { model.beginStart(history: session.id) }
        let choices = Set(model.moveUnderChoices(for: session.id))
        let rows = model.sessionRows.filter { choices.contains($0.session.id) }
        Menu("Move Under") {
            ForEach(rows, id: \.session.id) { row in
                Button { model.setParent(session.id, to: row.session.id) } label: {
                    Label { Text(MenuAction.short(row.session.name)) } icon: { Image(nsImage: MenuBarMenu.face(row.session, depth: row.depth)) }
                }
            }
        }
        .disabled(rows.isEmpty)
        Button("Make Root") { model.setParent(session.id, to: nil) }
            .disabled(top)
        Divider()
        if session.isRunning, session.tty != nil {
            Button("Close Session") { model.closeSession(session.id) }
        }
        if top && !team.isEmpty, case let count = model.openSessions(ofTeam: session.id).count, count > 0 {
            Button("Close Team (\(count) session\(count == 1 ? "" : "s"))…") { model.closeTeam(session.id) }
        }
        Button("Randomize Face") { model.randomizeFace(session.id) }
        Divider()
        Button("Copy") { model.copy([.session(session.id)]) }
        Button("Copy Resume Command") { Pasteboard.copy(session.resumeCommand) }
        Button("Copy Session ID") { Pasteboard.copy(session.id) }
    }
}
