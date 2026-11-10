import AppKit
import SwiftUI

/// A markdown editor (DESIGN.md §9) that looks like the rendered note: its fonts, heading sizes and line height, marks
/// dimmed, mono only in code. Return continues a list, Tab nests it; ⌘B, ⌘I, ⌘K; a URL pasted over words links them; a
/// click ticks a checkbox. Undo, Find, no spell check. ⌘Return commits, Escape cancels, leaving it ends the edit; Tab can
/// leave it too. Descriptions, notes and first messages share it.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var focusOnAppear = false
    /// Where the caret goes when it takes the keyboard: the end, or the start.
    var caretAtEnd = true
    /// A double-click on the rendered text, from its top-left: the caret goes to the source under it.
    var caretPoint: CGPoint?
    /// What VoiceOver calls it: "Description", "First message", the file's title.
    var label = "Markdown"
    /// Around the text: none where it replaces rendered markdown in place, a box's padding elsewhere.
    var inset: CGFloat = 0
    /// The text's height as it changes: the box grows with it.
    var onHeight: ((CGFloat) -> Void)?
    var onCommit: () -> Void = {}
    var onCancel: () -> Void = {}
    var onEnd: () -> Void = {}
    /// Tab and ⇧Tab (true) leave the editor instead of typing a tab, off a list line.
    var onTab: ((Bool) -> Void)?

    /// A box in a row: as tall as its text, then it scrolls.
    static func box(_ height: CGFloat) -> CGFloat { min(max(height, MarkdownStyle.lineHeight(.body)), Metric.editorMaximum) }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1: its layout answers where a checkbox is and how tall the text is.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let editor = EditorTextView(frame: .zero, textContainer: container)
        editor.autoresizingMask = [.width]
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        let scroll = EditorScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = editor
        editor.delegate = context.coordinator
        editor.coordinator = context.coordinator
        editor.isRichText = false
        editor.allowsUndo = true
        editor.usesFindBar = true
        editor.isIncrementalSearchingEnabled = true
        editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.drawsBackground = false
        editor.font = MarkdownStyle.body
        editor.textColor = Ink.textNS
        editor.textContainerInset = NSSize(width: inset, height: inset)
        editor.defaultParagraphStyle = MarkdownStyle.paragraph
        editor.typingAttributes = MarkdownStyle.base
        editor.string = text
        editor.setAccessibilityLabel(label)
        context.coordinator.restyle(editor)
        if focusOnAppear { editor.focusWhenShown(caretAtEnd: caretAtEnd, at: caretPoint) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView, editor.string != text, !context.coordinator.typing else { return }
        editor.string = text
        context.coordinator.restyle(editor)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        var typing = false
        private var ended = false
        private var reported: CGFloat = 0

        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            typing = true
            parent.text = editor.string
            typing = false
            restyle(editor)
        }

        /// Styles the text and tells the box its height.
        func restyle(_ editor: NSTextView) {
            if let storage = editor.textStorage { MarkdownStyle.apply(to: storage) }
            editor.typingAttributes = MarkdownStyle.base
            reportHeight(editor)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { reportHeight(editor) }
        }

        /// The text's height. The empty line after a final line break counts only with the caret on it: the rendered text
        /// has none.
        func reportHeight(_ editor: NSTextView) {
            guard let onHeight = parent.onHeight, let layout = editor.layoutManager, let container = editor.textContainer else { return }
            layout.ensureLayout(for: container)
            var used = layout.usedRect(for: container).height
            let length = (editor.string as NSString).length
            if layout.extraLineFragmentTextContainer != nil, editor.selectedRange().location < length || length == 0 {
                used = layout.glyphRange(for: container).length > 0
                    ? layout.boundingRect(forGlyphRange: layout.glyphRange(for: container), in: container).maxY : used
            }
            let height = ceil(used + editor.textContainerInset.height * 2)
            guard abs(height - reported) >= 1 else { return }
            reported = height
            // Never while SwiftUI updates the view.
            DispatchQueue.main.async { onHeight(height) }
        }

        func textDidEndEditing(_ notification: Notification) {
            guard !ended, let editor = notification.object as? NSTextView else { return }
            DispatchQueue.main.async { [weak self, weak editor] in
                guard let self, !self.ended else { return }
                // Its own find bar keeps the edit open.
                if let scroll = editor?.enclosingScrollView, let responder = editor?.window?.firstResponder as? NSView,
                   responder.isDescendant(of: scroll) { return }
                self.ended = true
                self.parent.onEnd()
            }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.cancelOperation(_:)):
                ended = true
                parent.onCancel()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                return MarkdownLists.continueList(in: textView)
            case #selector(NSResponder.insertTab(_:)):
                return MarkdownLists.indent(in: textView, out: false) || tab(backward: false)
            case #selector(NSResponder.insertBacktab(_:)):
                return MarkdownLists.indent(in: textView, out: true) || tab(backward: true)
            default:
                return false
            }
        }

        func commit() {
            ended = true
            parent.onCommit()
        }

        func tab(backward: Bool) -> Bool {
            guard let onTab = parent.onTab else { return false }
            ended = true
            onTab(backward)
            return true
        }
    }

    /// As tall as its text, it hands the scroll wheel to the page around it.
    final class EditorScrollView: NSScrollView {
        override func scrollWheel(with event: NSEvent) {
            guard let document = documentView, document.frame.height <= contentView.bounds.height + 0.5 else { return super.scrollWheel(with: event) }
            nextResponder?.scrollWheel(with: event)
        }
    }

    /// ⌘Return commits: the menu's own ⌘Return isn't bound while an editor has the keyboard. ⌘B, ⌘I and ⌘K mark the
    /// selection; a click on a checkbox ticks it, with the pointing hand over it.
    final class EditorTextView: NSTextView {
        weak var coordinator: Coordinator?
        private var wantsFocus: (atEnd: Bool, point: CGPoint?)?
        private var pointerArea: NSTrackingArea?

        /// The menus follow the keyboard in and out of editors (Find Next and Previous).
        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { NotificationCenter.default.post(name: .editorKeyboard, object: nil) }
            return accepted
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { DispatchQueue.main.async { NotificationCenter.default.post(name: .editorKeyboard, object: nil) } }
            return resigned
        }

        /// Takes the keyboard once it's in a window, after the window cleared its first focus: the caret at the end, the
        /// start, or under a point of the rendered text.
        func focusWhenShown(caretAtEnd: Bool, at point: CGPoint? = nil) {
            wantsFocus = (caretAtEnd, point)
            if window != nil { focusSoon() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { DispatchQueue.main.async { NotificationCenter.default.post(name: .editorKeyboard, object: nil) } }
            if window != nil, wantsFocus != nil { focusSoon() }
            if window != nil, pointerArea == nil {
                let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self)
                addTrackingArea(area)
                pointerArea = area
            }
        }

        private func focusSoon() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, let window = self.window, let wanted = self.wantsFocus else { return }
                self.wantsFocus = nil
                window.makeFirstResponder(self)
                let length = (self.string as NSString).length
                var caret = wanted.atEnd ? length : 0
                if let point = wanted.point {
                    let origin = self.textContainerOrigin
                    caret = min(self.characterIndexForInsertion(at: NSPoint(x: point.x + origin.x, y: point.y + origin.y)), length)
                }
                self.setSelectedRange(NSRange(location: caret, length: 0))
                self.scrollRangeToVisible(self.selectedRange())
            }
        }

        /// Grown to its text in a page that scrolls, the page follows the caret.
        override func scrollRangeToVisible(_ range: NSRange) {
            super.scrollRangeToVisible(range)
            guard let page = enclosingScrollView?.enclosingScrollView?.documentView, let layout = layoutManager else { return }
            let length = (string as NSString).length
            var rect = layout.extraLineFragmentRect
            if range.location < length || layout.extraLineFragmentTextContainer == nil {
                let glyph = layout.glyphIndexForCharacter(at: min(range.location, max(length - 1, 0)))
                rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            guard rect.height > 0 else { return }
            page.scrollToVisible(convert(rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y), to: page))
        }

        /// The editor is wider or narrower: its lines wrap again, and its box follows.
        override func setFrameSize(_ newSize: NSSize) {
            let widthChanged = abs(newSize.width - frame.width) > 0.5
            super.setFrameSize(newSize)
            if widthChanged { coordinator?.reportHeight(self) }
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command {
                coordinator?.commit()
                return
            }
            super.keyDown(with: event)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if event.keyCode == 36 || event.keyCode == 76, flags == .command {
                coordinator?.commit()
                return true
            }
            // Before the menus: ⌘I is Open on a task outside the editor.
            if flags == .command {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "b": wrap("**"); return true
                case "i": wrap("_"); return true
                case "k": link(); return true
                default: break
                }
            }
            return super.performKeyEquivalent(with: event)
        }

        /// ⌘B, ⌘I: the selection between the marks, or out of them when they're already there.
        func wrap(_ mark: String) {
            let text = string as NSString
            let range = selectedRange()
            let width = (mark as NSString).length
            if range.location >= width, NSMaxRange(range) + width <= text.length,
               text.substring(with: NSRange(location: range.location - width, length: width)) == mark,
               text.substring(with: NSRange(location: NSMaxRange(range), length: width)) == mark {
                let outer = NSRange(location: range.location - width, length: range.length + width * 2)
                insertText(text.substring(with: range), replacementRange: outer)
                setSelectedRange(NSRange(location: outer.location, length: range.length))
                return
            }
            insertText(mark + text.substring(with: range) + mark, replacementRange: range)
            setSelectedRange(NSRange(location: range.location + width, length: range.length))
        }

        /// ⌘K: the selection as a link's words, to a copied URL when there's one; the caret where the rest goes.
        func link() {
            let range = selectedRange()
            let words = (string as NSString).substring(with: range)
            let url = Self.copiedURL()
            let inserted = "[\(words)](\(url ?? ""))"
            insertText(inserted, replacementRange: range)
            let caret = words.isEmpty ? range.location + 1 : range.location + (inserted as NSString).length - (url == nil ? 1 : 0)
            setSelectedRange(NSRange(location: caret, length: 0))
        }

        /// A URL pasted over words on one line links them.
        override func paste(_ sender: Any?) {
            let range = selectedRange()
            let words = (string as NSString).substring(with: range)
            if range.length > 0, !words.contains("\n"), let url = Self.copiedURL() {
                insertText("[\(words)](\(url))", replacementRange: range)
                return
            }
            super.paste(sender)
        }

        /// The pasteboard's text when it's one web address.
        static func copiedURL() -> String? {
            guard let text = Pasteboard.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                  !text.contains(where: \.isWhitespace), let url = URL(string: text),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return text
        }

        // MARK: Checkboxes

        /// The `[ ]` or `[x]` of a task list item under a point in the view.
        func checkbox(at point: NSPoint) -> NSRange? {
            guard let layout = layoutManager, let container = textContainer, !string.isEmpty else { return nil }
            let origin = textContainerOrigin
            let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
            let glyph = layout.glyphIndex(for: local, in: container)
            let index = layout.characterIndexForGlyph(at: glyph)
            let text = string as NSString
            guard index < text.length else { return nil }
            let line = text.lineRange(for: NSRange(location: index, length: 0))
            guard let match = MarkdownStyle.checkbox.firstMatch(in: string, range: line) else { return nil }
            let box = match.range(at: 1)
            let glyphs = layout.glyphRange(forCharacterRange: box, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
            return rect.insetBy(dx: -Space.xs / 2, dy: -Space.xs / 2).contains(point) ? box : nil
        }

        /// Ticks or unticks it: one Undo step, the caret where it was.
        func toggle(_ box: NSRange) {
            let mark = NSRange(location: box.location + 1, length: 1)
            let ticked = (string as NSString).substring(with: mark) != " "
            let selection = selectedRange()
            guard shouldChangeText(in: mark, replacementString: ticked ? " " : "x") else { return }
            textStorage?.replaceCharacters(in: mark, with: ticked ? " " : "x")
            didChangeText()
            undoManager?.setActionName(ticked ? "Uncheck" : "Check")
            setSelectedRange(selection)
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 1, event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
               let box = checkbox(at: convert(event.locationInWindow, from: nil)) {
                if window?.firstResponder !== self { window?.makeFirstResponder(self) }
                toggle(box)
                return
            }
            super.mouseDown(with: event)
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            if checkbox(at: convert(event.locationInWindow, from: nil)) != nil { NSCursor.pointingHand.set() }
        }

        override func cursorUpdate(with event: NSEvent) {
            if checkbox(at: convert(event.locationInWindow, from: nil)) != nil { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
        }
    }
}

/// How the editor draws markdown: the viewer's fonts and sizes, blank lines as tall as the viewer's gap between blocks,
/// the marks dimmed, mono only in code.
@MainActor
enum MarkdownStyle {
    static var body: NSFont { KitType.body.nsFont }
    /// Code blocks, as the viewer's.
    static var code: NSFont { KitType.code.nsFont }
    /// Inline code, at the text's size.
    static var inlineCode: NSFont { KitType.editor.nsFont }

    static func headingType(_ level: Int) -> KitType { level == 1 ? .heading1 : level == 2 ? .heading2 : .heading3 }
    static func heading(_ level: Int) -> NSFont { headingType(level).nsFont }

    /// The viewer's line height for a type: SwiftUI's own, measured once per size (TextKit's differs at some sizes).
    static func lineHeight(_ type: KitType) -> CGFloat {
        let key = "\(type) \(type.nsFont.pointSize)"
        if let height = lineHeights[key] { return height }
        let lines = 10
        let probe = NSHostingView(rootView: Text(Array(repeating: "Ag", count: lines).joined(separator: "\n")).kitType(type).fixedSize())
        let height = probe.fittingSize.height / CGFloat(lines)
        lineHeights[key] = height
        return height
    }
    private static var lineHeights: [String: CGFloat] = [:]

    /// A line exactly `height` tall, `before` below the one above; wrapped lines start at `indent`.
    static func line(_ height: CGFloat, before: CGFloat = 0, indent: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        style.paragraphSpacingBefore = before
        style.headIndent = indent
        style.lineBreakStrategy = .standard
        return style
    }

    static var paragraph: NSParagraphStyle { line(lineHeight(.body)) }

    static var base: [NSAttributedString.Key: Any] { [.font: body, .foregroundColor: Ink.textNS, .paragraphStyle: paragraph] }

    /// What a source line is, for the room the viewer gives it.
    private enum Kind: Equatable {
        case blank, text, itemText, heading(Int), item, quote, quoteBlank, fenceOpen, fenceClose, code, rule
    }

    /// Each line as tall as the viewer draws it and as far below the line above: 12 pt between blocks (the blank lines
    /// between them share it), 4 pt between list items, a heading's room above, a code box's padding taken from the space
    /// around its fences. Only what the marks add (their own lines, longer lines) moves the text.
    private static func space(_ storage: NSTextStorage) {
        let text = storage.string as NSString
        let body = lineHeight(.body), code = lineHeight(.code)
        var inFence = false
        var previous: Kind?
        var blanks: [NSRange] = []
        // A list item whose marker differs from the last one at its indent (`-` then `1.`) starts a new list: a block's gap.
        var markers: [Int: String] = [:]
        var newList = false
        func gap(_ kind: Kind) -> CGFloat {
            guard let previous else {
                if case .heading(let level) = kind, level <= 2 { return Space.xs }
                return 0
            }
            var gap: CGFloat
            switch kind {
            case .code, .fenceClose, .quoteBlank: return 0
            case .heading(let level): gap = Space.md + (level <= 2 ? Space.xs : 0)
            case .item, .itemText: gap = [.item, .itemText].contains(previous) && !newList ? Space.xs : Space.md
            case .text where blanks.isEmpty && [.text, .quote].contains(previous): return 0
            case .quote where [.quote, .quoteBlank].contains(previous) && blanks.isEmpty: return 0
            default: gap = Space.md
            }
            if kind == .itemText && blanks.isEmpty { return 0 }
            if previous == .fenceClose { gap += Space.sm - code }
            if kind == .fenceOpen { gap += Space.sm - code }
            return max(gap, 0)
        }
        func width(_ prefix: String) -> CGFloat { (prefix as NSString).size(withAttributes: [.font: MarkdownStyle.body]).width }
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byLines) { line, _, enclosing, _ in
            let line = line ?? ""
            let whole = NSRange(location: 0, length: (line as NSString).length)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            var kind: Kind
            var indent: CGFloat = 0
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                kind = inFence ? .fenceClose : .fenceOpen
                inFence.toggle()
            } else if inFence {
                kind = .code
            } else if trimmed.isEmpty {
                blanks.append(enclosing)
                return
            } else if let marks = headingLine.firstMatch(in: line, range: whole) {
                kind = .heading((line as NSString).substring(with: marks.range(at: 1)).prefix { $0 == "#" }.count)
            } else if rule.firstMatch(in: line, range: whole) != nil {
                kind = .rule
            } else if let marker = item.firstMatch(in: line, range: whole) {
                kind = .item
                indent = width((line as NSString).substring(to: NSMaxRange(marker.range)))
                let depth = marker.range(at: 1).length
                let sign = marker.range(at: 2).location != NSNotFound ? (line as NSString).substring(with: marker.range(at: 2))
                    : (line as NSString).substring(with: marker.range(at: 4))
                newList = markers[depth].map { $0 != sign } ?? false
                markers[depth] = sign
                markers = markers.filter { $0.key <= depth }
            } else if let marker = quote.firstMatch(in: line, range: whole) {
                kind = marker.range(at: 2).length == 0 ? .quoteBlank : .quote
                indent = width((line as NSString).substring(to: NSMaxRange(marker.range(at: 1))))
            } else if let previous, [.item, .itemText].contains(previous), blanks.isEmpty || line.hasPrefix("  ") {
                kind = .itemText
            } else if previous == .quote, blanks.isEmpty {
                kind = .quote
            } else {
                kind = .text
            }
            if kind != .item, kind != .itemText { markers = [:]; newList = false }
            let space = gap(kind)
            newList = false
            if !blanks.isEmpty {
                // NSParagraphStyle reads 0 as no limit: a blank line is a point tall at least.
                let each = max(space / CGFloat(blanks.count), 1)
                for blank in blanks { storage.addAttribute(.paragraphStyle, value: MarkdownStyle.line(each), range: blank) }
            }
            let height: CGFloat = switch kind {
            case .heading(let level): lineHeight(headingType(level))
            case .fenceOpen, .fenceClose, .code: code
            case .quoteBlank: Space.md
            default: body
            }
            // TextKit gives the first line no room above: it goes into the line.
            let first = previous == nil && blanks.isEmpty
            storage.addAttribute(.paragraphStyle, value: MarkdownStyle.line(height + (first ? space : 0), before: blanks.isEmpty && !first ? space : 0, indent: indent),
                                 range: enclosing)
            blanks = []
            previous = kind
        }
        for blank in blanks { storage.addAttribute(.paragraphStyle, value: MarkdownStyle.line(body), range: blank) }
    }

    private static func pattern(_ text: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: text, options: [.anchorsMatchLines])
    }

    static let headingLine = pattern(#"^(#{1,6}[ \t]+)(.*)$"#)
    /// A list item's marker, its checkbox included: indent, marker, spaces, `[ ]`.
    static let item = pattern(#"^([ \t]*)(?:([-*+])|(\d{1,9})([.)]))([ \t]+)(\[[ xX]\][ \t]+)?"#)
    static let checkbox = pattern(#"^[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\])"#)
    static let doneItem = pattern(#"^[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+\[[xX]\][ \t]+(.*)$"#)
    static let quote = pattern(#"^([ \t]*>[ \t]?)(.*)$"#)
    static let rule = pattern(#"^[ \t]*(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$"#)
    static let inlineCodeSpan = pattern(#"(`)([^`\n]+)(`)"#)
    static let strong = pattern(#"(\*\*|__)(?=\S)([^\n]*?\S)\1"#)
    static let emphasis = pattern(#"(?<![*_\w])([*_])(?=[^\s*_])([^\n*_]*?[^\s*_])\1(?![*_\w])"#)
    static let link = pattern(#"(\[)([^\]\n]+)(\]\([^)\s]*\))"#)
    static let wiki = pattern(#"(\[\[)([^\]\n]+)(\]\])"#)
    static let address = pattern(#"(?<![(<\w])https?://[^\s)>\]]+"#)

    /// Styles the whole text again: cheap enough on every keystroke for any note HQ keeps (a self-test times it).
    static func apply(to storage: NSTextStorage) {
        let text = storage.string as NSString
        let all = NSRange(location: 0, length: text.length)
        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes(base, range: all)
        guard text.length > 0 else { return }
        // Fenced code first: nothing else styles it.
        var fenced = IndexSet()
        var fence: Int?
        text.enumerateSubstrings(in: all, options: .byLines) { line, range, enclosing, _ in
            let trimmed = (line ?? "").trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                storage.addAttributes([.font: code, .foregroundColor: Ink.syntaxQuietNS], range: range)
                if let start = fence {
                    fenced.insert(integersIn: start..<NSMaxRange(enclosing))
                    fence = nil
                } else {
                    fence = enclosing.location
                }
            } else if fence != nil {
                storage.addAttributes([.font: code, .foregroundColor: Ink.syntaxCodeNS], range: range)
            }
        }
        if let start = fence { fenced.insert(integersIn: start..<text.length) }
        space(storage)
        func each(_ regex: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            regex.enumerateMatches(in: storage.string, range: all) { match, _, _ in
                guard let match, !fenced.intersects(integersIn: match.range.location..<max(NSMaxRange(match.range), match.range.location + 1)) else { return }
                body(match)
            }
        }
        func quiet(_ range: NSRange) { if range.location != NSNotFound { storage.addAttribute(.foregroundColor, value: Ink.syntaxQuietNS, range: range) } }
        func trait(_ trait: NSFontTraitMask, _ range: NSRange) {
            storage.enumerateAttribute(.font, in: range) { value, run, _ in
                guard let font = value as? NSFont else { return }
                storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: run)
            }
        }
        each(headingLine) { match in
            let marks = match.range(at: 1)
            let level = text.substring(with: marks).prefix { $0 == "#" }.count
            storage.addAttribute(.font, value: heading(level), range: text.paragraphRange(for: match.range))
            quiet(marks)
        }
        each(item) { match in
            let marker = NSRange(location: match.range(at: 1).location + match.range(at: 1).length,
                                 length: NSMaxRange(match.range) - NSMaxRange(match.range(at: 1)))
            storage.addAttribute(.foregroundColor, value: Ink.secondaryTextNS, range: marker)
        }
        each(doneItem) { match in storage.addAttribute(.foregroundColor, value: Ink.secondaryTextNS, range: match.range(at: 1)) }
        each(quote) { match in
            quiet(match.range(at: 1))
            storage.addAttribute(.foregroundColor, value: Ink.secondaryTextNS, range: match.range(at: 2))
        }
        each(rule) { match in quiet(match.range) }
        each(strong) { match in
            trait(.boldFontMask, match.range(at: 2))
            quiet(NSRange(location: match.range.location, length: match.range(at: 1).length))
            quiet(NSRange(location: NSMaxRange(match.range) - match.range(at: 1).length, length: match.range(at: 1).length))
        }
        each(emphasis) { match in
            trait(.italicFontMask, match.range(at: 2))
            quiet(match.range(at: 1))
            quiet(NSRange(location: NSMaxRange(match.range) - 1, length: 1))
        }
        each(link) { match in
            storage.addAttribute(.foregroundColor, value: Ink.syntaxLinkNS, range: match.range(at: 2))
            quiet(match.range(at: 1))
            quiet(match.range(at: 3))
        }
        each(wiki) { match in
            storage.addAttribute(.foregroundColor, value: Ink.syntaxLinkNS, range: match.range(at: 2))
            quiet(match.range(at: 1))
            quiet(match.range(at: 3))
        }
        each(address) { match in storage.addAttribute(.foregroundColor, value: Ink.syntaxLinkNS, range: match.range) }
        // Inline code last: what's inside it is code, whatever it looks like.
        each(inlineCodeSpan) { match in
            storage.addAttributes([.font: inlineCode, .foregroundColor: Ink.syntaxCodeNS], range: match.range)
            quiet(match.range(at: 1))
            quiet(match.range(at: 3))
        }
    }

    /// The line at a location is inside a code fence.
    static func inFence(_ text: NSString, at location: Int) -> Bool {
        var inside = false
        text.enumerateSubstrings(in: NSRange(location: 0, length: min(location, text.length)), options: .byLines) { line, _, _, _ in
            let trimmed = (line ?? "").trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inside.toggle() }
        }
        return inside
    }
}

/// Lists as the user types them: Return continues the item (`-`, `1.`, `- [ ]`, `>`), on an empty one it ends the list;
/// Tab nests the item under the one before, ⇧Tab takes it back out.
@MainActor
enum MarkdownLists {
    static func continueList(in view: NSTextView) -> Bool {
        let text = view.string as NSString
        let caret = view.selectedRange()
        guard caret.length == 0 else { return false }
        let line = content(of: text.lineRange(for: NSRange(location: caret.location, length: 0)), in: text)
        guard !MarkdownStyle.inFence(text, at: line.location) else { return false }
        let next: String
        let prefixEnd: Int
        if let match = MarkdownStyle.item.firstMatch(in: view.string, range: line) {
            prefixEnd = NSMaxRange(match.range)
            let indent = text.substring(with: match.range(at: 1))
            let spacing = text.substring(with: match.range(at: 5))
            let marker = match.range(at: 2).location != NSNotFound ? text.substring(with: match.range(at: 2))
                : "\((Int(text.substring(with: match.range(at: 3))) ?? 0) + 1)\(text.substring(with: match.range(at: 4)))"
            next = indent + marker + spacing + (match.range(at: 6).location != NSNotFound ? "[ ] " : "")
        } else if let match = MarkdownStyle.quote.firstMatch(in: view.string, range: line) {
            prefixEnd = NSMaxRange(match.range(at: 1))
            next = text.substring(with: match.range(at: 1))
        } else {
            return false
        }
        guard caret.location >= prefixEnd else { return false }
        if text.substring(with: NSRange(location: prefixEnd, length: NSMaxRange(line) - prefixEnd)).trimmingCharacters(in: .whitespaces).isEmpty {
            // An empty item ends the list: its marker goes, the line stays.
            view.insertText("", replacementRange: line)
            return true
        }
        view.insertText("\n" + next, replacementRange: caret)
        return true
    }

    /// Tab and ⇧Tab on a list line nest it or take it out, by its marker's width; elsewhere they do what they did.
    static func indent(in view: NSTextView, out: Bool) -> Bool {
        let text = view.string as NSString
        let selection = view.selectedRange()
        let line = content(of: text.lineRange(for: NSRange(location: selection.location, length: 0)), in: text)
        guard !MarkdownStyle.inFence(text, at: line.location),
              let match = MarkdownStyle.item.firstMatch(in: view.string, range: line) else { return false }
        let width = match.range(at: 2).location != NSNotFound ? 2 : match.range(at: 3).length + 2
        let leading = text.substring(with: match.range(at: 1))
        if out {
            let removed = leading.hasPrefix("\t") ? 1 : min(leading.prefix { $0 == " " }.count, width)
            guard removed > 0 else { return true }
            view.insertText("", replacementRange: NSRange(location: line.location, length: removed))
            view.setSelectedRange(NSRange(location: max(selection.location - removed, line.location), length: selection.length))
        } else {
            view.insertText(String(repeating: " ", count: width), replacementRange: NSRange(location: line.location, length: 0))
            view.setSelectedRange(NSRange(location: selection.location + width, length: selection.length))
        }
        return true
    }

    /// A line's range without its line break.
    private static func content(of line: NSRange, in text: NSString) -> NSRange {
        var range = line
        while range.length > 0, [10, 13].contains(text.character(at: NSMaxRange(range) - 1)) { range.length -= 1 }
        return range
    }
}

extension NSRange {
    func shifted(by offset: Int) -> NSRange { NSRange(location: location + offset, length: length) }
}

extension Notification.Name {
    /// A markdown editor took or left the keyboard.
    static let editorKeyboard = Notification.Name("HQEditorKeyboard")
}
