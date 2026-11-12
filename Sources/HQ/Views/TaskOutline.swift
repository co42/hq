import AppKit
import HQKit
import SwiftUI

/// Tasks and the Backlog as one view-based `NSOutlineView` (DESIGN.md §7), with no scroll view of its
/// own: it sits in the page's. Edited like a markdown todo file; rows drag between and into each other.
struct TaskOutline: View {
    let width: CGFloat
    /// In a task's window: that task's subtasks, as the list shows them (2026-11-10). Nil: Tasks and the Backlog.
    var root: Int?
    @State private var rows = OutlineRows()

    // The rows' height is an input: SwiftUI lays the page out again whenever it changes.
    var body: some View {
        OutlineHost(width: width, root: root, rows: rows, height: rows.height)
    }
}

/// The height of an outline's rows, as AppKit last laid them out.
@Observable final class OutlineRows {
    var height: CGFloat = Metric.outlineHeader * 2
}

private struct OutlineHost: NSViewRepresentable {
    let width: CGFloat
    var root: Int?
    let rows: OutlineRows
    let height: CGFloat
    @Environment(AppModel.self) private var model

    func makeCoordinator() -> OutlineCoordinator { OutlineCoordinator(model: model, root: root) }

    func makeNSView(context: Context) -> OutlineContainer {
        let container = OutlineContainer(coordinator: context.coordinator)
        context.coordinator.container = container
        container.onRows = { [weak coordinator = context.coordinator] _ in coordinator?.reportHeight() }
        context.coordinator.onHeight = { [rows] value in if rows.height != value { rows.height = value } }
        context.coordinator.refresh()
        return container
    }

    func updateNSView(_ container: OutlineContainer, context: Context) {
        context.coordinator.model = model
        // A row's menu acts through the outline that shows it: the task's window's over the page's.
        model.showLinkPicker = { id in OutlineCoordinator.owner(of: id)?.showLinkPicker(id) }
        model.showHoldPicker = { id, kind in OutlineCoordinator.owner(of: id)?.showHoldPicker(id, kind) }
        model.foldTasks = { [weak model] ids, mode in
            if let coordinator = ids.first.flatMap(OutlineCoordinator.owner(of:)) { coordinator.fold(ids, mode) } else { for id in ids { model?.setFold(id, mode) } }
        }
        model.filterStory = { [weak model] id in
            if let coordinator = OutlineCoordinator.owner(of: id) { coordinator.toggleFilter(id) }
            else if let model { model.setStoryFilter(id, !model.storyFilter.contains(id)) }
        }
        // Read what the outline shows, so SwiftUI calls this again when it changes.
        _ = (model.tasks, model.sessions, model.search, model.listSearch, model.hideDone, model.allDescriptions, model.shownDescriptions, model.hiddenDescriptions,
             model.backlogOpen, model.folded, model.backlogFilter, model.fold, model.storyFilter, model.editingDescription, model.descriptionEditorHeight, model.seen,
             model.github, model.files, model.artifacts, model.quickAddFocus, model.outlineFocus, model.now, model.labelColors,
             model.sectionFocus, model.selectedSection, model.notices.count, // notices: reminders' marks on rows (T-311)
             model.pendingTaskLink, model.slackMessages)
        context.coordinator.width = width
        context.coordinator.refresh()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: OutlineContainer, context: Context) -> CGSize? {
        CGSize(width: width, height: max(height, nsView.contentHeight))
    }
}

// MARK: Nodes

/// What in the outline has the keyboard.
enum OutlineKeyboard {
    case none, rows, title
}

/// A request for the outline's keyboard, from outside its coordinator.
enum OutlineFocus: Equatable {
    /// The task's row, selected.
    case row(Int)
    /// The title of the task, or of the task `by` rows away.
    case title(Int, by: Int)
    /// The keyboard left the task's description for elsewhere.
    case left(Int)

    var task: Int {
        switch self {
        case .row(let id), .title(let id, _), .left(let id): id
        }
    }
}

/// One row of the outline. Classes, so the outline keeps their identity across updates.
final class OutlineNode: NSObject {
    enum Kind: Hashable {
        case header(TaskList)
        case task(Int)
        case quickAdd(TaskList)
        case empty(TaskList)
    }

    let kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
    }

    var task: Int? { if case .task(let id) = kind { id } else { nil } }

    /// Header, filter and empty rows span both columns.
    var spans: Bool {
        switch kind {
        case .header, .empty: true
        case .task, .quickAdd: false
        }
    }
}

/// What the outline shows: children per parent, after search, Hide Done and the Backlog's filter.
struct OutlineSnapshot: Equatable {
    var children: [OutlineNode.Kind?: [OutlineNode.Kind]] = [:]
    /// It shows at least one task.
    var hasTasks: Bool { children.values.contains { $0.contains { if case .task = $0 { true } else { false } } } }
    /// Tasks with subtasks shown: the outline keeps them open.
    var expandable: Set<Int> = []
    /// Tasks with subtasks, shown or folded: their chevron shows.
    var foldable: Set<Int> = []
    /// Top-level tasks with subtasks: their card has the story's filter button (2026-11-12).
    var filterable: Set<Int> = []

    /// What a list's searches look for: the toolbar's and the list's own.
    static func searchWords(_ model: AppModel, _ list: TaskList) -> [String] {
        [model.search, model.listSearch[list] ?? ""].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// While a search runs: the tasks whose title (or key) has every word, and their parents. Nil without a search.
    /// Kept per tasks' version and words: the headers and the outline ask several times per keystroke.
    static func found(_ model: AppModel, in list: TaskList) -> Set<Int>? {
        let words = searchWords(model, list)
        guard !words.isEmpty else { return nil }
        let key = "\(list.rawValue)\u{1}\(model.tasksVersion)\u{1}\(words.joined(separator: "\u{1}"))"
        if let cached = model.foundCache[list], cached.key == key { return cached.found }
        let tree = model.taskTree
        var shown = Set<Int>()
        for top in tree.top(list) {
            for id in tree.subtree(of: top) {
                guard let task = model.task(id), words.allSatisfy({ word in
                    task.title.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                        || task.key.range(of: word, options: .caseInsensitive) != nil
                }) else { continue }
                shown.insert(id)
                shown.formUnion(tree.ancestors(of: id))
            }
        }
        model.foundCache[list] = (key, shown)
        return shown
    }

    /// The top-level tasks of a list that the searches, Hide Done and the Backlog's filter show.
    static func matches(_ model: AppModel, in list: TaskList, found: Set<Int>?? = nil) -> [Int] {
        let tree = model.taskTree
        let found = found ?? Self.found(model, in: list)
        let hide = model.hideDone.contains(list)
        let top = tree.top(list).filter { id in (found?.contains(id) ?? true) && !(hide && model.task(id)?.status == .done) }
        guard list == .backlog else { return top }
        let filter = model.backlogFilter
        return top.filter { id in tree.subtree(of: id).contains { model.task($0).map(filter.matches) ?? false } }
    }

    /// `root`: that task's subtasks only, all of them, for its window.
    static func make(_ model: AppModel, root: Int? = nil) -> OutlineSnapshot {
        var snapshot = OutlineSnapshot()
        let tree = model.taskTree
        let flow = model.taskFlow
        /// A task's shown subtasks: Hide Done of its list hides the done ones, a search the ones it didn't find, its story's
        /// filter the ones it doesn't keep; then its chevron shows them or not. A search shows all it found.
        func add(_ id: Int, hiding: Bool, found: Set<Int>?, only: Set<Int>?) {
            let children = tree.children(of: id).filter { child in
                !(hiding && model.task(child)?.status == .done) && (found?.contains(child) ?? true) && (only?.contains(child) ?? true)
            }
            guard !children.isEmpty else { return }
            snapshot.foldable.insert(id)
            guard found != nil || model.fold[id] != .hidden else { return }
            snapshot.expandable.insert(id)
            snapshot.children[.task(id)] = children.map { .task($0) }
            children.forEach { add($0, hiding: hiding, found: found, only: only) }
        }
        /// A top-level task: its filter, on, keeps only its tree's Blocked and doing tasks.
        func story(_ id: Int, hiding: Bool, found: Set<Int>?) {
            if !tree.children(of: id).isEmpty { snapshot.filterable.insert(id) }
            add(id, hiding: hiding, found: found, only: model.storyFilter.contains(id) ? flow.blockedOrDoing(under: id, in: tree) : nil)
        }
        if let root {
            let kids = tree.children(of: root)
            kids.forEach { add($0, hiding: false, found: nil, only: nil) }
            snapshot.children[nil] = kids.map { .task($0) }
            return snapshot
        }
        snapshot.children[nil] = [.header(.overview), .header(.backlog)]
        let foundTasks = found(model, in: .overview)
        let tasks = model.folded.contains(.tasks) ? [] : matches(model, in: .overview, found: foundTasks)
        tasks.forEach { story($0, hiding: model.hideDone.contains(.overview), found: foundTasks) }
        var overview = tasks.map { OutlineNode.Kind.task($0) }
        if !model.folded.contains(.tasks) {
            if tasks.isEmpty { overview.append(.empty(.overview)) }
            overview.append(.quickAdd(.overview))
        }
        snapshot.children[.header(.overview)] = overview
        if model.backlogOpen {
            let foundLater = found(model, in: .backlog)
            let backlog = matches(model, in: .backlog, found: foundLater)
            backlog.forEach { story($0, hiding: model.hideDone.contains(.backlog), found: foundLater) }
            snapshot.children[.header(.backlog)] = backlog.map { .task($0) } + [.quickAdd(.backlog)]
        } else {
            snapshot.children[.header(.backlog)] = []
        }
        return snapshot
    }

    func children(of parent: OutlineNode.Kind?) -> [OutlineNode.Kind] { children[parent] ?? [] }
}

/// Where each task's card sits: a top-level task's big card, a block's tray when its subtasks show, and the space above
/// each card: from the card before, the trays that close above it, and its own tray's padding. A subtask's card sits a
/// level in from its parent's, but a story's own subtasks, under its big card (2026-11-10).
struct OutlinePlan: Equatable {
    /// A card's or a tray's edges: in from the outline's left, and in from the cards' right.
    struct Edges: Equatable {
        var left: CGFloat = 0
        var right: CGFloat = 0
    }

    var gaps: [Int: CGFloat] = [:]
    /// 0 for a top-level task.
    var depth: [Int: Int] = [:]
    /// Tasks whose subtasks show: each heads a tray.
    var blocks: Set<Int> = []
    var cards: [Int: Edges] = [:]
    var trays: [Int: Edges] = [:]
    /// Blocks whose header sits on its tray's edges, as its sibling cards do (a story's big card sits inside its tray).
    var flush: Set<Int> = []
    /// After a list's last task, the trays that close.
    var trailing: [TaskList: CGFloat] = [:]

    init() {}

    init(_ snapshot: OutlineSnapshot) {
        // A task's window: its subtasks at the top, as subtask cards; else each list's tasks, as stories.
        func tasks(_ kinds: [OutlineNode.Kind]) -> [Int] { kinds.compactMap { kind -> Int? in if case .task(let id) = kind { id } else { nil } } }
        let scoped = tasks(snapshot.children(of: nil))
        let scopes: [(list: TaskList, tops: [Int], depth: Int)] = scoped.isEmpty
            ? TaskList.allCases.map { ($0, tasks(snapshot.children(of: .header($0))), 0) } : [(.overview, scoped, 1)]
        for (list, tops, top) in scopes {
            var pending: CGFloat = 0
            var first = true
            func visit(_ id: Int, depth: Int, slot: Edges) {
                let kids = snapshot.children(of: .task(id)).compactMap { kind -> Int? in if case .task(let kid) = kind { kid } else { nil } }
                let block = !kids.isEmpty
                let pad = depth == 0 ? Metric.storyTrayPadding : Metric.trayPadding
                var gap = first ? 0 : depth == 0 ? Metric.storyGap : Metric.taskGap
                first = false
                gap += pending
                pending = 0
                // Below a story, a block's header lines up with its siblings, on its tray's edges; its subtasks sit the tray's padding inside it.
                let nested = depth > top
                if block && !nested { gap += pad }
                gaps[id] = gap
                self.depth[id] = depth
                guard block else {
                    cards[id] = slot
                    return
                }
                blocks.insert(id)
                trays[id] = slot
                if nested { flush.insert(id) }
                cards[id] = nested ? slot : Edges(left: slot.left + pad, right: slot.right + pad)
                let indent = depth == 0 ? 0 : Metric.subtaskIndent
                for kid in kids { visit(kid, depth: depth + 1, slot: Edges(left: slot.left + pad + indent, right: slot.right + pad)) }
                pending += pad
            }
            for id in tops { visit(id, depth: top, slot: Edges()) }
            trailing[list] = pending
        }
    }

    /// A task's card edges.
    func card(of id: Int) -> Edges { cards[id] ?? Edges() }

    /// A block's tray edges.
    func tray(of id: Int) -> Edges { trays[id] ?? Edges() }
}

// MARK: Container

/// Holds the outline; its height goes to SwiftUI through the coordinator.
final class OutlineContainer: NSView {
    let outline = TaskOutlineView()

    init(coordinator: OutlineCoordinator) {
        super.init(frame: .zero)
        let faces = NSTableColumn(identifier: OutlineCoordinator.facesColumn)
        faces.width = Metric.facesColumn
        faces.minWidth = faces.width
        faces.maxWidth = faces.width
        faces.resizingMask = []
        let main = NSTableColumn(identifier: OutlineCoordinator.mainColumn)
        main.resizingMask = .autoresizingMask
        outline.addTableColumn(faces)
        outline.addTableColumn(main)
        outline.outlineTableColumn = main
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.headerView = nil
        outline.style = .plain
        outline.backgroundColor = .clear
        outline.intercellSpacing = .zero
        outline.indentationPerLevel = Metric.subtaskIndent
        outline.indentationMarkerFollowsCell = true
        outline.autoresizesOutlineColumn = false
        outline.floatsGroupRows = false
        // One task at a time for now (2026-11-10): moving several at once is for a later version.
        outline.allowsMultipleSelection = false
        outline.allowsEmptySelection = true
        outline.selectionHighlightStyle = .regular
        outline.focusRingType = .none
        outline.usesAutomaticRowHeights = false
        outline.registerForDraggedTypes([DragItem.taskType, DragItem.itemType])
        outline.setDraggingSourceOperationMask([.move, .link], forLocal: true)
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)
        // The cards hold still under a drag: a line shows where it lands, a ring the card it drops onto (2026-11-10).
        outline.draggingDestinationFeedbackStyle = .none
        outline.setAccessibilityLabel("Tasks and Backlog")
        outline.dataSource = coordinator
        outline.delegate = coordinator
        outline.coordinator = coordinator
        outline.target = coordinator
        outline.doubleAction = #selector(OutlineCoordinator.doubleClicked(_:))
        addSubview(outline)
    }

    required init?(coder: NSCoder) { fatalError() }

    // AppKit reads it off the main thread while a drag of several items starts.
    nonisolated override var isFlipped: Bool { true }

    // The outline fills the container: rows outside its frame take no clicks.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fill()
    }

    override func layout() {
        super.layout()
        fill()
    }

    func fill() {
        if outline.frame != bounds { outline.frame = bounds }
    }

    /// The rows' height, whatever the frame is now.
    var contentHeight: CGFloat {
        let rows = outline.numberOfRows
        return rows == 0 ? 0 : outline.rect(ofRow: rows - 1).maxY
    }

    /// The page sizes the container from its rows: told the moment AppKit lays them out (`tile`).
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: contentHeight) }
    private var reported: CGFloat = -1
    var onRows: (CGFloat) -> Void = { _ in }

    func rowsLaidOut() {
        let height = contentHeight
        guard height != reported else { return }
        reported = height
        invalidateIntrinsicContentSize()
        onRows(height)
    }
}

/// The outline: top-level tasks sit at the headers' level, titles edit on one click, and the
/// keys a row's title field doesn't take go to the coordinator.
final class TaskOutlineView: NSOutlineView {
    weak var coordinator: OutlineCoordinator?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }


    /// Where a list's cards end: at the section's edge, as the other sections' cards (no lines, 2026-11-10).
    var cardsRight: CGFloat { bounds.width }

    /// A task's card, in the outline's coordinates: under the row's gap, its edges from the plan.
    func cardFrame(ofRow row: Int) -> NSRect? {
        guard let id = (item(atRow: row) as? OutlineNode)?.task, let coordinator else { return nil }
        let rect = rect(ofRow: row)
        let edges = coordinator.plan.card(of: id)
        let top = rect.minY + coordinator.gap(of: id)
        return NSRect(x: edges.left, y: top, width: max(cardsRight - edges.left - edges.right, 0), height: max(rect.maxY - top, 0))
    }

    /// The new task's card, at the bottom of its line: where a top-level task's card would be, one line tall.
    func newTaskCard(ofRow row: Int) -> NSRect? {
        guard let node = item(atRow: row) as? OutlineNode, case .quickAdd = node.kind else { return nil }
        let rect = rect(ofRow: row)
        return NSRect(x: 0, y: rect.maxY - Metric.outlineQuick, width: max(cardsRight, 0), height: Metric.outlineQuick)
    }

    /// The padding left and right inside a task's card.
    func cardPadding(ofRow row: Int) -> CGFloat {
        guard let id = (item(atRow: row) as? OutlineNode)?.task, let coordinator else { return Metric.cardPadding }
        return coordinator.padding(of: id)
    }

    /// Where a card's first line sits, from its top.
    func lineTop(ofRow row: Int) -> CGFloat {
        guard let id = (item(atRow: row) as? OutlineNode)?.task, let coordinator else { return 0 }
        return TaskCell.lineTop(big: coordinator.isBig(id))
    }

    /// The face, in its slot at the card's left, before the status glyph (2026-11-10).
    func faceFrame(ofRow row: Int) -> NSRect? {
        guard let card = cardFrame(ofRow: row) else { return nil }
        return NSRect(x: card.minX + cardPadding(ofRow: row), y: card.minY, width: Metric.faceRow, height: card.height)
    }

    /// A task's cells sit in its card: the title's cell over all of it, the face's in its slot at the left.
    /// Headers, the filter bar and empty lines span the row, flush with the page.
    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        let frame = super.frameOfCell(atColumn: column, row: row)
        guard let node = item(atRow: row) as? OutlineNode else { return frame }
        if node.spans { return NSRect(x: 0, y: frame.minY, width: bounds.width, height: frame.height) }
        guard let card = cardFrame(ofRow: row) else {
            // The new task's card: its plus where a top-level task's glyph sits, its field where the title does.
            if column == 0 { return .zero }
            let x = Metric.storyTrayPadding + Metric.cardPadding
            return NSRect(x: x, y: frame.minY, width: max(cardsRight - 2 * x, 0), height: frame.height)
        }
        if column == 0, let face = faceFrame(ofRow: row) { return NSRect(x: face.minX, y: frame.minY, width: face.width, height: frame.height) }
        let pad = cardPadding(ofRow: row)
        return NSRect(x: card.minX + pad, y: frame.minY, width: max(card.width - 2 * pad, 0), height: frame.height)
    }

    /// Tasks and the Backlog each sit on a raised card, from the row under their header to their last row: layers under
    /// the rows, so a scroll redraws nothing (T-337).
    private lazy var cards: CardsView = {
        let view = CardsView()
        addSubview(view, positioned: .below, relativeTo: nil)
        return view
    }()

    /// The selection's ring and the fade follow the window becoming key or not.
    private var keyObservers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyObservers.forEach(NotificationCenter.default.removeObserver)
        keyObservers = []
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            keyObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.placeCards() }
            })
        }
    }

    override func tile() {
        super.tile()
        (superview as? OutlineContainer)?.rowsLaidOut()
        placeCards()
    }

    /// Its container sets its frame: AppKit, which sees the page's scroll view above, sizes it to its rows otherwise.
    override func setFrameSize(_ newSize: NSSize) {
        if let container = superview as? OutlineContainer, newSize != container.bounds.size { return super.setFrameSize(container.bounds.size) }
        super.setFrameSize(newSize)
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(superview is OutlineContainer ? .zero : newOrigin)
    }

    override func layout() {
        super.layout()
        placeCards()
    }

    /// A task starts to fold or unfold: for as long as AppKit slides the rows, the cards and trays slide with them.
    func slideCards() { slidingUntil = .now.addingTimeInterval(Motion.rowsSeconds) }
    private var slidingUntil = Date.distantPast

    /// The cards and trays where the rows are; `animated` as a task folds or unfolds, so they slide with the rows.
    func placeCards(animated: Bool = false) {
        let animated = animated || Date.now < slidingUntil
        if cards.frame != bounds { cards.frame = bounds }
        if subviews.first !== cards { addSubview(cards, positioned: .below, relativeTo: nil) }
        let lit = coordinator?.lit()
        self.lit = lit
        cards.show(storyShapes(lit: lit), animated: animated)
        // Each row's highlight fills its card; unrelated rows fade with their cards.
        // A row's cells come from its row view: asking the outline for a row mid-move throws (T-372, a task moved by keys).
        enumerateAvailableRowViews { rowView, row in
            guard let rowView = rowView as? OutlineRowView else { return }
            guard row >= 0, row < numberOfRows else {
                if !Self.staleRowLogged { AppLog.write("outline: row \(row) of \(numberOfRows) placed while the rows change; skipped", to: "outline.log") }
                Self.staleRowLogged = true
                return
            }
            let task = (item(atRow: row) as? OutlineNode)?.task
            let alpha: CGFloat = task.map { lit?.contains($0) == false } == true ? Motion.dimmedOpacity : 1
            if rowView.alphaValue != alpha {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Motion.appearSeconds
                    rowView.animator().alphaValue = alpha
                }
            }
            let card = cardFrame(ofRow: row).map { rowView.convert($0, from: self) }
            if rowView.card != card { rowView.card = card }
            // The face's column keeps its width as the outline resizes, so AppKit leaves its cell where it was.
            if let faces = rowView.view(atColumn: 0) as? FacesCell {
                let frame = rowView.convert(frameOfCell(atColumn: 0, row: row), from: self)
                if faces.frame != frame { faces.frame = frame }
            }
            // The card's cell is placed here, with its card: the plan (edges, padding) changes without AppKit laying the row out.
            if let cell = rowView.view(atColumn: 1) as? TaskCell {
                let frame = rowView.convert(frameOfCell(atColumn: 1, row: row), from: self)
                if cell.frame != frame { cell.frame = frame }
            }
        }
    }

    /// The cards' layers, for the UI test.
    var cardsView: CardsView { cards }
    /// A row placed while the rows change was logged once.
    static var staleRowLogged = false
    /// The tasks the selection lights, as the cards were last placed: a row made while scrolling fades as its card.
    private(set) var lit: Set<Int>?

    /// The rows have the keyboard: a selected card's ring is the accent.
    var hasKeyboard: Bool {
        guard let window, window.isKeyWindow else { return false }
        return (window.firstResponder as? NSView).map { $0 === self || $0.isDescendant(of: self) } ?? false
    }

    /// The last row under a task's: its open subtasks', at any depth.
    func lastRow(under row: Int) -> Int {
        let level = level(forRow: row)
        var last = row
        while last + 1 < numberOfRows, self.level(forRow: last + 1) > level { last += 1 }
        return last
    }

    /// A block's tray, then a card for each task: the top-level ones big, a block's header on its tray alone.
    /// `lit`: the tasks related to the selected ones; the others fade (nil: nothing selected).
    private func storyShapes(lit: Set<Int>?) -> [CardShape] {
        guard let coordinator else { return [] }
        let flow = coordinator.model.taskFlow
        let selected = Set(selectedRowIndexes)
        let keyboard = hasKeyboard
        var trays: [CardShape] = []
        var cards: [CardShape] = []
        for row in 0..<numberOfRows {
            // The new task's line is a card too: dashed until typed in, then a raised card with its ring; never dimmed (2026-11-10).
            if let node = item(atRow: row) as? OutlineNode, case .quickAdd(let list) = node.kind, let card = newTaskCard(ofRow: row) {
                let typing = ((window?.firstResponder as? NSTextView)?.delegate as? QuickAddField)?.list == list
                cards.append(CardShape(rect: card, radius: Radius.row + 4, kind: typing ? .card : .newTask, ring: typing ? .selected : nil,
                                       key: "new:\(list)"))
                continue
            }
            guard let id = (item(atRow: row) as? OutlineNode)?.task, let card = cardFrame(ofRow: row) else { continue }
            // A Blocked card's red edge, a selected one's accent ring; no yellow edge for doing (2026-11-10).
            let ring: CardShape.Ring? = dropOnto == id ? .drop : selected.contains(row) && keyboard ? .selected : flow.state(id) == .blocked ? .blocked : nil
            let top = coordinator.plan.depth[id] == 0
            if coordinator.plan.blocks.contains(id) {
                let pad = top ? Metric.storyTrayPadding : Metric.trayPadding
                let edges = coordinator.plan.tray(of: id)
                // Under its last row, the trays that close there inside it, then its own padding.
                let last = lastRow(under: row)
                var bottom = rect(ofRow: last).maxY + pad
                var inner = (item(atRow: last) as? OutlineNode)?.task.flatMap(coordinator.model.taskTree.parent(of:))
                while let block = inner, block != id {
                    if coordinator.plan.blocks.contains(block) { bottom += coordinator.plan.depth[block] == 0 ? Metric.storyTrayPadding : Metric.trayPadding }
                    inner = coordinator.model.taskTree.parent(of: block)
                }
                let above = coordinator.plan.flush.contains(id) ? 0 : pad
                let tray = NSRect(x: edges.left, y: card.minY - above, width: max(cardsRight - edges.left - edges.right, 0), height: bottom - card.minY + above)
                trays.append(CardShape(rect: tray, radius: top ? Radius.card : Radius.row + 2, kind: .tray, key: "tray:\(id)"))
                // A block's header sits on its tray, but a story's big card; selected, its header gets the ring too.
                guard top || ring == .selected || ring == .drop || ring == .blocked else { continue }
                cards.append(CardShape(rect: coordinator.plan.flush.contains(id) ? card.insetBy(dx: 2, dy: 2) : card, radius: top ? Radius.row + 4 : Radius.row, kind: top ? .card : .flat, ring: ring, key: "card:\(id)"))
            } else {
                cards.append(CardShape(rect: card, radius: top ? Radius.row + 4 : Radius.row, kind: flow.state(id) == .done ? .flat : .card, ring: ring,
                                       key: "card:\(id)"))
            }
        }
        return trays + cards
    }

    /// No AppKit disclosure: a task with subtasks stays open, its card's chevron folds it to the subtasks that matter.
    override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }

    /// One row at a time (2026-11-10): AppKit takes several from code even so, so a selection made anywhere keeps its first.
    override func selectRowIndexes(_ indexes: IndexSet, byExtendingSelection extend: Bool) {
        guard !allowsMultipleSelection, indexes.count > 1 || (extend && !indexes.isEmpty) else {
            return super.selectRowIndexes(indexes, byExtendingSelection: extend)
        }
        super.selectRowIndexes(indexes.first.map { IndexSet(integer: $0) } ?? [], byExtendingSelection: false)
    }

    /// A click on a title selects its row; a double-click edits it.
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        // A press on an idle title goes to the row, so the row selects and drags from it.
        if let title = responder as? TitleField { return title.currentEditor() != nil || event?.type != .leftMouseDown }
        if responder is NSTextField { return true }
        return super.validateProposedFirstResponder(responder, for: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        // Anywhere on the new task's card types in it.
        if row >= 0, newTaskCard(ofRow: row)?.contains(point) == true, let cell = view(atColumn: 1, row: row, makeIfNecessary: false) as? QuickAddCell {
            window?.makeFirstResponder(cell.field)
            return takeRelease()
        }
        // The status glyph, the type icon and the faces take their clicks: the table would only select the row.
        // ⌥ goes through too: ⌥-click on the status picks one.
        if row >= 0, event.modifierFlags.intersection([.shift, .control, .command]).isEmpty {
            if event.clickCount == 1, let button = (view(atColumn: 1, row: row, makeIfNecessary: false) as? TaskCell)?.button(at: event.locationInWindow) {
                button.mouseDown(with: event)
                return
            }
            if let faces = view(atColumn: 0, row: row, makeIfNecessary: false) as? FacesCell, faces.click(event) { return takeRelease() }
            // A task it's blocked by: a click shows it, selected; behind "+2", a menu to pick one.
            if event.clickCount == 1, let ids = (view(atColumn: 1, row: row, makeIfNecessary: false) as? TaskCell)?.blockers(at: event.locationInWindow),
               let coordinator {
                if ids.count == 1, let id = ids.first {
                    coordinator.reveal(id)
                } else {
                    let menu = NSMenu()
                    for id in ids {
                        let item = NSMenuItem(cutting: "T-\(id) " + (coordinator.model.task(id)?.title ?? ""), action: #selector(pickLink(_:)))
                        item.target = self
                        item.representedObject = DropChoice { [weak coordinator] in coordinator?.reveal(id) }
                        menu.addItem(item)
                    }
                    FaceMenu.show(menu, "blockers:\(ids.map(String.init).joined(separator: ","))", NSPoint(x: point.x, y: point.y + Space.md), self)
                }
                return takeRelease()
            }
            // A link on the card opens on the press; several of a kind, a menu to pick one.
            if event.clickCount == 1, let (routes, task) = links(at: event), let model = coordinator?.model {
                if routes.count == 1, let route = routes.first {
                    model.open(route)
                } else {
                    FaceMenu.show(pickMenu(routes), Self.linksKey(routes, task: task), NSPoint(x: point.x, y: point.y + Space.md), self)
                }
                return takeRelease()
            }
        }
        let title = row >= 0 ? (view(atColumn: 1, row: row, makeIfNecessary: false) as? TaskCell)?.title : nil
        let onIdleTitle = title.map { $0.currentEditor() == nil && $0.bounds.contains($0.convert(event.locationInWindow, from: nil)) } ?? false
        // The second click of a double-click on a title edits it, caret where it landed.
        if onIdleTitle, event.clickCount == 2, event.modifierFlags.intersection([.command, .shift]).isEmpty, let id = title?.task {
            coordinator?.beginEditing(id, at: event.locationInWindow)
            return takeRelease()
        }
        super.mouseDown(with: event)
    }

    /// ⌘C, Edit › Copy: the selected tasks' lines (T-358).
    @objc func copy(_ sender: Any?) {
        let tasks = selectedRowIndexes.compactMap { (item(atRow: $0) as? OutlineNode)?.task }
        coordinator?.model.copy(tasks.map { .task($0) })
    }

    override func keyDown(with event: NSEvent) {
        if coordinator?.key(event) != true { super.keyDown(with: event) }
    }

    /// The rows' keys come before the menu bar's, so they never depend on its state.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, coordinator?.key(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if let menu = linkMenu(at: event) { return menu }
        return coordinator?.menu(forRow: row)
    }

    /// A right-click on a link on a card: its menu, where the click was.
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = linkMenu(at: event), let (routes, task) = links(at: event) else { return super.rightMouseDown(with: event) }
        FaceMenu.show(menu, Self.linksKey(routes, task: task), convert(event.locationInWindow, from: nil), self)
    }

    /// What a link's menu is shown for: the link on its task, or the kind's links.
    static func linksKey(_ routes: [ModalRoute], task: Int) -> String {
        routes.count == 1 ? routes[0].chipKey(task: task) : "links:\(task):" + routes.map(\.selectionKey).joined(separator: ",")
    }

    /// The menu of the link under the event: one link's own, or several to pick from.
    private func linkMenu(at event: NSEvent) -> NSMenu? {
        guard let (routes, task) = links(at: event), let model = coordinator?.model, let first = routes.first else { return nil }
        return routes.count == 1 ? model.linkMenu(first, task: task) : pickMenu(routes)
    }

    /// The links under the event on a card, and their task.
    private func links(at event: NSEvent) -> (routes: [ModalRoute], task: Int)? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        return (view(atColumn: 1, row: row, makeIfNecessary: false) as? TaskCell)?.links(at: event.locationInWindow)
    }

    /// Several links of a kind on a card: a menu of them; a pick opens it.
    private func pickMenu(_ routes: [ModalRoute]) -> NSMenu {
        let menu = NSMenu()
        guard let model = coordinator?.model else { return menu }
        for route in routes {
            let item = NSMenuItem(cutting: model.title(of: route), middle: route.isWeb, action: #selector(pickLink(_:)))
            item.target = self
            item.representedObject = DropChoice { model.open(route) }
            menu.addItem(item)
        }
        return menu
    }

    @objc private func pickLink(_ item: NSMenuItem) { (item.representedObject as? DropChoice)?.run() }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        // AppKit also gives it the keyboard mid-change, removing the row whose title had it: the rows are placed after.
        if accepted { DispatchQueue.main.async { [weak self] in self?.coordinator?.keyboardChanged() } }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { DispatchQueue.main.async { [weak self] in self?.coordinator?.keyboardChanged() } }
        return resigned
    }

    /// A dragged task's image: its card alone, as it looks (2026-11-10), not its row with the gap and tray around it.
    func cardImage(ofRow row: Int) -> NSImage? {
        guard let card = cardFrame(ofRow: row), card.width > 0, card.height > 0 else { return nil }
        let cells = [view(atColumn: 0, row: row, makeIfNecessary: false), view(atColumn: 1, row: row, makeIfNecessary: false)].compactMap { $0 }
        let shots = cells.compactMap { cell -> (NSRect, NSBitmapImageRep)? in
            guard let rep = cell.bitmapImageRepForCachingDisplay(in: cell.bounds) else { return nil }
            cell.cacheDisplay(in: cell.bounds, to: rep)
            return (convert(cell.bounds, from: cell), rep)
        }
        let id = (item(atRow: row) as? OutlineNode)?.task
        let radius = id.flatMap { coordinator?.plan.depth[$0] } == 0 ? Radius.row + 4 : Radius.row
        let appearance = effectiveAppearance
        return NSImage(size: card.size, flipped: true) { bounds in
            appearance.performAsCurrentDrawingAppearance {
                let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
                Ink.surfaceNS.setFill()
                shape.fill()
                Ink.cardHairlineNS.setStroke()
                shape.stroke()
                shape.addClip()
                for (frame, rep) in shots {
                    rep.draw(in: frame.offsetBy(dx: -card.minX, dy: -card.minY), from: .zero, operation: .sourceOver, fraction: 1,
                             respectFlipped: true, hints: nil)
                }
            }
            return true
        }
    }

    /// While a task is dragged over the rows: the card it would drop onto, ringed; the cards hold still (2026-11-10).
    var dropOnto: Int? { didSet { if dropOnto != oldValue { placeCards() } } }

    /// The line where a dragged task would land between cards; nil hides it.
    func showDropLine(_ rect: NSRect?) { cards.showDropLine(rect) }

    func clearDrop() {
        dropOnto = nil
        cards.showDropLine(nil)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
        clearDrop()
    }
}

// MARK: Coordinator

final class OutlineCoordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate {
    static let facesColumn = NSUserInterfaceItemIdentifier("faces")
    static let mainColumn = NSUserInterfaceItemIdentifier("main")
    /// One face per row (2026-11-05).
    static let faces = 1

    var model: AppModel
    /// In a task's window: that task, whose subtasks it shows. Nil: the page's Tasks and Backlog.
    let root: Int?
    weak var container: OutlineContainer?

    struct Live { weak var coordinator: OutlineCoordinator? }
    /// The outlines on screen: a row's menu and keys act through the one that shows it.
    static var live: [Live] = []

    /// The outline the user works in: a task window's while it's the window open, the page's when no window is over it.
    var inFront: Bool {
        if let root { return model.modal == .task(root) }
        return model.modal == nil
    }

    /// The outline that shows a task: a task's window's, while open, over the page's.
    static func owner(of id: Int) -> OutlineCoordinator? {
        live.removeAll { $0.coordinator == nil }
        let shown = live.compactMap(\.coordinator).filter { $0.outline?.window != nil }
        return shown.first { $0.root != nil && $0.row(of: id) >= 0 } ?? shown.first { $0.root == nil }
    }
    var onHeight: (CGFloat) -> Void = { _ in }
    /// The heights reported so far: a container check judges only the last one.
    private var reports = 0
    /// The zoom it was made at: the page and a task's window are made again at another (`.id(model.zoom)`).
    private let zoom = Zoom.factor
    var width: CGFloat = 0 { didSet { if width != oldValue { heights.removeAll(); remeasure = true } } }
    private var outline: TaskOutlineView? { container?.outline }
    private(set) var snapshot = OutlineSnapshot() { didSet { replan() } }
    /// Where each task's card sits: made again when the rows or what's open change.
    private(set) var plan = OutlinePlan()

    /// A top-level task: its big card.
    func isBig(_ id: Int) -> Bool { plan.depth[id] == 0 }

    /// The padding left and right inside a task's card: one for every card; a top-level task with no tray of its own
    /// takes a story's tray too, so every story's glyph, title and end line up (2026-11-10).
    func padding(of id: Int) -> CGFloat {
        Metric.cardPadding + (plan.depth[id] == 0 && !plan.blocks.contains(id) ? Metric.storyTrayPadding : 0)
    }

    /// The longest key among the tasks: the width of every card's key column.
    var longestKey: String { "T-\(model.tasks.lazy.map(\.id).max() ?? 0)" }

    /// While a task is selected: it, its parents and subtasks, what blocks it and what it blocks, what it comes after and
    /// what comes after it; the rest fades. Nil, nothing fades, unless it has such a link and the outline has the keyboard
    /// in the key window: the fade shows those links and nothing else (2026-11-11).
    func lit() -> Set<Int>? {
        let selected = selectedIDs
        guard !selected.isEmpty, outline?.hasKeyboard == true else { return nil }
        var linked = false
        let tree = model.taskTree
        let flow = model.taskFlow
        var lit = Set<Int>()
        for id in selected {
            lit.formUnion(tree.subtree(of: id))
            lit.formUnion(tree.ancestors(of: id))
            guard let task = model.task(id) else { continue }
            let links = task.blockedBy + task.after + flow.dependents(of: id, .blockedBy) + flow.dependents(of: id, .after)
            if !links.isEmpty { linked = true }
            lit.formUnion(links)
        }
        return linked ? lit : nil
    }
    private var nodes: [OutlineNode.Kind: OutlineNode] = [:]
    /// Headers, the filter bar and empty lines: kept, so scrolling back to them doesn't rebuild their SwiftUI views.
    private var hostCells: [OutlineNode.Kind: HostCell] = [:]
    /// Description heights by task, for the current width and text.
    private var heights: [Int: (key: Int, height: CGFloat)] = [:]
    private var remeasure = false
    private var refreshing = false
    /// The row whose title takes the keyboard after the next update, and where its caret goes.
    private var pendingEdit: (id: Int, caretAtEnd: Bool)?
    /// Where the caret goes in that title, when not at its end.
    private var pendingCaret: Int?
    /// A task whose row moved while its title was edited: kept, even empty, until the title is edited again.
    private var reEditing: Int?
    private var mermaidObserver: NSObjectProtocol?
    private var clickMonitor: Any?
    /// The rows selected when Tab left the tasks.
    private var parked: [Int] = []
    /// The completion list is opening, or the last key deleted: no new list.
    private var completing = false
    private var deleting = false

    init(model: AppModel, root: Int? = nil) {
        self.model = model
        self.root = root
        super.init()
        Self.live.append(Live(coordinator: self))
        mermaidObserver = NotificationCenter.default.addObserver(forName: .mermaidDidRender, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.descriptionsChanged() }
        }
        // Before the description's own views take the click.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.descriptionClick(event) ?? event
        }
    }

    isolated deinit {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let mermaidObserver { NotificationCenter.default.removeObserver(mermaidObserver) }
    }

    /// Link… on a row: the link picker in a popover under the task's title, the row selected.
    func showLinkPicker(_ id: Int) {
        showPicker(id) { [model] popover in AnyView(LinkPicker(task: id) { [weak popover] in popover?.close() }.environment(model).handCursors()) }
    }

    /// Block…, Blocked By… or After… on a row: their picker in a popover under the task's title, the row selected.
    func showHoldPicker(_ id: Int, _ kind: HoldPicker.Kind) {
        showPicker(id) { [model] popover in
            AnyView(HoldPicker(task: id, kind: kind) { [weak popover] in popover?.close() }.environment(model).handCursors())
        }
    }

    /// A picker in a popover under a task's title, its row selected and brought into view.
    private func showPicker(_ id: Int, _ content: @escaping (NSPopover) -> AnyView) {
        guard let outline else { return }
        let row = outline.row(forItem: node(.task(id)))
        guard row >= 0 else { return }
        outline.selectRowIndexes([row], byExtendingSelection: false)
        // The page scrolls, not the outline: the row comes into view clear of the toolbar, or the popover has nothing to show under.
        outline.scrollToVisible(outline.rect(ofRow: row).insetBy(dx: 0, dy: -Metric.outlineRow * 3))
        // Shown once the page has laid the row out where it scrolled, under the row the task has then.
        DispatchQueue.main.async { [weak self] in
            guard let self, let outline = self.outline else { return }
            let row = outline.row(forItem: self.node(.task(id)))
            guard row >= 0 else { return }
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentViewController = NSHostingController(rootView: content(popover))
            if let anchor = (outline.view(atColumn: 1, row: row, makeIfNecessary: false) as? TaskCell)?.title, anchor.window != nil {
                popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
            } else {
                popover.show(relativeTo: outline.rect(ofRow: row), of: outline, preferredEdge: .maxY)
            }
        }
    }

    func node(_ kind: OutlineNode.Kind) -> OutlineNode {
        if let node = nodes[kind] { return node }
        let node = OutlineNode(kind)
        nodes[kind] = node
        return node
    }

    private func kind(_ item: Any?) -> OutlineNode.Kind? { (item as? OutlineNode)?.kind }

    // MARK: Updates

    /// The model changed: structure as a diff with animations, content in place.
    func refresh() {
        // Rows hold still until AppKit ends the drag: it closes the drop gap on the rows it had, after the drop elsewhere
        // and after a refused drag's image slides back, with the button already up (T-353).
        guard dragged.isEmpty else { return holdUntilDragEnds() }
        // No rows before the outline has its width: they'd be laid out and measured at another.
        guard let outline, !refreshing, width > 0 else { return }
        // Made at another zoom, it's on its way out: its rows hold still in the frame SwiftUI gave them until it goes.
        guard zoom == Zoom.factor else { return }
        refreshing = true
        defer { refreshing = false }
        // Another section took the page's selection: the rows unselect, kept aside for when Tab comes back.
        if root == nil, model.selectedSection != .tasks, !outline.selectedRowIndexes.isEmpty {
            parked = selectedIDs
            outline.deselectAll(nil)
        }

        let next = OutlineSnapshot.make(model, root: root)
        replan()
        // The first tasks come in one reload, their stories open: row by row, AppKit would leave them shut.
        if outline.numberOfRows == 0 || (!snapshot.hasTasks && next.hasTasks) {
            snapshot = next
            outline.reloadData()
            expandAll()
        } else if next != snapshot {
            apply(next)
        }
        refreshVisibleCells()
        if remeasure {
            remeasure = false
            outline.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<outline.numberOfRows))
        } else {
            noteDescriptionHeights()
        }
        // The page's requests are the page's outline's, not a task window's.
        if root == nil, let focus = model.quickAddFocus {
            model.quickAddFocus = nil
            DispatchQueue.main.async { [weak self] in self?.focusQuickAdd(focus) }
        }
        // A row or title to take the keyboard: the task window's outline while it's open and shows that task, else the page's
        // once no window is over it.
        if let focus = model.outlineFocus, inFront, root == nil || row(of: focus.task) >= 0 {
            model.outlineFocus = nil
            DispatchQueue.main.async { [weak self] in self?.take(focus) }
        }
        if root == nil, model.sectionFocus == .tasks {
            model.sectionFocus = nil
            let first = snapshot.children(of: .header(.overview)).lazy.compactMap { kind -> Int? in if case .task(let id) = kind { id } else { nil } }.first
            let back = parked.filter { row(of: $0) >= 0 }
            parked = []
            if !back.isEmpty {
                DispatchQueue.main.async { [weak self] in self?.select(back) }
            } else if let id = model.focusedTask.flatMap({ row(of: $0) >= 0 ? $0 : nil }) ?? first {
                DispatchQueue.main.async { [weak self] in self?.select(id) }
            }
        }
        if let edit = pendingEdit {
            pendingEdit = nil
            let caret = pendingCaret
            pendingCaret = nil
            DispatchQueue.main.async { [weak self] in self?.beginEditing(edit.id, caretAtEnd: edit.caretAtEnd, caret: caret, retry: false) }
        }
        verifyRows()
        outline.placeCards()
        if root == nil, !model.tasks.isEmpty { LaunchLog.mark("tasks") }
        reportHeight()
    }

    /// Reloads that put lost rows back: none in a UI test run.
    static var repairs = 0

    /// The outline shows every row of the snapshot: if AppKit lost one of the changes, a reload puts them back, logged.
    private func verifyRows() {
        guard let outline else { return }
        var expected = 0
        func count(_ parent: OutlineNode.Kind?) {
            for child in snapshot.children(of: parent) {
                expected += 1
                if snapshot.children[child] != nil, outline.isItemExpanded(node(child)) { count(child) }
            }
        }
        count(nil)
        // A task with subtasks to show that AppKit shows closed, without them: opened again, logged.
        let shut = snapshot.expandable.filter { id in row(of: id) >= 0 && !outline.isItemExpanded(node(.task(id))) }
        if !shut.isEmpty {
            Self.repairs += 1
            AppLog.write("outline: \(shut.sorted().map { "T-\($0)" }.joined(separator: ", ")) open in the model, shut in the outline; reloaded", to: "outline.log")
            for id in shut {
                outline.reloadItem(node(.task(id)), reloadChildren: true)
                outline.expandItem(node(.task(id)))
            }
            return
        }
        guard expected != outline.numberOfRows else { return }
        Self.repairs += 1
        AppLog.write("outline: \(outline.numberOfRows) rows for \(expected) in the snapshot, editing \(String(describing: editingTitle)); reloaded",
                     to: "outline.log")
        outline.reloadData()
        expandAll()
    }

    // MARK: Focus

    /// The selection before an update: its tasks and their lists, the tasks around it nearest first,
    /// and whether the outline had the keyboard.
    private struct Selection {
        var ids: [Int]
        var lists: [Int: TaskList]
        var around: [Int]
        var keyboard: Bool
    }

    func row(of id: Int) -> Int { outline?.row(forItem: node(.task(id))) ?? -1 }

    private func task(atRow row: Int) -> Int? { (outline?.item(atRow: row) as? OutlineNode)?.task }

    private var selectedIDs: [Int] { outline?.selectedRowIndexes.compactMap { task(atRow: $0) } ?? [] }

    /// The list a shown task sits in.
    private func section(of id: Int) -> TaskList? {
        guard let outline else { return nil }
        var item = outline.parent(forItem: node(.task(id)))
        while let parent = item as? OutlineNode {
            if case .header(let list) = parent.kind { return list }
            item = outline.parent(forItem: parent)
        }
        return nil
    }

    private var outlineHasResponder: Bool {
        guard let outline, let responder = outline.window?.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: outline)
    }

    private func captureSelection() -> Selection? {
        guard let outline, let first = outline.selectedRowIndexes.first, let last = outline.selectedRowIndexes.last else { return nil }
        let ids = selectedIDs
        guard !ids.isEmpty else { return nil }
        var lists: [Int: TaskList] = [:]
        for id in ids { lists[id] = section(of: id) }
        func near(_ rows: some Sequence<Int>) -> [Int] {
            Array(rows.lazy.compactMap { self.task(atRow: $0) }.filter { !ids.contains($0) }.prefix(30))
        }
        let above = near(stride(from: first - 1, through: 0, by: -1))
        let below = near(stride(from: last + 1, to: outline.numberOfRows, by: 1))
        return Selection(ids: ids, lists: lists, around: above + below, keyboard: outlineHasResponder)
    }

    /// Selected tasks stay selected while they stay in their list; when none does, the nearest task
    /// above in that list takes the selection, else the one below. The keyboard stays in the outline.
    private func restore(_ selection: Selection) {
        guard let outline else { return }
        let kept = selection.ids.filter { row(of: $0) >= 0 && section(of: $0) == selection.lists[$0] }
        var target = kept
        if target.isEmpty {
            let list = selection.lists[selection.ids[0]]
            let shown = selection.around.filter { row(of: $0) >= 0 }
            target = (shown.first { section(of: $0) == list } ?? shown.first).map { [$0] } ?? []
        }
        let rows = IndexSet(target.map(row(of:)).filter { $0 >= 0 })
        if rows != outline.selectedRowIndexes { outline.selectRowIndexes(rows, byExtendingSelection: false) }
        guard selection.keyboard else { return }
        if let first = rows.first, kept.isEmpty { outline.scrollRowToVisible(first) }
        // The selection moved to another task: the keyboard goes to the rows, out of any title that kept it.
        if kept.isEmpty || !outlineHasResponder { outline.window?.makeFirstResponder(outline) }
    }

    /// Selects tasks' rows, with the keyboard.
    func select(_ ids: [Int]) {
        guard let outline else { return }
        let rows = IndexSet(ids.map(row(of:)).filter { $0 >= 0 })
        guard let first = rows.first else { return }
        outline.selectRowIndexes(rows, byExtendingSelection: false)
        outline.scrollRowToVisible(first)
        if outline.window?.firstResponder !== outline { outline.window?.makeFirstResponder(outline) }
    }

    /// Selects a task's row; with the keyboard, the outline takes it.
    /// A task anywhere in the lists, brought into view and selected: its parents unfold, its list shows.
    func reveal(_ id: Int) {
        // In a task's window: one of its subtasks selected there, any other task's window opened over it.
        if root != nil {
            if row(of: id) >= 0 { select(id) } else { model.open(.task(id), push: true) }
            return
        }
        if model.list(of: id) == .backlog { model.backlogOpen = true } else { model.folded.remove(.tasks) }
        // Hidden under a folded task or by its story's filter: those show it.
        if !OutlineSnapshot.make(model).children.values.contains(where: { $0.contains(.task(id)) }) {
            let ancestors = model.taskTree.ancestors(of: id)
            for ancestor in ancestors where model.fold[ancestor] == .hidden { model.setFold(ancestor, nil) }
            if let story = ancestors.last { model.setStoryFilter(story, false) }
        }
        refresh()
        DispatchQueue.main.async { [weak self] in self?.select(id) }
    }

    func select(_ id: Int, keyboard: Bool = true) {
        guard let outline else { return }
        let row = row(of: id)
        guard row >= 0 else { return }
        if outline.selectedRowIndexes != [row] { outline.selectRowIndexes([row], byExtendingSelection: false) }
        outline.scrollRowToVisible(row)
        if keyboard, outline.window?.firstResponder !== outline { outline.window?.makeFirstResponder(outline) }
    }

    /// A request from the description's editor.
    private func take(_ focus: OutlineFocus) {
        switch focus {
        case .row(let id):
            select(id)
            dropIfEmpty(id)
        case .title(let id, let offset):
            if let target = offset == 0 ? id : neighbor(of: id, by: offset) { beginEditing(target) } else { select(id) }
            if offset != 0 { dropIfEmpty(id) }
        case .left(let id):
            dropIfEmpty(id)
        }
    }

    /// A task left with nothing in it is deleted, unless its title or description is being edited
    /// or its modal is open. Its row's selection goes to the task above.
    private func dropIfEmpty(_ id: Int) {
        guard model.isEmptyTask(id), model.editingDescription != id, editingTitle != id, reEditing != id, model.modal != .task(id) else { return }
        model.deleteTasks([id])
        refresh()
    }

    /// The task whose title has the keyboard.
    private var editingTitle: Int? {
        (outline?.window?.firstResponder as? NSTextView)?.editedTitle?.task
    }

    /// Applies the new snapshot as removals, moves and inserts, so rows animate and the one being
    /// edited keeps its field editor.
    private func apply(_ next: OutlineSnapshot) {
        guard let outline else { return }
        let old = snapshot
        snapshot = next
        // What the outline shows now: the children of the root, the headers and open tasks.
        func loaded(_ parent: OutlineNode.Kind?) -> Bool {
            guard let parent else { return true }
            if case .header = parent { return true }
            return outline.isItemExpanded(node(parent))
        }
        var current: [OutlineNode.Kind?: [OutlineNode.Kind]] = [:]
        for (parent, children) in old.children where loaded(parent) { current[parent] = children }
        let wanted = Set(next.children.values.flatMap { $0 })
        // Many rows at once, as a search keystroke does: they change in place, with no fades.
        let shown = Set(current.values.flatMap { $0 })
        let incoming = Set(next.children.filter { loaded($0.key) }.values.flatMap { $0 })
        let changed = shown.symmetricDifference(incoming).count
        let still = changed > 24 || landing
        landing = false
        let effect: NSTableView.AnimationOptions = still ? [] : .effectFade
        let selection = captureSelection()
        // Most rows at once (a search keystroke over hundreds of tasks): one reload costs less than each row in turn.
        if changed > 150, editingTitle == nil, model.editingDescription == nil {
            outline.reloadData()
            expandAll()
            if let selection { restore(selection) }
            return
        }
        Motion.appKit(still: still) { applyRows(old: old, next: next, current: &current, wanted: wanted, effect: effect) }
        // Folded tasks whose subtasks changed, and tasks that just got subtasks.
        for id in next.expandable where !outline.isItemExpanded(node(.task(id))) {
            if old.children[.task(id)] != next.children[.task(id)] { outline.reloadItem(node(.task(id)), reloadChildren: true) }
        }
        // Tasks whose last shown subtask went: their disclosure goes.
        for id in old.expandable.subtracting(next.expandable) where outline.row(forItem: node(.task(id))) >= 0 {
            outline.reloadItem(node(.task(id)), reloadChildren: true)
        }
        expandAll()
        if let selection { restore(selection) }
    }

    private func applyRows(old: OutlineSnapshot, next: OutlineSnapshot, current: inout [OutlineNode.Kind?: [OutlineNode.Kind]],
                           wanted: Set<OutlineNode.Kind>, effect: NSTableView.AnimationOptions) {
        guard let outline else { return }
        func loaded(_ parent: OutlineNode.Kind?) -> Bool {
            guard let parent else { return true }
            if case .header = parent { return true }
            return outline.isItemExpanded(node(parent))
        }
        outline.beginUpdates()
        // Rows that are gone.
        for (parent, children) in current {
            let gone = IndexSet(children.indices.filter { !wanted.contains(children[$0]) })
            guard !gone.isEmpty else { continue }
            outline.removeItems(at: gone, inParent: parent.map(node), withAnimation: effect)
            current[parent] = children.enumerated().filter { !gone.contains($0.offset) }.map(\.element)
        }
        // Parents in outline order, each child moved or inserted into place.
        var order: [OutlineNode.Kind?] = [nil]
        var index = 0
        while index < order.count {
            for child in next.children(of: order[index]) where next.children[child] != nil { order.append(child) }
            index += 1
        }
        for parent in order where loaded(parent) || current[parent] != nil {
            let target = next.children(of: parent)
            var list = current[parent] ?? []
            for (position, child) in target.enumerated() {
                if position < list.count, list[position] == child { continue }
                if let from = list.firstIndex(of: child) {
                    outline.moveItem(at: from, inParent: parent.map(node), to: position, inParent: parent.map(node))
                    list.remove(at: from)
                    list.insert(child, at: min(position, list.count))
                } else if let (source, from) = current.first(where: { $0.key != parent && $0.value.contains(child) }).map({ ($0.key, $0.value.firstIndex(of: child)!) }) {
                    outline.moveItem(at: from, inParent: source.map(node), to: position, inParent: parent.map(node))
                    current[source]?.remove(at: from)
                    list.insert(child, at: min(position, list.count))
                } else {
                    outline.insertItems(at: IndexSet(integer: position), inParent: parent.map(node), withAnimation: effect)
                    list.insert(child, at: min(position, list.count))
                }
                current[parent] = list
            }
            // Children moved under a folded task: they leave this parent.
            if list.count > target.count {
                outline.removeItems(at: IndexSet(integersIn: target.count..<list.count), inParent: parent.map(node), withAnimation: effect)
                list.removeLast(list.count - target.count)
            }
            current[parent] = list
        }
        outline.endUpdates()
    }

    /// Opens what the user left open; folds what they folded.
    private func expandAll() {
        guard let outline else { return }
        if root != nil { return expandOpen(snapshot.children(of: nil)) }
        outline.expandItem(node(.header(.overview)))
        outline.expandItem(node(.header(.backlog)))
        expandOpen(snapshot.children(of: .header(.overview)) + snapshot.children(of: .header(.backlog)))
    }

    /// These tasks and their subtasks, open: a folded task's snapshot holds only the subtasks it still shows.
    private func expandOpen(_ kinds: [OutlineNode.Kind]) {
        guard let outline else { return }
        var queue = kinds
        while let kind = queue.popLast() {
            guard case .task(let id) = kind, snapshot.expandable.contains(id) else { continue }
            if !outline.isItemExpanded(node(kind)) { outline.expandItem(node(kind)) }
            queue.append(contentsOf: snapshot.children(of: kind))
        }
    }

    /// Every row view the outline keeps, in view or not, shows the model as it is now, except a title being edited.
    private func refreshVisibleCells() {
        guard let outline else { return }
        var rows: [Int] = []
        outline.enumerateAvailableRowViews { _, row in rows.append(row) }
        for row in rows where row >= 0 && row < outline.numberOfRows { configure(row: row) }
    }

    private func configure(row: Int) {
        guard let outline, let node = outline.item(atRow: row) as? OutlineNode else { return }
        let gap = node.task.map(gap(of:)) ?? 0
        (outline.rowView(atRow: row, makeIfNecessary: false) as? OutlineRowView)?.gap = gap
        if let cell = outline.view(atColumn: 1, row: row, makeIfNecessary: false) as? TaskCell, let id = node.task {
            dress(cell, id)
        } else if let cell = outline.view(atColumn: node.spans ? 0 : 1, row: row, makeIfNecessary: false) as? HostCell {
            cell.show(hosted(node))
        } else if let cell = outline.view(atColumn: 1, row: row, makeIfNecessary: false) as? QuickAddCell, case .quickAdd(let list) = node.kind {
            cell.configure(list: list, coordinator: self)
        }
        if let faces = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? FacesCell, let id = node.task {
            dress(faces, id)
        }
    }

    /// A task's card: under its gap, its end left for its face and its chevron.
    private func dress(_ cell: TaskCell, _ id: Int) {
        cell.gap = gap(of: id)
        cell.expandable = snapshot.foldable.contains(id)
        cell.open = snapshot.expandable.contains(id)
        cell.filterable = root == nil && snapshot.filterable.contains(id)
        cell.show(model: model, id: id, coordinator: self, hovered: false)
    }

    /// A task's face, on its card's first line.
    private func dress(_ faces: FacesCell, _ id: Int) {
        faces.gap = gap(of: id)
        faces.lineTop = TaskCell.lineTop(big: isBig(id))
        faces.show(model: model, id: id)
    }

    /// The rows' height goes to SwiftUI now, and again once row animations end.
    func reportHeight() {
        guard let container else { return }
        let height = container.contentHeight
        reports += 1
        let report = reports
        DispatchQueue.main.async { [weak self] in
            self?.onHeight(height)
            // Once the page laid out again, the container holds its rows; a defect if not, logged (no repair).
            // A later report means rows SwiftUI may not have had yet: that report's check judges them.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, report == reports, let container = self.container, container.window != nil else { return }
                let rows = container.contentHeight
                guard container.frame.height + 0.5 < rows || container.outline.frame != container.bounds else { return }
                AppLog.write("outline: container \(container.frame.integral), outline \(container.outline.frame.integral), rows \(Int(rows))", to: "outline.log")
            }
        }
    }

    // MARK: Descriptions

    func descriptionShown(_ id: Int) -> Bool {
        model.descriptionShownInOutline(id) || model.editingDescription == id
    }

    /// Space above a task's card: from the row before, the trays that close and its own tray's padding.
    func gap(of id: Int) -> CGFloat { plan.gaps[id] ?? 0 }

    /// The plan again, after the rows or what's open changed; rows whose height changed are measured again.
    func replan() {
        let next = OutlinePlan(snapshot)
        guard next != plan else { return }
        plan = next
        remeasure = true
    }

    /// The task card's height under its gap: what TaskCell stacks in it (its first line, a big card's title, description
    /// line and story, a Blocked reason), and its description when shown.
    private func height(of id: Int) -> CGFloat {
        let big = isBig(id)
        let shown = descriptionShown(id)
        let line = TaskCell.stack(model, id, big: big, description: shown).height
        guard shown else { return line }
        let task = model.task(id)
        let editing = model.editingDescription == id
        var hasher = Hasher()
        hasher.combine(task?.body)
        hasher.combine(editing)
        hasher.combine(model.outputs(ofTask: id))
        hasher.combine(width)
        let key = hasher.finalize()
        if let cached = heights[id], cached.key == key { return line + cached.height }
        // The card's width, less its padding and, but on a big card, the glyph before the lines under the first.
        let edges = plan.card(of: id)
        let available = width - edges.left - edges.right - 2 * padding(of: id) - (big ? 0 : TaskCell.titleX)
        // Editing, the box grows with its text: never cached.
        if editing { return line + model.descriptionEditorBox + Space.xs + Space.md }
        let height = DescriptionBlock.measure(model: model, id: id, width: max(available, Metric.titleMinimum))
        heights[id] = (key, height)
        return line + height
    }

    private func noteDescriptionHeights() {
        guard let outline else { return }
        var changed = IndexSet()
        for row in 0..<outline.numberOfRows {
            guard let id = (outline.item(atRow: row) as? OutlineNode)?.task else { continue }
            if abs(outline.rect(ofRow: row).height - gap(of: id) - height(of: id)) > 0.5 { changed.insert(row) }
        }
        if !changed.isEmpty {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                outline.noteHeightOfRows(withIndexesChanged: changed)
            }
        }
    }

    /// A diagram finished drawing: description heights may have changed.
    func descriptionsChanged() {
        heights.removeAll()
        // Mid-drag the gap's heights stay: the refresh after the drag notes the new ones.
        guard dragged.isEmpty else { return }
        noteDescriptionHeights()
        refreshVisibleCells()
        reportHeight()
    }

    // MARK: Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        snapshot.children(of: kind(item)).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        node(snapshot.children(of: kind(item))[index])
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        switch kind(item) {
        case .header: true
        case .task(let id): snapshot.expandable.contains(id)
        default: false
        }
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? OutlineNode)?.spans ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        switch kind(item) {
        // The Backlog's header sits a section's space under the Tasks card.
        case .header(let list): list == .backlog ? Metric.outlineHeader + Metric.backlogHeaderGap : Metric.outlineHeader
        // On the page, as far under the last card as the cards are apart.
        case .quickAdd(let list): (plan.trailing[list] ?? 0) + (root == nil ? Metric.storyGap : Metric.taskGap) + Metric.outlineQuick
        case .empty: Metric.outlineEmpty
        case .task(let id): gap(of: id) + height(of: id)
        case nil: Metric.outlineRow
        }
    }

    // MARK: Views

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let row = outlineView.makeView(withIdentifier: OutlineRowView.id, owner: nil) as? OutlineRowView ?? OutlineRowView()
        row.identifier = OutlineRowView.id
        row.isTask = (item as? OutlineNode)?.task != nil
        row.gap = (item as? OutlineNode)?.task.map(gap(of:)) ?? 0
        let task = (item as? OutlineNode)?.task
        row.alphaValue = task.map { outline?.lit?.contains($0) == false } == true ? Motion.dimmedOpacity : 1
        return row
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? OutlineNode else { return nil }
        if node.spans {
            let cell = hostCells[node.kind] ?? HostCell()
            hostCells[node.kind] = cell
            cell.show(hosted(node))
            return cell
        }
        switch (tableColumn?.identifier, node.kind) {
        case (Self.facesColumn, .task(let id)):
            let cell = outlineView.makeView(withIdentifier: FacesCell.id, owner: nil) as? FacesCell ?? FacesCell()
            dress(cell, id)
            return cell
        case (Self.mainColumn, .task(let id)):
            let cell = outlineView.makeView(withIdentifier: TaskCell.id, owner: nil) as? TaskCell ?? TaskCell()
            dress(cell, id)
            return cell
        case (Self.mainColumn, .quickAdd(let list)):
            let cell = outlineView.makeView(withIdentifier: QuickAddCell.id, owner: nil) as? QuickAddCell ?? QuickAddCell()
            cell.configure(list: list, coordinator: self)
            return cell
        default:
            return nil
        }
    }

    private func hosted(_ node: OutlineNode) -> AnyView {
        switch node.kind {
        case .header(let list): AnyView(OutlineHeader(list: list).handCursors().environment(model))
        case .empty: AnyView(Text(model.search.isEmpty ? "Nothing on the overview. Add from the Backlog or type a task." : "No task matches “\(model.search)”.")
            .kitType(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, Metric.bigCardPadding + TaskCell.titleX))
        default: AnyView(EmptyView())
        }
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? OutlineNode)?.task != nil
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outline else { return }
        // A task's window: the selection is its own, the page's stays.
        if root != nil {
            outline.placeCards()
            return
        }
        let row = outline.selectedRow
        let id = row >= 0 ? (outline.item(atRow: row) as? OutlineNode)?.task : nil
        if model.focusedTask != id { model.focusedTask = id }
        let selected = outline.selectedRowIndexes.compactMap { (outline.item(atRow: $0) as? OutlineNode)?.task }
        if model.selectedTasks != selected { model.selectedTasks = selected }
        // A chip under a row unselects when the rows change; a click on a chip selects it again after.
        if model.modal == nil, model.selectedItem.flatMap(AppModel.section(ofItem:)) == .tasks { model.selectedItem = nil }
        if !selected.isEmpty { model.selectSection(.tasks) }
        // The selected cards take their ring; what isn't related to them fades.
        outline.placeCards()
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !refreshing, let id = ((notification.userInfo?["NSObject"]) as? OutlineNode)?.task else { return }
        // Not the outline's own (VoiceOver's expand): all its subtasks.
        model.setFold(id, .all)
        // AppKit loads its subtasks folded: the ones the user left open open again.
        refreshing = true
        defer { refreshing = false }
        expandOpen(snapshot.children(of: .task(id)))
        replanRows()
    }

    /// A task opened or folded: its tray comes or goes, the gaps around it change.
    private func replanRows() {
        replan()
        guard remeasure, let outline else { return }
        remeasure = false
        outline.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<outline.numberOfRows))
        // The cards and trays slide with the rows AppKit animates.
        outline.placeCards(animated: true)
        reportHeight()
    }

    /// Folding a task whose subtask is selected selects the task.
    private var foldingSelection = false

    func outlineViewItemWillExpand(_ notification: Notification) {
        if !refreshing { outline?.slideCards() }
    }

    func outlineViewItemWillCollapse(_ notification: Notification) {
        guard let outline, let item = notification.userInfo?["NSObject"] as? OutlineNode else { return }
        if !refreshing { outline.slideCards() }
        foldingSelection = outline.selectedRowIndexes.contains { row in
            var parent = outline.parent(forItem: outline.item(atRow: row))
            while let node = parent as? OutlineNode {
                if node === item { return true }
                parent = outline.parent(forItem: node)
            }
            return false
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let item = notification.userInfo?["NSObject"] as? OutlineNode, let id = item.task else { return }
        if foldingSelection {
            foldingSelection = false
            select(id, keyboard: outlineHasResponder)
        }
        guard !refreshing else { return }
        model.setFold(id, .hidden)
        replanRows()
    }

    // MARK: Clicks and keys

    @objc func doubleClicked(_ sender: NSOutlineView) {
        guard let id = (sender.item(atRow: sender.clickedRow) as? OutlineNode)?.task else { return }
        model.open(.task(id), push: root != nil)
    }

    func keyboardChanged() {
        guard let outline, let window = outline.window else { return }
        let responder = window.firstResponder
        // The outline's rows, or a title's field editor: not a description's editor, which keeps its text keys.
        let keyboard: OutlineKeyboard = if responder === outline { .rows }
            else if (responder as? NSTextView)?.editedTitle != nil { .title }
            else { .none }
        // A task's window keeps the page's keyboard state.
        if root == nil, model.outlineKeyboard != keyboard { model.outlineKeyboard = keyboard }
        // A selected card's ring is the accent only while the rows have the keyboard.
        outline.placeCards()
    }

    /// Keys on selected rows, DESIGN.md §7. Return and Tab never reach the table, which would edit a title.
    func key(_ event: NSEvent) -> Bool {
        let ids = selectedIDs
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let letter = event.charactersIgnoringModifiers?.lowercased()
        let newTask = letter == "n" && flags.subtracting(.shift).isEmpty
        guard let first = ids.first, let last = ids.last else {
            guard root == nil else { return false }
            if newTask { model.focusQuickAdd(.overview) }
            return newTask
        }
        switch (event.keyCode, flags) {
        case (36, []), (76, []): beginEditing(first)
        case (36, .shift), (76, .shift): model.toggleDescriptions(ids)
        case (36, .command), (76, .command): model.nextStatus(ids)
        case (36, [.command, .option]), (76, [.command, .option]): model.beginStart(task: first)
        case (36, _), (76, _): break
        case (48, []) where root != nil, (48, .shift) where root != nil: return false
        case (48, []), (48, .shift): leaveSection(by: flags.contains(.shift) ? -1 : 1)
        case (48, _): break
        // A held key moves among siblings only: it never indents, outdents or leaves the parent.
        case (124, .shift): if !event.isARepeat { model.indentTasks(ids.filter(indentsInView)) }
        case (123, .shift): if !event.isARepeat { model.outdentTasks(ids) }
        case (126, .shift): model.shiftTasks(ids, by: -1, leavingParent: !event.isARepeat)
        case (125, .shift): model.shiftTasks(ids, by: 1, leavingParent: !event.isARepeat)
        // ↓ on a list's last task: its new task's card; on a task window's last subtask, its new subtask's.
        case (125, []) where newTaskBelow(last):
            outline?.deselectAll(nil)
            if let root { model.newSubtaskFocus = root } else if let list = quickAddBelow(last) { focusQuickAdd(list) }
        case (123, []), (123, .option): foldLeft(ids, deep: flags == .option)
        case (124, []), (124, .option): foldRight(ids, deep: flags == .option)
        case (49, []), (34, .command): model.open(.task(first), push: root != nil)
        // In a task's window too, the selected subtask moves, not the window's task.
        case (11, [.command, .shift]): model.moveTasks(ids, toBacklog: ids.contains { model.list(of: $0) != .backlog })
        // Escape unselects: nothing stays dimmed.
        case (53, []): outline?.deselectAll(nil)
        case (51, []), (117, []), (51, .command): model.deleteTasks(ids)
        // B blocks or unblocks, ⇧B asks what blocks it, A what it comes after: by the letter, whatever the layout.
        case (_, []) where letter == "b":
            if model.task(first)?.blocked == true { model.unblock(first) } else if model.task(first)?.status != .done { showHoldPicker(first, .block) }
        case (_, .shift) where letter == "b": if model.task(first)?.status != .done { showHoldPicker(first, .blockedBy) }
        case (_, []) where letter == "a": if model.task(first)?.status != .done { showHoldPicker(first, .after) }
        default:
            guard newTask else { return false }
            let added = flags.contains(.shift) ? model.addSubtask(to: first) : model.addTask(after: last)
            guard let added else { break }
            pendingEdit = (added.id, true)
            refresh()
        }
        return true
    }

    // MARK: Folding

    /// Hides or shows tasks' subtasks; `deep`, every task under them too. A selected subtask that goes gives the
    /// selection to the task that hid it.
    func fold(_ ids: [Int], _ mode: FoldMode, deep: Bool = false) {
        let tree = model.taskTree
        let targets = deep ? ids.flatMap { tree.subtree(of: $0) }.filter { !tree.children(of: $0).isEmpty } : ids.filter(snapshot.foldable.contains)
        let change = targets.filter { (model.fold[$0] ?? .all) != mode }
        guard !change.isEmpty else { return }
        changeRows(hiding: change) { for id in change { model.setFold(id, mode) } }
    }

    /// The chevron: its subtasks shown or hidden (2026-11-12).
    func toggleFold(_ id: Int) {
        fold([id], snapshot.expandable.contains(id) ? .hidden : .all)
    }

    /// A story's filter button: on, only its Blocked and doing tasks show (2026-11-12).
    func toggleFilter(_ id: Int) {
        let on = !model.storyFilter.contains(id)
        changeRows(hiding: [id]) { model.setStoryFilter(id, on) }
    }

    /// Rows change as `change` says; a selected task that goes gives the selection to the one in `hiding` above it.
    private func changeRows(hiding: [Int], _ change: () -> Void) {
        let selected = selectedIDs
        let keyboard = outlineHasResponder
        outline?.slideCards()
        change()
        refresh()
        guard let hidden = selected.first(where: { row(of: $0) < 0 }),
              let holder = model.taskTree.ancestors(of: hidden).first(where: hiding.contains) else { return }
        select(holder, keyboard: keyboard)
    }

    /// ←: hides the selected tasks' subtasks; on one that shows none, or has none, its parent takes the selection.
    private func foldLeft(_ ids: [Int], deep: Bool) {
        if deep { return fold(ids, .hidden, deep: true) }
        let open = ids.filter(snapshot.expandable.contains)
        if !open.isEmpty { return fold(open, .hidden) }
        guard ids.count == 1, let parent = model.taskTree.parent(of: ids[0]), row(of: parent) >= 0 else { return }
        select(parent)
    }

    /// →: shows the selected tasks' subtasks; on one that shows them, its first subtask takes the selection.
    private func foldRight(_ ids: [Int], deep: Bool) {
        if deep { return fold(ids, .all, deep: true) }
        let shut = ids.filter { snapshot.foldable.contains($0) && !snapshot.expandable.contains($0) }
        if !shut.isEmpty { return fold(shut, .all) }
        guard ids.count == 1, case .task(let first)? = snapshot.children(of: .task(ids[0])).first else { return }
        select(first)
    }

    /// Tab and ⇧Tab on rows: the next section takes the keyboard; the rows unselect, kept aside for when Tab comes back.
    private func leaveSection(by offset: Int) {
        let ids = selectedIDs
        guard model.moveSection(from: .tasks, by: offset) != .tasks else { return }
        parked = ids
        outline?.deselectAll(nil)
    }

    func menu(forRow row: Int) -> NSMenu? {
        guard let outline, row >= 0, let id = (outline.item(atRow: row) as? OutlineNode)?.task else { return nil }
        if !outline.selectedRowIndexes.contains(row) { outline.selectRowIndexes([row], byExtendingSelection: false) }
        let selected = outline.selectedRowIndexes.compactMap { (outline.item(atRow: $0) as? OutlineNode)?.task }
        return NSHostingMenu(rootView: TaskMenu(ids: selected.count > 1 ? selected : [id]).environment(model))
    }

    // MARK: Editing titles

    /// The row, selected, and its title take the keyboard, caret at the end or all selected. A row
    /// that isn't shown yet is edited after the next update.
    func beginEditing(_ id: Int, caretAtEnd: Bool = true, caret: Int? = nil, at click: NSPoint? = nil, retry: Bool = true) {
        guard let outline else { return }
        let row = outline.row(forItem: node(.task(id)))
        guard row >= 0 else {
            if retry { pendingEdit = (id, caretAtEnd) }
            return
        }
        outline.scrollRowToVisible(row)
        guard let cell = outline.view(atColumn: 1, row: row, makeIfNecessary: true) as? TaskCell else { return }
        if outline.selectedRowIndexes != [row] { outline.selectRowIndexes([row], byExtendingSelection: false) }
        outline.window?.makeFirstResponder(cell.title)
        if let editor = cell.title.currentEditor() {
            let end = (cell.title.stringValue as NSString).length
            editor.selectedRange = caret.map { NSRange(location: min($0, end), length: 0) }
                ?? (caretAtEnd ? NSRange(location: end, length: 0) : NSRange(location: 0, length: end))
            if let click, let text = editor as? NSTextView {
                let index = text.characterIndexForInsertion(at: text.convert(click, from: nil))
                text.selectedRange = NSRange(location: min(index, end), length: 0)
            }
        }
        if model.focusedTask != id { model.focusedTask = id }
        if reEditing == id { reEditing = nil }
        keyboardChanged()
    }

    /// A title took the keyboard: the Task menu acts on its task.
    func titleFocused(_ id: Int) {
        if model.focusedTask != id { model.focusedTask = id }
        DispatchQueue.main.async { [weak self] in self?.keyboardChanged() }
    }

    /// The Task menu's chords, typed in a title: they come before the menu bar, whatever its state.
    func chord(_ field: TitleField, _ id: Int, event: NSEvent? = NSApp.currentEvent) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch (event.keyCode, flags) {
        case (36, .command), (76, .command):
            commitTitle(field)
            model.nextStatus([id])
        case (36, [.command, .option]), (76, [.command, .option]):
            commitTitle(field)
            model.beginStart(task: id)
        case (36, .shift), (76, .shift):
            commitTitle(field)
            editDescription(id)
        case (11, [.command, .shift]):
            commitTitle(field)
            model.toggleList(id)
        case (34, .command):
            commitTitle(field)
            model.open(.task(id))
        case (51, .command):
            commitTitle(field)
            model.deleteTasks([id])
        default:
            return false
        }
        return true
    }

    /// Return, Tab, arrows, Escape: an outliner's keys in a title field.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        deleting = selector == #selector(NSResponder.deleteBackward(_:)) || selector == #selector(NSResponder.deleteForward(_:))
        if let quick = control as? QuickAddField { return quickAdd(quick, selector) }
        guard let field = control as? TitleField, let id = field.task else { return false }
        if chord(field, id) { return true }
        let flags = NSApp.currentEvent?.modifierFlags.intersection([.command, .shift, .option, .control]) ?? []
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            commitTitle(field)
            if flags.contains(.shift) {
                editDescription(id)
            } else if flags.contains(.command) {
                model.nextStatus([id])
            } else if flags.isEmpty, !field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty, let added = model.addTask(after: id) {
                pendingEdit = (added.id, true)
                refresh()
            }
            return true
        case #selector(NSResponder.insertTab(_:)):
            commitTitle(field)
            editDescription(id)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            commitTitle(field)
            if let previous = neighbor(of: id, by: -1) { beginEditing(previous) }
            return true
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
            // The row above or below, selected: arrows leave the title as Escape does.
            commitTitle(field)
            select(neighbor(of: id, by: selector == #selector(NSResponder.moveUp(_:)) ? -1 : 1) ?? id)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            commitTitle(field)
            select(id)
            return true
        case #selector(NSResponder.moveLeftAndModifySelection(_:)), #selector(NSResponder.moveRightAndModifySelection(_:)):
            // ⇧← at the start of the title outdents the task, ⇧→ at its end indents it; the title stays edited.
            let left = selector == #selector(NSResponder.moveLeftAndModifySelection(_:))
            let selection = textView.selectedRange()
            guard selection.length == 0, selection.location == (left ? 0 : (textView.string as NSString).length) else { return false }
            // A held key selecting the title stops at its edge.
            guard NSApp.currentEvent?.isARepeat != true else { return true }
            commitTitle(field)
            let parent = model.taskTree.parent(of: id)
            // Moving the row ends its edit for a moment: an empty task stays until its title is edited again.
            reEditing = id
            if left { model.outdent(id) } else if indentsInView(id) { model.indent(id) }
            guard model.taskTree.parent(of: id) != parent else {
                reEditing = nil
                return true
            }
            pendingEdit = (id, !left)
            pendingCaret = left ? 0 : nil
            refresh()
            return true
        default:
            return false
        }
    }

    // MARK: Completion

    /// Typing after `#` in a title or the quick-add line lists the statuses, projects and tags that start so. A Slack link
    /// pasted in the quick-add line becomes the link the task comes with (T-313).
    func controlTextDidChange(_ notification: Notification) {
        if let field = notification.object as? QuickAddField, let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView,
           let found = SlackLink.find(in: editor.string) {
            var rest = editor.string
            rest.removeSubrange(found.range)
            editor.string = rest.trimmingCharacters(in: .whitespaces)
            model.pendingTaskLink = PendingTaskLink(url: found.url, list: field.list)
            model.resolveSlack(found.url)
            return
        }
        guard !completing, !deleting, let control = notification.object as? NSTextField, control is TitleField || control is QuickAddField,
              let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView, Self.hashWord(in: editor) != nil else {
            deleting = false
            return
        }
        completing = true
        editor.complete(nil)
        completing = false
    }

    func control(_ control: NSControl, textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange,
                 indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
        guard control is TitleField || control is QuickAddField, let word = Self.hashWord(in: textView), word.range == charRange else { return [] }
        index.pointee = 0
        return model.titleCompletions(word.text)
    }

    /// The word being typed right after a `#` at the caret: its text and range, without the `#`.
    static func hashWord(in editor: NSTextView) -> (text: String, range: NSRange)? {
        let text = editor.string as NSString
        let caret = editor.selectedRange().location
        guard editor.selectedRange().length == 0 || editor.selectedRange().location > 0 else { return nil }
        var start = caret
        while start > 0 {
            let character = text.substring(with: NSRange(location: start - 1, length: 1))
            guard character.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "_-/".unicodeScalars.contains($0) }) else { break }
            start -= 1
        }
        guard start > 0, caret > start, text.substring(with: NSRange(location: start - 1, length: 1)) == "#" else { return nil }
        if start > 1, !text.substring(with: NSRange(location: start - 2, length: 1)).trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        let range = NSRange(location: start, length: caret - start)
        return (text.substring(with: range), range)
    }

    /// The previous or next task row, across both lists.
    private func neighbor(of id: Int, by offset: Int) -> Int? {
        guard let outline else { return nil }
        let start = outline.row(forItem: node(.task(id)))
        // A task this outline doesn't show has no neighbor here.
        guard start >= 0 else { return nil }
        var row = start + offset
        while row >= 0 && row < outline.numberOfRows {
            if let next = (outline.item(atRow: row) as? OutlineNode)?.task { return next }
            row += offset
        }
        return nil
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        let field = notification.object as? TitleField
        if let field { commitTitle(field) }
        let left = field?.task
        DispatchQueue.main.async { [weak self] in
            self?.keyboardChanged()
            if let left { self?.dropIfEmpty(left) }
        }
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        if let field = notification.object as? TitleField, let id = field.task, model.focusedTask != id { model.focusedTask = id }
        keyboardChanged()
    }

    private func commitTitle(_ field: TitleField) {
        guard let id = field.task, let task = model.task(id) else { return }
        let text = field.stringValue
        // Untouched, it writes nothing and shows the title as it is now.
        guard text != field.base else {
            if text != task.title { field.stringValue = task.title }
            return
        }
        field.base = text
        let split = TitleTags.split(text)
        if split.title != task.title || !split.tags.allSatisfy(task.tags.contains) { model.setTitle(id, text) }
        if !split.tags.isEmpty { field.stringValue = model.task(id)?.title ?? split.title }
    }

    /// Edits the description, the caret under `point` (a double-click on the rendered text, from its top-left), else at its end.
    func editDescription(_ id: Int, at point: CGPoint? = nil) {
        model.shownDescriptions.insert(id)
        model.editorCaret = point
        let rendered = heights[id]?.height
        model.editingDescription = id
        // The box opens as tall as the text it replaces, until the editor measures its own.
        if let rendered { model.descriptionEditorHeight = max(rendered - Space.xs - Space.md, 0) }
    }

    /// A click in a shown description selects its row and still reaches its links, checkboxes and
    /// chips; a double-click edits the description and goes no further.
    func descriptionClick(_ event: NSEvent) -> NSEvent? {
        guard let outline, let window = outline.window, event.window === window, model.modal == nil,
              event.modifierFlags.intersection([.command, .shift]).isEmpty else { return event }
        let row = outline.row(at: outline.convert(event.locationInWindow, from: nil))
        guard row >= 0, let id = task(atRow: row), model.editingDescription != id,
              let host = (outline.view(atColumn: 1, row: row, makeIfNecessary: false) as? TaskCell)?.descriptionHost,
              let hit = window.contentView?.superview?.hitTest(event.locationInWindow), hit.isDescendant(of: host) else { return event }
        guard event.clickCount >= 2 else {
            DispatchQueue.main.async { [weak self] in self?.select(id) }
            return event
        }
        if outline.selectedRowIndexes != [row] { outline.selectRowIndexes([row], byExtendingSelection: false) }
        // At the spot: the editor shows the same text in the same place, so the point finds its source (T-368).
        var point = host.convert(event.locationInWindow, from: nil)
        if !host.isFlipped { point.y = host.bounds.height - point.y }
        editDescription(id, at: CGPoint(x: point.x, y: point.y - Space.xs))
        return nil
    }

    // MARK: Quick add

    private func quickAdd(_ field: QuickAddField, _ selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            let option = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
            let list: TaskList = option ? .backlog : field.list
            // A Slack link copied before New Task comes with it, and names it when nothing is typed.
            let pending = model.pendingTaskLink.flatMap { $0.list == field.list ? $0.url : nil }
            var text = field.stringValue.trimmingCharacters(in: .whitespaces)
            if text.isEmpty, let pending { text = model.name(fromSlack: pending) }
            guard !text.isEmpty else { return true }
            model.addTask(to: list, title: text, links: pending.flatMap(URL.init(string:)).map { [$0] } ?? [])
            if pending != nil { model.pendingTaskLink = nil }
            field.stringValue = ""
            return true
        case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.moveUp(_:)), #selector(NSResponder.insertBacktab(_:)):
            // Back to the rows: the task above, selected. Escape drops what was typed and the Slack link with it.
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                field.stringValue = ""
                if model.pendingTaskLink?.list == field.list { model.pendingTaskLink = nil }
            }
            guard let outline else { return true }
            let row = outline.row(forItem: node(.quickAdd(field.list)))
            if let previous = (stride(from: row - 1, through: 0, by: -1).lazy.compactMap { self.task(atRow: $0) }).first {
                select(previous)
            } else {
                outline.window?.makeFirstResponder(outline)
            }
            return true
        default:
            return false
        }
    }

    /// ⇧→ goes under the sibling above only when it shows: not a done one Hide Done hides, where the task would vanish.
    private func indentsInView(_ id: Int) -> Bool {
        let tree = model.taskTree
        guard let index = tree.index(of: id), index > 0, let container = tree.container(of: id) else { return false }
        return row(of: tree.children(of: container)[index - 1]) >= 0
    }

    /// The list whose new task's card comes right under a task's row.
    private func quickAddBelow(_ id: Int) -> TaskList? {
        guard let outline else { return nil }
        let row = outline.row(forItem: node(.task(id)))
        guard row >= 0, row + 1 < outline.numberOfRows, case .quickAdd(let list)? = (outline.item(atRow: row + 1) as? OutlineNode)?.kind else { return nil }
        return list
    }

    /// A new task's card comes under this task's row: its list's, or in a task's window the new subtask's, under the last row.
    private func newTaskBelow(_ id: Int) -> Bool {
        guard let outline else { return false }
        if root != nil { return outline.row(forItem: node(.task(id))) == outline.numberOfRows - 1 }
        return quickAddBelow(id) != nil
    }

    /// ↑ from a task window's new subtask: its last subtask, selected.
    func selectLast() {
        guard let outline, let id = (stride(from: outline.numberOfRows - 1, through: 0, by: -1).lazy.compactMap { self.task(atRow: $0) }).first else { return }
        select(id)
    }

    /// The task window's outline that shows a task's subtasks.
    static func scoped(_ root: Int) -> OutlineCoordinator? {
        live.compactMap(\.coordinator).first { $0.root == root && $0.outline?.window != nil }
    }

    func focusQuickAdd(_ list: TaskList) {
        guard let outline else { return }
        let row = outline.row(forItem: node(.quickAdd(list)))
        guard row >= 0 else { return }
        outline.scrollRowToVisible(row)
        if let cell = outline.view(atColumn: 1, row: row, makeIfNecessary: true) as? QuickAddCell {
            outline.window?.makeFirstResponder(cell.field)
        }
    }

    // MARK: Drag and drop

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let id = (item as? OutlineNode)?.task, let task = model.task(id) else { return nil }
        // Never while its title is being edited: the field editor keeps its text drags.
        if (outlineView.window?.firstResponder as? NSTextView)?.editedTitle?.task == id { return nil }
        // The whole card drags (2026-11-10): between cards it moves, onto a task the drop menu asks, onto a session card it
        // links, in another app it's the task's line.
        let pasteboard = NSPasteboardItem()
        pasteboard.setString("\(id)", forType: DragItem.taskType)
        pasteboard.setString(model.line(of: .task(task.id)), forType: .string)
        return pasteboard
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
        session.draggingFormation = .list
        // Each dragged task as its card alone.
        if let outline = outlineView as? TaskOutlineView {
            let rows = draggedItems.map { outline.row(forItem: $0) }
            session.enumerateDraggingItems(options: [], for: outline, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, index, _ in
                guard index < rows.count, rows[index] >= 0, let card = outline.cardFrame(ofRow: rows[index]),
                      let image = outline.cardImage(ofRow: rows[index]) else { return }
                item.setDraggingFrame(card, contents: image)
            }
        }
        dragBegan(draggedItems.compactMap { ($0 as? OutlineNode)?.task })
    }

    func dragBegan(_ ids: [Int]) { dragged = ids }

    private(set) var dragged: [Int] = []
    /// The card the last dragged task over the middle of was proposed onto, for the UI test.
    private(set) var proposedOnto: Int?
    /// A drop moved rows: the next update puts them in place without animating the move.
    private var landing = false

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let outline = outlineView as? TaskOutlineView
        let operation = proposeDrop(info, item: item, index: index, outline: outlineView)
        // The cards hold still (2026-11-10): the card it drops onto takes a ring, a move between cards shows its line.
        if operation.isEmpty {
            outline?.clearDrop()
        } else if let onto = proposedOnto {
            outline?.dropOnto = onto
            outline?.showDropLine(nil)
        } else {
            outline?.dropOnto = nil
            outline?.showDropLine(outline.flatMap { outline in proposedBetween.flatMap { dropLine(item: $0.item, index: $0.index, in: outline) } })
        }
        return operation
    }

    /// Where the last move between cards was proposed: its parent and index.
    private var proposedBetween: (item: Any?, index: Int)?

    private func proposeDrop(_ info: NSDraggingInfo, item: Any?, index: Int, outline outlineView: NSOutlineView) -> NSDragOperation {
        proposedOnto = nil
        proposedBetween = nil
        var item = item
        var index = index
        let carried = DragItem.routes(on: info.draggingPasteboard)
        if !carried.isEmpty {
            // Onto the task under the pointer: they link there, or tasks ask what to do.
            guard let id = linkTarget(info, item: item, index: index, outline: outlineView),
                  !linkable(carried, to: id).isEmpty || carried.contains(where: { $0.taskID.map { $0 != id } ?? false }) else { return [] }
            outlineView.setDropItem(node(.task(id)), dropChildIndex: NSOutlineViewDropOnItemIndex)
            proposedOnto = id
            return .link
        }
        // The middle of a card takes the drop (its menu asks); its top and bottom quarters, and the space between cards,
        // move the task there.
        if let ids = draggedIDs(info), let outline = outlineView as? TaskOutlineView {
            let point = outline.convert(info.draggingLocation, from: nil)
            let row = outline.row(at: point)
            if row >= 0, let target = (outline.item(atRow: row) as? OutlineNode)?.task, let card = outline.cardFrame(ofRow: row),
               !ids.contains(where: { model.taskTree.subtree(of: $0).contains(target) }) {
                let edge = min(Metric.dropEdge, card.height / 4)
                if point.y > card.minY + edge, point.y < card.maxY - edge {
                    outline.setDropItem(node(.task(target)), dropChildIndex: NSOutlineViewDropOnItemIndex)
                    proposedOnto = target
                    return .move
                }
            }
        }
        // Onto a row outside its card's middle: above the card or below it, by the half the pointer is in.
        if index == NSOutlineViewDropOnItemIndex, let id = (item as? OutlineNode)?.task {
            // On its own card, or one under it: nothing.
            if let ids = draggedIDs(info), ids.contains(where: { model.taskTree.subtree(of: $0).contains(id) }) { return [] }
            let parent = outlineView.parent(forItem: item)
            let row = outlineView.row(forItem: item)
            guard var position = snapshot.children(of: kind(parent)).firstIndex(of: .task(id)), row >= 0,
                  let card = (outlineView as? TaskOutlineView)?.cardFrame(ofRow: row) else { return [] }
            if outlineView.convert(info.draggingLocation, from: nil).y > card.midY { position += 1 }
            outlineView.setDropItem(parent, dropChildIndex: position)
            item = parent
            index = position
        }
        guard let ids = draggedIDs(info), !ids.isEmpty, let target = dropTarget(item: item, index: index, outline: outlineView) else { return [] }
        guard model.taskTree.canMove(ids, to: target.container) else { return [] }
        proposedBetween = (item, index)
        return .move
    }

    /// Where a move between cards lands, as a line: in the gap above the card it goes before, else under its new
    /// parent's last subtask, at that card's left; in a task with no subtasks shown, a level in under its card.
    private func dropLine(item: Any?, index: Int, in outline: TaskOutlineView) -> NSRect? {
        let parent = kind(item)
        let kids = snapshot.children(of: parent).filter { if case .task = $0 { true } else { false } }
        let thickness = Space.sm
        func line(_ card: NSRect, x: CGFloat, y: CGFloat) -> NSRect {
            NSRect(x: x, y: y - thickness / 2, width: max(card.maxX - x, 0), height: thickness)
        }
        if index >= 0, index < kids.count {
            let row = outline.row(forItem: node(kids[index]))
            guard row >= 0, let card = outline.cardFrame(ofRow: row) else { return nil }
            return line(card, x: card.minX, y: card.minY - Metric.taskGap / 2)
        }
        if let last = kids.last {
            let row = outline.row(forItem: node(last))
            guard row >= 0, let card = outline.cardFrame(ofRow: row) else { return nil }
            return line(card, x: card.minX, y: outline.rect(ofRow: outline.lastRow(under: row)).maxY + Metric.taskGap / 2)
        }
        guard case .task(let id)? = parent else { return nil }
        let row = outline.row(forItem: node(.task(id)))
        guard row >= 0, let card = outline.cardFrame(ofRow: row) else { return nil }
        return line(card, x: card.minX + Metric.subtaskIndent, y: card.maxY + Metric.taskGap / 2)
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        (outlineView as? TaskOutlineView)?.clearDrop()
        let carried = DragItem.routes(on: info.draggingPasteboard)
        // Tasks onto a task: a menu asks where they go or how they link, once the drag is over.
        if index == NSOutlineViewDropOnItemIndex, let target = (item as? OutlineNode)?.task {
            let moved = draggedIDs(info) != nil
            let tasks = (draggedIDs(info) ?? carried.compactMap(\.taskID)).filter { $0 != target }
            if !tasks.isEmpty {
                let others = linkable(carried.filter { $0.taskID == nil }, to: target)
                if !others.isEmpty { model.link(others, to: target) }
                let point = outlineView.convert(info.draggingLocation, from: nil)
                DispatchQueue.main.async { [weak self] in self?.showDropMenu(tasks, onto: target, at: point, moved: moved) }
                return true
            }
        }
        if !carried.isEmpty {
            guard let id = (item as? OutlineNode)?.task, case let routes = linkable(carried, to: id), !routes.isEmpty else { return false }
            model.link(routes, to: id)
            return true
        }
        guard let ids = draggedIDs(info), let target = dropTarget(item: item, index: index, outline: outlineView),
              model.taskTree.canMove(ids, to: target.container) else { return false }
        // The rows change once the drag session is over: until then AppKit keeps the drop gap's row heights.
        DispatchQueue.main.async { [weak self] in self?.drop(ids, into: target.container, at: target.index) }
        return true
    }

    /// Tasks dropped onto a task: add them as its subtasks, above or below it, or link them to it. One Undo step each.
    func showDropMenu(_ ids: [Int], onto target: Int, at point: NSPoint, moved: Bool) {
        guard let outline, !ids.isEmpty, model.task(target) != nil else { return }
        let tree = model.taskTree
        let flow = model.taskFlow
        let menu = NSMenu()
        menu.autoenablesItems = false
        let key = "T-\(target)"
        let one = ids.count == 1
        let these = one ? "T-\(ids[0])" : "These \(ids.count)"
        func add(_ title: String, _ enabled: Bool, _ run: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(runDropChoice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = DropChoice(run)
            item.isEnabled = enabled
            menu.addItem(item)
        }
        if let container = tree.container(of: target), let index = tree.index(of: target) {
            add(one ? "Add as Subtask of \(key)" : "Add as Subtasks of \(key)", tree.canMove(ids, to: .task(target))) { [weak self] in
                self?.drop(ids, into: .task(target), at: tree.children(of: target).count)
            }
            add("Add Above \(key)", tree.canMove(ids, to: container)) { [weak self] in self?.drop(ids, into: container, at: index) }
            add("Add Below \(key)", tree.canMove(ids, to: container)) { [weak self] in self?.drop(ids, into: container, at: index + 1) }
            menu.addItem(.separator())
        }
        let model = model
        add("Link to \(key)", true) { model.link(ids.map { ModalRoute.task($0) }, to: target) }
        add("\(key) Is Blocked by \(these)", ids.allSatisfy { flow.refusal(target, .blockedBy, $0) == nil }) {
            for id in ids { model.addLink(target, .blockedBy, id) }
        }
        add("\(these) \(one ? "Is" : "Are") Blocked by \(key)", ids.allSatisfy { flow.refusal($0, .blockedBy, target) == nil }) {
            for id in ids { model.addLink(id, .blockedBy, target) }
        }
        add("\(key) Comes After \(these)", ids.allSatisfy { flow.refusal(target, .after, $0) == nil }) {
            for id in ids { model.addLink(target, .after, id) }
        }
        add("\(these) \(one ? "Comes" : "Come") After \(key)", ids.allSatisfy { flow.refusal($0, .after, target) == nil }) {
            for id in ids { model.addLink(id, .after, target) }
        }
        if let pick = Self.pickDropChoice {
            if let item = pick(menu, moved) { runDropChoice(item) }
            return
        }
        menu.popUp(positioning: nil, at: point, in: outline)
    }

    /// The UI test picks from the drop menu instead of opening it: the grip's move or the carried task's, and what it chose.
    static var pickDropChoice: ((NSMenu, Bool) -> NSMenuItem?)?

    @objc private func runDropChoice(_ item: NSMenuItem) { (item.representedObject as? DropChoice)?.run() }

    /// The dropped rows stay selected where they landed.
    private func drop(_ ids: [Int], into container: TaskTree.Container, at index: Int) {
        guard model.drop(ids, into: container, at: index) else { return }
        // The rows land where they were dropped: no slide from where they were (2026-11-10).
        landing = true
        refresh()
        let rows = IndexSet(ids.map(row(of:)).filter { $0 >= 0 })
        if !rows.isEmpty { outline?.selectRowIndexes(rows, byExtendingSelection: false) }
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        DragItem.logEnd("task", operation: operation)
        dragEnded()
    }

    /// A drag ended, dropped, cancelled or outside the window: nothing stays marked. The rows change once AppKit is done
    /// with the drag session, after this call returns.
    func dragEnded() {
        dragged = []
        outline?.clearDrop()
        DispatchQueue.main.async { [weak self] in
            self?.refreshVisibleCells()
            self?.refresh()
        }
    }

    /// The mouse button is down: the system's, which a UI test sets so the user's own clicks beside it don't count.
    static var buttonDown: () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }

    /// A drag whose end never comes (its source gone) holds the rows until the button has been up 3 s.
    private func holdUntilDragEnds() {
        guard dragWatch == nil else { return }
        dragWatch = Task { [weak self] in
            var upSince: Date?
            while let self, !self.dragged.isEmpty {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Self.buttonDown() else { upSince = nil; continue }
                let since = upSince ?? .now
                upSince = since
                if Date.now.timeIntervalSince(since) >= 3 {
                    AppLog.write("outline: a drag of \(self.dragged) never ended; rows move again", to: "outline.log")
                    self.dragged = []
                }
            }
            self?.dragWatch = nil
            self?.refresh()
        }
    }

    private var dragWatch: Task<Void, Never>?

    /// What of the carried items can link to a task: not the task itself, nor what's linked there already.
    private func linkable(_ routes: [ModalRoute], to id: Int) -> [ModalRoute] {
        routes.filter { $0 != .task(id) && !model.isLinked($0, to: id) }
    }

    /// The task a link drop lands on: the row proposed, else the task row under the pointer.
    private func linkTarget(_ info: NSDraggingInfo, item: Any?, index: Int, outline: NSOutlineView) -> Int? {
        if index == NSOutlineViewDropOnItemIndex, let id = (item as? OutlineNode)?.task { return id }
        let row = outline.row(at: outline.convert(info.draggingLocation, from: nil))
        return row >= 0 ? (outline.item(atRow: row) as? OutlineNode)?.task : nil
    }

    /// The tasks a grip moves.
    private func draggedIDs(_ info: NSDraggingInfo) -> [Int]? {
        let ids = info.draggingPasteboard.pasteboardItems?.compactMap { $0.string(forType: DragItem.taskType).flatMap(Int.init) } ?? []
        return ids.isEmpty ? nil : ids
    }

    /// Where a drop lands, as the tree counts it; the outline is told where to show it.
    private func dropTarget(item: Any?, index: Int, outline: NSOutlineView) -> (container: TaskTree.Container, index: Int)? {
        let tree = model.taskTree
        switch kind(item) {
        case nil where root != nil:
            // A task's window: among its subtasks.
            guard let root else { return nil }
            let shown = snapshot.children(of: nil).compactMap { kind -> Int? in if case .task(let id) = kind { id } else { nil } }
            if index == NSOutlineViewDropOnItemIndex { return (.task(root), tree.children(of: root).count) }
            return (.task(root), treeIndex(before: index, of: shown, in: tree.children(of: root)))
        case nil:
            // Between the lists: the end of Tasks.
            let header = node(.header(.overview))
            let count = snapshot.children(of: .header(.overview)).filter { if case .task = $0 { true } else { false } }.count
            outline.setDropItem(header, dropChildIndex: count)
            return (.list(.overview), tree.top(.overview).count)
        case .header(let list):
            let shown = snapshot.children(of: .header(list))
            let tasks = shown.compactMap { kind -> Int? in if case .task(let id) = kind { id } else { nil } }
            if list == .backlog && !model.backlogOpen || index == NSOutlineViewDropOnItemIndex {
                // On the header: the end of that list.
                return (.list(list), tree.top(list).count)
            }
            // After the quick-add line: snap to the tasks.
            let before = shown.prefix(max(index, 0)).filter { if case .task = $0 { true } else { false } }.count
            let snapped = before
            if snapped != index { outline.setDropItem(node(.header(list)), dropChildIndex: snapped) }
            return (.list(list), treeIndex(before: before, of: tasks, in: tree.top(list)))
        case .task(let parent):
            let shown = snapshot.children(of: .task(parent)).compactMap { kind -> Int? in if case .task(let id) = kind { id } else { nil } }
            if index == NSOutlineViewDropOnItemIndex { return (.task(parent), tree.children(of: parent).count) }
            return (.task(parent), treeIndex(before: index, of: shown, in: tree.children(of: parent)))
        case .quickAdd, .empty:
            return nil
        }
    }

    /// A drop before the n-th shown child, as an index among all the children (search and filters hide some).
    private func treeIndex(before index: Int, of shown: [Int], in all: [Int]) -> Int {
        if index < shown.count { return all.firstIndex(of: shown[index]) ?? all.count }
        return shown.last.flatMap { all.firstIndex(of: $0) }.map { $0 + 1 } ?? all.count
    }
}

/// A task's context menu: the Task menu's commands for this row.
struct TaskMenu: View {
    let ids: [Int]
    @Environment(AppModel.self) private var model

    var body: some View {
        if ids.count > 1 {
            several
        } else if let id = ids.first, let task = model.task(id) {
            Button("Open") { model.open(.task(id)) }
            Button("Start Session…") { model.beginStart(task: id) }
            Button("Link…") { model.showLinkPicker(id) }
            if task.status != .done {
                if task.blocked { Button("Unblock") { model.unblock(id) } } else { Button("Block…") { model.showHoldPicker(id, .block) } }
                Button("Blocked By…") { model.showHoldPicker(id, .blockedBy) }
                Button("After…") { model.showHoldPicker(id, .after) }
            }
            ForEach(task.blockedBy, id: \.self) { other in Button("Not Blocked by T-\(other)") { model.removeLink(id, .blockedBy, other) } }
            ForEach(task.after, id: \.self) { other in Button("Not After T-\(other)") { model.removeLink(id, .after, other) } }
            Menu("Link to Session") {
                ForEach(model.gridSessions) { session in
                    Button(session.name) { model.link(task: id, session: session.id) }
                        .disabled(task.sessions.contains(session.id))
                }
            }
            .disabled(model.gridSessions.isEmpty)
            Divider()
            Button(task.status == .done ? "Mark Not Done" : "Mark Done") { model.toggleDone(id) }
            Menu("Status") {
                ForEach(TaskStatus.allCases) { status in
                    Toggle(status.title, isOn: Binding(get: { task.status == status }, set: { _ in model.setStatus(id, status) }))
                }
            }
            Divider()
            Button(model.descriptionShownInOutline(id) ? "Hide Description" : "Show Description") { model.toggleDescription(id) }
            if !model.taskTree.children(of: id).isEmpty {
                let shown = model.fold[id] != .hidden
                Button(shown ? "Hide Subtasks" : "Show Subtasks") { model.foldTasks([id], shown ? .hidden : .all) }
                if model.taskTree.parent(of: id) == nil {
                    Toggle("Only Blocked and Doing", isOn: Binding(get: { model.storyFilter.contains(id) }, set: { _ in model.filterStory(id) }))
                }
            }
            Button("Add Subtask") { if let added = model.addSubtask(to: id) { model.outlineFocus = .title(added.id, by: 0) } }
            Button(model.list(of: id) == .backlog ? "Move to Tasks" : "Move to Backlog") { model.toggleList(id) }
            Button("Remind Me…") { model.beginReminder(about: .task(id)) }
            Divider()
            Button("Copy") { model.copy([.task(id)]) }
            Button("Delete") { model.deleteTasks([id]) }
        }
    }

    /// Several selected rows: what applies to all of them.
    @ViewBuilder
    private var several: some View {
        let tasks = ids.compactMap { model.task($0) }
        let toBacklog = tasks.contains { model.list(of: $0.id) != .backlog }
        let allDone = tasks.allSatisfy { $0.status == .done }
        Button(allDone ? "Mark \(tasks.count) Not Done" : "Mark \(tasks.count) Done") { model.markDone(tasks.map(\.id)) }
        Menu("Status") {
            ForEach(TaskStatus.allCases) { status in
                Button(status.title) { for task in tasks { model.setStatus(task.id, status) } }
            }
        }
        Divider()
        Button(toBacklog ? "Move \(tasks.count) to Backlog" : "Move \(tasks.count) to Tasks") {
            model.moveTasks(tasks.map(\.id), toBacklog: toBacklog)
        }
        Divider()
        Button("Copy") { model.copy(tasks.map { .task($0.id) }) }
        Button("Delete \(tasks.count) Tasks") { model.deleteTasks(tasks.map(\.id)) }
    }
}

extension AppModel {
    /// Several tasks to the Backlog or to Tasks, keeping their order: the Backlog takes them at its top.
    /// A subtask selected with its parent goes with it.
    func moveTasks(_ ids: [Int], toBacklog: Bool) {
        let moving = outermost(ids).filter { (list(of: $0) == .backlog) != toBacklog }
        for id in toBacklog ? moving.reversed() : moving { toggleList(id) }
    }

    /// Several tasks done; when all are done already, not done.
    func markDone(_ ids: [Int]) {
        let allDone = ids.allSatisfy { task($0)?.status == .done }
        for id in ids where (task(id)?.status == .done) == allDone { toggleDone(id) }
    }

    /// The tasks among `ids` whose parent isn't among them: they carry the others.
    private func outermost(_ ids: [Int]) -> [Int] {
        let tree = taskTree
        return ids.filter { id in !ids.contains { $0 != id && tree.subtree(of: $0).contains(id) } }
    }

    /// Tab on rows: each under its previous sibling, in order, so a run of siblings nests together.
    func indentTasks(_ ids: [Int]) {
        for id in outermost(ids) { indent(id) }
    }

    /// ⇧Tab on rows: each out one level, last first, so siblings keep their order.
    func outdentTasks(_ ids: [Int]) {
        for id in outermost(ids).reversed() { outdent(id) }
    }

    /// ⇧↑ ⇧↓ on rows: each one place among its siblings, past the first or last out one level;
    /// a run stops whole at the end of its list.
    /// Past the first or last sibling a task goes out one level, unless `leavingParent` is false.
    func shiftTasks(_ ids: [Int], by offset: Int, leavingParent: Bool = true) {
        let moving = outermost(ids)
        var stuck = Set<Int>()
        for id in offset < 0 ? moving : moving.reversed() {
            let tree = taskTree
            guard let container = tree.container(of: id), let index = tree.index(of: id) else { continue }
            let siblings = tree.children(of: container)
            let target = index + offset
            let atTop: Bool = if case .list = container { true } else { false }
            let blocked = siblings.indices.contains(target) ? stuck.contains(siblings[target]) : atTop || !leavingParent || keptInWindow(id)
            guard !blocked else {
                stuck.insert(id)
                continue
            }
            shift(id, by: offset)
        }
    }

    /// ⇧Return on rows: shows every description, or hides them when the first is shown.
    func toggleDescriptions(_ ids: [Int]) {
        guard let first = ids.first else { return }
        let show = !descriptionShownInOutline(first)
        for id in ids where descriptionShownInOutline(id) != show { toggleDescription(id) }
    }

    /// No title, description, subtasks or outputs: leaving it deletes it.
    func isEmptyTask(_ id: Int) -> Bool {
        guard let task = task(id) else { return false }
        return task.title.trimmingCharacters(in: .whitespaces).isEmpty && task.tags.isEmpty
            && task.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && taskTree.children(of: id).isEmpty && outputs(ofTask: id).isEmpty
    }

    /// Shown one by one, or all at once by its list's Descriptions for the tasks that have one.
    func descriptionShownInOutline(_ id: Int) -> Bool {
        if shownDescriptions.contains(id) { return true }
        guard !allDescriptions.isEmpty, allDescriptions.contains(list(of: id)), !hiddenDescriptions.contains(id), let task = task(id) else { return false }
        return !task.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Shows or hides one description, also one its list's Descriptions shows.
    func toggleDescription(_ id: Int) {
        if descriptionShownInOutline(id) {
            shownDescriptions.remove(id)
            if descriptionShownInOutline(id) { hiddenDescriptions.insert(id) }
            if editingDescription == id { editingDescription = nil }
        } else {
            hiddenDescriptions.remove(id)
            if !descriptionShownInOutline(id) { shownDescriptions.insert(id) }
        }
    }
}
