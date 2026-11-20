import AppKit
import HQKit

extension UITest {
    /// A control to point at: where it is now (anchors scroll the page), its plate's shape.
    struct PlateKind {
        let name: String
        let point: () -> NSPoint?
        let shape: PlateShape
    }

    /// The story the plate groups point at, its card's cells, and every kind of control on the page.
    struct PlatePage {
        let row: OutlineRowView
        let cell: TaskCell
        let kinds: [PlateKind]
        let reminder: Notice
        /// A point on the story's card that no control takes, its card scrolled into view.
        let bare: () -> NSPoint?
        let center: (NSView) -> NSPoint?
    }

    /// Every small control a click acts on shows a plate under the pointer, in its own shape and `Ink.plate`, deeper while
    /// pressed, gone when the pointer leaves, and nothing moves; a task card stays the same under the pointer (T-637,
    /// DESIGN.md §7, §12 Hover). The pointer reaches each plate through its own tracker: posted events don't move the
    /// window server's pointer; `pointerPlates` moves the real one.
    static func hoverPlates(_ model: AppModel, _ ui: Driver) async {
        // The section bar shows only in a window that has room for it.
        let ran = await ui.atLeast(width: Metric.sectionBarWindow) { await hoverPlatesShown(model, ui) }
        if !ran { await check("a screen with room for the section bar", false, "\(Int(ui.window.screen?.visibleFrame.width ?? 0)) pt") }
    }

    private static func hoverPlatesShown(_ model: AppModel, _ ui: Driver) async {
        guard let page = await platePage(model, ui) else { return }
        var missing: [String] = []
        var wrong: [String] = []
        for kind in page.kinds {
            guard let point = kind.point() else { missing.append("\(kind.name): not on the page"); continue }
            if let fault = await plate(at: point, in: ui.window, kind.shape, ui) { wrong.append("\(kind.name): \(fault)") }
        }
        await check("every control on the page shows its plate under the pointer, in its shape, and leaves it (\(page.kinds.count) kinds)",
                    missing.isEmpty && wrong.isEmpty && page.kinds.count == 17, (missing + wrong).joined(separator: "; "))

        // Pressed: deeper.
        let cell = page.cell
        if let point = page.center(cell.glyph), let plate = plateView(at: point, in: ui.window) {
            plate.pointer(at: point)
            var pressed: (rect: NSRect, radius: CGFloat, pressed: Bool, color: CGColor?)?
            HoverPlateView.pressing(cell.glyph) { pressed = plate.shown }
            plate.pointer(at: nil)
            await check("a held status glyph's plate is deeper", pressed?.pressed == true && pressed?.color == plate.fill(pressed: true),
                        "\(String(describing: pressed))")
        }

        // The card holds still: nothing more shows while a control's plate does, and the pointer on the card itself,
        // outside its controls, changes nothing (2026-11-20, Co).
        let atRest = cell.subviews.filter { !$0.isHidden }.map { "\(type(of: $0))" }
        if let point = page.center(cell.glyph), let plate = plateView(at: point, in: ui.window) {
            plate.pointer(at: point)
            await ui.settle(0.1)
            await check("a task card shows nothing more while a control's plate shows", cell.subviews.filter { !$0.isHidden }.map { "\(type(of: $0))" } == atRest)
            plate.pointer(at: nil)
        }
        if let bare = page.bare() {
            await ui.settle(0.3)
            let before = image(of: page.row)
            await ui.settle(0.1)
            let steady = image(of: page.row) == before
            if let event = NSEvent.enterExitEvent(with: .mouseEntered, location: bare, modifierFlags: [], timestamp: 0, windowNumber: ui.window.windowNumber,
                                                  context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) {
                page.row.mouseEntered(with: event)
            }
            await ui.settle(0.1)
            let hovered = image(of: page.row)
            let wasHovered = page.row.hovered
            if let event = NSEvent.enterExitEvent(with: .mouseExited, location: bare, modifierFlags: [], timestamp: 0, windowNumber: ui.window.windowNumber,
                                                  context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) {
                page.row.mouseExited(with: event)
            }
            await check("a task card looks the same with the pointer on it, outside its controls", wasHovered && before != nil && before == hovered,
                        "hovered \(wasHovered), steady at rest \(steady), \(before == nil ? "no image" : "the card changed")")
        } else {
            await check("a point on the card that no control takes", false)
        }

        // The notification center: a face, Later, Focus.
        await ui.click(ui.anchor("bell"))
        await ui.until(2) { model.modal == .notifications }
        await ui.settle(0.5)
        let sheet = ui.window.attachedSheet ?? ui.window
        var inCenter: [PlateKind] = []
        if let notice = model.notices.first(where: { $0.kind == .session && $0.readAt == nil && model.session($0.source) != nil }) {
            model.noticeSelection = notice.id.uuidString
            await ui.settle(0.4)
            inCenter.append(PlateKind(name: "a notification's face", point: { ui.anchor("notice-avatar:\(notice.id.uuidString)") }, shape: .face(Metric.faceRow + Space.xs)))
            inCenter.append(PlateKind(name: "a notification's Later", point: { ui.anchor("later:\(notice.id.uuidString)") }, shape: .chip))
        }
        if let blocked = model.blockedSessions.first { inCenter.append(PlateKind(name: "Focus", point: { ui.anchor("focus:\(blocked.id)") }, shape: .capsule)) }
        var centerFaults: [String] = []
        for kind in inCenter {
            guard let point = kind.point() else { centerFaults.append("\(kind.name): not in the center"); continue }
            if let fault = await plate(at: point, in: sheet, kind.shape, ui) { centerFaults.append("\(kind.name): \(fault)") }
        }
        await check("the notification center's controls show their plate", !inCenter.isEmpty && centerFaults.isEmpty, centerFaults.joined(separator: "; "))
        model.closeModal()
        model.notices.removeAll { $0.id == page.reminder.id }
        await ui.settle(0.3)
    }

    /// The real pointer, moved by the window server over one control of each kind: each shows its plate and loses it as the
    /// pointer moves on; on the card outside its controls nothing changes. Moves the user's pointer: a foreground run only
    /// (HQ_FOREGROUND=1), with the user away or saying yes.
    static func pointerPlates(_ model: AppModel, _ ui: Driver) async {
        guard !Store.background, NSApp.isActive else { return skip("the real pointer over each control") }
        // Checked silently: posting pointer events untrusted makes macOS ask the user for Accessibility.
        guard CGPreflightPostEventAccess() else {
            return skip("the real pointer over each control", because: "HQ isn't allowed to post pointer events (Accessibility); judge the plates by eye")
        }
        let ran = await ui.atLeast(width: Metric.sectionBarWindow) { await pointerPlatesShown(model, ui) }
        if !ran { await check("a screen with room for the section bar", false, "\(Int(ui.window.screen?.visibleFrame.width ?? 0)) pt") }
    }

    private static func pointerPlatesShown(_ model: AppModel, _ ui: Driver) async {
        guard let page = await platePage(model, ui) else { return }
        let home = NSEvent.mouseLocation
        defer { movePointer(toScreen: home) }
        var faults: [String] = []
        for kind in page.kinds {
            guard let point = kind.point() else { faults.append("\(kind.name): not on the page"); continue }
            guard let plate = plateView(at: point, in: ui.window) else { faults.append("\(kind.name): no plate under it"); continue }
            movePointer(to: point, in: ui.window)
            await ui.until(1) { plate.shown != nil }
            let shown = plate.shown
            // Off the control, onto the window's title bar: the plate goes.
            movePointer(to: NSPoint(x: ui.window.frame.width / 2, y: ui.window.frame.height - Space.sm), in: ui.window)
            await ui.until(1) { plate.shown == nil }
            if shown == nil { faults.append("\(kind.name): no plate under the pointer") }
            else if plate.shown != nil { faults.append("\(kind.name): the plate stays once the pointer leaves") }
        }
        await check("the real pointer lights each control's plate and leaves it (\(page.kinds.count) kinds)", faults.isEmpty,
                    faults.joined(separator: "; "))
        if let bare = page.bare() {
            let before = image(of: page.row)
            movePointer(to: bare, in: ui.window)
            await ui.until(1) { page.row.hovered }
            await ui.settle(0.2)
            await check("with the real pointer on a task card outside its controls, the card looks the same",
                        page.row.hovered && before != nil && image(of: page.row) == before, "hovered \(page.row.hovered)")
        }
        model.notices.removeAll { $0.id == page.reminder.id }
    }

    /// A story with every control a card can have, on the page, and the kinds to point at.
    private static func platePage(_ model: AppModel, _ ui: Driver) async -> PlatePage? {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator else {
            await check("the outline is on the page", false)
            return nil
        }
        model.folded = []
        guard let story = model.addTask(status: .doing, title: "Plates story", body: "Its description.", project: "Registry"),
              model.addSubtask(to: story.id, title: "Plates subtask") != nil,
              let blocker = model.addTask(status: .todo, title: "Plates blocker") else {
            await check("tasks for the plates", false)
            return nil
        }
        model.addLink(story.id, .blockedBy, blocker.id)
        let pr = model.ownPullRequests.first
        if let pr, let url = URL(string: pr.url) { model.link(task: story.id, url: url) }
        let reminder = model.remind("Plates reminder", at: .now.addingTimeInterval(3600), level: .update, links: [ModalRoute.task(story.id).selectionKey])
        if let session = model.gridSessions.first { model.link(task: story.id, session: session.id) }
        await endUndoGroup(model)
        await ui.settle(0.5)
        let index = outline.row(forItem: coordinator.node(.task(story.id)))
        ui.show(row: index, in: outline)
        await ui.settle(0.3)
        guard index >= 0, let row = outline.rowView(atRow: index, makeIfNecessary: false) as? OutlineRowView,
              let cell = outline.view(atColumn: 1, row: index, makeIfNecessary: false) as? TaskCell,
              let faces = outline.view(atColumn: 0, row: index, makeIfNecessary: false) as? FacesCell else {
            await check("the story's card is on the page", false)
            return nil
        }

        // A control of the story's card: the card scrolled into view first, as an anchor is.
        func center(_ view: NSView) -> NSPoint? {
            guard !view.isHidden, view.window != nil, let superview = view.superview else { return nil }
            cell.scrollToVisible(cell.bounds.insetBy(dx: 0, dy: -Driver.overlayClearance))
            ui.window.layoutIfNeeded()
            let frame = superview.convert(view.frame, to: nil)
            return NSPoint(x: frame.midX, y: frame.midY)
        }
        var kinds: [PlateKind] = [
            PlateKind(name: "a task's face", point: { center(faces.subviews.first { $0 is FaceStackView && !$0.isHidden } ?? faces.noSession) }, shape: .face(Metric.faceRow)),
            PlateKind(name: "a task's status glyph", point: { center(cell.glyph) }, shape: .circle),
            PlateKind(name: "a task's key", point: { center(cell.key).map { NSPoint(x: $0.x - cell.key.frame.width / 2 + ceil(cell.key.intrinsicContentSize.width) / 2, y: $0.y) } }, shape: .chip),
            PlateKind(name: "a task's project chip", point: { center(cell.project) }, shape: .capsule),
            PlateKind(name: "a blocking task's chip", point: { _ = center(cell); return cell.blockers.windowPoint(of: blocker.id) }, shape: .capsule),
            PlateKind(name: "a task's reminder mark", point: { center(cell.reminderMark) }, shape: .chip),
            PlateKind(name: "a task's chevron", point: { center(cell.fold) }, shape: .chip),
            PlateKind(name: "a task's description button", point: { center(cell.note) }, shape: .chip),
            PlateKind(name: "a story's filter button", point: { center(cell.filter) }, shape: .chip),
            PlateKind(name: "the Backlog toggle", point: { ui.anchor("toggle:backlog") }, shape: .capsule),
        ]
        if let pr {
            kinds.append(PlateKind(name: "a task's PR link", point: { _ = center(cell); return cell.links.windowPoint(of: .github(pr.url)) }, shape: .chip))
            kinds.append(PlateKind(name: "a PR row's face", point: { ui.anchor("pr-face:\(pr.number)") }, shape: .face(Metric.faceRow)))
        }
        if let card = model.gridSessions.first(where: { !model.team(of: $0.id).isEmpty }) ?? model.gridSessions.first {
            kinds.append(PlateKind(name: "a session card's face", point: { ui.anchor("card-face:\(card.id)") }, shape: .face(Metric.faceCard)))
            if let member = model.team(of: card.id).first {
                kinds.append(PlateKind(name: "a team's face in its tray", point: { ui.anchor("tray-face:\(member.session.id)") }, shape: .face(Metric.faceTeam)))
                kinds.append(PlateKind(name: "a team's toggle", point: { ui.anchor("team-toggle:\(card.id)") }, shape: .circle))
            }
        }
        if let waiting = model.waitingItems.first {
            kinds.append(PlateKind(name: "a face in who waits", point: { ui.anchor("waiting:\(waiting.id)") }, shape: .rounded(Radius.control)))
        }
        kinds.append(PlateKind(name: "the section bar", point: { ui.anchorFrame("section-bar").map { NSPoint(x: $0.minX + Space.xl, y: $0.midY) } }, shape: .capsule))
        // The story's first line between its chips and its end, where no control is.
        let bare: () -> NSPoint? = {
            guard let start = center(cell.project), let end = center(cell.blockers) else { return nil }
            let point = NSPoint(x: (start.x + cell.project.frame.width / 2 + end.x - cell.blockers.frame.width / 2) / 2, y: start.y)
            return plateView(at: point, in: ui.window) == nil ? point : nil
        }
        return PlatePage(row: row, cell: cell, kinds: kinds, reminder: reminder, bare: bare, center: center)
    }

    /// A view as it draws, to compare.
    private static func image(of view: NSView) -> Data? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.tiffRepresentation
    }

    /// Moves the real pointer through the window server, as a mouse does.
    private static func movePointer(to point: NSPoint, in window: NSWindow) {
        movePointer(toScreen: window.convertPoint(toScreen: point))
    }

    private static func movePointer(toScreen point: NSPoint) {
        guard CGPreflightPostEventAccess() else { return }
        let flipped = CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
        CGWarpMouseCursorPosition(flipped)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: flipped, mouseButton: .left)?.post(tap: .cghidEventTap) // lint: ok trust checked above, silently
    }

    /// The plate whose spot holds `point` (window coordinates), the smallest when spots nest.
    private static func plateView(at point: NSPoint, in window: NSWindow) -> HoverPlateView? {
        HoverPlateView.all.allObjects
            .filter { $0.window === window }
            .compactMap { plate in plate.windowSpots.filter { $0.contains(point) }.map { (plate, $0.width * $0.height) }.min { $0.1 < $1.1 } }
            .min { $0.1 < $1.1 }?.0
    }

    /// Points at a control and leaves it: nil when its plate showed in `shape` and its fill, and went; else what was wrong.
    private static func plate(at point: NSPoint, in window: NSWindow, _ shape: PlateShape, _ ui: Driver) async -> String? {
        guard let plate = plateView(at: point, in: window) else { return "no plate under it" }
        plate.pointer(at: point)
        await ui.settle(0.1)
        guard let shown = plate.shown else {
            plate.pointer(at: nil)
            return "no plate shows"
        }
        plate.pointer(at: nil)
        await ui.settle(0.1)
        var faults: [String] = []
        if !shown.rect.contains(point) { faults.append("the plate \(shown.rect) misses the control") }
        let radius = shape.radius(shown.rect.size)
        if abs(shown.radius - radius) > 0.5 { faults.append("radius \(shown.radius), not \(radius)") }
        if shown.pressed || shown.color != plate.fill(pressed: false) { faults.append("not the plate's fill") }
        if plate.shown != nil { faults.append("it stays once the pointer leaves") }
        return faults.isEmpty ? nil : faults.joined(separator: ", ")
    }
}
