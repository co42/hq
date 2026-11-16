import AppKit
import HQKit
import SwiftUI

/// Markdown drawn natively: headings, paragraphs, lists and task lists, quotes, tables, code
/// with Copy, and Mermaid diagrams. `[[links]]` open the note in Obsidian.
struct MarkdownView: View {
    let blocks: [ViewerBlock]
    /// Ticks a checkbox in the source; without it, checkboxes are read-only.
    var toggle: ((Int) -> Void)?
    /// Text selectable for copying; off where a click selects and a double-click edits.
    var selectable = true
    /// A note's: a leading `# Title` is its title, in Title 1 (T-470).
    var title = false
    @Environment(AppModel.self) private var model

    init(_ text: String, selectable: Bool = true, title: Bool = false, toggle: ((Int) -> Void)? = nil) {
        blocks = ViewerBlock.prepare(Markdown.blocks(text), style: .current)
        self.selectable = selectable
        self.title = title
        self.toggle = toggle
    }

    /// Blocks prepared before: a note's, off the main thread.
    init(prepared blocks: [ViewerBlock], title: Bool = false, toggle: ((Int) -> Void)? = nil) {
        self.blocks = blocks
        self.title = title
        self.toggle = toggle
    }

    /// The blocks start with a `# Title`.
    static func hasTitle(_ blocks: [ViewerBlock]?) -> Bool {
        if case .block(.heading(1, _)) = blocks?.first { true } else { false }
    }

    var body: some View {
        selection(MarkdownBlocks(blocks: blocks, title: title))
            .environment(\.markdownSelectable, selectable)
            .environment(\.checkboxToggle, toggle.map(CheckboxToggle.init))
            .environment(\.openURL, OpenURLAction { url in
                if let name = Markdown.noteName(url) {
                    model.openNoteInObsidian(named: name)
                    return .handled
                }
                return .systemAction
            })
    }
}

extension MarkdownView {
    @ViewBuilder
    private func selection(_ content: some View) -> some View {
        if selectable { content.textSelection(.enabled) } else { content.textSelection(.disabled) }
    }
}

/// Parsed markdown ready to draw: each table measured (T-460).
nonisolated enum ViewerBlock: Sendable {
    /// A heading, paragraph, code block or rule.
    case block(MarkdownBlock)
    case list(ordered: Bool, start: Int, items: [ViewerItem])
    case quote([ViewerBlock])
    case table(MarkdownTableLayout)

    static func prepare(_ blocks: [MarkdownBlock], style: MarkdownTableLayout.Style) -> [ViewerBlock] {
        blocks.map { block in
            switch block {
            case .list(let ordered, let start, let items):
                .list(ordered: ordered, start: start, items: items.map {
                    ViewerItem(checked: $0.checked, taskIndex: $0.taskIndex, blocks: prepare($0.blocks, style: style), spoken: spoken($0.blocks))
                })
            case .quote(let blocks): .quote(prepare(blocks, style: style))
            case .table(let alignments, let rows): .table(MarkdownTableLayout(alignments: alignments, rows: rows, style: style))
            default: .block(block)
            }
        }
    }

    /// A list item's first line, for VoiceOver.
    private static func spoken(_ blocks: [MarkdownBlock]) -> String {
        for block in blocks {
            if case .paragraph(let text) = block { return String(text.characters) }
        }
        return ""
    }
}

nonisolated struct ViewerItem: Sendable {
    let checked: Bool?
    let taskIndex: Int?
    let blocks: [ViewerBlock]
    let spoken: String
}

private struct MarkdownBlocks: View {
    let blocks: [ViewerBlock]
    /// Tighter inside a list item, so a nested list stays with its item.
    var spacing = Space.md
    /// The first block, a `# Title`, is the note's title.
    var title = false
    /// The heading these blocks sit under: an expanded table or diagram is named by it.
    var section: String?

    var body: some View {
        var sections: [String?] = []
        var current = section
        for block in blocks {
            sections.append(current)
            if let heading = Self.heading(block) { current = heading }
        }
        return VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                MarkdownBlockView(block: block, title: title && index == 0, section: sections[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func heading(_ block: ViewerBlock) -> String? {
        if case .block(.heading(_, let text)) = block { String(text.characters) } else { nil }
    }
}

private struct MarkdownBlockView: View {
    let block: ViewerBlock
    var title = false
    var section: String?
    @Environment(\.checkboxToggle) private var toggle
    @Environment(AppModel.self) private var model

    var body: some View {
        switch block {
        case .block(.heading(1, let text)) where title:
            Text(text)
                .kitType(.pageTitle)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Space.md)
        case .block(.heading(let level, let text)):
            Text(text)
                .kitType(level == 1 ? .heading1 : level == 2 ? .heading2 : .heading3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? Space.xs : 0)
        case .block(.paragraph(let text)):
            Text(text)
                .kitType(.body)
                .fixedSize(horizontal: false, vertical: true)
        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        marker(ordered: ordered, number: start + index, checked: item.checked, task: item.taskIndex, text: item.spoken)
                        // A done item steps back (T-368).
                        MarkdownBlocks(blocks: item.blocks, spacing: Space.xs, section: section)
                            .foregroundStyle(item.checked == true ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    }
                }
            }
        case .quote(let blocks):
            HStack(alignment: .top, spacing: Space.md) {
                Rectangle().fill(Ink.quoteBar).frame(width: Metric.quoteBar)
                MarkdownBlocks(blocks: blocks, section: section).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .block(.code(let language, let text)):
            if language == "mermaid" {
                MermaidDiagram(source: text) { model.expand(ExpandedBlock(heading: section, content: .diagram(text))) }
            } else {
                CodeBlock(text: text, copies: true)
            }
        case .table(let layout):
            MarkdownTable(layout: layout) { model.expand(ExpandedBlock(heading: section, content: .table(layout))) }
        case .block(.rule):
            Divider()
        case .block:
            EmptyView()
        }
    }

    @ViewBuilder
    private func marker(ordered: Bool, number: Int, checked: Bool?, task: Int?, text: String) -> some View {
        if let checked {
            let mark = (checked ? KitIcon.checked : KitIcon.unchecked).image
                .foregroundStyle(checked ? AnyShapeStyle(Ink.accent) : AnyShapeStyle(.secondary))
            if let toggle, let task {
                Button { toggle.run(task) } label: { mark }
                    .buttonStyle(.plain)
                    .clickable()
                    .help(checked ? "Uncheck" : "Check")
                    .accessibilityLabel(text)
                    .accessibilityValue(checked ? "Done" : "To do")
                    .accessibilityAddTraits(.isToggle)
                    .uiTestAnchor("checkbox:\(task)")
            } else {
                mark.accessibilityLabel(text).accessibilityValue(checked ? "Done" : "To do")
            }
        } else if ordered {
            Text("\(number).").kitType(.body).monospacedDigit().foregroundStyle(.secondary)
        } else {
            Text("•").kitType(.body).foregroundStyle(.secondary)
        }
    }
}

/// A Mermaid diagram as an image, drawn for the current appearance. A diagram mermaid.js
/// can't read shows its source and why.
struct MermaidDiagram: View {
    let source: String
    /// Opens it to the whole sheet (T-490).
    var expand: (() -> Void)?
    @Environment(\.colorScheme) private var scheme
    @Environment(AppModel.self) private var model
    @State private var result: MermaidRenderer.Result?
    /// Drawn at less than 80% of its size: Expand shows under the pointer.
    @State private var scaled = false
    @State private var hovering = false

    var body: some View {
        Group {
            switch MermaidRenderer.shared.cached(source, dark: scheme == .dark) ?? result {
            case .image(let image):
                DiagramImage(image: image, expand: expand)
                    .aspectRatio(image.size, contentMode: .fit)
                    .frame(maxWidth: image.size.width)
                    .onGeometryChange(for: Bool.self) { $0.size.width < image.size.width * 0.8 } action: { scaled = $0 }
                    .overlay(alignment: .topTrailing) {
                        if let expand, scaled, hovering || model.showBlockControls { ExpandCorner(expand: expand) }
                    }
                    .frame(maxWidth: .infinity)
                    .onHover { hovering = $0 }
            case .failed(let message):
                VStack(alignment: .leading, spacing: Space.xs) {
                    CodeBlock(text: source, copies: true)
                    Text("Couldn’t draw this diagram: \(message)")
                        .kitType(.secondary)
                        .foregroundStyle(.secondary)
                }
            case nil:
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Ink.chipFill)
                    .frame(height: Metric.diagramPlaceholder)
            }
        }
        .contextMenu {
            if let expand { Button("Expand", action: expand) }
            Button("Copy Diagram Source") { Pasteboard.copy(source) }
        }
        .task(id: "\(scheme)\n\(source)") {
            result = await MermaidRenderer.shared.render(source, dark: scheme == .dark)
        }
    }
}

/// Expand in a block's top-right corner, under the pointer (T-490): where a code block has Copy.
struct ExpandCorner: View {
    let expand: () -> Void

    var body: some View {
        Button("Expand", icon: .expand, action: expand)
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .clickable()
            .help("Expand to the whole sheet")
            .padding(Space.xs)
            .uiTestAnchor("expand-block")
    }
}

/// A diagram drawn by AppKit, sharp at any size: a double-click expands it (T-490), wherever a double-click would edit the
/// text; other clicks go to what's under it, a task's card in the outline.
private struct DiagramImage: NSViewRepresentable {
    let image: NSImage
    let expand: (() -> Void)?

    func makeNSView(context: Context) -> DiagramImageView { DiagramImageView() }

    func updateNSView(_ view: DiagramImageView, context: Context) {
        if view.image !== image {
            view.image = image
            view.needsDisplay = true
        }
        view.expand = expand
    }
}

final class DiagramImageView: NSView {
    var image: NSImage?
    var expand: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Diagram")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) { image?.draw(in: bounds) }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let expand { return expand() }
        super.mouseDown(with: event)
    }
}

/// A double-click on rendered markdown edits it at the spot (T-368): behind the text, it hands where the double-click landed,
/// from the text's top-left, and keeps that click from selecting a word. A single click, a link or a checkbox work as before.
struct EditOnDoubleClick: NSViewRepresentable {
    let edit: (CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) { view.edit = edit }

    final class CatcherView: NSView {
        var edit: ((CGPoint) -> Void)?
        private var monitor: Any?

        nonisolated override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in self?.take(event) ?? event }
        }

        /// A press in the window: a double-click over the text edits it and goes no further; anything else goes on.
        func take(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window, event.clickCount == 2,
                  event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty else { return event }
            let point = convert(event.locationInWindow, from: nil)
            // In its own bounds: a view SwiftUI hosts can report a visible rect far bigger than itself (T-372).
            guard bounds.contains(point), visibleRect.contains(point) else { return event }
            // Only when its text is what's under the pointer: a task window's subtasks below its description take their own
            // double-clicks (T-372).
            guard let hit = window.contentView?.superview?.hitTest(event.locationInWindow), !Self.covered(self, by: hit) else { return event }
            edit?(point)
            return nil
        }

        /// A list is between the view under the pointer and what it shares with the catcher.
        static func covered(_ catcher: NSView, by hit: NSView) -> Bool {
            for view in sequence(first: hit, next: \.superview) {
                if catcher.isDescendant(of: view) { return false }
                if view is NSTableView, !(view is MarkdownTableView) { return true }
                // A diagram takes its own double-click: it expands (T-490).
                if view is DiagramImageView { return true }
            }
            return true
        }
    }
}

/// The closure that ticks a checkbox, through the environment to nested lists.
struct CheckboxToggle {
    let run: (Int) -> Void
}

extension EnvironmentValues {
    @Entry var checkboxToggle: CheckboxToggle?
}
