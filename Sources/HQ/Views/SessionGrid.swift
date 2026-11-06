import AppKit
import HQKit
import SwiftUI

/// The session cards (DESIGN.md §5): an `NSCollectionView` with no scroll view of its own, inside the
/// page's. Cards reorder by drag with the rows parting; a task dropped on a card links it.
struct SessionGrid: NSViewRepresentable {
    let sessions: [SessionItem]
    let width: CGFloat
    @Environment(AppModel.self) private var model

    static func columns(for width: CGFloat) -> Int {
        width >= Metric.fourColumns ? 4 : width >= Metric.threeColumns ? 3 : width >= Metric.twoColumns ? 2 : 1
    }

    static func height(count: Int, width: CGFloat) -> CGFloat {
        let rows = (count + columns(for: width) - 1) / columns(for: width)
        return CGFloat(rows) * Metric.card + CGFloat(max(rows - 1, 0)) * Metric.cardGap
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> GridView {
        let grid = GridView()
        grid.coordinator = context.coordinator
        context.coordinator.grid = grid
        context.coordinator.apply(sessions, width: width, now: model.now, selected: model.selectedSession)
        return grid
    }

    func updateNSView(_ grid: GridView, context: Context) {
        context.coordinator.model = model
        // Blinking follows what the user acknowledged.
        _ = model.seen
        context.coordinator.apply(sessions, width: width, now: model.now, selected: model.selectedSession)
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
        private(set) var ids: [String] = []
        private var byID: [String: SessionItem] = [:]
        private var now = Date.now
        private var width: CGFloat = 0
        /// The card a task hovers.
        private(set) var dropTarget: IndexPath?

        init(model: AppModel) {
            self.model = model
        }

        /// New or removed cards reload; a change inside cards only redraws them.
        func apply(_ sessions: [SessionItem], width: CGFloat, now: Date, selected: String?) {
            guard let grid else { return }
            self.now = now
            byID = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let newIDs = sessions.map(\.id)
            if width != self.width {
                self.width = width
                grid.layout(width: width)
            }
            if newIDs != ids {
                let old = ids
                let oldSet = Set(old), newSet = Set(newIDs)
                ids = newIDs
                // Cards that join or leave, the others keeping their order: the gap opens or closes. Anything else reloads.
                if old.filter(newSet.contains) == newIDs.filter(oldSet.contains) {
                    let removed = Set(old.indices.filter { !newSet.contains(old[$0]) }.map { IndexPath(item: $0, section: 0) })
                    let inserted = Set(newIDs.indices.filter { !oldSet.contains(newIDs[$0]) }.map { IndexPath(item: $0, section: 0) })
                    Motion.appKit(still: removed.count + inserted.count > 6) {
                        grid.collection.animator().performBatchUpdates {
                            grid.collection.deleteItems(at: removed)
                            grid.collection.insertItems(at: inserted)
                        }
                    }
                } else {
                    grid.collection.reloadData()
                }
                for case let item as CardItem in grid.collection.visibleItems() { refresh(item) }
            } else {
                for case let item as CardItem in grid.collection.visibleItems() { refresh(item) }
            }
            let wanted: Set<IndexPath> = selected.flatMap { ids.firstIndex(of: $0) }.map { [IndexPath(item: $0, section: 0)] } ?? []
            if grid.collection.selectionIndexPaths != wanted {
                grid.collection.selectionIndexPaths = wanted
                for case let item as CardItem in grid.collection.visibleItems() { refresh(item) }
            }
        }

        private func refresh(_ item: CardItem) {
            guard let path = grid?.collection.indexPath(for: item), ids.indices.contains(path.item),
                  let session = byID[ids[path.item]] else { return }
            item.show(session, now: now, selected: item.isSelected, dropTarget: dropTarget == path, blinking: model.blinks(session), model: model)
        }

        // MARK: Data

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { ids.count }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: CardItem.id, for: indexPath)
            if let card = item as? CardItem, let session = byID[ids[indexPath.item]] {
                card.show(session, now: now, selected: card.isSelected, dropTarget: dropTarget == indexPath, blinking: model.blinks(session), model: model)
            }
            return item
        }

        /// Where a dragged card will land: an accent bar between cards.
        func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                            at indexPath: IndexPath) -> NSView {
            collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: GapIndicator.id, for: indexPath)
        }

        // MARK: Clicks and keys

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            guard let path = indexPaths.first, ids.indices.contains(path.item) else { return }
            let id = ids[path.item]
            model.selectedSession = id
            model.selectSection(.sessions)
            model.acknowledge(id)
            for case let item as CardItem in collectionView.visibleItems() { refresh(item) }
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            for case let item as CardItem in collectionView.visibleItems() { refresh(item) }
        }

        /// Tab brought the keyboard here: the selected card, else the one selected when Tab left, else the first.
        func takeKeyboard() {
            guard let collection = grid?.collection, !ids.isEmpty else { return }
            let id = [model.selectedSession, model.parkedItems[.sessions]].compactMap { $0 }.first(where: ids.contains) ?? ids[0]
            model.selectedSession = id
            collection.window?.makeFirstResponder(collection)
            if let index = ids.firstIndex(of: id) {
                let path = IndexPath(item: index, section: 0)
                collection.selectionIndexPaths = [path]
                // The page scrolls, not the grid: it has no scroll view of its own.
                if let card = collection.item(at: path)?.view { card.scrollToVisible(card.bounds) }
                for case let item as CardItem in collection.visibleItems() { refresh(item) }
            }
        }

        /// A double-click shows the session.
        /// A double-click on the face opens the session in Ghostty (or asks to resume it); elsewhere, its modal.
        func doubleClicked(at path: IndexPath, onFace: Bool = false) {
            guard ids.indices.contains(path.item) else { return }
            if onFace { model.openFace(ids[path.item]) } else { model.open(.session(ids[path.item])) }
        }

        /// Return opens the selected session in Ghostty; Space shows its details.
        func key(_ event: NSEvent) -> Bool {
            if event.keyCode == 48, event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                // The card unselects, kept aside by the model for when Tab comes back.
                model.moveSection(from: .sessions, by: event.modifierFlags.contains(.shift) ? -1 : 1)
                return true
            }
            guard let id = model.selectedSession, ids.contains(id),
                  event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty else { return false }
            switch event.keyCode {
            case 36, 76: model.open(id)
            case 49: model.open(.session(id))
            default: return false
            }
            return true
        }

        func menu(at point: NSPoint) -> NSMenu? {
            guard let grid, let path = grid.collection.indexPathForItem(at: point) else { return nil }
            return menu(for: path)
        }

        func menu(for path: IndexPath) -> NSMenu? {
            guard ids.indices.contains(path.item), let session = byID[ids[path.item]] else { return nil }
            return NSHostingMenu(rootView: SessionMenu(session: session).environment(model))
        }

        /// A click on a card's face: the card's menu, under the face.
        /// A card's face focuses its session's terminal, or offers to resume it; the card's menu is a right-click.
        func faceClicked(at path: IndexPath) {
            guard ids.indices.contains(path.item) else { return }
            model.openFace(ids[path.item])
        }

        // MARK: Drag and drop

        func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool { true }

        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            guard let session = byID[ids[indexPath.item]] else { return nil }
            let item = NSPasteboardItem()
            item.setString(session.id, forType: DragItem.sessionType)
            item.setString(session.name, forType: .string)
            return item
        }

        func collectionView(_ collectionView: NSCollectionView, validateDrop info: NSDraggingInfo,
                            proposedIndexPath path: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                            dropOperation operation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
            let pasteboard = info.draggingPasteboard
            if pasteboard.availableType(from: [DragItem.taskType]) != nil {
                // A task links to the card it's dropped on.
                let index = path.pointee.item
                guard ids.indices.contains(index) else { return setDropTarget(nil) }
                operation.pointee = .on
                setDropTarget(IndexPath(item: index, section: 0))
                return .link
            }
            setDropTarget(nil)
            guard pasteboard.availableType(from: [DragItem.sessionType]) != nil, info.draggingSource as? NSCollectionView === collectionView else { return [] }
            if operation.pointee == .on { operation.pointee = .before }
            return .move
        }

        @discardableResult
        private func setDropTarget(_ path: IndexPath?) -> NSDragOperation {
            guard dropTarget != path, let grid else { return [] }
            dropTarget = path
            for case let item as CardItem in grid.collection.visibleItems() { refresh(item) }
            return []
        }

        func collectionView(_ collectionView: NSCollectionView, acceptDrop info: NSDraggingInfo, indexPath: IndexPath,
                            dropOperation: NSCollectionView.DropOperation) -> Bool {
            let pasteboard = info.draggingPasteboard
            defer { setDropTarget(nil) }
            if let tasks = pasteboard.pasteboardItems?.compactMap({ $0.string(forType: DragItem.taskType).flatMap(Int.init) }), !tasks.isEmpty {
                guard ids.indices.contains(indexPath.item) else { return false }
                let session = ids[indexPath.item]
                for task in tasks { model.link(task: task, session: session) }
                return true
            }
            guard let id = pasteboard.pasteboardItems?.first?.string(forType: DragItem.sessionType),
                  let from = ids.firstIndex(of: id) else { return false }
            let to = indexPath.item > from ? indexPath.item - 1 : indexPath.item
            guard to != from else { return false }
            // The card moves in place first, so the model's update finds the grid already in order.
            ids.remove(at: from)
            ids.insert(id, at: to)
            Motion.appKit { collectionView.animator().moveItem(at: IndexPath(item: from, section: 0), to: IndexPath(item: to, section: 0)) }
            model.moveSession(id, to: indexPath.item)
            return true
        }

        func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
            dragEnded()
        }

        /// A drag ended, dropped or not: no card stays marked.
        func dragEnded() {
            setDropTarget(nil)
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
            collection.setDraggingSourceOperationMask([], forLocal: false)
            collection.register(GapIndicator.self, forSupplementaryViewOfKind: NSCollectionView.elementKindInterItemGapIndicator,
                                withIdentifier: GapIndicator.id)
            collection.setAccessibilityLabel("Sessions")
            collection.onKey = { [weak self] event in self?.coordinator?.key(event) ?? false }
            collection.onMenu = { [weak self] point in self?.coordinator?.menu(at: point) }
            collection.onDoubleClick = { [weak self] path, onFace in self?.coordinator?.doubleClicked(at: path, onFace: onFace) }
            collection.onFaceClick = { [weak self] path in self?.coordinator?.faceClicked(at: path) }
            collection.onEmptyClick = { [weak self] in self?.coordinator?.model.selectSection(nil) }
            collection.onDragLeft = { [weak self] in self?.coordinator?.dragEnded() }
            addSubview(collection)
        }

        required init?(coder: NSCoder) { fatalError() }

        // The cards fill the view whatever size their layout gave them: cards outside its frame take no clicks.
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            if collection.frame != bounds { collection.frame = bounds }
        }

        override func layout() {
            super.layout()
            if collection.frame != bounds { collection.frame = bounds }
        }

        func layout(width: CGFloat) {
            let columns = CGFloat(SessionGrid.columns(for: width))
            let item = ((width - Metric.cardGap * (columns - 1)) / columns).rounded(.down)
            flow.itemSize = NSSize(width: max(item, 1), height: Metric.card)
            flow.invalidateLayout()
        }
    }

    /// Takes the first click, Return and Space, double-clicks, and asks for each card's menu.
    final class CardCollection: NSCollectionView {
        var onKey: ((NSEvent) -> Bool)?
        var onMenu: ((NSPoint) -> NSMenu?)?
        var onDoubleClick: ((IndexPath, Bool) -> Void)?
        var onFaceClick: ((IndexPath) -> Void)?
        var onEmptyClick: (() -> Void)?
        /// A press on a face: its card and where it started.
        private var facePress: (path: IndexPath, at: NSPoint)?
        /// A drag left the grid or ended, wherever it started.
        var onDragLeft: (() -> Void)?

        /// AppKit sizes a collection view and lays out its cards to its enclosing scroll view, the page's, wider than the
        /// grid: cards past the grid's edge show but take no clicks. The grid has no scroll view, and stays its own size.
        override var enclosingScrollView: NSScrollView? { nil }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(superview?.bounds.size ?? newSize)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
            let face = onFace(path, event)
            if event.clickCount == 2, !face {
                onDoubleClick?(path, false)
                return
            }
            facePress = face ? (path, event.locationInWindow) : nil
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
            guard hypot(event.locationInWindow.x - press.at.x, event.locationInWindow.y - press.at.y) < 4 else { return }
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
        private var shown: (session: SessionItem, now: Date, selected: Bool, dropTarget: Bool, blinking: Bool)?

        func show(_ session: SessionItem, now: Date, selected: Bool, dropTarget: Bool, blinking: Bool, model: AppModel) {
            if let shown, shown.session == session, shown.now == now, shown.selected == selected, shown.dropTarget == dropTarget,
               shown.blinking == blinking { return }
            shown = (session, now, selected, dropTarget, blinking)
            let id = session.id
            host.rootView = AnyView(SessionCard(session: session, now: now, selected: selected, dropTarget: dropTarget, blinking: blinking)
            .accessibilityHidden(true)
            .uiTestAnchor("card:\(id)"))
            guard let card = view as? CardView else { return }
            card.setAccessibilityLabel("\(session.name), \(session.reason ?? session.status.title)" + (session.status.isNew ? ", new" : ""))
            card.selected = selected
            card.press = { [weak model] in model?.open(.session(id)) }
            card.actions = [(session.isRunning ? "Focus" : "Resume", { [weak model] in model?.open(id) })]
        }

    }

    /// The bar that shows where a dragged card lands.
    final class GapIndicator: NSView, NSCollectionViewElement {
        static let id = NSUserInterfaceItemIdentifier("gap")

        override func draw(_ dirtyRect: NSRect) {
            Ink.dropNS.setFill()
            let bar = NSRect(x: bounds.midX - 1.5, y: Space.sm, width: 3, height: bounds.height - Space.md) // grid: ok drawn mark
            NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    /// The card's root: clicks go to the collection view.
    final class CardView: NSView {
        var press: () -> Void = {}
        var actions: [(name: String, run: () -> Void)] = []

        var selected = false

        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .button }
        override func isAccessibilitySelected() -> Bool { selected }
        override func accessibilityPerformPress() -> Bool { press(); return true }
        override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
            actions.map { action in NSAccessibilityCustomAction(name: action.name) { action.run(); return true } }
        }

        override var isFlipped: Bool { true }

        /// The face, at the card's top left inside its padding.
        static var face: NSRect { NSRect(x: Space.md, y: Space.md, width: Metric.faceCard, height: Metric.faceCard) }
        private var pointerArea: NSTrackingArea?

        override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

        // The pointing hand over the face, which SwiftUI can't give: the card takes its clicks.
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
            (Self.face.contains(convert(event.locationInWindow, from: nil)) ? NSCursor.pointingHand : NSCursor.arrow).set()
        }

        /// Over the face, as the pointer sees it.
        var handOverFace: Bool { pointerArea != nil }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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

extension AppModel {
    /// A session's menu; from a task's or a PR's faces, with a new session on it too.
    func faceMenu(_ id: String, task: Int? = nil, pullRequest: GitHubItem? = nil) -> NSMenu? {
        guard let session = session(id) else { return nil }
        return NSHostingMenu(rootView: SessionMenu(session: session, task: task, pullRequest: pullRequest).environment(self))
    }
}

/// A session's menu: a card's context menu, and a click on its face anywhere (DESIGN.md §5, §10).
struct SessionMenu: View {
    let session: SessionItem
    /// From a task's faces: Start Session… on that task.
    var task: Int?
    /// From a PR's face: a session on that PR.
    var pullRequest: GitHubItem?
    @Environment(AppModel.self) private var model

    var body: some View {
        Button(session.isRunning ? "Focus" : "Resume") { model.open(session.id) }
        Button("Show Details") { model.open(.session(session.id)) }
        if let task, let item = model.task(task) {
            Button("Start Another Session on \(item.key)…") { model.beginStart(task: task) }
        }
        if let pullRequest {
            Button("Start Another Session on \(pullRequest.reference)…") { model.beginStart(pullRequest: pullRequest) }
        }
        if session.isRunning, session.tty != nil {
            Divider()
            Button("Close Session") { model.closeSession(session.id) }
        }
        Divider()
        Button("Copy Resume Command") { Pasteboard.copy(session.resumeCommand) }
        Button("Copy Session ID") { Pasteboard.copy(session.id) }
    }
}
