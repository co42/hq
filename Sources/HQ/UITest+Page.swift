import AppKit
import HQKit
import SwiftUI

/// The page's cards and grid, and the modal: keys past a card's fifth row, the modal's own selection, New File… and
/// Import Artifact… as sheets, the grid under a filtered or busy drag, a PR page a poll drops, Escape in forms over a modal,
/// ⇧⌘B on a subtask in its task's window.
extension UITest {
    static func pageFixes(_ model: AppModel, _ ui: Driver) async {
        await stackPastFive(model, ui)
        await scenario(model, ui)
        await keysPastFive(model, ui)
        await scenario(model, ui)
        await capsAtTwenty(model, ui)
        await scenario(model, ui)
        await modalSelection(model, ui)
        await scenario(model, ui)
        await fileSheets(model, ui)
        await scenario(model, ui)
        await filteredGridDrag(model, ui)
        await scenario(model, ui)
        await gridHoldsUnderDrag(model, ui)
        await scenario(model, ui)
        await prPageStays(model, ui)
        await scenario(model, ui)
        await escapeInForms(model, ui)
        await scenario(model, ui)
        await subtaskToBacklog(model, ui)
        await scenario(model, ui)
        await zoomSteps(model, ui)
        await scenario(model, ui)
        await sheetsFollowZoom(model, ui)
        await scenario(model, ui)
        await linkRows(model, ui)
        await scenario(model, ui)
        await pinnedHeaders(model, ui)
    }

    /// Every form sheet grows with the zoom: its header and its buttons stay inside it, at the user's 115% and at 150% (T-446),
    /// and it stays inside a half-laptop window, its fields scrolling (T-564).
    private static func sheetsFollowZoom(_ model: AppModel, _ ui: Driver) async {
        let forms: [(ModalRoute, String)] = [(.start, "start-button"), (.newTask(.todo), "new-task-add"), (.newReminder, "new-reminder-add"),
                                             (.newFile, "new-file-create"), (.importArtifact, "import-add")]
        let frame = ui.window.frame
        ui.window.setContentSize(NSSize(width: 756, height: 640)) // grid: ok a half-laptop window
        for zoom in [1.15, 1.5] as [CGFloat] {
            model.zoom = zoom
            for (route, button) in forms {
                if route == .start { model.beginStart() } else { model.open(route) }
                /// The parts of the sheet that run past its edges.
                func cut() -> [String] {
                    guard let sheet = ui.window.attachedSheet, let bounds = sheet.contentView?.bounds.insetBy(dx: -0.5, dy: -0.5) else { return ["no sheet"] }
                    let shown = [button, "\(button)-off"].first { ui.anchorFrame($0) != nil } ?? button
                    return ["modal-close", shown].filter { name in ui.anchorFrame(name).map { !bounds.contains($0) } ?? true }
                        .map { "\($0) at \(ui.anchorFrame($0)?.integral ?? .zero) in \(sheet.frame.size)" }
                        + (sheet.frame.width > ui.window.frame.width + 0.5 || sheet.frame.height > ui.window.frame.height + 0.5 ? ["the sheet, \(sheet.frame.size) in a \(ui.window.frame.size) window"] : [])
                }
                await ui.settle(0.3)
                await check("at \(Int((zoom * 100).rounded()))%, \(model.title(of: route)) shows its header and its buttons whole, inside the window", cut().isEmpty, cut().joined(separator: ", "))
                model.closeModal()
                await ui.until { ui.window.attachedSheet == nil }
            }
        }
        ui.window.setFrame(frame, display: true)
        model.zoom = 1
    }

    /// View › Zoom In, Zoom Out and Actual Size, as choosing them does. An inactive app's menu bar keeps the state it had,
    /// so a background run takes their actions; `MenuState`, which turns them on and off, is checked at each step.
    private static func chooseView(_ model: AppModel, _ title: String) {
        if NSApp.isActive, let view = NSApp.mainMenu?.items.first(where: { $0.title == "View" })?.submenu,
           let item = view.items.first(where: { $0.title == title && $0.isEnabled }) {
            return view.performActionForItem(at: view.index(of: item))
        }
        switch title {
        case "Zoom In": model.zoom(by: 1)
        case "Zoom Out": model.zoom(by: -1)
        default: model.zoom = 1
        }
    }

    /// Each zoom step lays the page out at once, as a launch at that zoom does: the column, the sky over it, the problem
    /// banner, the section bar and Quick Open take the step's sizes.
    private static func zoomSteps(_ model: AppModel, _ ui: Driver) async {
        model.problem = .githubSignedOut
        await ui.settle(0.4)
        func probe(_ name: String) -> NSView? { UITest.anchors[name, default: []].compactMap(\.view).last { $0.window === ui.window } }
        func gap(_ found: CGFloat?, _ wanted: CGFloat) -> String { found.map { abs($0 - wanted) < 1 ? "" : "\($0) for \(wanted)" } ?? "none for \(wanted)" }
        /// What's off at this zoom, or nothing.
        func off() -> [String] {
            ui.window.layoutIfNeeded()
            guard let column = probe("page-column"), let visible = column.enclosingScrollView?.contentView.bounds.width else { return ["no column"] }
            let wanted = CockpitView.column(visible)
            let sky = ui.find(SkyLayerView.self, in: ui.window.contentView)
            let bar = probe("section-bar").map { $0.convert($0.bounds, to: nil).height }
            let shows = model.windowSize.width >= Metric.sectionBarWindow
            var off = [
                "column " + gap(column.bounds.width, wanted.width),
                "inset " + gap(column.convert(column.bounds, to: column.enclosingScrollView?.contentView).minX, wanted.inset),
                "banner " + gap(probe("problem-banner")?.bounds.width, wanted.width),
                "sky " + gap(sky?.bounds.height, Metric.skyHeight),
                "section bar " + (shows ? gap(bar, Metric.sectionBarItem + Metric.lineGap * 2) : bar == nil ? "" : "shown below \(Metric.sectionBarWindow)"),
                // View's Zoom In, Zoom Out and Actual Size turn on and off by it.
                "menu " + (MenuState.shared.zoom == model.zoom ? "" : "at \(MenuState.shared.zoom)"),
            ]
            if let panel = AppDelegate.shared?.quickOpenPanel {
                off.append("Quick Open " + gap(panel.contentLayoutRect.width, Metric.quickOpenWidth))
            }
            return off.filter { !$0.hasSuffix(" ") }
        }
        // Scroll bars shown always, as with a mouse plugged in: the column fits the room they leave (T-436).
        let page = probe("page-column")?.enclosingScrollView, style = page?.scrollerStyle
        page?.scrollerStyle = .legacy
        defer { if let style { page?.scrollerStyle = style } }
        await check("with scroll bars shown always, the page's scroll bar takes room",
                    page.map { $0.contentView.bounds.width < $0.bounds.width - 1 } == true && off().isEmpty, (off() + ["clip \(page?.contentView.bounds.width ?? 0) of \(page?.bounds.width ?? 0), document \(page?.documentView?.frame.width ?? 0), scroller \(page?.verticalScroller?.isHidden == false)"]).joined(separator: ", "))
        // Quick Open made at 100%, as the first ⌘K makes it.
        _ = AppDelegate.shared?.quickOpenPanel.frame
        for (title, zoom) in [("Zoom In", 1.15), ("Zoom In", 1.3), ("Zoom In", 1.5), ("Zoom Out", 1.3), ("Zoom Out", 1.15), ("Zoom Out", 1), ("Zoom Out", 0.85), ("Actual Size", 1)] as [(String, CGFloat)] {
            chooseView(model, title)
            AppDelegate.shared?.quickOpenPanel.fit()
            await check("View › \(title) to \(Int((zoom * 100).rounded()))%: the page's column, sky, banner, section bar and Quick Open follow at once",
                        model.zoom == zoom && off().isEmpty, "zoom \(model.zoom): \(off().joined(separator: ", "))")
        }
        model.problem = nil
    }

    /// A task's window lists every kind of link under one title, each with its kind's icon: a PR or an issue GitHub
    /// hasn't brought yet too.
    private static func linkRows(_ model: AppModel, _ ui: Driver) async {
        let pr = "https://github.com/acme/registry/pull/9001", issue = SeedData.unfetchedIssue
        guard let task = model.addTask(status: .todo, title: "Every kind of link"), let file = model.addFile(title: "Linked note"),
              let artifact = model.artifacts.first?.id, model.githubItem(pr) == nil, model.githubItem(issue) == nil else {
            return await check("a task, a file, an artifact and two GitHub links HQ hasn't fetched", false)
        }
        let routes: [ModalRoute] = [.github(pr), .github(issue), .file(file.id), .artifact(artifact), .slack(SlackService.fixtureLink), .web(SeedData.webLink)]
        for route in routes { model.link(route, to: task.id) }
        await endUndoGroup(model)
        model.open(.task(task.id))
        await ui.until(2) { ui.window.attachedSheet != nil }
        await ui.settle(0.6)
        func missing() -> [String] {
            routes.filter { route in
                guard let icon = ui.anchorFrame("kind-icon:\(route.selectionKey)"), let row = ui.anchorFrame("row:\(route.selectionKey)") else { return true }
                return icon.width < 1 || !row.insetBy(dx: -0.5, dy: -0.5).contains(icon)
            }.map(\.selectionKey)
        }
        await check("each link's row in a task's window shows its kind's icon, a PR and an issue not fetched yet too", missing().isEmpty,
                    "no icon: \(missing())")
        await check("and their group's title names every kind: Links", ui.anchorFrame("group:Links") != nil)
        model.closeModal()
        await ui.until(2) { ui.window.attachedSheet == nil }
    }

    /// A key pressed in the sheet, as AppKit gives it to the key window: its key equivalents first (a button's shortcut),
    /// then its first responder. A background run's sheet is never key, so the window gets it directly.
    private static func sheetKey(_ ui: Driver, _ characters: String, _ flags: NSEvent.ModifierFlags = [], code: UInt16) async {
        guard let sheet = ui.window.attachedSheet,
              let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: sheet.windowNumber, context: nil, characters: characters,
                                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { return }
        if !sheet.performKeyEquivalent(with: event) { sheet.sendEvent(event) }
        await ui.settle(0.4)
    }

    /// Text typed into the field that has the sheet's keyboard, as its editor takes it.
    private static func typeInSheet(_ ui: Driver, _ text: String) async {
        (ui.window.attachedSheet?.firstResponder as? NSTextView)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        await ui.settle(0.2)
    }

    /// Five rows per PR card at rest (T-767): the seed's six-PR stack in Yours is cut after its fourth, Show 4 More shows the rest.
    private static func stackPastFive(_ model: AppModel, _ ui: Driver) async {
        model.search = ""
        model.expandedCards = []
        await ui.until(3) { ui.anchorFrame("pr:83") != nil }
        let drawn = { (numbers: [Int]) in numbers.filter { ui.anchorFrame("pr:\($0)") != nil } }
        let yours = model.ownPullRequests.map(\.number)
        await check("Yours draws its first five rows, the stack cut after #83", drawn(yours).count == PRCards.shown
                    && drawn([80, 81, 82, 83, 84, 85]) == [80, 81, 82, 83], "\(drawn(yours)) of \(yours)")
        await check("Reviews draws five rows at most", drawn(model.reviewRequests.map(\.number)).count <= PRCards.shown)
        let rail = { ui.anchorFrame("stack-rail:80") }
        await check("the cut stack's rail runs on to the bottom of its last row shown", {
            guard let rail = rail(), let last = ui.anchorFrame("pr:83") else { return false }
            // Window coordinates: the bottom edge is minY.
            return abs(rail.minY - last.minY) < 1
        }(), "rail \(String(describing: rail())), #83 \(String(describing: ui.anchorFrame("pr:83")))")
        await ui.click(await ui.steadyAnchor("show-more:yours"))
        await ui.until(2) { ui.anchorFrame("pr:85") != nil }
        await check("Show 4 More shows the rest of the stack and the rows after it", drawn(yours).count == yours.count,
                    "\(drawn(yours)) of \(yours)")
        await check("the whole stack's rail ends at its last tile's middle", {
            guard let rail = rail(), let last = ui.anchorFrame("pr:85") else { return false }
            return abs(rail.minY - last.midY) < 1
        }(), "rail \(String(describing: rail())), #85 \(String(describing: ui.anchorFrame("pr:85")))")
        await ui.click(await ui.steadyAnchor("show-more:yours"))
        await ui.until(2) { ui.anchorFrame("pr:84") == nil }
        await check("Show Fewer cuts it at the fifth row again", drawn(yours).count == PRCards.shown, "\(drawn(yours))")
    }

    /// Show N More: the arrows reach every row it shows, Return opens one past the fifth; a filter that shows every row
    /// never lets the arrows select one the card doesn't draw.
    private static func keysPastFive(_ model: AppModel, _ ui: Driver) async {
        let made = (1...7).compactMap { model.addFile(title: "Page note \($0)") }
        await ui.settle(0.5)
        let rows = model.listedFiles.map { ModalRoute.file($0.id).selectionKey }
        guard made.count == 7, rows.count == 7 else { return await check("seven files to walk", false, "\(rows.count)") }
        await ui.click(ui.anchor("show-more:files"))
        await check("Show 2 More shows every file", model.expandedCards.contains(.files) && ui.anchorFrame("item:\(rows[6])") != nil)
        await ui.click(ui.anchor("item:\(rows[0])"))
        await check("a click selects the first file", model.selectedItem == rows[0], model.selectedItem ?? "none")
        for _ in 0..<6 { await ui.key(.down) }
        await check("↓ walks past the fifth row once Show More shows them", model.selectedItem == rows[6], model.selectedItem ?? "none")
        await ui.key(.return)
        await ui.until(2) { model.modal != nil }
        await check("Return opens the seventh", model.modal?.selectionKey == rows[6], "\(String(describing: model.modal))")
        model.closeModal()
        await ui.until(2) { ui.window.attachedSheet == nil }
        await ui.settle(0.4)

        // Show Fewer, then Pinned Only: a filter shows every pinned row, and the arrows walk only those.
        await ui.click(await ui.steadyAnchor("show-more:files"))
        await check("Show Fewer folds the card back to five", !model.expandedCards.contains(.files))
        for file in made { model.setPinned(.file(file.id), true) }
        model.pinnedOnly = true
        // Pinning rewrites each note and the vault reads its time back from disk: the rows hold their order once every one is read.
        func listed() -> [String] { model.listedFiles.map { ModalRoute.file($0.id).selectionKey } }
        func readBack() -> Bool {
            made.allSatisfy { item in
                guard let file = model.file(item.id), file.pinned, let path = file.path,
                      let disk = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { return false }
                return abs(file.modified.timeIntervalSince(disk)) < 0.001
            }
        }
        await ui.until(5) { readBack() }
        await ui.settle(0.3)
        let pinned = listed()
        guard readBack(), pinned.count == made.count else { return await check("the pinned notes are read back from disk", false, "\(pinned)") }
        await ui.click(await ui.steadyAnchor("item:\(pinned[0])"))
        await check("with Pinned Only, a click selects the first pinned file", model.selectedItem == pinned.first, model.selectedItem ?? "none")
        var unshown: [String] = []
        var walk: [String] = []
        for _ in 0..<6 {
            await ui.key(.down)
            walk.append(String((model.selectedItem ?? "none").suffix(10)))
            if let key = model.selectedItem, ui.anchorFrame("item:\(key)") == nil { unshown.append(key) }
        }
        await check("with Pinned Only, the card shows every pinned file and ↓ selects only rows it shows",
              unshown.isEmpty && model.selectedItem == pinned.last,
              "not shown: \(unshown), at \(model.selectedItem ?? "none"), \(model.listedFiles.count) listed of \(pinned.count) pinned, \(model.files.filter(\.pinned).count) pinned now, walk \(walk), pinned \(pinned.map { String($0.suffix(10)) }), listed now \(listed().map { String($0.suffix(10)) })")
    }

    /// Show N More past twenty rows (T-527): the card stops at twenty and scrolls inside, the card beside it as tall;
    /// ↓ brings a row past the twentieth into view; a search with more matches scrolls too; Show Fewer folds it where it was.
    private static func capsAtTwenty(_ model: AppModel, _ ui: Driver) async {
        let made = (1...24).compactMap { model.addFile(title: "Long list \($0)") }
        // Tasks under the cards: the page is long enough below them that folding never meets its end.
        for n in 1...20 { _ = model.addTask(status: .todo, title: "Below the cards \(n)") }
        await ui.settle(0.5)
        let rows = model.listedFiles.map { ModalRoute.file($0.id).selectionKey }
        guard made.count == 24, rows.count > PRCards.scrollsPast else { return await check("more than twenty files", false, "\(rows.count)") }
        let tall = CGFloat(PRCards.scrollsPast) * Metric.itemRow
        // The card's title line, twenty rows, Show Fewer and the foot's inset.
        let most = Metric.boxRow + Space.xs + tall + Metric.boxRow + Space.sm
        await ui.click(await ui.steadyAnchor("show-more:files"))
        await check("Show More past twenty rows scrolls them inside the card, twenty rows tall",
                    model.expandedCards.contains(.files) && abs((ui.anchorFrame("card-scroll:files")?.height ?? 0) - tall) < 1
                    && (ui.anchorFrame("card:files")?.height ?? .infinity) <= most + 1,
                    "scroll \(String(describing: ui.anchorFrame("card-scroll:files"))), card \(String(describing: ui.anchorFrame("card:files")))")
        await check("the card beside it grows to the same height, no more", {
            guard let files = ui.anchorFrame("card:files"), let artifacts = ui.anchorFrame("card:artifacts") else { return false }
            return abs(files.maxY - artifacts.maxY) >= 1 || abs(files.height - artifacts.height) < 1
        }(), "files \(String(describing: ui.anchorFrame("card:files"))), artifacts \(String(describing: ui.anchorFrame("card:artifacts")))")

        await ui.click(await ui.steadyAnchor("item:\(rows[0])"))
        for _ in 1..<rows.count { await ui.key(.down) }
        func shown(_ key: String) -> CGFloat { UITest.anchors["item:\(key)", default: []].compactMap(\.view).last { $0.window != nil }?.visibleRect.height ?? 0 }
        await check("↓ past the twentieth row scrolls the card to it", model.selectedItem == rows.last && shown(rows.last!) >= Metric.itemRow - 1,
                    "at \(model.selectedItem ?? "none"), \(shown(rows.last!)) pt of it shown")

        guard let fewer = await ui.steadyAnchor("show-more:files") else { return await check("Show Fewer under the rows", false) }
        let top = ui.anchorFrame("card:files")?.maxY ?? 0
        let page = UITest.anchors["card:files", default: []].compactMap(\.view).last { $0.window != nil }?.enclosingScrollView
        func scrolled() -> String { page.map { "offset \($0.contentView.bounds.minY) of \(($0.documentView?.frame.height ?? 0) - $0.contentView.bounds.height)" } ?? "no page" }
        let before = scrolled()
        await ui.click(fewer)
        await check("Show Fewer folds the long card back to five, its top where it was",
                    !model.expandedCards.contains(.files) && ui.anchorFrame("card-scroll:files") == nil
                    && abs((ui.anchorFrame("card:files")?.maxY ?? 0) - top) < 1,
                    "top \(top), now \(String(describing: ui.anchorFrame("card:files"))); page before \(before), after \(scrolled())")

        model.search = "Long list"
        await ui.settle(0.4)
        await check("a search with more than twenty matches scrolls them inside the card",
                    abs((ui.anchorFrame("card-scroll:files")?.height ?? 0) - tall) < 1)
        model.search = ""
    }

    /// A row clicked in the modal selects there: the page's selection is still the one thing selected once it closes.
    private static func modalSelection(_ model: AppModel, _ ui: Driver) async {
        guard let pr = model.reviewRequests.first ?? model.ownPullRequests.first, let file = model.addFile(title: "Linked note"),
              let task = model.addTask(status: .todo, title: "Has a note") else { return await check("a PR, a file and a task", false) }
        model.link(.file(file.id), to: task.id)
        await endUndoGroup(model)
        await ui.settle(0.4)
        let prKey = ModalRoute.github(pr.url).selectionKey
        let fileKey = ModalRoute.file(file.id).selectionKey
        await ui.click(ui.anchor("pr:\(pr.number)"))
        await check("a click selects the PR", model.selectedItem == prKey, model.selectedItem ?? "none")
        model.open(.task(task.id))
        await ui.until(2) { ui.window.attachedSheet != nil }
        await ui.settle(0.6)
        // A background run's sheet takes no click on a row: the click's own path stands in.
        if ui.canClickTables {
            await ui.click(await ui.steadyAnchor("row:\(fileKey)"), inSheet: true)
        } else {
            model.select(fileKey, in: nil, inModal: true)
        }
        await check("a click on a link's row in the modal selects it there", model.modalSelection == fileKey, model.modalSelection ?? "none")
        await check("and leaves the page's selection as it was", model.selectedItem == prKey, model.selectedItem ?? "none")
        await ui.click(ui.anchor("modal-close"), inSheet: true)
        await ui.until(2) { ui.window.attachedSheet == nil }
        await check("closed, one thing is selected on the page, and the menus act on it: the PR",
              model.selectedItem == prKey && model.modalSelection == nil && model.menuRoute == .github(pr.url),
              "\(model.selectedItem ?? "none"), modal's \(model.modalSelection ?? "none")")
    }

    /// New File… and Import Artifact… are sheets: they work with Files folded, and over a task go back to it.
    private static func fileSheets(_ model: AppModel, _ ui: Driver) async {
        model.folded.insert(.files)
        await ui.settle(0.4)
        // File › New File… (⌃⌘N): the menu's action.
        model.beginNewFile()
        await ui.until(2) { ui.sheetIsTyping }
        await check("New File… with Files folded opens its sheet, the keyboard in its title", model.modal == .newFile && ui.sheetIsTyping,
              ui.sheetResponder)
        await typeInSheet(ui, "Sheet note")
        await ui.click(await ui.steadyAnchor("new-file-create"), inSheet: true)
        // Looked up again at each try: under load the note comes after the click.
        func note() -> FileItem? { model.files.first { $0.title == "Sheet note" } }
        await check("Create writes the note and opens it in its editor; Files unfolds with its row selected",
              note() != nil && model.modal == note().map { .file($0.id) } && model.editingFile == note()?.id && !model.folded.contains(.files)
              && model.selectedItem == note().map { ModalRoute.file($0.id).selectionKey }, "\(String(describing: model.modal)) \(model.selectedItem ?? "none")")
        model.editingFile = nil
        model.closeModal()
        await ui.until(2) { ui.window.attachedSheet == nil }

        // Import Artifact… with Files folded: a sheet; the artifact imported is selected on the page.
        model.folded.insert(.files)
        await ui.settle(0.4)
        model.beginImport()
        await ui.until(2) { ui.sheetIsTyping }
        await check("Import Artifact… with Files folded opens its sheet with the keyboard", model.modal == .importArtifact && ui.sheetIsTyping,
              ui.sheetResponder)
        let link = "https://claude.ai/artifact/0f0f0f0f-aaaa-4bbb-8ccc-0123456789ab"
        let fields = textFields(ui.window.attachedSheet?.contentView)
        let titleField = fields.first { ($0.placeholderString ?? $0.placeholderAttributedString?.string) == "HQ Notification Center" } ?? fields.last
        for (field, text) in [(fields.first { $0 !== titleField }, link), (titleField, "Imported page")] {
            guard let field else { continue }
            ui.window.attachedSheet?.makeFirstResponder(field)
            (ui.window.attachedSheet?.firstResponder as? NSTextView)?.selectAll(nil)
            await typeInSheet(ui, text)
        }
        await ui.click(await ui.steadyAnchor("import-add"), inSheet: true)
        await ui.until(2) { model.modal == nil }
        let key = URL(string: link).map { ModalRoute.artifact($0).selectionKey }
        await check("Import adds it, the sheet goes and its row is selected in Files and Artifacts",
              model.artifacts.contains { $0.title == "Imported page" } && model.modal == nil && model.selectedItem == key
              && model.selectedSection == .files && !model.folded.contains(.files),
              "\(model.selectedItem ?? "none"), modal \(String(describing: model.modal)), fields \(fields.map { "\($0.placeholderString ?? "-")=\($0.stringValue)" })")

        // Over a task's window: Cancel (Escape) goes back to it.
        guard let task = model.addTask(status: .todo, title: "Under the sheet") else { return }
        await endUndoGroup(model)
        model.open(.task(task.id))
        await ui.until(2) { ui.window.attachedSheet != nil }
        await ui.settle(0.5)
        model.beginNewFile()
        await ui.until(2) { model.modal == .newFile && ui.sheetIsTyping }
        await sheetKey(ui, "\u{1b}", code: 53)
        await check("Escape in New File… over a task goes back to the task", model.modal == .task(task.id), "\(String(describing: model.modal))")
        // New Task…'s title is an AppKit field (T-772): Escape in it goes back too.
        model.beginTask(.todo)
        await ui.until(2) { model.modal == .newTask(.todo) && ui.sheetIsTyping }
        await sheetKey(ui, "\u{1b}", code: 53)
        await check("Escape in New Task… over a task goes back to the task", model.modal == .task(task.id), "\(String(describing: model.modal))")
        // Its title takes the keyboard as the sheet shows, unless a click put it in another field first (T-772).
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let other = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        window.contentView?.addSubview(other)
        window.makeFirstResponder(other)
        window.contentView?.addSubview(FirstField(frame: NSRect(x: 0, y: 60, width: 300, height: 24)))
        await ui.settle(0.2)
        let late = FirstField(frame: NSRect(x: 0, y: 90, width: 300, height: 24))
        let empty = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
        empty.isReleasedWhenClosed = false
        empty.contentView?.addSubview(late)
        await ui.settle(0.2)
        await check("New Task…'s title takes the keyboard as it shows, never from a field typed in first", window.firstResponder === other
                    && (empty.firstResponder as? NSText)?.delegate as? FirstField === late,
                    "\(String(describing: window.firstResponder)) \(String(describing: empty.firstResponder))")
    }

    private static func textFields(_ view: NSView?) -> [NSTextField] {
        guard let view else { return [] }
        return ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(textFields)
    }

    /// A card dropped while the search filters the grid lands right before the card it was dropped before.
    private static func filteredGridDrag(_ model: AppModel, _ ui: Driver) async {
        guard let collection = ui.find(SessionGrid.CardCollection.self),
              let coordinator = collection.delegate as? SessionGrid.Coordinator else { return await check("the session grid", false) }
        // Two top-level cards say main; the first card doesn't.
        model.search = "main"
        await ui.until(2) { coordinator.ids == model.shownRoots.map(\.id) }
        let shown = model.shownRoots.map(\.id)
        let all = model.gridRoots.map(\.id)
        guard shown.count >= 2, let first = all.firstIndex(of: shown[0]), first > 0, let moving = shown.last else {
            return await check("a search that hides a card before the first one it shows", false, "\(shown.count) of \(all.count)")
        }
        let info = FakeDrag(session: moving, source: collection, at: cardEdge(0, after: false, collection, coordinator))
        _ = validate(coordinator, collection, info, item: 0, operation: .before)
        await endUndoGroup(model)
        _ = coordinator.collectionView(collection, acceptDrop: info, indexPath: IndexPath(item: 0, section: 0), dropOperation: .on)
        await endUndoGroup(model)
        coordinator.dragEnded()
        await ui.settle(0.4)
        var expected = all.filter { $0 != moving }
        expected.insert(moving, at: expected.firstIndex(of: shown[0]) ?? 0)
        await check("a card dropped on a filtered grid lands right before the card it was dropped before",
              model.gridRoots.map(\.id) == expected, "\(model.gridRoots.map { $0.id.suffix(2) }) for \(expected.map { $0.suffix(2) })")
        await check("and the grid shows the model's order", coordinator.ids == model.shownRoots.map(\.id))
    }

    /// The cards hold still under a drag: a session that ends mid-drag leaves once it's over, and a drop goes where AppKit
    /// said; an index past the cards puts the card last.
    private static func gridHoldsUnderDrag(_ model: AppModel, _ ui: Driver) async {
        guard let collection = ui.find(SessionGrid.CardCollection.self), let coordinator = collection.delegate as? SessionGrid.Coordinator,
              let task = model.addTask(status: .todo, title: "Drop me on a card") else { return await check("the grid and a task", false) }
        await endUndoGroup(model)
        await ui.settle(0.4)
        let before = coordinator.ids
        guard before.count >= 3 else { return await check("three cards", false) }
        let target = before[1], leaving = before[0]
        let drag = FakeDrag(tasks: [task.id], source: nil)
        _ = validate(coordinator, collection, drag, item: 1, operation: .before)
        model.sessions.removeAll { $0.id == leaving }
        await ui.settle(0.4)
        await check("the cards hold still while a drag is over the grid", coordinator.ids == before, "\(coordinator.ids.count) of \(before.count)")
        _ = coordinator.collectionView(collection, acceptDrop: drag, indexPath: IndexPath(item: 1, section: 0), dropOperation: .on)
        await endUndoGroup(model)
        await check("a task dropped on a card links the session it was over, not its new neighbour", model.task(task.id)?.sessions == [target],
              "\(model.task(task.id)?.sessions ?? [])")
        coordinator.dragEnded()
        await ui.until(2) { coordinator.ids == model.shownRoots.map(\.id) }
        await check("the drag over, the card whose session ended leaves", coordinator.ids == model.shownRoots.map(\.id) && !coordinator.ids.contains(leaving))

        // Let go past the last card, whatever index AppKit gives: the card goes last, nothing traps.
        let moving = coordinator.ids[0]
        let info = FakeDrag(session: moving, source: collection, at: cardEdge(coordinator.ids.count - 1, after: true, collection, coordinator))
        _ = validate(coordinator, collection, info, item: 0, operation: .before)
        _ = coordinator.collectionView(collection, acceptDrop: info, indexPath: IndexPath(item: coordinator.ids.count + 3, section: 0), dropOperation: .on)
        await endUndoGroup(model)
        coordinator.dragEnded()
        await ui.settle(0.4)
        await check("a card let go past the last one goes last", model.gridRoots.last?.id == moving && coordinator.ids.last == moving)
    }

    /// A PR's page in the modal stays when a poll no longer brings its item (a read notification's thread, a merge from HQ).
    private static func prPageStays(_ model: AppModel, _ ui: Driver) async {
        guard let pr = model.ownPullRequests.first ?? model.reviewRequests.first else { return await check("a PR", false) }
        model.open(.github(pr.url))
        await ui.until(2) { ui.window.attachedSheet != nil }
        await ui.settle(0.6)
        let gone = Snapshot.goneShown
        await check("the PR's page shows with its actions", ui.anchor("reload") != nil)
        model.github?.items.removeAll { $0.url == pr.url }
        await ui.settle(0.6)
        await check("a poll that drops it leaves its page, never This Item Is Gone",
              Snapshot.goneShown == gone && ui.anchor("reload") != nil && model.modal == .github(pr.url), "gone \(Snapshot.goneShown - gone)")
        await check("and the next poll asks GitHub for what the modal shows", model.modalGitHubURLs == [pr.url])
    }

    /// A section's header pins under the toolbar while its section scrolls, over its cards, and its controls take clicks
    /// there (T-542): Sessions over its grid, Tasks over its outline, both AppKit.
    private static func pinnedHeaders(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let scroll = outline.enclosingScrollView, let document = scroll.documentView,
              let grid = ui.find(SessionGrid.GridView.self) else { return await check("the page scrolls", false) }
        let under = ui.window.contentLayoutRect.maxY
        // Its top `by` points above the page's visible top.
        func scrollPast(_ view: NSView, by: CGFloat) async {
            let frame = view.convert(view.bounds, to: document)
            let top = document.isFlipped ? frame.minY : document.frame.height - frame.maxY
            scroll.contentView.scroll(to: NSPoint(x: 0, y: top - scroll.contentView.contentInsets.top + by))
            scroll.reflectScrolledClipView(scroll.contentView)
            await ui.settle(0.4)
        }
        func pinned(_ name: String) -> NSRect? {
            ui.anchorFrame(name).flatMap { $0.maxY <= under + 1 && $0.minY >= under - Metric.sectionBar - 2 ? $0 : nil }
        }
        await scrollPast(grid, by: Metric.card)
        await check("Sessions' header pins over its grid", pinned("roles-button").flatMap { ui.hitView(NSPoint(x: $0.midX, y: $0.midY)) }
            .map { view in !sequence(first: view, next: \.superview).contains { $0 is SessionGrid.GridView } } ?? false,
            "\(String(describing: ui.anchorFrame("roles-button"))) under \(under)")
        // T-644: pinned, the header slims; on the page it's full size again.
        await check("a pinned header's controls are slimmer", abs((ui.anchorFrame("roles-button")?.height ?? 0) - Metric.pinnedControl) < 0.5,
                    "\(String(describing: ui.anchorFrame("roles-button")))")
        await scrollPast(grid, by: -Metric.skyHeight)
        await check("back on the page, its controls are full size", abs((ui.anchorFrame("roles-button")?.height ?? 0) - Metric.headerControl) < 0.5,
                    "\(String(describing: ui.anchorFrame("roles-button")))")
        if let lead = model.gridRoots.first(where: { !model.team(of: $0.id).isEmpty })?.id {
            model.openTeam = lead
            await ui.settle(0.3)
            await scrollPast(grid, by: grid.bounds.height + Metric.skyHeight / 2)
            await check("an open team folds once Files' header pins, never over it", model.openTeam == nil)
        } else {
            await check("a seed team to open", false)
        }
        await scrollPast(outline, by: outline.bounds.height / 3)
        let backlog = model.showBacklog
        await check("Tasks' header pins over its outline", pinned("toggle:backlog") != nil, "\(String(describing: ui.anchorFrame("toggle:backlog"))) under \(under)")
        await ui.click(pinned("toggle:backlog").map { NSPoint(x: $0.midX, y: $0.midY) })
        await check("its toggle takes a click there", model.showBacklog != backlog)
        model.showBacklog = backlog
    }

    /// Escape in a form over a modal goes back to what's under it; in the center's reminder editor it ends the edit.
    private static func escapeInForms(_ model: AppModel, _ ui: Driver) async {
        guard let task = model.addTask(status: .todo, title: "Remind me of this") else { return }
        await endUndoGroup(model)
        model.open(.task(task.id))
        await ui.until(2) { ui.window.attachedSheet != nil }
        await ui.settle(0.5)
        model.beginReminder(about: .task(task.id))
        await ui.until(2) { model.modal == .newReminder && ui.sheetIsTyping }
        await sheetKey(ui, "\u{1b}", code: 53)
        await check("Escape in Remind Me… over a task goes back to the task", model.modal == .task(task.id), "\(String(describing: model.modal))")

        model.closeModal()
        await ui.until(2) { ui.window.attachedSheet == nil }
        model.openCenter()
        await ui.until(2) { ui.window.attachedSheet != nil }
        await ui.settle(0.5)
        model.beginReminder()
        await ui.until(2) { model.modal == .newReminder && ui.sheetIsTyping }
        await sheetKey(ui, "\u{1b}", code: 53)
        await check("Escape in New Reminder… over the center goes back to the center", model.modal == .notifications, "\(String(describing: model.modal))")

        let waiting = model.remind("Call the bank", at: .now.addingTimeInterval(7200), level: .update)
        await ui.settle(0.4)
        model.noticeSelection = waiting.id.uuidString
        await ui.settle(0.3)
        await ui.click(await ui.steadyAnchor("edit:\(waiting.id.uuidString)"), inSheet: true)
        await ui.until(2) { ui.anchor("reminder-text") != nil && ui.sheetIsTyping }
        await sheetKey(ui, "\u{1b}", code: 53)
        await check("Escape in the center's reminder editor ends the edit and leaves the center",
              model.modal == .notifications && ui.anchorFrame("reminder-text") == nil, "\(String(describing: model.modal))")
    }

    /// ⇧⌘B in a task's window moves the selected subtask to the backlog, as B and ⌘⌫ act on it, not the window's task.
    private static func subtaskToBacklog(_ model: AppModel, _ ui: Driver) async {
        guard let parent = model.addTask(status: .todo, title: "Window's task"), let sub = model.addSubtask(to: parent.id, title: "Its subtask") else {
            return await check("a task with a subtask", false)
        }
        await endUndoGroup(model)
        model.open(.task(parent.id))
        await ui.until(2) { ui.window.attachedSheet != nil }
        await ui.settle(0.8)
        guard let sheet = ui.window.attachedSheet, let scoped = OutlineCoordinator.scoped(parent.id) else { return await check("the task's window and its outline", false) }
        scoped.select(sub.id)
        await ui.settle(0.3)
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: sheet.windowNumber, context: nil, characters: "B", charactersIgnoringModifiers: "b",
                                           isARepeat: false, keyCode: 11) else { return }
        // As AppKit sends a key equivalent: the window's views first, then the menu bar.
        if !sheet.performKeyEquivalent(with: event) { _ = NSApp.mainMenu?.performKeyEquivalent(with: event) }
        await endUndoGroup(model)
        await ui.settle(0.4)
        await check("⇧⌘B on a selected subtask in its task's window moves the subtask to the backlog, not the window's task",
              model.task(sub.id)?.status == .backlog && model.task(parent.id)?.status == .todo && model.modal == .task(parent.id),
              "subtask \(String(describing: model.task(sub.id)?.status)), task \(String(describing: model.task(parent.id)?.status))")
        model.closeModal()
        await ui.until(2) { ui.window.attachedSheet == nil }
    }

    /// Settings › Appearance reaches the page's sky at once: where it shows, its strength, the day's mood (T-642, T-790).
    static func look(_ model: AppModel, _ ui: Driver) async {
        let look = Look.shared
        defer { look.sky = .topAndBottom; look.skyStrength = 1 }
        func shown() -> [SkyLayerView.Sky?] { ui.findAll(SkyLayerView.self).map(\.shown) }
        func says() -> String { shown().map { $0.map { "\($0.part) \($0.mood) \($0.strength)" } ?? "nothing" }.joined(separator: ", ") }
        await check("the page shows the sky at its top and foot", shown().count == 2 && shown().allSatisfy { $0?.mood == model.skyMood }, says())
        look.skyStrength = 2
        await check("a stronger sky redraws the page's sky", shown().count == 2 && shown().allSatisfy { $0?.strength == 2 }, says())
        look.sky = .top
        await check("Top shows the sky at the top only", shown().count == 1 && shown().first??.part == .top, says())
        look.sky = .none
        await check("None shows no sky", shown().isEmpty, says())
    }
}
