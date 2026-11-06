import AppKit
import SwiftUI

/// A markdown editor (DESIGN.md §9): monospaced, Undo, Find, no spell check, light syntax coloring.
/// ⌘Return commits, Escape cancels, leaving it ends the edit; Tab can leave it too. Descriptions and files share it.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var focusOnAppear = false
    /// Where the caret goes when it takes the keyboard: the end.
    var caretAtEnd = true
    /// A message rather than a note: the body font.
    var prose = false
    /// What VoiceOver calls it: "Description", "First message", the file's title.
    var label = "Markdown"
    var onCommit: () -> Void = {}
    var onCancel: () -> Void = {}
    var onEnd: () -> Void = {}
    /// Tab and ⇧Tab (true) leave the editor instead of typing a tab.
    var onTab: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        let editor = EditorTextView(frame: view.frame, textContainer: view.textContainer)
        editor.autoresizingMask = view.autoresizingMask
        editor.minSize = view.minSize
        editor.maxSize = view.maxSize
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
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
        editor.font = prose ? KitType.body.nsFont : KitType.editor.nsFont
        context.coordinator.font = editor.font ?? KitType.editor.nsFont
        editor.textColor = Ink.textNS
        editor.textContainerInset = NSSize(width: Space.sm, height: Space.sm)
        editor.defaultParagraphStyle = Coordinator.paragraph
        editor.typingAttributes[.paragraphStyle] = Coordinator.paragraph
        editor.string = text
        editor.setAccessibilityLabel(label)
        context.coordinator.highlight(editor)
        if focusOnAppear { editor.focusWhenShown(caretAtEnd: caretAtEnd) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView, editor.string != text, !context.coordinator.typing else { return }
        editor.string = text
        context.coordinator.highlight(editor)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        var typing = false
        var font = KitType.editor.nsFont
        private var ended = false

        init(_ parent: MarkdownEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            typing = true
            parent.text = editor.string
            typing = false
            highlight(editor)
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
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
                return tab(backward: selector == #selector(NSResponder.insertBacktab(_:)))
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

        /// Lines with room between them, as the rendered note has.
        static let paragraph: NSParagraphStyle = {
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = Metric.editorLineHeight
            return style
        }()

        /// Headings, list markers, code spans and fences, links: colored, never restyled.
        func highlight(_ editor: NSTextView) {
            guard let storage = editor.textStorage else { return }
            let text = storage.string as NSString
            let all = NSRange(location: 0, length: text.length)
            storage.beginEditing()
            storage.setAttributes([.font: font, .foregroundColor: Ink.textNS, .paragraphStyle: Self.paragraph], range: all)
            var inFence = false
            text.enumerateSubstrings(in: all, options: .byLines) { line, range, _, _ in
                guard let line else { return }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                    inFence.toggle()
                    storage.addAttribute(.foregroundColor, value: Ink.syntaxQuietNS, range: range)
                    return
                }
                if inFence {
                    storage.addAttribute(.foregroundColor, value: Ink.syntaxCodeNS, range: range)
                    return
                }
                if trimmed.hasPrefix("#") {
                    storage.addAttribute(.font, value: NSFontManager.shared.convert(self.font, toHaveTrait: .boldFontMask), range: range)
                    storage.addAttribute(.foregroundColor, value: Ink.syntaxHeadingNS, range: range)
                }
                if let marker = line.range(of: #"^\s*(?:[-*+]|\d+[.)])(?: \[[ xX]\])?\s"#, options: .regularExpression) {
                    storage.addAttribute(.foregroundColor, value: Ink.syntaxMarkerNS, range: NSRange(marker, in: line).shifted(by: range.location))
                }
                for match in line.matches(of: /`[^`]+`/) {
                    storage.addAttribute(.foregroundColor, value: Ink.syntaxCodeNS, range: NSRange(match.range, in: line).shifted(by: range.location))
                }
                for match in line.matches(of: /\[\[[^\]]+\]\]|\[[^\]]+\]\([^)\s]+\)|https?:\/\/\S+/) {
                    storage.addAttribute(.foregroundColor, value: Ink.syntaxLinkNS, range: NSRange(match.range, in: line).shifted(by: range.location))
                }
            }
            storage.endEditing()
        }
    }

    /// ⌘Return commits: the menu's own ⌘Return isn't bound while an editor has the keyboard.
    final class EditorTextView: NSTextView {
        weak var coordinator: Coordinator?
        private var wantsFocus: Bool?

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

        /// Takes the keyboard once it's in a window, after the window cleared its first focus.
        func focusWhenShown(caretAtEnd: Bool) {
            wantsFocus = caretAtEnd
            if window != nil { focusSoon() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { DispatchQueue.main.async { NotificationCenter.default.post(name: .editorKeyboard, object: nil) } }
            if window != nil, wantsFocus != nil { focusSoon() }
        }

        private func focusSoon() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, let window = self.window, let atEnd = self.wantsFocus else { return }
                self.wantsFocus = nil
                window.makeFirstResponder(self)
                let end = (self.string as NSString).length
                self.setSelectedRange(NSRange(location: atEnd ? end : 0, length: 0))
                self.scrollRangeToVisible(self.selectedRange())
            }
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command {
                coordinator?.commit()
                return
            }
            super.keyDown(with: event)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
               window?.firstResponder === self {
                coordinator?.commit()
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }
}

extension NSRange {
    func shifted(by offset: Int) -> NSRange { NSRange(location: location + offset, length: length) }
}

extension Notification.Name {
    /// A markdown editor took or left the keyboard.
    static let editorKeyboard = Notification.Name("HQEditorKeyboard")
}
