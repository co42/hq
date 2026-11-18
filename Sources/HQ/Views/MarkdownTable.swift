import AppKit
import HQKit
import SwiftUI

/// A markdown table's cells and geometry, measured once: off the main thread for a note (T-460). A semibold header row,
/// a hairline between rows, each column as wide as its widest cell.
nonisolated final class MarkdownTableLayout: @unchecked Sendable {
    /// The fonts, line heights and spaces, read on the main thread.
    struct Style: @unchecked Sendable {
        var text, header, code, headerCode: NSFont
        var textLine, headerLine, codeLine: CGFloat
        var columnGap, rowGap, rule: CGFloat
        var color, link, highlight: NSColor

        @MainActor static var current: Style {
            Style(text: KitType.callout.nsFont, header: KitType.tableHeader.nsFont, code: KitType.code.nsFont, headerCode: KitType.tableHeaderCode.nsFont,
                  textLine: MarkdownStyle.lineHeight(.callout), headerLine: MarkdownStyle.lineHeight(.tableHeader),
                  codeLine: MarkdownStyle.lineHeight(.code), columnGap: Space.lg, rowGap: Space.sm, rule: Metric.tableRule,
                  color: Ink.textNS, link: Ink.accentNS, highlight: Ink.highlightNS)
        }
    }

    let alignments: [MarkdownAlignment]
    let cells: [[NSAttributedString]]
    let widths: [CGFloat]
    /// Each row's line height.
    let lines: [CGFloat]
    let style: Style
    let width: CGFloat
    let height: CGFloat

    init(alignments: [MarkdownAlignment], rows: [[AttributedString]], style: Style) {
        self.alignments = alignments
        self.style = style
        let columns = rows.map(\.count).max() ?? 0
        var widths = Array(repeating: CGFloat(0), count: columns)
        var lines: [CGFloat] = []
        var cells: [[NSAttributedString]] = []
        for (index, row) in rows.enumerated() {
            let header = index == 0
            var line = header ? style.headerLine : style.textLine
            var made: [NSAttributedString] = []
            for (column, text) in row.enumerated() {
                let (cell, code) = Self.cell(text, header: header, style: style)
                if code { line = max(line, style.codeLine) }
                widths[column] = max(widths[column], cell.boundingRect(with: .zero, options: [.usesLineFragmentOrigin]).width)
                made.append(cell)
            }
            lines.append(line)
            cells.append(made)
        }
        // Every line exactly its row's height, as SwiftUI lays it out, aligned as its column.
        let aligned: [NSTextAlignment] = widths.indices.map { column in
            switch alignments.indices.contains(column) ? alignments[column] : .leading {
            case .leading: .left
            case .center: .center
            case .trailing: .right
            }
        }
        for (row, made) in cells.enumerated() {
            for (column, cell) in made.enumerated() {
                guard let paragraph = MarkdownStyle.line(lines[row]).mutableCopy() as? NSMutableParagraphStyle else { continue }
                paragraph.alignment = aligned[column]
                (cell as? NSMutableAttributedString)?.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: cell.length))
            }
        }
        self.cells = cells
        self.widths = widths
        self.lines = lines
        width = widths.reduce(0, +) + style.columnGap * CGFloat(max(columns - 1, 0))
        height = lines.reduce(0, +) + (2 * style.rowGap + style.rule) * CGFloat(max(lines.count - 1, 0))
    }

    /// A row's height: the hairline and its spaces above it, then its line.
    func rowHeight(_ row: Int) -> CGFloat { lines[row] + (row > 0 ? 2 * style.rowGap + style.rule : 0) }

    /// Where a row's text starts, from the row's top.
    func textTop(_ row: Int) -> CGFloat { row > 0 ? 2 * style.rowGap + style.rule : 0 }

    func columnX(_ column: Int) -> CGFloat { widths.prefix(column).reduce(0, +) + style.columnGap * CGFloat(column) }

    /// A cell's text with the viewer's fonts: bold, italic, code, struck through and links as SwiftUI draws them. True when
    /// it holds code, whose line is taller.
    private static func cell(_ text: AttributedString, header: Bool, style: Style) -> (NSMutableAttributedString, Bool) {
        let out = NSMutableAttributedString()
        var code = false
        for run in text.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = intent.contains(.code) ? (header ? style.headerCode : style.code) : (header ? style.header : style.text)
            code = code || intent.contains(.code)
            var traits = font.fontDescriptor.symbolicTraits
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            if traits != font.fontDescriptor.symbolicTraits { font = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: style.color]
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link {
                attributes[.link] = link
                attributes[.foregroundColor] = style.link
            }
            out.append(NSAttributedString(string: String(text[run.range].characters), attributes: attributes))
        }
        return (out, code)
    }
}

/// A table in markdown: AppKit makes only the rows in view, so a note with a thousand-row table opens at once (T-460).
/// Wider than the text, it scrolls sideways.
struct MarkdownTable: View {
    let layout: MarkdownTableLayout
    /// Opens it to the whole sheet (T-490).
    var expand: (() -> Void)?
    @Environment(AppModel.self) private var model
    @State private var edges = CutEdges()
    @State private var hovering = false

    var body: some View {
        ScrollView(.horizontal) {
            MarkdownTableHost(layout: layout, expand: expand)
                .frame(width: layout.width, height: layout.height)
                .padding(.vertical, Space.xs)
        }
        .scrollIndicators(.automatic)
        // Cut sideways, its cut edges fade into the card: more this way (T-490).
        .onScrollGeometryChange(for: CutEdges.self) { geometry in
            CutEdges(leading: geometry.contentOffset.x > 0.5,
                     trailing: geometry.contentOffset.x + geometry.containerSize.width < geometry.contentSize.width - 0.5)
        } action: { _, cut in edges = cut }
        .overlay(alignment: .leading) { if edges.leading { fade(from: .trailing, to: .leading).uiTestAnchor("table-fade-leading") } }
        .overlay(alignment: .trailing) { if edges.trailing { fade(from: .leading, to: .trailing).uiTestAnchor("table-fade-trailing") } }
        .overlay(alignment: .topTrailing) {
            if let expand, edges.leading || edges.trailing || layout.cells.count > Self.longRows + 1, hovering || model.showBlockControls {
                ExpandCorner(expand: expand)
            }
        }
        .onHover { hovering = $0 }
    }

    /// Longer than this, a table offers Expand even when it fits sideways.
    static let longRows = 25

    private func fade(from start: UnitPoint, to end: UnitPoint) -> some View {
        LinearGradient(colors: [Ink.card.opacity(0), Ink.card], startPoint: start, endPoint: end)
            .frame(width: Metric.cutFade)
            .allowsHitTesting(false)
    }
}

/// Which sides of a table are cut by its column.
private struct CutEdges: Equatable {
    var leading = false
    var trailing = false
}

private struct MarkdownTableHost: NSViewRepresentable {
    let layout: MarkdownTableLayout
    let expand: (() -> Void)?
    @Environment(\.openURL) private var openURL
    @Environment(\.markdownSelectable) private var selectable

    func makeNSView(context: Context) -> MarkdownTableView { MarkdownTableView() }

    func updateNSView(_ view: MarkdownTableView, context: Context) {
        view.open = { openURL($0) }
        view.expand = expand
        view.show(layout, selectable: selectable)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MarkdownTableView, context: Context) -> CGSize? {
        CGSize(width: layout.width, height: layout.height)
    }
}

/// The table's rows: no scroll view of its own, so the note's scroll view decides which rows AppKit makes.
final class MarkdownTableView: NSTableView, NSTableViewDataSource, NSTableViewDelegate {
    private(set) var layout: MarkdownTableLayout?
    private var selectable = true
    var open: (URL) -> Void = { _ in }
    var expand: (() -> Void)?

    init() {
        super.init(frame: .zero)
        headerView = nil
        style = .plain
        intercellSpacing = .zero
        backgroundColor = .clear
        selectionHighlightStyle = .none
        gridStyleMask = []
        columnAutoresizingStyle = .noColumnAutoresizing
        focusRingType = .none
        allowsColumnReordering = false
        allowsColumnResizing = false
        usesAutomaticRowHeights = false
        dataSource = self
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    nonisolated override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    /// Not selectable (an outline's card): a click goes through to the card, but on a link.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return selectable || hit is MarkdownCell ? hit : nil
    }

    /// Expand and Copy Table (T-490).
    override func menu(for event: NSEvent) -> NSMenu? { blockMenu(text: nil) }

    /// The table's menu; a cell's selected words add Copy first.
    func blockMenu(text: NSTextView?) -> NSMenu? {
        guard let layout else { return nil }
        let menu = NSMenu()
        if let text, text.selectedRange().length > 0 {
            menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "").target = text
            menu.addItem(.separator())
        }
        func add(_ title: String, _ run: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(runChoice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = DropChoice(run)
            menu.addItem(item)
        }
        if let expand { add("Expand", expand) }
        add("Copy Table") { Pasteboard.copy(layout.markdown) }
        return menu
    }

    @objc private func runChoice(_ item: NSMenuItem) { (item.representedObject as? DropChoice)?.run() }

    func show(_ layout: MarkdownTableLayout, selectable: Bool) {
        guard layout !== self.layout || selectable != self.selectable else { return }
        self.layout = layout
        self.selectable = selectable
        while tableColumns.count > layout.widths.count { removeTableColumn(tableColumns[tableColumns.count - 1]) }
        while tableColumns.count < layout.widths.count { addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(tableColumns.count)"))) }
        for (index, column) in tableColumns.enumerated() {
            let width = layout.widths[index] + (index < layout.widths.count - 1 ? layout.style.columnGap : 0)
            column.minWidth = 0
            column.maxWidth = .greatestFiniteMagnitude
            column.width = width
        }
        reloadData()
    }

    /// A cell sits at its column's start, as wide as the column's widest cell, under its row's hairline.
    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        guard let layout, layout.widths.indices.contains(column), layout.lines.indices.contains(row) else { return super.frameOfCell(atColumn: column, row: row) }
        return NSRect(x: layout.columnX(column), y: rect(ofRow: row).minY + layout.textTop(row), width: layout.widths[column], height: layout.lines[row])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { layout?.cells.count ?? 0 }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { layout?.rowHeight(row) ?? 1 }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = makeView(withIdentifier: MarkdownRuleRow.id, owner: nil) as? MarkdownRuleRow ?? MarkdownRuleRow()
        view.identifier = MarkdownRuleRow.id
        view.rule = row > 0 ? layout.map { NSRect(x: 0, y: $0.style.rowGap, width: $0.width, height: $0.style.rule) } : nil
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let layout, let tableColumn, let column = tableColumns.firstIndex(of: tableColumn) else { return nil }
        let cell = makeView(withIdentifier: MarkdownCell.id, owner: nil) as? MarkdownCell ?? MarkdownCell()
        cell.identifier = MarkdownCell.id
        let text = layout.cells[row].indices.contains(column) ? layout.cells[row][column] : NSAttributedString()
        cell.show(text, selectable: selectable, link: layout.style.link) { [weak self] in self?.open($0) }
        return cell
    }
}

/// A row with the hairline above it.
final class MarkdownRuleRow: NSTableRowView {
    static let id = NSUserInterfaceItemIdentifier("markdown-row")
    var rule: NSRect? { didSet { if rule != oldValue { needsDisplay = true } } }

    nonisolated override var isFlipped: Bool { true }

    override func drawBackground(in dirtyRect: NSRect) {
        guard let rule else { return }
        Ink.separatorNS.setFill()
        rule.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {}
}

/// A cell's text: selectable where the viewer's text is; its links open as the note's do.
final class MarkdownCell: NSTextView, NSTextViewDelegate {
    static let id = NSUserInterfaceItemIdentifier("markdown-cell")
    private var opens: (URL) -> Void = { _ in }

    init() {
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        let layout = NSLayoutManager()
        let storage = NSTextStorage()
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        drawsBackground = false
        textContainerInset = .zero
        isVerticallyResizable = false
        isHorizontallyResizable = false
        delegate = self
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Out of the key view loop: a sheet's first focus would land in a cell and scroll its table sideways to it. A click
    /// still selects its text.
    override var canBecomeKeyView: Bool { false }

    /// A cell never scrolls what's around it: a right-aligned cell's caret, off to the side, slid the table sideways.
    override func scrollToVisible(_ rect: NSRect) -> Bool { false }

    func show(_ text: NSAttributedString, selectable: Bool, link: NSColor, opens: @escaping (URL) -> Void) {
        self.opens = opens
        isSelectable = selectable
        linkTextAttributes = [.foregroundColor: link, .cursor: NSCursor.pointingHand]
        textStorage?.setAttributedString(text)
        setSelectedRange(NSRange(location: 0, length: 0))
    }

    /// Not selectable (an outline's card): only its links take a click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard hit != nil, !isSelectable else { return hit }
        return link(at: convert(point, from: superview)) != nil ? hit : nil
    }

    /// The pointing hand over its links (T-536), selectable or not.
    override func cursorUpdate(with event: NSEvent) {
        if link(at: convert(event.locationInWindow, from: nil)) != nil { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }

    override func mouseMoved(with event: NSEvent) {
        if link(at: convert(event.locationInWindow, from: nil)) != nil { NSCursor.pointingHand.set() } else { super.mouseMoved(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        if !isSelectable, let url = link(at: convert(event.locationInWindow, from: nil)) { return opens(url) }
        super.mouseDown(with: event)
    }

    /// In a note's table, its table's menu: Expand and Copy Table, Copy first over selected words.
    override func menu(for event: NSEvent) -> NSMenu? {
        let table = sequence(first: superview, next: { $0?.superview }).lazy.compactMap { $0 as? MarkdownTableView }.first
        return table?.blockMenu(text: self) ?? super.menu(for: event)
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = link as? URL ?? (link as? String).flatMap(URL.init(string:)) else { return false }
        opens(url)
        return true
    }

    private func link(at point: NSPoint) -> URL? {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let index = layoutManager.characterIndex(for: point, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        guard index < storage.length, layoutManager.boundingRect(forGlyphRange: NSRange(location: index, length: 1), in: textContainer).contains(point) else { return nil }
        return storage.attribute(.link, at: index, effectiveRange: nil) as? URL
    }
}

extension EnvironmentValues {
    /// Markdown's text can be selected: off where a click selects and a double-click edits.
    @Entry var markdownSelectable = true
}
