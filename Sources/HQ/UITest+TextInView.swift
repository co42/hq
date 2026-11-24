import AppKit
import HQKit

/// Multi-line fields keep their text in view (T-778): after blank lines typed between paragraphs, or a line wrapping past
/// what the field shows, the line with the caret shows whole, at the user's zoom, in a window tall enough for the form and in one where the form scrolls.
extension UITest {
    static func textInView(_ model: AppModel, _ ui: Driver) async {
        model.zoom = 1.15
        let frame = ui.window.frame
        guard let task = model.addTask(status: .todo, title: "Text in view") else { return await check("a task to write in", false) }
        await endUndoGroup(model)
        defer { model.deleteTasks([task.id]) }
        for height in [frame.height, 640] as [CGFloat] {
            ui.window.setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height), display: true)
            await ui.settle(0.4)
            let tall = "window \(Int(height)) pt tall"

            model.beginStart()
            await ui.until(3) { editor(ui) is MarkdownEditor.EditorTextView }
            await typeParagraphs(ui, "First message, \(tall)", newline: returnKey)
            await close(model, ui)

            model.open(.newTask(.todo))
            await ui.until(3) { editor(ui) != nil }
            await ui.settle(0.3)
            // A click focuses no text view in a background copy: the description takes the keyboard as a click gives it.
            func walk(_ view: NSView) -> MarkdownEditor.EditorTextView? {
                view as? MarkdownEditor.EditorTextView ?? view.subviews.lazy.compactMap(walk).first
            }
            if let sheet = ui.window.attachedSheet, let description = sheet.contentView.flatMap(walk) { sheet.makeFirstResponder(description) }
            await ui.until(3) { editor(ui) is MarkdownEditor.EditorTextView }
            await typeParagraphs(ui, "New Task’s description, \(tall)", newline: returnKey)
            await close(model, ui)

            model.changeTask(task.id, "Edit") { $0.body = "" }
            model.open(.task(task.id))
            await ui.until(3) { ui.anchorFrame("modal-title") != nil }
            model.editDescription(task.id)
            await ui.until(3) { editor(ui) is MarkdownEditor.EditorTextView }
            await typeParagraphs(ui, "a task’s description, \(tall)", newline: returnKey)
            await close(model, ui)

            model.open(.roles)
            model.selectedRole = "Worker"
            await ui.settle(0.3)
            model.beginRoleEdit(.text)
            await ui.until(3) { editor(ui) is MarkdownEditor.EditorTextView }
            await typeParagraphs(ui, "a role’s text, \(tall)", newline: returnKey)
            model.cancelRoleEdit()
            await close(model, ui)

            // SwiftUI's own fields: one line that wraps, up to four shown, Return saves them.
            model.open(.task(task.id))
            await ui.click(await ui.steadyAnchor("modal-title"), inSheet: true)
            await ui.until(2) { editor(ui) != nil }
            await typeWrapping(ui, "a task’s title, \(tall)")
            await close(model, ui)
            model.setTitle(task.id, "Text in view")

            model.block(task.id)
            model.open(.task(task.id))
            await ui.until(3) { ui.anchorFrame("blocked-row") != nil }
            model.reasonFocus = task.id
            await ui.until(2) { editor(ui) != nil }
            await typeWrapping(ui, "a Block reason, \(tall)")
            await close(model, ui)
            model.unblock(task.id)
        }
        model.zoom = 1
        ui.window.setFrame(frame, display: true)
        await ui.settle(0.6)
    }

    private static func close(_ model: AppModel, _ ui: Driver) async {
        model.closeModal()
        await ui.until(2) { ui.window.attachedSheet == nil }
    }

    /// The text view that has the sheet's keyboard: an AppKit editor, or the field editor of a SwiftUI field.
    private static func editor(_ ui: Driver) -> NSTextView? { ui.window.attachedSheet?.firstResponder as? NSTextView }

    /// Paragraphs with blank lines between, past the box's height: at each step the caret's line whole inside what the field
    /// shows, every view around it that clips it included.
    private static func typeParagraphs(_ ui: Driver, _ field: String, newline: (Driver) async -> Void) async {
        guard let start = editor(ui) as? MarkdownEditor.EditorTextView else {
            return await check("\(field): the field has the keyboard", false, "it is in \(holder(ui))")
        }
        var hidden: [String] = []
        for paragraph in ["A first paragraph", "A second paragraph", "A third paragraph"] {
            await type(ui, paragraph)
            look(ui, start, paragraph, into: &hidden)
            for _ in 0..<5 { await newline(ui) }
            await ui.settle(0.2)
            look(ui, start, "five new lines after \(paragraph)", into: &hidden)
        }
        await type(ui, "The last line")
        look(ui, start, "the last line", into: &hidden)
        let lines = start.string.components(separatedBy: .newlines).count
        if lines < 16 { hidden.append("\(lines) lines typed, not 16") }
        await check("\(field): the line with the caret shows whole after blank lines, at zoom 1.15", hidden.isEmpty, hidden.joined(separator: "; "))
    }

    /// One line of words that wraps past the four lines the field shows: at each step the caret's line whole.
    private static func typeWrapping(_ ui: Driver, _ field: String) async {
        guard let start = editor(ui) else { return await check("\(field): the field has the keyboard", false, "it is in \(holder(ui))") }
        start.selectAll(nil)
        var hidden: [String] = []
        for count in 1...12 {
            await type(ui, "\(count == 1 ? "" : " ")a sentence long enough to wrap the field's line once more, number \(count)")
            look(ui, start, "sentence \(count)", into: &hidden)
        }
        if start.string.contains(where: \.isNewline) { hidden.append("it holds a line break") }
        if let layout = start.layoutManager, let container = start.textContainer {
            var lines = 0
            layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, _, _ in lines += 1 }
            if lines < 5 { hidden.append("it wraps to \(lines) lines, not past 4") }
        }
        await check("\(field): the line with the caret shows whole as it wraps past four lines, at zoom 1.15", hidden.isEmpty, hidden.joined(separator: "; "))
    }

    private static func holder(_ ui: Driver) -> String {
        ui.window.attachedSheet.map { String(describing: $0.firstResponder.map { Swift.type(of: $0) }) } ?? "no sheet"
    }

    private static func type(_ ui: Driver, _ text: String) async {
        editor(ui)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        await ui.settle(0.2)
    }

    /// The caret's line whole inside what `start` shows; still `start` with the keyboard.
    private static func look(_ ui: Driver, _ start: NSTextView, _ step: String, into hidden: inout [String]) {
        guard let editor = editor(ui), editor === start, let layout = editor.layoutManager, let container = editor.textContainer else {
            return hidden.append("\(step): the field lost the keyboard")
        }
        layout.ensureLayout(for: container)
        let caret = editor.selectedRange().location
        let length = (editor.string as NSString).length
        var line: NSRect
        if caret >= length, layout.extraLineFragmentTextContainer != nil {
            line = layout.extraLineFragmentRect
        } else {
            let glyph = layout.glyphIndexForCharacter(at: max(0, min(caret, length) - (caret >= length ? 1 : 0)))
            line = layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        }
        line = line.offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
        let shown = editor.visibleRect
        if line.minY < shown.minY - 0.5 || line.maxY > shown.maxY + 0.5 {
            hidden.append(String(format: "%@: line %.1f–%.1f, shown %.1f–%.1f", step, line.minY, line.maxY, shown.minY, shown.maxY))
        }
    }

    /// Return, as AppKit gives it to the sheet: its key equivalents first, then the editor.
    private static func returnKey(_ ui: Driver) async {
        guard let sheet = ui.window.attachedSheet,
              let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: sheet.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                                           isARepeat: false, keyCode: 36) else { return }
        if !sheet.performKeyEquivalent(with: event) { sheet.sendEvent(event) }
        await ui.settle(0.05)
    }
}
