import AppKit
import HQKit

extension UITest {
    /// Every small control a click acts on shows a plate under the pointer, in its own shape and `Ink.plate`, deeper while
    /// pressed, gone when the pointer leaves, and nothing moves (T-637, DESIGN.md §12 Hover). The pointer reaches each
    /// plate through its own tracker: posted events don't move the window server's pointer.
    static func hoverPlates(_ model: AppModel, _ ui: Driver) async {
        guard let outline = ui.find(TaskOutlineView.self), let coordinator = outline.coordinator else { return await check("the outline is on the page", false) }
        model.folded = []
        guard let story = model.addTask(status: .doing, title: "Plates story", body: "Its description.", project: "Registry"),
              model.addSubtask(to: story.id, title: "Plates subtask") != nil,
              let blocker = model.addTask(status: .todo, title: "Plates blocker") else { return await check("tasks for the plates", false) }
        model.addLink(story.id, .blockedBy, blocker.id)
        let pr = model.ownPullRequests.first
        if let pr, let url = URL(string: pr.url) { model.link(task: story.id, url: url) }
        let reminder = model.remind("Plates reminder", at: .now.addingTimeInterval(3600), level: .update, links: [ModalRoute.task(story.id).selectionKey])
        if let session = model.gridSessions.first { model.link(task: story.id, session: session.id) }
        await endUndoGroup(model)
        await ui.settle(0.5)
        let index = outline.row(forItem: coordinator.node(.task(story.id)))
        outline.scrollRowToVisible(index)
        await ui.settle(0.3)
        guard index >= 0, let cell = outline.view(atColumn: 1, row: index, makeIfNecessary: false) as? TaskCell,
              let faces = outline.view(atColumn: 0, row: index, makeIfNecessary: false) as? FacesCell else { return await check("the story's card is on the page", false) }

        // A control of the story's card: the card scrolled into view first, as an anchor is.
        func center(_ view: NSView) -> NSPoint? {
            guard !view.isHidden, view.window != nil, let superview = view.superview else { return nil }
            cell.scrollToVisible(cell.bounds.insetBy(dx: 0, dy: -Driver.overlayClearance))
            ui.window.layoutIfNeeded()
            let frame = superview.convert(view.frame, to: nil)
            return NSPoint(x: frame.midX, y: frame.midY)
        }
        var kinds: [(name: String, point: () -> NSPoint?, shape: PlateShape, window: NSWindow?)] = [
            ("a task's face", { faces.window.flatMap { _ in center(faces.subviews.first { $0 is FaceStackView && !$0.isHidden } ?? faces.noSession) } }, .face(Metric.faceRow), ui.window),
            ("a task's status glyph", { center(cell.glyph) }, .circle, ui.window),
            ("a task's key", { center(cell.key).map { NSPoint(x: $0.x - cell.key.frame.width / 2 + ceil(cell.key.intrinsicContentSize.width) / 2, y: $0.y) } }, .chip, ui.window),
            ("a task's project chip", { center(cell.project) }, .capsule, ui.window),
            ("a blocking task's chip", { _ = center(cell); return cell.blockers.windowPoint(of: blocker.id) }, .capsule, ui.window),
            ("a task's reminder mark", { center(cell.reminderMark) }, .chip, ui.window),
            ("a task's chevron", { center(cell.fold) }, .chip, ui.window),
            ("a task's description button", { center(cell.note) }, .chip, ui.window),
            ("a story's filter button", { center(cell.filter) }, .chip, ui.window),
            ("the Backlog toggle", { ui.anchor("toggle:backlog") }, .capsule, ui.window),
        ]
        if let pr {
            kinds.append(("a task's PR link", { _ = center(cell); return cell.links.windowPoint(of: .github(pr.url)) }, .chip, ui.window))
            kinds.append(("a PR row's face", { ui.anchor("pr-face:\(pr.number)") }, .face(Metric.faceRow), ui.window))
        }
        if let card = model.gridSessions.first(where: { !model.team(of: $0.id).isEmpty }) ?? model.gridSessions.first {
            kinds.append(("a session card's face", { ui.anchor("card-face:\(card.id)") }, .face(Metric.faceCard), ui.window))
            if let member = model.team(of: card.id).first {
                kinds.append(("a team's face in its tray", { ui.anchor("tray-face:\(member.session.id)") }, .face(Metric.faceTeam), ui.window))
                kinds.append(("a team's toggle", { ui.anchor("team-toggle:\(card.id)") }, .circle, ui.window))
            }
        }
        if let waiting = model.waitingItems.first { kinds.append(("a face in who waits", { ui.anchor("waiting:\(waiting.id)") }, .rounded(Radius.control), ui.window)) }
        kinds.append(("the section bar", { ui.anchorFrame("section-bar").map { NSPoint(x: $0.minX + Space.xl, y: $0.midY) } }, .capsule, ui.window))

        var missing: [String] = []
        var wrong: [String] = []
        for kind in kinds {
            guard let point = kind.point(), let window = kind.window else { missing.append("\(kind.name): not on the page"); continue }
            if let fault = await plate(at: point, in: window, kind.shape, ui) { wrong.append("\(kind.name): \(fault)") }
        }
        await check("every control on the page shows its plate under the pointer, in its shape, and leaves it (\(kinds.count) kinds)", missing.isEmpty && wrong.isEmpty && kinds.count == 17,
                    (missing + wrong).joined(separator: "; "))

        // Pressed: deeper, on an AppKit control and a SwiftUI one.
        if let point = center(cell.glyph), let plate = plateView(at: point, in: ui.window) {
            plate.pointer(at: point)
            var pressed: (rect: NSRect, radius: CGFloat, pressed: Bool, color: CGColor?)?
            HoverPlateView.pressing(cell.glyph) { pressed = plate.shown }
            plate.pointer(at: nil)
            await check("a held status glyph's plate is deeper", pressed?.pressed == true && pressed?.color == plate.fill(pressed: true),
                        "\(String(describing: pressed))")
        }

        // The card around the controls holds still: no lift, no grip, the same subviews (DESIGN.md §7).
        let atRest = cell.subviews.filter { !$0.isHidden }.map { "\(type(of: $0))" }
        if let point = center(cell.glyph), let plate = plateView(at: point, in: ui.window) {
            plate.pointer(at: point)
            await ui.settle(0.1)
            await check("a task card shows nothing more while a control's plate shows", cell.subviews.filter { !$0.isHidden }.map { "\(type(of: $0))" } == atRest)
            plate.pointer(at: nil)
        }

        // The notification center: a face, a chip, Focus, Later.
        await ui.click(ui.anchor("bell"))
        await ui.until(2) { model.modal == .notifications }
        await ui.settle(0.5)
        let sheet = ui.window.attachedSheet ?? ui.window
        var inCenter: [(name: String, point: () -> NSPoint?, shape: PlateShape)] = []
        if let notice = model.notices.first(where: { $0.kind == .session && $0.readAt == nil && model.session($0.source) != nil }) {
            model.noticeSelection = notice.id.uuidString
            await ui.settle(0.4)
            inCenter.append(("a notification's face", { ui.anchor("notice-avatar:\(notice.id.uuidString)") }, .face(Metric.faceRow + Space.xs)))
            inCenter.append(("a notification's Later", { ui.anchor("later:\(notice.id.uuidString)") }, .chip))
        }
        if let blocked = model.blockedSessions.first { inCenter.append(("Focus", { ui.anchor("focus:\(blocked.id)") }, .capsule)) }
        var centerFaults: [String] = []
        for kind in inCenter {
            guard let point = kind.point() else { centerFaults.append("\(kind.name): not in the center"); continue }
            if let fault = await plate(at: point, in: sheet, kind.shape, ui) { centerFaults.append("\(kind.name): \(fault)") }
        }
        await check("the notification center's controls show their plate", !inCenter.isEmpty && centerFaults.isEmpty, centerFaults.joined(separator: "; "))
        model.closeModal()
        model.notices.removeAll { $0.id == reminder.id }
        await ui.settle(0.3)
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
