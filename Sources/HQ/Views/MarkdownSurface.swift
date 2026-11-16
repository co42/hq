import AppKit
import HQKit
import SwiftUI

/// Markdown as HQ shows and edits it everywhere (T-469 item 8, DESIGN §9): rendered, a double-click edits it at the spot,
/// the editor taking the rendered text's place and size; on a card or not; checkboxes, Expand, ⌘B ⌘I ⌘K and lists come from
/// the viewer and the editor inside. The one way a view shows markdown: tools/code-lint.sh holds it.
struct MarkdownSurface: View {
    /// What it sits on: nothing (the outline's card, a box), a task's description card, a note's page card.
    enum Look { case plain, compact, page }

    /// Its text, or a note's blocks prepared off the main thread.
    var text = ""
    var prepared: [ViewerBlock]?
    var look = Look.plain
    /// A note's: a leading `# Title` is its title, in Title 1; without one, `fallbackTitle` shows there, outside the text.
    var title = false
    var fallbackTitle: String?
    /// Still loading: this line shows instead of the text.
    var loading: String?
    var selectable = true
    /// Shown when there's no text; editable, a double-click on it starts the editor.
    var placeholder: String?
    var toggle: ((Int) -> Void)?
    /// How it edits; read only without it.
    var editing: MarkdownEditing?
    /// The page catches its own double-click (the outline).
    var catchesDoubleClick = true
    /// For the UI checks: the rendered text (or its placeholder), the editor, the loading line.
    var anchors = MarkdownAnchors()
    @Environment(AppModel.self) private var model
    /// The editor's text height, and the rendered text's: the editor opens as tall as what it replaces, then grows.
    @State private var editorHeight: CGFloat = 0
    @State private var renderedHeight: CGFloat = 0

    private var isEditing: Bool { editing?.isOn == true }
    private var hasTitle: Bool { title && MarkdownView.hasTitle(prepared) }
    private var isEmpty: Bool { prepared.map(\.isEmpty) ?? text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        switch look {
        case .plain:
            content
                .overlay {
                    if isEditing {
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Ink.accent).padding(-Space.xs).allowsHitTesting(false)
                    }
                }
        case .compact: TextCard(editing: isEditing) { content }
        case .page: TextCard(size: .page, editing: isEditing) { content }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if title, let fallbackTitle, loading == nil, !hasTitle {
                Text(fallbackTitle).kitType(.pageTitle).padding(.bottom, Space.md)
            }
            if let loading {
                LoadingLine(title: loading).uiTestAnchor(anchors.loading ?? "markdown-loading")
            } else if let editing, editing.isOn {
                editor(editing)
            } else if isEmpty, let placeholder {
                Text(placeholder).kitType(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background { if let editing, catchesDoubleClick { EditOnDoubleClick { _ in editing.begin(nil) } } }
                    .uiTestAnchor(anchors.text ?? "markdown-text")
            } else if !isEmpty {
                viewer
                    .background { if let editing, catchesDoubleClick { EditOnDoubleClick { point in editing.begin(point) } } }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { renderedHeight = $0 }
                    .uiTestAnchor(anchors.text ?? "markdown-text")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var viewer: some View {
        if let prepared {
            MarkdownView(prepared: prepared, title: title, toggle: toggle)
        } else {
            MarkdownView(text, selectable: selectable, title: title, toggle: toggle)
        }
    }

    @ViewBuilder
    private func editor(_ editing: MarkdownEditing) -> some View {
        let editor = MarkdownEditor(text: editing.draft, focusOnAppear: true, caretPoint: model.editorCaret, label: editing.label, title: hasTitle,
                                    onHeight: { height in
                                        editorHeight = height
                                        editing.box?.wrappedValue = height
                                    },
                                    maxHeight: editing.box == nil ? .infinity : Metric.editorMaximum,
                                    onCommit: editing.commit, onCancel: editing.cancel, onEnd: editing.end, onTab: editing.tab)
            .onAppear { model.editorCaret = nil }
            .onDisappear { editorHeight = 0 }
            .uiTestAnchor(anchors.editor ?? "markdown-editor")
        if let box = editing.box {
            // In a row: as tall as its text up to its tallest, the row measuring it from the model.
            editor.frame(height: MarkdownEditor.box(box.wrappedValue))
        } else {
            editor.frame(height: max(editorHeight > 0 ? editorHeight : renderedHeight, MarkdownStyle.lineHeight(.body)))
        }
    }
}

/// A surface's anchors for the UI checks.
struct MarkdownAnchors {
    var text: String?
    var editor: String?
    var loading: String?
}

/// How a surface edits: whether its editor shows, the draft, and what starts and ends the edit.
struct MarkdownEditing {
    var isOn: Bool
    var draft: Binding<String>
    /// What VoiceOver calls the editor.
    var label: String
    /// A double-click at a point of the rendered text, from its top-left; nil from the placeholder.
    var begin: (CGPoint?) -> Void
    var commit: () -> Void
    var cancel: () -> Void
    var end: () -> Void = {}
    /// Tab and ⇧Tab leave it, off a list line.
    var tab: ((Bool) -> Void)?
    /// In a row: the editor's height, kept by the model so the row can measure it.
    var box: Binding<CGFloat>?
}

/// A form's markdown field, always the editor: a session's first message, a new task's description (T-469 item 8). The same
/// keys and lists as everywhere; ⌘Return submits the form, Escape cancels it, Tab and ⇧Tab move to the next field.
struct MarkdownField: View {
    @Binding var text: String
    var placeholder = ""
    var label: String
    var focusOnAppear = false
    var minHeight: CGFloat
    var maxHeight: CGFloat = .infinity
    var submit: () -> Void
    var cancel: () -> Void

    var body: some View {
        MarkdownEditor(text: $text, focusOnAppear: focusOnAppear, label: label, inset: Space.sm, onCommit: submit, onCancel: cancel,
                       onTab: { backward in
                           let window = NSApp.keyWindow
                           if backward { window?.selectPreviousKeyView(nil) } else { window?.selectNextKeyView(nil) }
                       })
            .frame(minHeight: minHeight, maxHeight: maxHeight)
            // A form's label lines up with its first line: an AppKit text view gives the grid no baseline.
            .alignmentGuide(.firstTextBaseline) { _ in Space.sm + MarkdownStyle.body.ascender }
            .background(Ink.editor, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Ink.boxFrame))
            .overlay(alignment: .topLeading) {
                if text.isEmpty, !placeholder.isEmpty {
                    Text(placeholder).kitType(.body).foregroundStyle(.tertiary).padding(Space.sm).allowsHitTesting(false)
                }
            }
    }
}

/// A notification's text (T-469 item 8): inline marks only, bold, italic, code and links that open, as Co chose; tooltips and
/// banners get it without the marks.
enum MarkdownLine {
    static func text(_ source: String) -> Text { Text(attributed(source)) }

    static func plain(_ source: String) -> String { String(attributed(source).characters) }

    private static func attributed(_ source: String) -> AttributedString {
        if let cached = cache[source] { return cached }
        let parsed = (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(source)
        if cache.count > 500 { cache.removeAll() }
        cache[source] = parsed
        return parsed
    }

    private static var cache: [String: AttributedString] = [:]
}
