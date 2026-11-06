import AppKit
import HQKit
import SwiftUI

/// Markdown drawn natively: headings, paragraphs, lists and task lists, quotes, tables, code
/// with Copy, and Mermaid diagrams. `[[links]]` open the note in Obsidian.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    /// Ticks a checkbox in the source; without it, checkboxes are read-only.
    var toggle: ((Int) -> Void)?
    /// Text selectable for copying; off where a click selects and a double-click edits.
    var selectable = true
    @Environment(AppModel.self) private var model

    init(_ text: String, selectable: Bool = true, toggle: ((Int) -> Void)? = nil) {
        blocks = Markdown.blocks(text)
        self.selectable = selectable
        self.toggle = toggle
    }

    init(blocks: [MarkdownBlock], toggle: ((Int) -> Void)? = nil) {
        self.blocks = blocks
        self.toggle = toggle
    }

    var body: some View {
        selection(MarkdownBlocks(blocks: blocks))
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

private struct MarkdownBlocks: View {
    let blocks: [MarkdownBlock]
    /// Tighter inside a list item, so a nested list stays with its item.
    var spacing = Space.md

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    @Environment(\.checkboxToggle) private var toggle

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .kitType(level == 1 ? .heading1 : level == 2 ? .heading2 : .heading3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? Space.xs : 0)
        case .paragraph(let text):
            Text(text)
                .kitType(.body)
                .fixedSize(horizontal: false, vertical: true)
        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        marker(ordered: ordered, number: start + index, checked: item.checked, task: item.taskIndex, text: Self.spoken(item.blocks))
                        MarkdownBlocks(blocks: item.blocks, spacing: Space.xs)
                    }
                }
            }
        case .quote(let blocks):
            HStack(alignment: .top, spacing: Space.md) {
                Rectangle().fill(Ink.quoteBar).frame(width: Metric.quoteBar)
                MarkdownBlocks(blocks: blocks).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let language, let text):
            if language == "mermaid" {
                MermaidDiagram(source: text)
            } else {
                CodeBlock(text: text, copies: true)
            }
        case .table(let alignments, let rows):
            MarkdownTable(alignments: alignments, rows: rows)
        case .rule:
            Divider()
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

extension MarkdownBlockView {
    /// A list item's first line, for VoiceOver.
    static func spoken(_ blocks: [MarkdownBlock]) -> String {
        for block in blocks {
            if case .paragraph(let text) = block { return String(text.characters) }
        }
        return ""
    }
}

/// A table: a semibold header row, hairlines between rows.
private struct MarkdownTable: View {
    let alignments: [MarkdownAlignment]
    let rows: [[AttributedString]]

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: Space.lg, verticalSpacing: Space.sm) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider() }
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            Text(cell)
                                .kitType(index == 0 ? .tableHeader : .callout)
                                .fixedSize(horizontal: false, vertical: true)
                                .gridColumnAlignment(alignment(column))
                        }
                    }
                }
            }
            .padding(.vertical, Space.xs)
        }
        .scrollIndicators(.automatic)
    }

    private func alignment(_ column: Int) -> HorizontalAlignment {
        switch alignments.indices.contains(column) ? alignments[column] : .leading {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

/// A Mermaid diagram as an image, drawn for the current appearance. A diagram mermaid.js
/// can't read shows its source and why.
struct MermaidDiagram: View {
    let source: String
    @Environment(\.colorScheme) private var scheme
    @State private var result: MermaidRenderer.Result?

    var body: some View {
        Group {
            switch MermaidRenderer.shared.cached(source, dark: scheme == .dark) ?? result {
            case .image(let image):
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: image.size.width)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Diagram")
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
            Button("Copy Diagram Source") { Pasteboard.copy(source) }
        }
        .task(id: "\(scheme)\n\(source)") {
            result = await MermaidRenderer.shared.render(source, dark: scheme == .dark)
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
