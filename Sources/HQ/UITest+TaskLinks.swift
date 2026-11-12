import AppKit
import HQKit

/// A task's links and its description in its window: every kind of link on a selected card (T-377), their tooltip and
/// menu in lines read at a glance (T-429), and a long description edited without the window jumping (T-378).
extension UITest {
    static func taskLinks(_ model: AppModel, _ ui: Driver) async {
        await linksOnSelectedCards(model, ui)
        await scenario(model, ui)
        await longDescriptionScroll(model, ui)
    }

    /// The task's card, made if it's scrolled away.
    private static func taskCell(_ ui: Driver, _ id: Int) -> TaskCell? {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator else { return nil }
        let row = outline.row(forItem: coordinator.node(.task(id)))
        guard row >= 0 else { return nil }
        outline.scrollRowToVisible(row)
        return outline.view(atColumn: 1, row: row, makeIfNecessary: true) as? TaskCell
    }

    /// The kinds of link a card draws whole, where they can be seen: its tray shown, inside the card, over nothing else.
    private static func drawnKinds(_ cell: TaskCell) -> Set<String> {
        let tray = cell.links
        guard !tray.isHidden, tray.window != nil, cell.bounds.contains(tray.frame),
              tray.width(compact: tray.compact) <= tray.bounds.width + 0.5 else { return [] }
        let others = [cell.title, cell.fold, cell.note, cell.filter, cell.project, cell.labels, cell.blockers, cell.progress] as [NSView]
        guard !others.contains(where: { !$0.isHidden && $0.frame.intersects(tray.frame) }) else { return [] }
        return Set(tray.tokens.flatMap(\.routes).map(kind))
    }

    private static func kind(_ route: ModalRoute) -> String {
        switch route {
        case .github: "PR"
        case .file: "file"
        case .artifact: "artifact"
        case .slack: "Slack"
        case .web: "web page"
        default: "other"
        }
    }

    /// T-377, T-429: a top-level task and a subtask, each with a PR, a file, an artifact, Slack messages and a web page.
    private static func linksOnSelectedCards(_ model: AppModel, _ ui: Driver) async {
        let pr = "https://github.com/acme/registry/pull/418"
        guard let parent = model.addTask(to: .overview, title: "Every kind of link"),
              let child = model.addSubtask(to: parent.id, title: "Every kind, on a subtask"),
              let file = model.addFile(title: "Linked note", body: "# Linked note\n"),
              let artifact = model.artifacts.first?.id else {
            return await check("a task, a subtask, a file and an artifact to link", false)
        }
        model.slackMessages = SlackService.fixtures
        model.slackMessages[SeedData.longSlackLink] = SeedData.longSlackMessage
        for id in [parent.id, child.id] {
            for route: ModalRoute in [.github(pr), .file(file.id), .artifact(artifact), .slack(SeedData.longSlackLink), .web(SeedData.webLink)] {
                model.link(route, to: id)
            }
        }
        // Two Slack messages on the top-level task: its token picks one.
        model.link(.slack(SlackService.fixtureLink), to: parent.id)
        model.setFold(parent.id, .all)
        await endUndoGroup(model)
        await ui.settle(0.5)
        let every: Set<String> = ["PR", "file", "artifact", "Slack", "web page"]
        for (id, name) in [(parent.id, "a top-level task's card"), (child.id, "a subtask's card")] {
            await ui.until { taskCell(ui, id).map { drawnKinds($0) == every } ?? false }
            let rest = taskCell(ui, id)?.links.tokens ?? []
            await check("at rest, \(name) draws every kind of link", taskCell(ui, id).map { drawnKinds($0) == every } ?? false,
                  taskCell(ui, id).map { "drew \(drawnKinds($0).sorted()) of \(every.sorted())" } ?? "no card")
            // Selected, with the rows' keyboard, as a click leaves it.
            if let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator {
                outline.selectRowIndexes([outline.row(forItem: coordinator.node(.task(id)))], byExtendingSelection: false)
                ui.window.makeFirstResponder(outline)
            }
            await ui.settle(0.4)
            await check("selected, \(name) still draws every kind of link, the same as at rest (T-377)",
                  taskCell(ui, id).map { drawnKinds($0) == every && $0.links.tokens == rest } ?? false,
                  taskCell(ui, id).map { "drew \(drawnKinds($0).sorted()), tray hidden \($0.links.isHidden), \($0.links.frame) in \($0.bounds)" } ?? "no card")
        }

        // T-429: the Slack token's tooltip and menu in lines read at a glance; one link's whole text wrapped.
        func tooltip(_ id: Int, _ route: ModalRoute) -> String? {
            guard let tray = taskCell(ui, id)?.links, let point = tray.windowPoint(of: route) else { return nil }
            return tray.view(tray, stringForToolTip: 0, point: tray.convert(point, from: nil), userData: nil)
        }
        func short(_ text: String?) -> Bool { text.map { $0.split(separator: "\n").allSatisfy { $0.count <= LineCut.width } } ?? false }
        let long = model.title(of: .slack(SeedData.longSlackLink))
        let several = tooltip(parent.id, .slack(SeedData.longSlackLink))
        await check("several Slack messages' tooltip: a line each, none past \(LineCut.width) characters (T-429)",
              short(several) && several?.split(separator: "\n").count == 3 && several?.contains("…") == true, several ?? "no tooltip")
        let one = tooltip(child.id, .slack(SeedData.longSlackLink))
        await check("one Slack message's tooltip: its whole text, wrapped in lines of at most \(LineCut.width) characters (T-429)",
              short(one) && one.map { $0.split(whereSeparator: \.isNewline).dropLast().joined(separator: " ").hasPrefix("Slack: " + String(long.prefix(200))) } == true,
              one ?? "no tooltip")
        // The menu a click on them shows: each item a line, the whole title in its tooltip.
        var shownMenu: NSMenu?
        let showMenu = FaceMenu.show
        FaceMenu.show = { menu, _, _, _ in shownMenu = menu }
        if let outline = ui.find(TaskOutlineView.self), let point = taskCell(ui, parent.id)?.links.windowPoint(of: .slack(SeedData.longSlackLink)),
           let down = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                         windowNumber: ui.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
            outline.rightMouseDown(with: down)
        }
        FaceMenu.show = showMenu
        let items = shownMenu?.items ?? []
        let cut = items.first { $0.title.hasSuffix("…") }
        await check("the menu of several Slack messages: each a line of at most \(LineCut.width) characters, the whole one in its tooltip (T-429)",
              items.count == 2 && items.allSatisfy { $0.title.count <= LineCut.width }
              && cut?.toolTip.map { $0.split(whereSeparator: \.isNewline).joined(separator: " ").hasPrefix(String(long.prefix(200))) } == true,
              items.map(\.title).joined(separator: " | "))
        model.deleteTasks([parent.id, child.id])
        await endUndoGroup(model)
    }

    /// T-378: typing, moving the caret and Return near the end of a long description in the task's window: the window
    /// scrolls only to keep the caret in view, never back and forth, and the editor's own box never scrolls.
    private static func longDescriptionScroll(_ model: AppModel, _ ui: Driver) async {
        let paragraphs = (1...40).map { "Paragraph \($0): the retry budget holds per upload, so a slow part never starves the others in the push." }
        guard let task = model.addTask(to: .overview, title: "A long description", body: paragraphs.joined(separator: "\n\n")) else {
            return await check("a task with a long description", false)
        }
        await endUndoGroup(model)
        model.open(.task(task.id))
        await ui.settle(0.8)
        model.editDescription(task.id)
        await ui.until { (ui.window.attachedSheet?.firstResponder as? MarkdownEditor.EditorTextView) != nil }
        guard let sheet = ui.window.attachedSheet, let editor = sheet.firstResponder as? MarkdownEditor.EditorTextView,
              let box = editor.enclosingScrollView, let page = box.enclosingScrollView else {
            model.closeModal()
            return await check("the task's window edits its description, in a page that scrolls", false)
        }
        // The caret on the last paragraph's line, shown.
        let length = (editor.string as NSString).length
        editor.setSelectedRange(NSRange(location: length - 20, length: 0))
        editor.scrollRangeToVisible(editor.selectedRange())
        await ui.settle(0.6)

        func key(_ characters: String, _ code: UInt16) {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: sheet.windowNumber, context: nil, characters: characters,
                                               charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { return }
            editor.keyDown(with: event)
        }
        let returnKey = ("\r", UInt16(36)), up = (String(UnicodeScalar(NSUpArrowFunctionKey)!), UInt16(126)),
            down = (String(UnicodeScalar(NSDownArrowFunctionKey)!), UInt16(125))
        let steps: [(String, UInt16)] = [("a", 0), ("b", 11), returnKey, ("c", 8), returnKey, returnKey, up, up, down, returnKey, ("d", 2), down, returnKey]
        var backAndForth: [String] = []
        var boxScrolled: CGFloat = 0
        var hidden: [String] = []
        for (index, step) in steps.enumerated() {
            var offsets = [page.contentView.bounds.origin.y]
            key(step.0, step.1)
            // Every turn of the run loop for a moment: where the window is scrolled, and the editor's own box.
            let until = Date.now.addingTimeInterval(0.35)
            while Date.now < until {
                offsets.append(page.contentView.bounds.origin.y)
                boxScrolled = max(boxScrolled, abs(box.contentView.bounds.origin.y))
                try? await Task.sleep(for: .milliseconds(4))
            }
            offsets.append(page.contentView.bounds.origin.y)
            let travelled = zip(offsets, offsets.dropFirst()).map { abs($1 - $0) }.reduce(0, +)
            if travelled - abs(offsets.last! - offsets.first!) > 2 {
                backAndForth.append("step \(index): \(offsets.map { Int($0.rounded()) }.reduce(into: [Int]()) { if $0.last != $1 { $0.append($1) } })")
            }
            // The caret's line in view in the window.
            if let layout = editor.layoutManager, let container = editor.textContainer {
                let caret = editor.selectedRange().location
                let line = caret < (editor.string as NSString).length
                    ? layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: caret), effectiveRange: nil)
                    : layout.extraLineFragmentRect.height > 0 ? layout.extraLineFragmentRect : layout.usedRect(for: container)
                let shown = page.documentView.map { editor.convert(line.offsetBy(dx: 0, dy: editor.textContainerOrigin.y), to: $0) }
                if let shown, !page.documentVisibleRect.insetBy(dx: 0, dy: -1).contains(NSRect(x: page.documentVisibleRect.midX, y: shown.minY, width: 1, height: shown.height)) {
                    hidden.append("step \(index)")
                }
            }
        }
        await check("editing a long description in its window: the window never scrolls back and forth (T-378)", backAndForth.isEmpty,
              backAndForth.joined(separator: "; "))
        await check("…the editor's own box never scrolls: it grows with the text", boxScrolled <= 1, "scrolled \(boxScrolled) pt")
        await check("…and the caret stays in view", hidden.isEmpty, hidden.joined(separator: ", "))
        model.saveModalEdits()
        model.closeModal()
        model.deleteTasks([task.id])
        await endUndoGroup(model)
    }
}
