import AppKit
import SwiftUI

/// A form's task title, in AppKit so `#` lists the statuses, projects and tags that start so, as a title in the list does
/// (T-772). Return submits, Escape cancels.
struct HashtagTitleField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let model: AppModel
    let submit: () -> Void
    let cancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = FirstField()
        field.bezelStyle = .roundedBezel
        field.isBezeled = true
        field.font = KitType.body.nsFont
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.placeholderString = placeholder
        field.setAccessibilityLabel("Task")
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        guard field.stringValue != text else { return }
        // Named after a link while it has the keyboard: its editor takes the words.
        if let editor = field.currentEditor() {
            editor.string = text
            editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        } else {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: HashtagTitleField
        private var completing = false
        private var deleting = false

        init(_ parent: HashtagTitleField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            guard !completing, !deleting, let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView,
                  OutlineCoordinator.hashWord(in: editor) != nil else {
                deleting = false
                return
            }
            completing = true
            editor.complete(nil)
            completing = false
        }

        func control(_ control: NSControl, textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange,
                     indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
            guard let word = OutlineCoordinator.hashWord(in: textView), word.range == charRange else { return [] }
            index.pointee = 0
            return parent.model.titleCompletions(word.text)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            deleting = selector == #selector(NSResponder.deleteBackward(_:)) || selector == #selector(NSResponder.deleteForward(_:))
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.text = control.stringValue
                parent.submit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.cancel()
                return true
            default:
                return false
            }
        }
    }
}

/// Takes the keyboard once it is in its window, as a form's first field does, unless a text has it by then.
final class FirstField: NSTextField {
    private var focused = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !focused, let window else { return }
        focused = true
        // After this turn: a click into another field meanwhile keeps the keyboard there.
        DispatchQueue.main.async { [weak self] in
            guard let self, !(window.firstResponder is NSText) else { return }
            window.makeFirstResponder(self)
        }
    }
}
