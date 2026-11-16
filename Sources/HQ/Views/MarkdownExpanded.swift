import AppKit
import HQKit
import SwiftUI

/// A table or a diagram opened to the whole sheet (T-490), named by the heading it sits under.
struct ExpandedBlock: Hashable {
    enum Content {
        case table(MarkdownTableLayout)
        case diagram(String)
    }

    let id = UUID()
    let heading: String?
    let content: Content

    var title: String {
        if let heading { return heading }
        if case .table = content { return "Table" }
        return "Diagram"
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension AppModel {
    /// An expanded diagram is the sheet's: View › Zoom and ⌘9 act on it.
    var diagramShown: Bool {
        if case .block(let block) = modal, case .diagram = block.content { true } else { false }
    }

    /// Expands a block over the modal it's in, Back and Escape returning to it; from the page, the sheet opens on it.
    func expand(_ block: ExpandedBlock) { open(.block(block), push: modal != nil) }
}

/// The expanded block on a card that fills the sheet.
struct ExpandedBlockView: View {
    let block: ExpandedBlock
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var diagram: MermaidRenderer.Result?

    var body: some View {
        Group {
            switch block.content {
            case .table(let layout):
                ExpandedTable(layout: layout)
                    .uiTestAnchor("expanded-table")
            case .diagram(let source):
                switch MermaidRenderer.shared.cached(source, dark: scheme == .dark) ?? diagram {
                case .image(let image):
                    ExpandedDiagram(image: image, zoom: model.diagramZoom)
                        .uiTestAnchor("expanded-diagram")
                case .failed(let message):
                    Text("Couldn’t draw this diagram: \(message)").kitType(.secondary).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case nil:
                    LoadingLine(title: "Drawing the diagram…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .task(id: "\(scheme)\n\(source)") { diagram = await MermaidRenderer.shared.render(source, dark: scheme == .dark) }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .surface(radius: Radius.card)
        .padding([.horizontal, .bottom], Space.xxl)
        .padding(.top, Space.sm)
    }
}

// MARK: Table

extension MarkdownTableLayout {
    /// The table as markdown: its cells' marks, the alignment row, pipes escaped.
    nonisolated var markdown: String {
        func cell(_ text: NSAttributedString) -> String { text.string.replacingOccurrences(of: "|", with: "\\|") }
        func line(_ cells: [String]) -> String { "| " + cells.joined(separator: " | ") + " |" }
        let columns = widths.count
        let marks = (0..<columns).map { column in
            switch alignments.indices.contains(column) ? alignments[column] : .leading {
            case .leading: "---"
            case .center: ":-:"
            case .trailing: "--:"
            }
        }
        var lines = [line((cells.first ?? []).map(cell)), line(marks)]
        lines += cells.dropFirst().map { line($0.map(cell)) }
        return lines.joined(separator: "\n")
    }

    /// Rows as tab-separated lines, as Numbers pastes them.
    nonisolated func tabSeparated(_ rows: [Int]) -> String {
        rows.map { cells[$0].map { $0.string.replacingOccurrences(of: "\t", with: " ") }.joined(separator: "\t") }.joined(separator: "\n")
    }

    /// Each body row's height with its cells wrapped at these text widths, padded `pad` above and below.
    nonisolated func wrappedHeights(_ widths: [CGFloat], pad: CGFloat) -> [CGFloat] {
        cells.indices.dropFirst().map { row in
            var height = lines[row]
            for (column, cell) in cells[row].enumerated() where widths.indices.contains(column) && self.widths[column] > widths[column] + 0.5 {
                let size = NSSize(width: widths[column], height: .greatestFiniteMagnitude)
                height = max(height, ceil(cell.boundingRect(with: size, options: [.usesLineFragmentOrigin, .usesFontLeading]).height))
            }
            return height + 2 * pad
        }
    }
}

/// The whole table: AppKit makes only the rows in view, the header row stays on top.
private struct ExpandedTable: NSViewRepresentable {
    let layout: MarkdownTableLayout
    @Environment(\.openURL) private var openURL

    func makeNSView(context: Context) -> NSScrollView {
        let table = ExpandedTableView(layout: layout)
        table.open = { openURL($0) }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        (scroll.documentView as? ExpandedTableView)?.open = { openURL($0) }
    }
}

/// Rows that alternate, sort by a header (a third click back to the note's order), select, copy as tab-separated lines,
/// and wrap a cell past its column's 320 pt; a column resizes by its header's edge.
final class ExpandedTableView: NSTableView, NSTableViewDataSource, NSTableViewDelegate {
    let layout: MarkdownTableLayout
    var open: (URL) -> Void = { _ in }
    /// The body rows, in the order shown: the note's, or sorted.
    private(set) var order: [Int]
    /// Each body row's height, by its row in the note.
    private var heights: [CGFloat]
    private var measuring: Task<Void, Never>?
    private static let cellID = NSUserInterfaceItemIdentifier("expanded-cell")
    private static let rowID = NSUserInterfaceItemIdentifier("expanded-row")

    init(layout: MarkdownTableLayout) {
        self.layout = layout
        order = Array(layout.cells.indices.dropFirst())
        heights = layout.lines.map { $0 + 2 * Space.sm }
        super.init(frame: .zero)
        style = .plain
        intercellSpacing = .zero
        backgroundColor = .clear
        gridStyleMask = []
        columnAutoresizingStyle = .noColumnAutoresizing
        allowsMultipleSelection = true
        allowsColumnReordering = false
        allowsColumnResizing = true
        usesAutomaticRowHeights = false
        focusRingType = .none
        let header = layout.cells.first ?? []
        for column in layout.widths.indices {
            let item = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(column)"))
            item.headerCell = ExpandedHeaderCell(textCell: header.indices.contains(column) ? header[column].string : "")
            item.headerCell.alignment = alignment(column)
            // A point to spare: TextKit wraps a line that fills its width exactly.
            item.width = ceil(min(layout.widths[column], Metric.expandedColumn)) + 2 * Space.sm + 1
            item.minWidth = Metric.boxRow
            item.maxWidth = .greatestFiniteMagnitude
            item.sortDescriptorPrototype = NSSortDescriptor(key: "\(column)", ascending: true)
            item.headerToolTip = "Sort by \(item.title)"
            addTableColumn(item)
        }
        dataSource = self
        delegate = self
        measure()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func alignment(_ column: Int) -> NSTextAlignment {
        switch layout.alignments.indices.contains(column) ? layout.alignments[column] : .leading {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
    }

    /// Row heights for the columns' widths, measured off the main thread; one line each until then.
    private func measure() {
        measuring?.cancel()
        let layout = layout, pad = Space.sm
        let widths = tableColumns.map { $0.width - 2 * pad }
        measuring = Task { [weak self] in
            let measured = await Task.detached(priority: .userInitiated) { layout.wrappedHeights(widths, pad: pad) }.value
            guard !Task.isCancelled, let self else { return }
            self.heights = [layout.lines.first ?? 0] + measured
            self.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<self.order.count))
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { order.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { heights[order[row]] }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = makeView(withIdentifier: Self.rowID, owner: nil) as? ExpandedRow ?? ExpandedRow()
        view.identifier = Self.rowID
        view.striped = row % 2 == 1
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let column = tableColumns.firstIndex(of: tableColumn) else { return nil }
        let cell = makeView(withIdentifier: Self.cellID, owner: nil) as? MarkdownCell ?? MarkdownCell()
        cell.identifier = Self.cellID
        cell.textContainerInset = NSSize(width: Space.sm, height: Space.sm)
        let cells = layout.cells[order[row]]
        cell.show(cells.indices.contains(column) ? cells[column] : NSAttributedString(), selectable: false, link: layout.style.link) { [weak self] in
            self?.open($0)
        }
        return cell
    }

    func tableViewColumnDidResize(_ notification: Notification) { measure() }

    /// A header click sorts by its column, again reverses, a third time goes back to the note's order.
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        let selected = Set(selectedRowIndexes.map { order[$0] })
        if let new = sortDescriptors.first, let old = oldDescriptors.first, new.key == old.key, !old.ascending, new.ascending {
            sortDescriptors = []
            return
        }
        if let sort = sortDescriptors.first, let column = sort.key.flatMap(Int.init) {
            let text = { (row: Int) -> String in self.layout.cells[row].indices.contains(column) ? self.layout.cells[row][column].string : "" }
            order.sort { a, b in
                let result = text(a).localizedStandardCompare(text(b))
                return result == .orderedSame ? a < b : (result == .orderedAscending) == sort.ascending
            }
        } else {
            order.sort()
        }
        reloadData()
        selectRowIndexes(IndexSet(order.indices.filter { selected.contains(order[$0]) }), byExtendingSelection: false)
    }

    /// ⌘C: the selected rows as tab-separated lines.
    @objc func copy(_ sender: Any?) {
        let rows = selectedRowIndexes.map { order[$0] }
        guard !rows.isEmpty else { return }
        Pasteboard.copy(layout.tabSeparated(rows))
    }
}

/// A header title as far in as its cells' text: AppKit's own 3 pt, and the rest.
final class ExpandedHeaderCell: NSTableHeaderCell {
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: cellFrame.insetBy(dx: Space.sm - 3, dy: 0), in: controlView)
    }
}

/// A row on the card, every other one faintly filled.
private final class ExpandedRow: NSTableRowView {
    var striped = false { didSet { if striped != oldValue { needsDisplay = true } } }

    override func drawBackground(in dirtyRect: NSRect) {
        guard striped else { return }
        Ink.trayNS.setFill()
        bounds.fill()
    }
}

// MARK: Diagram

/// The expanded diagram's zoom, shown and set from the sheet's header and View › Zoom.
@Observable
final class DiagramZoom {
    private(set) var scale: CGFloat = 1
    /// Fit to the sheet, and kept fit as the sheet takes its size, until the user zooms.
    @ObservationIgnored private(set) var fitted = true
    @ObservationIgnored weak var scroll: NSScrollView?
    static let steps: [CGFloat] = [0.25, 0.33, 0.5, 0.67, 0.75, 0.9, 1, 1.25, 1.5, 2, 3, 4]

    /// The diagram whole in the sheet, never past twice its size.
    func fit() {
        fitted = true
        guard let scroll, let document = scroll.documentView, scroll.contentSize.width > 0, scroll.contentSize.height > 0 else { return }
        let size = document.frame.size
        guard size.width > 0, size.height > 0 else { return }
        let value = min(scroll.contentSize.width / size.width, scroll.contentSize.height / size.height, 2)
        if abs(value - scroll.magnification) > 0.001 { apply(value) } else { read() }
    }

    /// The next step in or out, about the middle of what shows.
    func step(_ by: Int) {
        let next = by > 0 ? Self.steps.first { $0 > scale + 0.01 } : Self.steps.last { $0 < scale - 0.01 }
        if let next { set(next) }
    }

    func set(_ value: CGFloat) {
        fitted = false
        apply(value)
    }

    /// A pinch ended.
    func pinched() {
        fitted = false
        read()
    }

    private func apply(_ value: CGFloat) {
        guard let scroll else { return }
        let middle = NSPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.midY)
        scroll.setMagnification(min(max(value, scroll.minMagnification), scroll.maxMagnification), centeredAt: middle)
        read()
    }

    private func read() {
        if let scroll, abs(scroll.magnification - scale) > 0.001 { scale = scroll.magnification }
    }
}

/// Keeps its diagram fit while the sheet takes its size, until the user zooms.
private final class DiagramScroll: NSScrollView {
    weak var zoom: DiagramZoom?

    override func layout() {
        super.layout()
        if let zoom, zoom.fitted { zoom.fit() }
    }
}

/// The diagram as a vector image: pinch to zoom, scroll or drag to pan, centered while it's smaller than the sheet.
private struct ExpandedDiagram: NSViewRepresentable {
    let image: NSImage
    let zoom: DiagramZoom

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = DiagramScroll()
        scroll.zoom = zoom
        scroll.contentView = CenteringClip()
        let view = PanImageView(frame: NSRect(origin: .zero, size: image.size))
        view.image = image
        view.imageScaling = .scaleAxesIndependently
        scroll.documentView = view
        scroll.allowsMagnification = true
        scroll.minMagnification = DiagramZoom.steps.first ?? 0.25
        scroll.maxMagnification = DiagramZoom.steps.last ?? 4
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        zoom.scroll = scroll
        zoom.fit()
        context.coordinator.observe(scroll, zoom)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        zoom.scroll = scroll
        if let view = scroll.documentView as? NSImageView, view.image !== image {
            view.image = image
            view.setFrameSize(image.size)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var observer: Any?

        func observe(_ scroll: NSScrollView, _ zoom: DiagramZoom) {
            observer = NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveMagnifyNotification, object: scroll, queue: .main) { _ in
                MainActor.assumeIsolated { zoom.pinched() }
            }
        }

        isolated deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}

/// Keeps a document smaller than the view in its middle.
private final class CenteringClip: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        if rect.width > document.frame.width { rect.origin.x = (document.frame.width - rect.width) / 2 }
        if rect.height > document.frame.height { rect.origin.y = (document.frame.height - rect.height) / 2 }
        return rect
    }
}

/// A drag pans the diagram, with the open and closed hands.
private final class PanImageView: NSImageView {
    private var last: NSPoint?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, trackingAreas.isEmpty {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self))
        }
    }

    override func cursorUpdate(with event: NSEvent) { (last == nil ? NSCursor.openHand : NSCursor.closedHand).set() }

    override func mouseDown(with event: NSEvent) {
        last = event.locationInWindow
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last, let clip = enclosingScrollView?.contentView else { return }
        let now = event.locationInWindow
        let scale = enclosingScrollView?.magnification ?? 1
        var origin = clip.bounds.origin
        origin.x -= (now.x - last.x) / scale
        origin.y += (now.y - last.y) / scale * (isFlipped ? 1 : -1)
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
        enclosingScrollView?.reflectScrolledClipView(clip)
        self.last = now
    }

    override func mouseUp(with event: NSEvent) {
        last = nil
        NSCursor.openHand.set()
    }
}
