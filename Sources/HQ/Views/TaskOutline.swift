import AppKit
import HQKit
import SwiftUI

/// Tasks and the Backlog as one view-based `NSOutlineView` (DESIGN.md §7), with no scroll view of its
/// own: it sits in the page's. Edited like a markdown todo file; rows drag between and into each other.
struct TaskOutline: NSViewRepresentable {
    let width: CGFloat
    @Environment(AppModel.self) private var model
    @State private var height: CGFloat = Metric.outlineHeader * 2

    func makeCoordinator() -> OutlineCoordinator { OutlineCoordinator(model: model) }

    func makeNSView(context: Context) -> OutlineContainer {
        let container = OutlineContainer(coordinator: context.coordinator)
        context.coordinator.container = container
        context.coordinator.onHeight = { [binding = $height] value in
            if binding.wrappedValue != value { binding.wrappedValue = value }
        }
        context.coordinator.refresh()
        return container
    }

    func updateNSView(_ container: OutlineContainer, context: Context) {
        context.coordinator.model = model
        model.showLinkPicker = { [weak coordinator = context.coordinator] id in coordinator?.showLinkPicker(id) }
        context.coordinator.onHeight = { [binding = $height] value in
            if binding.wrappedValue != value { binding.wrappedValue = value }
        }
        // Read what the outline shows, so SwiftUI calls this again when it changes.
        _ = (model.tasks, model.sessions, model.search, model.listSearch, model.hideDone, model.allDescriptions, model.shownDescriptions, model.hiddenDescriptions,
             model.backlogOpen, model.folded, model.backlogFilter, model.collapsed, model.editingDescription, model.seen,
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
    /// Tasks with subtasks to show, so their disclosure applies.
    var expandable: Set<Int> = []

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

    static func make(_ model: AppModel) -> OutlineSnapshot {
        var snapshot = OutlineSnapshot()
        let tree = model.taskTree
        /// A task's shown subtasks: Hide Done of its list hides the done ones, a search the ones it didn't find.
        func add(_ id: Int, hiding: Bool, found: Set<Int>?) {
            let children = tree.children(of: id).filter { child in
                !(hiding && model.task(child)?.status == .done) && (found?.contains(child) ?? true)
            }
            if !children.isEmpty {
                snapshot.expandable.insert(id)
                snapshot.children[.task(id)] = children.map { .task($0) }
                children.forEach { add($0, hiding: hiding, found: found) }
            }
        }
        snapshot.children[nil] = [.header(.overview), .header(.backlog)]
        let foundTasks = found(model, in: .overview)
        let tasks = model.folded.contains(.tasks) ? [] : matches(model, in: .overview, found: foundTasks)
        tasks.forEach { add($0, hiding: model.hideDone.contains(.overview), found: foundTasks) }
        var overview = tasks.map { OutlineNode.Kind.task($0) }
        if !model.folded.contains(.tasks) {
            if tasks.isEmpty { overview.append(.empty(.overview)) }
            overview.append(.quickAdd(.overview))
        }
        snapshot.children[.header(.overview)] = overview
        if model.backlogOpen {
            let foundLater = found(model, in: .backlog)
            let backlog = matches(model, in: .backlog, found: foundLater)
            backlog.forEach { add($0, hiding: model.hideDone.contains(.backlog), found: foundLater) }
            snapshot.children[.header(.backlog)] = backlog.map { .task($0) } + [.quickAdd(.backlog)]
        } else {
            snapshot.children[.header(.backlog)] = []
        }
        return snapshot
    }

    func children(of parent: OutlineNode.Kind?) -> [OutlineNode.Kind] { children[parent] ?? [] }
}

// MARK: Container

/// Holds the outline; its height goes to SwiftUI through the coordinator.
final class OutlineContainer: NSView {
    let outline = TaskOutlineView()

    init(coordinator: OutlineCoordinator) {
        super.init(frame: .zero)
        let faces = NSTableColumn(identifier: OutlineCoordinator.facesColumn)
        faces.width = OutlineCoordinator.facesWidth
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
        outline.indentationPerLevel = Metric.outlineIndent
        outline.indentationMarkerFollowsCell = true
        outline.autoresizesOutlineColumn = false
        outline.floatsGroupRows = false
        outline.allowsMultipleSelection = true
        outline.allowsEmptySelection = true
        outline.selectionHighlightStyle = .regular
        outline.focusRingType = .none
        outline.usesAutomaticRowHeights = false
        outline.registerForDraggedTypes([DragItem.taskType, DragItem.itemType])
        outline.setDraggingSourceOperationMask([.move, .link], forLocal: true)
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)
        outline.draggingDestinationFeedbackStyle = .gap
        outline.setAccessibilityLabel("Tasks and Backlog")
        outline.dataSource = coordinator
        outline.delegate = coordinator
        outline.coordinator = coordinator
        outline.target = coordinator
        outline.doubleAction = #selector(OutlineCoordinator.doubleClicked(_:))
        addSubview(outline)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // The outline fills the container whatever size its rows gave it: rows outside its frame take no clicks.
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
}

/// The outline: top-level tasks sit at the headers' level, titles edit on one click, and the
/// keys a row's title field doesn't take go to the coordinator.
final class TaskOutlineView: NSOutlineView {
    weak var coordinator: OutlineCoordinator?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// AppKit's disclosure triangle takes the pointing hand, as every control on a row does (T-350).
    override func makeView(withIdentifier identifier: NSUserInterfaceItemIdentifier, owner: Any?) -> NSView? {
        let view = super.makeView(withIdentifier: identifier, owner: owner)
        if identifier == NSOutlineView.disclosureButtonIdentifier { view?.trackHandCursor(for: HandCursorOwner.shared) }
        return view
    }

    /// How far a list's rows sit inside its card.
    static var cardInset: CGFloat { Space.sm }

    /// Tasks are children of a header: one level less indentation than the outline gives them.
    /// Their cells sit `cardInset` inside the list's card.
    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        var frame = super.frameOfCell(atColumn: column, row: row)
        guard let node = item(atRow: row) as? OutlineNode else { return frame }
        // Headers, the filter bar and empty lines span the row, flush with the page.
        if node.spans { return NSRect(x: 0, y: frame.minY, width: bounds.width, height: frame.height) }
        guard column == 1 else {
            frame.origin.x += Self.cardInset
            return frame
        }
        frame.origin.x += Self.cardInset - indentationPerLevel
        frame.size.width += indentationPerLevel - Self.cardInset * 2
        return frame
    }

    /// Tasks and the Backlog each sit on a raised card, from the row under their header to their last row: layers under
    /// the rows, so a scroll redraws nothing (T-337).
    private lazy var cards: CardsView = {
        let view = CardsView()
        addSubview(view, positioned: .below, relativeTo: nil)
        return view
    }()

    override func tile() {
        super.tile()
        placeCards()
    }

    override func layout() {
        super.layout()
        placeCards()
    }

    func placeCards() {
        if cards.frame != bounds { cards.frame = bounds }
        if subviews.first !== cards { addSubview(cards, positioned: .below, relativeTo: nil) }
        cards.show(listCards())
    }

    /// The cards' layers, for the UI test.
    var cardsView: CardsView { cards }

    /// The rows of each list under its header, as one rect each.
    private func listCards() -> [NSRect] {
        var cards: [NSRect] = []
        var start: Int?
        func close(_ end: Int) {
            if let first = start, end >= first {
                let rows = rect(ofRow: first).union(rect(ofRow: end))
                cards.append(NSRect(x: 0, y: rows.minY, width: bounds.width, height: rows.height))
            }
            start = nil
        }
        for row in 0..<numberOfRows {
            guard let node = item(atRow: row) as? OutlineNode else { continue }
            if case .header = node.kind { close(row - 1); continue }
            if start == nil { start = row }
        }
        close(numberOfRows - 1)
        return cards
    }

    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        var frame = super.frameOfOutlineCell(atRow: row)
        guard let node = item(atRow: row) as? OutlineNode, case .task = node.kind else { return .zero }
        frame.origin.x += Self.cardInset - indentationPerLevel
        // On the title's line, also when a description makes the row taller; OutlineRowView keeps it there.
        frame.origin.y = rect(ofRow: row).minY + (coordinator?.gap(ofRow: row) ?? 0)
        frame.size.height = Metric.outlineRow
        return frame
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
        // The press a drag starts from, also when AppKit doesn't ask canDragRows.
        dragsFromGrip = onGrip(point)
        let row = self.row(at: point)
        // The status glyph, the type icon and the faces take their clicks: the table would only select the row.
        // ⌥ goes through too: ⌥-click on the status picks one.
        if row >= 0, event.modifierFlags.intersection([.shift, .control, .command]).isEmpty {
            if event.clickCount == 1, let button = (view(atColumn: 1, row: row, makeIfNecessary: false) as? TaskCell)?.button(at: event.locationInWindow) {
                button.mouseDown(with: event)
                return
            }
            if let faces = view(atColumn: 0, row: row, makeIfNecessary: false) as? FacesCell, faces.click(event) { return takeRelease() }
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

    /// The drag starting now came from a grip: it moves the rows. From anywhere else it carries the tasks, to link them
    /// where they land and to give other apps their lines (T-348, T-359).
    private(set) var dragsFromGrip = false

    override func canDragRows(with rowIndexes: IndexSet, at mouseDownPoint: NSPoint) -> Bool {
        dragsFromGrip = onGrip(mouseDownPoint)
        return super.canDragRows(with: rowIndexes, at: mouseDownPoint)
    }

    /// A point in the outline on a row's grip.
    private func onGrip(_ point: NSPoint) -> Bool {
        let row = row(at: point)
        let faces = row >= 0 ? view(atColumn: 0, row: row, makeIfNecessary: false) as? FacesCell : nil
        return faces?.onGrip(convert(point, to: nil)) == true
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
        if let (route, task) = link(at: event), let model = coordinator?.model {
            model.selectedItem = route.chipKey(task: task)
            return model.linkMenu(route, task: task)
        }
        return coordinator?.menu(forRow: row)
    }

    /// A right-click on a link chip under a task: the link's menu, where the click was.
    override func rightMouseDown(with event: NSEvent) {
        guard let (route, task) = link(at: event), let model = coordinator?.model else { return super.rightMouseDown(with: event) }
        model.selectedItem = route.chipKey(task: task)
        FaceMenu.show(model.linkMenu(route, task: task), route.chipKey(task: task), convert(event.locationInWindow, from: nil), self)
    }

    /// The link chip under the event, and its task.
    private func link(at event: NSEvent) -> (route: ModalRoute, task: Int)? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        return (view(atColumn: 1, row: row, makeIfNecessary: false) as? TaskCell)?.link(at: event.locationInWindow)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { coordinator?.keyboardChanged() }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { DispatchQueue.main.async { [weak self] in self?.coordinator?.keyboardChanged() } }
        return resigned
    }

    /// Drag images: the row as it looks.
    override func dragImageForRows(with dragRows: IndexSet, tableColumns: [NSTableColumn], event dragEvent: NSEvent,
                                   offset dragImageOffset: NSPointPointer) -> NSImage {
        super.dragImageForRows(with: dragRows, tableColumns: tableColumns, event: dragEvent, offset: dragImageOffset)
    }
}

// MARK: Coordinator

final class OutlineCoordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate {
    static let facesColumn = NSUserInterfaceItemIdentifier("faces")
    static let mainColumn = NSUserInterfaceItemIdentifier("main")
    /// One face per row (2026-11-05).
    static let faces = 1
    /// Grip, attention dot and the face, with room between each.
    static var facesWidth: CGFloat { Space.md + Space.sm + Space.sm + FaceStackView.width(faces, limit: faces, more: false) }
    private var facesWidth: CGFloat { Self.facesWidth }

    var model: AppModel
    weak var container: OutlineContainer?
    var onHeight: (CGFloat) -> Void = { _ in }
    var width: CGFloat = 0 { didSet { if width != oldValue { heights.removeAll(); remeasure = true } } }
    private var outline: TaskOutlineView? { container?.outline }
    private var snapshot = OutlineSnapshot() { didSet { gapped = Self.gapped(snapshot) } }
    /// Top-level tasks that follow another task in their list: a gap above them.
    private var gapped: [Int: CGFloat] = [:]
    /// Tasks with links: a line of chips under their title.
    private var withLinks: Set<Int> = []
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

    init(model: AppModel) {
        self.model = model
        super.init()
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
    }

    /// Link… on a row: the link picker in a popover under the task's title, the row selected.
    func showLinkPicker(_ id: Int) {
        guard let outline else { return }
        let row = outline.row(forItem: node(.task(id)))
        guard row >= 0 else { return }
        outline.selectRowIndexes([row], byExtendingSelection: false)
        // The page scrolls, not the outline: the row comes into view clear of the toolbar, or the popover has nothing to show under.
        outline.scrollToVisible(outline.rect(ofRow: row).insetBy(dx: 0, dy: -Metric.outlineRow * 3))
        // Shown once the page has laid the row out where it scrolled.
        DispatchQueue.main.async { [weak self] in
            guard let self, let outline = self.outline else { return }
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentViewController = NSHostingController(rootView: LinkPicker(task: id) { [weak popover] in popover?.close() }
                .environment(self.model).handCursors())
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
        guard let outline, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        // Another section took the page's selection: the rows unselect, kept aside for when Tab comes back.
        if model.selectedSection != .tasks, !outline.selectedRowIndexes.isEmpty {
            parked = selectedIDs
            outline.deselectAll(nil)
        }
        withLinks = model.tasksWithOutputs
        let next = OutlineSnapshot.make(model)
        if outline.numberOfRows == 0 {
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
        if let focus = model.quickAddFocus {
            model.quickAddFocus = nil
            DispatchQueue.main.async { [weak self] in self?.focusQuickAdd(focus) }
        }
        if let focus = model.outlineFocus {
            model.outlineFocus = nil
            DispatchQueue.main.async { [weak self] in self?.take(focus) }
        }
        if model.sectionFocus == .tasks {
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
        if !model.tasks.isEmpty { LaunchLog.mark("tasks") }
        reportHeight()
    }

    /// Reloads that put lost rows back: none in a UI test run.
    static var repairs = 0

    /// The outline shows every row of the snapshot: if AppKit lost one of the changes, a reload puts them back, logged.
    private func verifyRows() {
        guard let outline else { return }
        // A shown task whose links don't show under its row (T-352, not reproduced): its row again, logged.
        var linkless: [Int] = []
        outline.enumerateAvailableRowViews { _, row in
            guard let id = (outline.item(atRow: row) as? OutlineNode)?.task, withLinks.contains(id),
                  let cell = outline.view(atColumn: 1, row: row, makeIfNecessary: false) as? TaskCell else { return }
            if cell.linksHost == nil || outline.rect(ofRow: row).height < gap(of: id) + Metric.outlineRow + Metric.linksLine - 0.5 { linkless.append(row) }
        }
        if !linkless.isEmpty {
            Self.repairs += 1
            AppLog.write("outline: \(linkless.compactMap { (outline.item(atRow: $0) as? OutlineNode)?.task }.map { "T-\($0)" }.joined(separator: ", ")) have links their rows don't show; refitted",
                         to: "outline.log")
            for row in linkless { configure(row: row) }
            outline.noteHeightOfRows(withIndexesChanged: IndexSet(linkless))
        }
        var expected = 0
        func count(_ parent: OutlineNode.Kind?) {
            for child in snapshot.children(of: parent) {
                expected += 1
                if snapshot.children[child] != nil, outline.isItemExpanded(node(child)) { count(child) }
            }
        }
        count(nil)
        // A task the user left open that AppKit shows closed, without its subtasks: opened again, logged.
        let shut = snapshot.expandable.filter { id in
            (!model.collapsed.contains(id) || !model.search.isEmpty) && row(of: id) >= 0 && !outline.isItemExpanded(node(.task(id)))
        }
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

    private func row(of id: Int) -> Int { outline?.row(forItem: node(.task(id))) ?? -1 }

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
    private func select(_ ids: [Int]) {
        guard let outline else { return }
        let rows = IndexSet(ids.map(row(of:)).filter { $0 >= 0 })
        guard let first = rows.first else { return }
        outline.selectRowIndexes(rows, byExtendingSelection: false)
        outline.scrollRowToVisible(first)
        if outline.window?.firstResponder !== outline { outline.window?.makeFirstResponder(outline) }
    }

    /// Selects a task's row; with the keyboard, the outline takes it.
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
        let still = changed > 24
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
        outline.expandItem(node(.header(.overview)))
        outline.expandItem(node(.header(.backlog)))
        expandOpen(snapshot.children(of: .header(.overview)) + snapshot.children(of: .header(.backlog)))
    }

    /// These tasks and their subtasks, open or folded as the user left them.
    private func expandOpen(_ kinds: [OutlineNode.Kind]) {
        guard let outline else { return }
        var queue = kinds
        while let kind = queue.popLast() {
            guard case .task(let id) = kind, snapshot.expandable.contains(id) else { continue }
            let open = !model.collapsed.contains(id) || !model.search.isEmpty
            if open != outline.isItemExpanded(node(kind)) {
                if open { outline.expandItem(node(kind)) } else { outline.collapseItem(node(kind)) }
            }
            if open { queue.append(contentsOf: snapshot.children(of: kind)) }
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
            cell.gap = gap
            cell.show(model: model, id: id, coordinator: self, hovered: (outline.rowView(atRow: row, makeIfNecessary: false) as? OutlineRowView)?.hovered ?? false)
        } else if let cell = outline.view(atColumn: node.spans ? 0 : 1, row: row, makeIfNecessary: false) as? HostCell {
            cell.show(hosted(node))
        } else if let cell = outline.view(atColumn: 1, row: row, makeIfNecessary: false) as? QuickAddCell, case .quickAdd(let list) = node.kind {
            cell.configure(list: list, coordinator: self)
        }
        if let faces = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? FacesCell, let id = node.task {
            faces.gap = gap
            faces.show(model: model, id: id)
        }
    }

    /// The rows' height goes to SwiftUI now, and again once row animations end.
    func reportHeight() {
        guard let container else { return }
        let height = container.contentHeight
        DispatchQueue.main.async { [weak self] in
            self?.onHeight(height)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, let container = self.container else { return }
                let rows = container.contentHeight
                self.onHeight(rows)
                if container.outline.frame != container.bounds {
                    AppLog.write("outline: frame \(Int(container.outline.frame.height)) in its container's \(Int(container.frame.height)); refitted", to: "outline.log")
                    container.fill()
                }
                // The page left the outline shorter than its rows: the rows below would be cut. Logged, and asked again.
                guard container.frame.height + 0.5 < rows else { return }
                AppLog.write("outline: frame \(Int(container.frame.height)) for rows \(Int(rows)); asked again", to: "outline.log")
                self.onHeight(rows + 1)
                DispatchQueue.main.async { [weak self] in self?.onHeight(rows) }
            }
        }
    }

    // MARK: Descriptions

    func descriptionShown(_ id: Int) -> Bool {
        model.descriptionShownInOutline(id) || model.editingDescription == id
    }

    /// Space above a task's line: top-level tasks that follow another task in their list.
    func gap(of id: Int) -> CGFloat { gapped[id] ?? 0 }

    /// The space above each top-level task: the list card's top padding above the first, a group gap between tasks.
    private static func gapped(_ snapshot: OutlineSnapshot) -> [Int: CGFloat] {
        var ids: [Int: CGFloat] = [:]
        for list in TaskList.allCases {
            var previousIsTask = false
            for (index, kind) in snapshot.children(of: .header(list)).enumerated() {
                if case .task(let id) = kind {
                    if previousIsTask { ids[id] = Metric.outlineGroupGap } else if index == 0 { ids[id] = Metric.listCardPadding }
                    previousIsTask = true
                } else {
                    previousIsTask = false
                }
            }
        }
        return ids
    }

    /// The gap above the task on a row, if it's a task's.
    func gap(ofRow row: Int) -> CGFloat {
        (outline?.item(atRow: row) as? OutlineNode)?.task.map(gap(of:)) ?? 0
    }

    /// The task row's height under its gap: its line, its links, and its description when shown.
    private func height(of id: Int) -> CGFloat {
        let line = Metric.outlineRow + (withLinks.contains(id) ? Metric.linksLine : 0)
        guard descriptionShown(id), let outline else { return line }
        let task = model.task(id)
        let editing = model.editingDescription == id
        var hasher = Hasher()
        hasher.combine(task?.body)
        hasher.combine(editing)
        hasher.combine(model.outputs(ofTask: id))
        let key = hasher.finalize()
        if let cached = heights[id], cached.key == key { return line + cached.height }
        // The task cell's width at its level, less the glyphs before the title.
        let level = CGFloat(max(outline.level(forItem: node(.task(id))), 1))
        let available = width - facesWidth - level * outline.indentationPerLevel - TaskCell.titleX
        let height = editing ? Metric.editorMin + Space.xl : DescriptionBlock.measure(model: model, id: id, width: max(available, Metric.titleMinimum))
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
        case .quickAdd: Metric.outlineQuick + Metric.listCardPadding
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
        row.onHover = { [weak self, weak row] hovered in
            guard let self, let row, let outline = self.outline else { return }
            let index = outline.row(for: row)
            if index >= 0, let cell = outline.view(atColumn: 1, row: index, makeIfNecessary: false) as? TaskCell { cell.setHovered(hovered) }
            if index >= 0, let cell = outline.view(atColumn: 0, row: index, makeIfNecessary: false) as? FacesCell { cell.setHovered(hovered) }
        }
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
            cell.gap = gap(of: id)
            cell.show(model: model, id: id)
            return cell
        case (Self.mainColumn, .task(let id)):
            let cell = outlineView.makeView(withIdentifier: TaskCell.id, owner: nil) as? TaskCell ?? TaskCell()
            cell.gap = gap(of: id)
            cell.show(model: model, id: id, coordinator: self, hovered: false)
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
            .padding(.leading, facesWidth + TaskOutlineView.cardInset + TaskCell.titleX))
        default: AnyView(EmptyView())
        }
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? OutlineNode)?.task != nil
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outline else { return }
        let row = outline.selectedRow
        let id = row >= 0 ? (outline.item(atRow: row) as? OutlineNode)?.task : nil
        if model.focusedTask != id { model.focusedTask = id }
        let selected = outline.selectedRowIndexes.compactMap { (outline.item(atRow: $0) as? OutlineNode)?.task }
        if model.selectedTasks != selected { model.selectedTasks = selected }
        // A chip under a row unselects when the rows change; a click on a chip selects it again after.
        if model.modal == nil, model.selectedItem.flatMap(AppModel.section(ofItem:)) == .tasks { model.selectedItem = nil }
        if !selected.isEmpty { model.selectSection(.tasks) }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !refreshing, let id = ((notification.userInfo?["NSObject"]) as? OutlineNode)?.task else { return }
        model.setCollapsed(id, false)
        // AppKit loads its subtasks folded: the ones the user left open open again.
        refreshing = true
        defer { refreshing = false }
        expandOpen(snapshot.children(of: .task(id)))
    }

    /// Folding a task whose subtask is selected selects the task.
    private var foldingSelection = false

    func outlineViewItemWillCollapse(_ notification: Notification) {
        guard let outline, let item = notification.userInfo?["NSObject"] as? OutlineNode else { return }
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
        model.setCollapsed(id, true)
    }

    // MARK: Clicks and keys

    @objc func doubleClicked(_ sender: NSOutlineView) {
        guard let id = (sender.item(atRow: sender.clickedRow) as? OutlineNode)?.task else { return }
        model.open(.task(id))
    }

    func keyboardChanged() {
        guard let outline, let window = outline.window else { return }
        let responder = window.firstResponder
        // The outline's rows, or a title's field editor: not a description's editor, which keeps its text keys.
        let keyboard: OutlineKeyboard = if responder === outline { .rows }
            else if (responder as? NSTextView)?.editedTitle != nil { .title }
            else { .none }
        if model.outlineKeyboard != keyboard { model.outlineKeyboard = keyboard }
    }

    /// Keys on selected rows, DESIGN.md §7. Return and Tab never reach the table, which would edit a title.
    func key(_ event: NSEvent) -> Bool {
        let ids = selectedIDs
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let letter = event.charactersIgnoringModifiers?.lowercased()
        let newTask = letter == "n" && flags.subtracting(.shift).isEmpty
        guard let first = ids.first, let last = ids.last else {
            if newTask { model.focusQuickAdd(.overview) }
            return newTask
        }
        switch (event.keyCode, flags) {
        case (36, []), (76, []): beginEditing(first)
        case (36, .shift), (76, .shift): model.toggleDescriptions(ids)
        case (36, .command), (76, .command): model.nextStatus(ids)
        case (36, [.command, .option]), (76, [.command, .option]): model.beginStart(task: first)
        case (36, _), (76, _): break
        case (48, []), (48, .shift): leaveSection(by: flags.contains(.shift) ? -1 : 1)
        case (48, _): break
        // A held key moves among siblings only: it never indents, outdents or leaves the parent.
        case (124, .shift): if !event.isARepeat { model.indentTasks(ids) }
        case (123, .shift): if !event.isARepeat { model.outdentTasks(ids) }
        case (126, .shift): model.shiftTasks(ids, by: -1, leavingParent: !event.isARepeat)
        case (125, .shift): model.shiftTasks(ids, by: 1, leavingParent: !event.isARepeat)
        case (49, []): model.open(.task(first))
        case (51, []), (117, []), (51, .command): model.deleteTasks(ids)
        default:
            guard newTask else { return false }
            let added = flags.contains(.shift) ? model.addSubtask(to: first) : model.addTask(after: last)
            guard let added else { break }
            pendingEdit = (added.id, true)
            refresh()
        }
        return true
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
            if left { model.outdent(id) } else { model.indent(id) }
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
        var row = outline.row(forItem: node(.task(id))) + offset
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
        let split = TitleTags.split(text)
        if split.title != task.title || !split.tags.allSatisfy(task.tags.contains) { model.setTitle(id, text) }
        if !split.tags.isEmpty { field.stringValue = model.task(id)?.title ?? split.title }
    }

    func editDescription(_ id: Int) {
        model.shownDescriptions.insert(id)
        model.editingDescription = id
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
        editDescription(id)
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
        let pasteboard = NSPasteboardItem()
        if (outlineView as? TaskOutlineView)?.dragsFromGrip == true {
            pasteboard.setString("\(id)", forType: DragItem.taskType)
        } else {
            pasteboard.setData(Data(ModalRoute.task(task.id).selectionKey.utf8), forType: DragItem.itemType)
        }
        pasteboard.setString(model.line(of: .task(task.id)), forType: .string)
        return pasteboard
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
        session.draggingFormation = .list
        dragBegan(draggedItems.compactMap { ($0 as? OutlineNode)?.task })
    }

    func dragBegan(_ ids: [Int]) { dragged = ids }

    private(set) var dragged: [Int] = []

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let carried = DragItem.routes(on: info.draggingPasteboard)
        if !carried.isEmpty {
            // Onto the task under the pointer, its row highlighted: they link there.
            guard let id = linkTarget(info, item: item, index: index, outline: outlineView), !linkable(carried, to: id).isEmpty else { return [] }
            outlineView.setDropItem(node(.task(id)), dropChildIndex: NSOutlineViewDropOnItemIndex)
            return .link
        }
        guard let ids = draggedIDs(info), !ids.isEmpty, let target = dropTarget(item: item, index: index, outline: outlineView) else { return [] }
        guard model.taskTree.canMove(ids, to: target.container) else { return [] }
        return .move
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let carried = DragItem.routes(on: info.draggingPasteboard)
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

    /// The dropped rows stay selected where they landed.
    private func drop(_ ids: [Int], into container: TaskTree.Container, at index: Int) {
        guard model.drop(ids, into: container, at: index) else { return }
        refresh()
        let rows = IndexSet(ids.map(row(of:)).filter { $0 >= 0 })
        if !rows.isEmpty { outline?.selectRowIndexes(rows, byExtendingSelection: false) }
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragEnded()
    }

    /// A drag ended, dropped, cancelled or outside the window: nothing stays marked. The rows change once AppKit is done
    /// with the drag session, after this call returns.
    func dragEnded() {
        dragged = []
        DispatchQueue.main.async { [weak self] in
            self?.refreshVisibleCells()
            self?.refresh()
        }
    }

    /// A drag whose end never comes (its source gone) holds the rows until the button has been up 3 s.
    private func holdUntilDragEnds() {
        guard dragWatch == nil else { return }
        dragWatch = Task { [weak self] in
            var upSince: Date?
            while let self, !self.dragged.isEmpty {
                try? await Task.sleep(for: .milliseconds(250))
                guard NSEvent.pressedMouseButtons & 1 == 0 else { upSince = nil; continue }
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
            let blocked = siblings.indices.contains(target) ? stuck.contains(siblings[target]) : atTop || !leavingParent
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
