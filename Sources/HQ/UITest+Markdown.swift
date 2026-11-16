import AppKit
import HQKit

/// T-490: a table or a diagram in a note expands to the whole sheet, named by its heading; the table sorts, wraps and
/// copies, the diagram fits, zooms and pans; Escape goes back to the note where it was scrolled. From the page, the sheet
/// opens on the block and Escape closes it.
extension UITest {
    static func markdownWide(_ model: AppModel, _ ui: Driver) async {
        model.closeModal()
        let long = String(repeating: "a long note that wraps ", count: 24)
        var rows = ["| Region | Requests | Notes |", "|---|--:|---|"]
        for index in 1...40 { rows.append("| region-\(String(format: "%02d", 41 - index)) | \(index * 7) | \(index == 3 ? long : "fine") |") }
        let body = "# Wide blocks\n\n" + String(repeating: "Some text above.\n\n", count: 30) + "## Errors by region\n\n" + rows.joined(separator: "\n")
            + "\n\n## The retry path\n\n```mermaid\ngraph LR\n  a[Upload part] -->|503| b{Budget left?}\n  b -->|yes| a\n  b -->|no| c[Return the error]\n```\n"
        guard let file = model.addFile(title: "Wide blocks", body: body) else { return await check("a note with a wide table", false) }
        model.open(.file(file.id))
        await ui.until(3) { tableView(ui) != nil }
        guard let shown = tableView(ui) else {
            return await check("the note shows its table", false)
        }
        // In place: every row, its cut edge fading; Expand in its corner under the pointer (the switch stands in for it).
        await check("in place, the table keeps every row; cut sideways, its right edge fades, its left doesn't yet",
                    shown.numberOfRows == 41 && ui.anchor("table-fade-trailing") != nil && UITest.anchors["table-fade-leading", default: []].allSatisfy { $0.view?.window == nil },
                    "\(shown.numberOfRows) rows")
        await check("no Expand while the pointer is elsewhere", UITest.anchors["expand-block", default: []].allSatisfy { $0.view?.window == nil })
        model.showBlockControls = true
        await ui.until(2) { ui.anchor("expand-block") != nil }
        await ui.settle(0.4)
        await check("Expand in its corner doesn't scroll the table", (tableView(ui)?.enclosingScrollView?.contentView.bounds.origin.x ?? -1) == 0,
                    "x \(tableView(ui)?.enclosingScrollView?.contentView.bounds.origin.x ?? -1), responder \(String(describing: ui.window.attachedSheet?.firstResponder))")
        await ui.click(ui.anchor("expand-block"), inSheet: true)
        await ui.until(3) { expandedTable(ui) != nil }
        await check("a click on Expand opens the whole table over the note", expandedTable(ui) != nil && model.modalStack == [.file(file.id)],
                    "\(String(describing: model.modal))")
        await sheetKey(ui, "\u{1b}", code: 53)
        model.showBlockControls = false
        await ui.until(3) { tableView(ui) != nil && model.modal == .file(file.id) }
        guard let table = tableView(ui), let page = pageScroll(ui) else { return await check("back, the note shows its table", false) }
        // Scrolled halfway down, then the table expanded from its menu.
        let reach = (page.documentView?.frame.height ?? 0) - page.contentView.bounds.height
        page.contentView.scroll(to: NSPoint(x: 0, y: (reach / 2).rounded()))
        page.reflectScrolledClipView(page.contentView)
        await ui.settle(0.4)
        let scrolled = page.contentView.bounds.origin.y
        guard let menu = table.blockMenu(text: nil), let expand = menu.items.first(where: { $0.title == "Expand" }) else {
            return await check("a table's menu has Expand", false, "items \(table.blockMenu(text: nil)?.items.map(\.title) ?? []), expand \(table.expand != nil), layout \(table.layout != nil)")
        }
        await check("a table's menu: Expand, Copy Table", menu.items.map(\.title) == ["Expand", "Copy Table"], menu.items.map(\.title).joined(separator: ", "))
        menu.performActionForItem(at: menu.index(of: expand))
        await ui.until(3) { expandedTable(ui) != nil }
        guard let expanded = expandedTable(ui) else { return await check("Expand shows the whole table in the sheet", false, "\(String(describing: model.modal))") }
        let titled: Bool = if case .block(let block) = model.modal { block.title == "Errors by region" } else { false }
        await check("Expand shows the whole table in the sheet, named by its heading, Back to the note under it",
                    titled && model.modalStack == [.file(file.id)] && expanded.numberOfRows == 40 && ui.anchor("expanded-rows") != nil,
                    "\(String(describing: model.modal)) \(model.modalStack) \(expanded.numberOfRows) rows")
        // Columns as wide as their content up to 320 pt, the long cell wrapping onto more lines.
        let notes = expanded.tableColumns[2].width
        await check("a column stops at 320 pt and its long cell wraps",
                    notes <= Metric.expandedColumn + 2 * Space.sm + 1.5 && expanded.rect(ofRow: 2).height > expanded.rect(ofRow: 0).height * 2,
                    "column \(notes), rows \(expanded.rect(ofRow: 0).height) and \(expanded.rect(ofRow: 2).height)")
        // A header sorts, again reverses, a third time goes back to the note's order.
        func first() -> String { expanded.layout.cells[expanded.order[0]][0].string }
        expanded.sortDescriptors = [NSSortDescriptor(key: "0", ascending: true)]
        await check("a header sorts by its column", first() == "region-01", first())
        expanded.sortDescriptors = [NSSortDescriptor(key: "0", ascending: false)]
        await check("again reverses it", first() == "region-40", first())
        expanded.sortDescriptors = [NSSortDescriptor(key: "0", ascending: true)]
        await check("a third time goes back to the note's order", first() == "region-40" && expanded.sortDescriptors.isEmpty && expanded.order == Array(1...40), first())
        expanded.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)
        expanded.copy(nil)
        await check("Copy gives the selected rows as tab-separated lines", Pasteboard.text == "region-40\t7\tfine\nregion-39\t14\tfine", Pasteboard.text ?? "-")
        await sheetKey(ui, "\u{1b}", code: 53)
        await check("Escape goes back to the note", model.modal == .file(file.id) && model.modalStack.isEmpty, "\(String(describing: model.modal))")
        await ui.until(2) { pageScroll(ui).map { abs($0.contentView.bounds.origin.y - scrolled) <= 1 } == true }
        await check("scrolled where it was", scrolled > 0 && pageScroll(ui).map { abs($0.contentView.bounds.origin.y - scrolled) <= 1 } == true,
                    "\(pageScroll(ui)?.contentView.bounds.origin.y ?? -1) for \(scrolled)")

        // The diagram: fit, zoom by the keys, pan by a drag, back.
        model.expand(ExpandedBlock(heading: "The retry path", content: .diagram("graph LR\n  a[Upload part] -->|503| b{Budget left?}\n  b -->|yes| a\n  b -->|no| c[Return the error]")))
        await ui.until(5) { diagramScroll(ui) != nil }
        guard let diagram = diagramScroll(ui) else { return await check("Expand shows the diagram in the sheet", false) }
        await ui.settle(0.4)
        let fit = model.diagramZoom.scale
        let size = diagram.documentView?.frame.size ?? .zero
        await check("the diagram opens fit to the sheet", abs(fit - min(diagram.contentSize.width / size.width, diagram.contentSize.height / size.height, 2)) < 0.01,
                    "\(fit) for \(size) in \(diagram.contentSize)")
        await ui.key("=", .command, code: 24)
        await check("Command-= zooms it in", model.diagramZoom.scale > fit + 0.01 && model.zoom == 1, "\(model.diagramZoom.scale), page \(model.zoom)")
        await ui.key("-", .command, code: 27)
        await ui.key("-", .command, code: 27)
        await check("Command-minus zooms it out", model.diagramZoom.scale < fit - 0.01 && model.zoom == 1, "\(model.diagramZoom.scale)")
        await ui.key("9", .command, code: 25)
        await check("Command-9 fits it again", abs(model.diagramZoom.scale - fit) < 0.01, "\(model.diagramZoom.scale)")
        model.diagramZoom.set(3)
        if let view = diagram.documentView, let down = ui.mouseDown(view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil), clicks: 1) {
            let before = diagram.contentView.bounds.origin
            view.mouseDown(with: down)
            if let drag = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: down.locationInWindow.x + 60, y: down.locationInWindow.y), modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: down.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                view.mouseDragged(with: drag)
                view.mouseUp(with: drag)
            }
            await check("a drag pans it", diagram.contentView.bounds.origin.x < before.x - 1, "\(before) → \(diagram.contentView.bounds.origin)")
        }
        await sheetKey(ui, "\u{1b}", code: 53)
        await check("Escape goes back to the note from the diagram too", model.modal == .file(file.id), "\(String(describing: model.modal))")
        // In the note, a diagram drawn at its size offers no Expand; a double-click on it expands it, where one on text edits.
        await ui.until(5) { diagramView(ui) != nil }
        if let shown = diagramView(ui) {
            shown.scrollToVisible(shown.bounds)
            model.showBlockControls = true
            await ui.settle(0.4)
            await check("a diagram drawn at its size shows no Expand", UITest.anchors["expand-block", default: []].filter { $0.view?.window != nil }.count == 1,
                        "\(UITest.anchors["expand-block", default: []].filter { $0.view?.window != nil }.count) shown")
            model.showBlockControls = false
            let frame = shown.convert(shown.bounds, to: nil)
            await ui.click(NSPoint(x: frame.midX, y: frame.midY), count: 2, inSheet: true)
            await check("a double-click on a diagram expands it, not the editor", model.diagramShown && model.editingFile == nil,
                        "\(String(describing: model.modal)), editing \(model.editingFile ?? "-")")
            await sheetKey(ui, "\u{1b}", code: 53)
        } else {
            await check("the note draws its diagram", false)
        }

        // Opened with Expand already showing, the table starts at its left edge.
        model.closeModal()
        await ui.settle(0.6)
        model.showBlockControls = true
        model.open(.file(file.id))
        await ui.until(3) { tableView(ui) != nil }
        await ui.settle(0.6)
        await check("a note opens with its table at its left edge", (tableView(ui)?.enclosingScrollView?.contentView.bounds.origin.x ?? -1) == 0,
                    "x \(tableView(ui)?.enclosingScrollView?.contentView.bounds.origin.x ?? -1), responder \(String(describing: ui.window.attachedSheet?.firstResponder))")
        model.showBlockControls = false
        model.closeModal()
        await ui.settle(0.6)
        if let wide = model.addFile(title: "Errors by region", body: "One row per region, bucket and day.\n\n" + Snapshot.wideTable) {
            model.open(.file(wide.id))
            await ui.until(3) { tableView(ui) != nil }
            await ui.settle(0.6)
            await check("a note with a ten-column table opens with it at its left edge", (tableView(ui)?.enclosingScrollView?.contentView.bounds.origin.x ?? -1) == 0,
                        "x \(tableView(ui)?.enclosingScrollView?.contentView.bounds.origin.x ?? -1), table \(tableView(ui)?.frame ?? .zero), responder \(String(describing: ui.window.attachedSheet?.firstResponder))")
            model.closeModal()
            model.deleteFile(wide.id)
        }

        // In the outline: a double-click on a diagram in a card's description opens the sheet on it.
        if let task = model.addTask(status: .todo, title: "Draw the path",
                                    body: "```mermaid\ngraph LR\n  a[Upload part] -->|503| b{Budget left?}\n  b -->|no| c[Return the error]\n```") {
            await endUndoGroup(model)
            model.shownDescriptions.insert(task.id)
            await ui.settle(0.6)
            if let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator {
                outline.scrollRowToVisible(outline.row(forItem: coordinator.node(.task(task.id))))
            }
            await ui.until(5) { ui.find(DiagramImageView.self) != nil }
            if let shown = ui.find(DiagramImageView.self) {
                shown.scrollToVisible(shown.bounds)
                await ui.settle(0.4)
                // A background run hands a click in the outline to the table itself: the two steps a real double-click takes.
                let frame = shown.convert(shown.bounds, to: nil)
                if let double = ui.mouseDown(NSPoint(x: frame.midX, y: frame.midY), clicks: 2), let coordinator = ui.find(TaskOutlineView.self)?.coordinator {
                    let passed = coordinator.descriptionClick(double) != nil
                    shown.mouseDown(with: double)
                    await check("in the outline, a double-click on a diagram is left to it, and it opens the sheet on it, with no Back",
                                passed && model.diagramShown && model.modalStack.isEmpty && model.editingDescription == nil,
                                "passed \(passed), \(String(describing: model.modal)), editing \(String(describing: model.editingDescription))")
                }
                await ui.until(3) { diagramScroll(ui) != nil }
                await sheetKey(ui, "\u{1b}", code: 53)
                await check("and Escape closes it", model.modal == nil)
            } else {
                await check("a card's description draws its diagram", false)
            }
            model.deleteTasks([task.id])
            await ui.settle(0.4)
        }

        // A picture from the vault, `![[name.png]]`: drawn in the note, a double-click expands it (T-368 item 7).
        model.closeModal()
        await ui.settle(0.6)
        if let vault = model.vault?.root.deletingLastPathComponent(), let picture = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 200,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let png = picture.representation(using: .png, properties: [:]) {
            try? png.write(to: vault.appending(path: "uitest-picture.png"))
            if let note = model.addFile(title: "With a picture", body: "Above.\n\n![[uitest-picture.png]]\n\nBelow.") {
                model.open(.file(note.id))
                await ui.until(5) { diagramView(ui) != nil }
                await check("a picture from the vault shows in the note, at its size", diagramView(ui).map { abs($0.frame.width - 200) < 1 } == true,
                            "\(diagramView(ui)?.frame ?? .zero)")
                if let shown = diagramView(ui) {
                    let frame = shown.convert(shown.bounds, to: nil)
                    await ui.click(NSPoint(x: frame.midX, y: frame.midY), count: 2, inSheet: true)
                    let named: Bool = if case .block(let block) = model.modal { block.title == "Image" } else { false }
                    await check("a double-click on it expands it, zoomable as a diagram", named && model.diagramShown, "\(String(describing: model.modal))")
                    await sheetKey(ui, "\u{1b}", code: 53)
                }
                model.closeModal()
                model.deleteFile(note.id)
            }
            try? FileManager.default.removeItem(at: vault.appending(path: "uitest-picture.png"))
            await ui.settle(0.4)
        }

        // From the page, the sheet opens on the block and Escape closes it.
        model.closeModal()
        await ui.settle(0.6)
        model.expand(ExpandedBlock(heading: nil, content: .table(expanded.layout)))
        await ui.until(3) { expandedTable(ui) != nil }
        await check("from the page, the sheet opens on the block, with no Back", expandedTable(ui) != nil && model.modalStack.isEmpty && ui.anchor("modal-back") == nil)
        await sheetKey(ui, "\u{1b}", code: 53)
        await check("and Escape closes it", model.modal == nil)
        await ui.settle(0.6)
        model.deleteFile(file.id)
    }

    private static func tableView(_ ui: Driver) -> MarkdownTableView? {
        ui.window.attachedSheet?.contentView.flatMap { ui.find(MarkdownTableView.self, in: $0) }
    }

    private static func diagramView(_ ui: Driver) -> DiagramImageView? {
        ui.window.attachedSheet?.contentView.flatMap { ui.find(DiagramImageView.self, in: $0) }
    }

    private static func expandedTable(_ ui: Driver) -> ExpandedTableView? {
        ui.window.attachedSheet?.contentView.flatMap { ui.find(ExpandedTableView.self, in: $0) }
    }

    /// The expanded diagram's scroll view: the one that magnifies.
    private static func diagramScroll(_ ui: Driver) -> NSScrollView? {
        guard let root = ui.window.attachedSheet?.contentView else { return nil }
        func search(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.allowsMagnification { return scroll }
            return view.subviews.lazy.compactMap(search).first
        }
        return search(root)
    }

    /// The note's page: the scroll view around its card.
    private static func pageScroll(_ ui: Driver) -> NSScrollView? {
        UITest.anchors["file-card", default: []].compactMap(\.view).last { $0.window === ui.window.attachedSheet }?.enclosingScrollView
    }

    /// A key as the sheet gets it.
    private static func sheetKey(_ ui: Driver, _ characters: String, code: UInt16) async {
        guard let sheet = ui.window.attachedSheet else { return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: sheet.windowNumber, context: nil, characters: characters,
                                            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) {
                NSApp.sendEvent(event)
            }
        }
        await ui.settle(0.4)
    }
}
