import AppKit
import HQKit
import SwiftUI

// MARK: Row

/// A row that knows when the pointer is over it, and draws a quiet selection that keeps text colors.
final class OutlineRowView: NSTableRowView {
    static let id = NSUserInterfaceItemIdentifier("outline-row")
    var onHover: (Bool) -> Void = { _ in }
    var isTask = false
    /// A selected task row shows its key, as under the pointer.
    override var isSelected: Bool {
        didSet { if isSelected != oldValue { for case let cell as TaskCell in subviews { cell.needsLayout = true } } }
    }
    /// Space above a task's line, outside its highlight.
    var gap: CGFloat = 0 {
        didSet {
            guard gap != oldValue else { return }
            needsDisplay = true
            needsLayout = true
        }
    }
    /// The task's card, in this row's coordinates: hover and selection fill it.
    var card: NSRect? { didSet { if card != oldValue { needsDisplay = true } } }
    private(set) var hovered = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        // One area for the row's life: it follows the visible rect on its own.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        onHover(value)
        needsDisplay = true
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isTask, hovered, !isSelected else { return }
        fill(Ink.hoverFillNS)
    }

    /// A selected card: a faint tint here, its accent ring on the card's own layer, whole (2026-11-10); gray while the rows
    /// don't have the keyboard.
    override func drawSelection(in dirtyRect: NSRect) {
        let active = (window?.firstResponder as? NSView).map { $0.isDescendant(of: superview ?? self) } ?? false
        guard card != nil else { return fill(active ? Ink.rowSelectionNS : Ink.rowSelectionInactiveNS) }
        fill(active ? Ink.cardSelectionNS : Ink.rowSelectionInactiveNS)
    }

    override func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {
        fill(Ink.rowDropNS)
    }

    private func fill(_ color: NSColor) {
        color.setFill()
        if let card {
            NSBezierPath(roundedRect: card, xRadius: Radius.row, yRadius: Radius.row).fill()
            return
        }
        var rect = bounds
        rect.origin.y += gap
        rect.size.height -= gap
        // Inside the list's card, concentric with it.
        NSBezierPath(roundedRect: rect.insetBy(dx: Space.xs + 2, dy: 1), xRadius: Radius.row, yRadius: Radius.row).fill()
    }

    override func layout() {
        super.layout()
        spanCells()
    }

    /// Text keeps its colors on a selected row.
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    /// Headers, the filter bar and empty lines take the whole row.
    private func spanCells() {
        for case let cell as HostCell in subviews where cell.frame != bounds { cell.frame = bounds }
    }
}

// MARK: Task row

/// A title that knows its task, and says when it takes the keyboard.
final class TitleField: NSTextField {
    var task: Int?
    /// The title when editing began: an untouched field writes nothing, so a rename made meanwhile stays.
    var base: String?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        // Scrolls while edited, truncates with an ellipsis otherwise.
        cell?.isScrollable = true
        let accepted = super.becomeFirstResponder()
        if accepted { base = stringValue }
        if accepted, let task { (delegate as? OutlineCoordinator)?.titleFocused(task) }
        if !accepted { cell?.isScrollable = false }
        // Edited, the field takes the row's width; at rest, its text's (T-351).
        superview?.needsLayout = true
        return accepted
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        cell?.isScrollable = false
        superview?.needsLayout = true
    }

    /// ⇧⌘B, ⌘I and the other chords come as key equivalents while the title is edited.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if currentEditor() != nil, let task, (delegate as? OutlineCoordinator)?.chord(self, task, event: event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

extension NSTextView {
    /// The task title this field editor edits, if any.
    var editedTitle: TitleField? { (delegate as AnyObject?) as? TitleField }
}

/// A status glyph that opens the status menu on a click.
final class GlyphButton: TaskGlyphView {
    var onPick: (TaskStatus) -> Void = { _ in }
    /// A click: the next status, from Done back to Todo.
    var onNext: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: frame)
        trackHandCursor()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// A click steps to the next status; ⌥-click picks one from the menu.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option) { showMenu() } else { onNext() }
        takeRelease()
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .popUpButton }
    override func accessibilityHelp() -> String? { "Changes the task’s status" }
    override func accessibilityPerformPress() -> Bool { showMenu(); return true }

    /// The statuses with their glyphs, the current one checked, under the glyph.
    func showMenu() {
        let menu = NSMenu()
        for status in TaskStatus.allCases {
            let item = NSMenuItem(title: status.title, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = status.rawValue
            item.image = TaskGlyphView.image(status)
            item.state = status == self.status ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY + Space.xs), in: self)
    }

    @objc private func pick(_ item: NSMenuItem) {
        if let raw = item.representedObject as? String, let status = TaskStatus(rawValue: raw) { onPick(status) }
    }
}

/// A block's progress, on its header's line or a folded task's: how many are blocked, a small bar of its subtasks by
/// state, and how many are done (2026-11-10).
final class BlockProgressView: NSView {
    private(set) var tally = TaskFlow.Tally()
    var started: Bool { tally.total > 0 }

    nonisolated override var isFlipped: Bool { true }

    func show(_ tally: TaskFlow.Tally) {
        guard tally != self.tally else { return }
        self.tally = tally
        toolTip = "\(tally.done) done, \(tally.doing) doing, \(tally.blocked) blocked, \(tally.ready + tally.waiting) to do"
        setAccessibilityLabel(toolTip)
        needsDisplay = true
    }

    private var blockedText: NSAttributedString? {
        tally.blocked > 0 ? NSAttributedString(string: "\(tally.blocked) blocked", attributes: [.font: KitType.groupLabel.nsFont, .foregroundColor: Ink.blockedTextNS]) : nil
    }

    private var countText: NSAttributedString {
        NSAttributedString(string: "\(tally.done)/\(tally.total)", attributes: [.font: KitType.meta.nsFont, .foregroundColor: Ink.secondaryTextNS])
    }

    /// Its parts' width, whole.
    var naturalWidth: CGFloat {
        let blocked = blockedText.map { ceil($0.size().width) + Space.sm } ?? 0
        return blocked + Metric.blockBar + Space.sm + ceil(countText.size().width)
    }

    override func draw(_ dirtyRect: NSRect) {
        var x: CGFloat = 0
        if let blocked = blockedText {
            let size = blocked.size()
            blocked.draw(at: NSPoint(x: x, y: (bounds.height - size.height) / 2))
            x += ceil(size.width) + Space.sm
        }
        let height = Space.xs
        let bar = NSRect(x: x, y: (bounds.height - height) / 2, width: Metric.blockBar, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bar, xRadius: height / 2, yRadius: height / 2).addClip()
        Ink.labelFillNS.setFill()
        bar.fill()
        let total = CGFloat(max(tally.total, 1))
        var segment = bar.minX
        for (count, color) in [(tally.done, Ink.doneNS), (tally.doing, Ink.doingNS), (tally.blocked, Ink.blockedNS)] where count > 0 {
            let width = bar.width * CGFloat(count) / total
            color.setFill()
            NSRect(x: segment, y: bar.minY, width: width, height: bar.height).fill()
            segment += width
        }
        NSGraphicsContext.restoreGraphicsState()
        x += Metric.blockBar + Space.sm
        let count = countText
        count.draw(at: NSPoint(x: x, y: (bounds.height - count.size().height) / 2))
    }

    override func isAccessibilityElement() -> Bool { started }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The tasks a task is blocked by, still open: a red capsule each, "⊘ T-268", first at its card's end; three, then "+2"
/// (2026-11-10). A click on one selects that task and brings it into view; on "+2", a menu of the others.
final class BlockersView: NSView, NSViewToolTipOwner {
    struct Chip: Equatable {
        /// The blocking tasks it stands for: one, or the rest behind "+2".
        var ids: [Int]
        var text: String
        var help: String
    }

    static let shown = 3
    private(set) var chips: [Chip] = []
    private var frames: [NSRect] = []

    nonisolated override var isFlipped: Bool { true }

    /// The blocking tasks' keys, for the UI test: "T-268, T-269".
    var keys: String { chips.flatMap(\.ids).map { "T-\($0)" }.joined(separator: ", ") }

    func show(_ blockers: [(id: Int, title: String)]) {
        var chips = blockers.prefix(blockers.count > Self.shown ? Self.shown - 1 : Self.shown).map { Chip(ids: [$0.id], text: "T-\($0.id)", help: "Blocked by T-\($0.id) \($0.title): click to show it") }
        let rest = blockers.dropFirst(chips.count)
        if !rest.isEmpty {
            chips.append(Chip(ids: rest.map(\.id), text: "+\(rest.count)", help: "Also blocked by " + rest.map { "T-\($0.id) \($0.title)" }.joined(separator: ", ")))
        }
        guard chips != self.chips else { return }
        self.chips = chips
        needsDisplay = true
        refreshHints()
    }

    private var font: NSFont { KitType.meta.nsFont }
    private var markSide: CGFloat { Metric.glyphSlot - Space.xs }

    private func width(_ chip: Chip) -> CGFloat {
        let mark = chip.ids.count == 1 ? markSide + Space.xs : 0
        return Space.sm + mark + ceil((chip.text as NSString).size(withAttributes: [.font: font]).width) + Space.sm
    }

    /// The chips' width, side by side.
    var naturalWidth: CGFloat {
        chips.isEmpty ? 0 : chips.map(width).reduce(0, +) + Space.xs * CGFloat(chips.count - 1)
    }

    private func layoutFrames() -> [NSRect] {
        var x: CGFloat = 0
        return chips.map { chip in
            let width = width(chip)
            defer { x += width + Space.xs }
            return NSRect(x: x, y: 0, width: width, height: bounds.height)
        }
    }

    /// The blocking tasks under a point in this view.
    func ids(at point: NSPoint) -> [Int]? {
        for (frame, chip) in zip(layoutFrames(), chips) where frame.contains(point) { return chip.ids }
        return nil
    }

    /// The middle of the chip that stands for a task, in window coordinates, for the UI test.
    func windowPoint(of id: Int) -> NSPoint? {
        for (frame, chip) in zip(layoutFrames(), chips) where chip.ids.contains(id) { return convert(NSPoint(x: frame.midX, y: frame.midY), to: nil) }
        return nil
    }

    /// The pointer over a window point: the hand over a chip.
    func cursor(at windowPoint: NSPoint) -> NSCursor? {
        let local = convert(windowPoint, from: nil)
        return frames.contains { $0.contains(local) } ? .pointingHand : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        for (frame, chip) in zip(layoutFrames(), chips) {
            let capsule = NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2)
            Ink.blockedChipNS.setFill()
            capsule.fill()
            var x = frame.minX + Space.sm
            if chip.ids.count == 1, let mark = KitIcon.blocked.nsImage(.mark, weight: .semibold) {
                let rect = NSRect(x: x, y: frame.midY - markSide / 2, width: markSide, height: markSide)
                mark.tinted(Ink.blockedTextNS).draw(in: rect)
                x += markSide + Space.xs
            }
            let text = NSAttributedString(string: chip.text, attributes: [.font: font, .foregroundColor: Ink.blockedTextNS])
            text.draw(at: NSPoint(x: x, y: frame.midY - text.size().height / 2))
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshHints()
    }

    private func refreshHints() {
        removeAllToolTips()
        frames = layoutFrames()
        for frame in frames { addToolTip(frame, owner: self, userData: nil) }
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        for frame in frames { addCursorRect(frame, cursor: .pointingHand) }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        for (frame, chip) in zip(frames, chips) where frame.contains(point) { return chip.help }
        return ""
    }

    override func isAccessibilityElement() -> Bool { !chips.isEmpty }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityLabel() -> String? { "Blocked by " + keys }
}

/// The project and tags after a title: colored chips, whole, as many as fit.
class LabelStripView: NSView {
    /// A chip; no color and no text: the icon alone, quiet.
    struct Label: Equatable {
        let text: String
        let color: LabelColor?
        let icon: NSImage?
    }

    var labels: [Label] = [] { didSet { if labels != oldValue { needsDisplay = true } } }
    /// One image each, so labels compare equal from one refresh to the next.
    static let projectIcon = KitIcon.project.nsImage(.mark)
    static let tagIcon = KitIcon.tag.nsImage(.mark)

    nonisolated override var isFlipped: Bool { true }

    private let font = KitType.secondary.nsFont

    /// A tag shows its color as a dot; a project as its tinted symbol.
    private func isTag(_ label: Label) -> Bool { label.icon === Self.tagIcon && label.color != nil }

    private func width(_ label: Label) -> CGFloat {
        let text = textWidth(label.text)
        let mark = isTag(label) ? Metric.labelDot : Metric.pillIcon
        let icon = label.icon == nil ? 0 : mark + (label.text.isEmpty ? 0 : Space.xs + 1)
        return text + icon + (label.color == nil ? 0 : Metric.pillPadding * 2)
    }

    /// Text widths by font size, measured once: rows lay out and draw their chips on every update.
    private static var textWidths: [String: CGFloat] = [:]

    private func textWidth(_ text: String) -> CGFloat {
        let key = "\(font.pointSize) \(text)"
        if let width = Self.textWidths[key] { return width }
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        if Self.textWidths.count >= 2000 { Self.textWidths.removeAll() }
        Self.textWidths[key] = width
        return width
    }

    /// Every chip, side by side.
    var naturalWidth: CGFloat { labels.isEmpty ? 0 : labels.map(width).reduce(0, +) + CGFloat(labels.count - 1) * Space.xs }
    var firstWidth: CGFloat { labels.first.map(width) ?? 0 }

    override func draw(_ dirtyRect: NSRect) {
        var x: CGFloat = 0
        for label in labels {
            let chip = width(label)
            guard x + chip <= bounds.width + 0.5 else { break }
            let rect = NSRect(x: x, y: 0, width: chip, height: bounds.height)
            // A neutral capsule; the label's color is only in its mark, so a row stays calm.
            if label.color != nil {
                Ink.labelFillNS.setFill()
                NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            }
            var textX = x + (label.color == nil ? 0 : Metric.pillPadding)
            if isTag(label), let color = label.color {
                let side = Metric.labelDot
                color.baseNS.setFill()
                NSBezierPath(ovalIn: NSRect(x: textX, y: (bounds.height - side) / 2, width: side, height: side)).fill()
                textX += side + Space.xs + 1
            } else if let icon = label.icon {
                let side = Metric.pillIcon
                let iconRect = NSRect(x: textX, y: (bounds.height - side) / 2, width: side, height: side)
                icon.tinted(label.color?.textNS ?? Ink.quietMarkNS)
                    .draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                textX += side + Space.xs + 1
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Ink.secondaryTextNS]
            let size = (label.text as NSString).size(withAttributes: attributes)
            (label.text as NSString).draw(at: NSPoint(x: textX, y: (bounds.height - size.height) / 2), withAttributes: attributes)
            x += chip + Space.xs
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { !labels.isEmpty }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityLabel() -> String? { "Tags: " + labels.map(\.text).joined(separator: ", ") }
}

/// The task's project as its chip, or a quiet project icon when the task is in none: a click picks the project.
final class ProjectButton: LabelStripView {
    private(set) var project: String?
    var projects: () -> [String] = { [] }
    var onPick: (String?) -> Void = { _ in }
    private var popover: NSPopover?

    override init(frame: NSRect) {
        super.init(frame: frame)
        trackHandCursor()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The project's chip; none, and none from a parent: the icon alone; else nothing.
    func show(_ project: String?, color: LabelColor?, inherited: Bool) {
        self.project = project
        labels = if let project { [LabelStripView.Label(text: project, color: color, icon: Self.projectIcon)] }
            else if inherited { [] } else { [LabelStripView.Label(text: "", color: nil, icon: Self.projectIcon)] }
        toolTip = project.map { "\($0): click to change the project" } ?? "Pick a project"
    }

    override func hitTest(_ point: NSPoint) -> NSView? { !labels.isEmpty && frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) {
        showMenu()
        takeRelease()
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .popUpButton }
    override func accessibilityLabel() -> String? { "Project: \(project ?? "none")" }
    override func accessibilityPerformPress() -> Bool { showMenu(); return true }

    /// None, the projects, the current one checked, then New Project…, under the chip.
    func showMenu() {
        let menu = NSMenu()
        func add(_ title: String, _ value: String?, action: Selector = #selector(pick(_:))) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = value != nil && value == project ? .on : .off
            menu.addItem(item)
        }
        add("None", nil)
        menu.items.last?.isEnabled = project != nil
        menu.items.last?.state = project == nil ? .on : .off
        menu.addItem(.separator())
        for name in projects() { add(name, name) }
        menu.addItem(.separator())
        add("New Project…", nil, action: #selector(newProject))
        menu.autoenablesItems = false
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY + Space.xs), in: self)
    }

    @objc private func pick(_ item: NSMenuItem) { onPick(item.representedObject as? String) }

    @objc private func newProject() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: NewProjectField { [weak self] name in
            self?.popover?.close()
            self?.popover = nil
            if let name { self?.onPick(name) }
        })
        self.popover = popover
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
    }
}

/// A task's line, and its description under it when shown.
/// A task's key: a click copies its line ("Task T-12: Title"), as Copy does, and it turns the accent color a moment.
final class KeyField: NSTextField {
    var copied = "" { didSet { if copied != oldValue, flashes == shownFlash { toolTip = help } } }
    private var flashes = 0
    private var shownFlash = 0

    override var isHidden: Bool { didSet { if isHidden != oldValue { trackHandCursor(!isHidden) } } }

    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard !copied.isEmpty else { return }
        Pasteboard.copy(copied)
        flashes += 1
        let flash = flashes
        textColor = Ink.accentNS
        toolTip = "Copied"
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: "Copied \(stringValue)", .priority: NSAccessibilityPriorityLevel.high.rawValue])
        DispatchQueue.main.asyncAfter(deadline: .now() + Motion.copiedSeconds) { [weak self] in
            guard let self, self.flashes == flash else { return }
            self.textColor = Ink.secondaryTextNS
            self.shownFlash = flash
            self.toolTip = self.help
        }
        takeRelease()
    }

    var help: String { "Click to copy \u{201C}\(copied)\u{201D}" }
}

/// A task's card (2026-11-10, T-372): its first line (the face's slot, the outline's; status glyph, key, reminder, title,
/// project and tags, then at its end the tasks blocking it, its links, its block's progress and its fold chevron), then a
/// Blocked reason, and its description when shown. A top-level task's big card has its title on a line of its own and its
/// story's progress under it.
final class TaskCell: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("task-cell")
    /// The face's slot at the line's start, every card's (2026-11-10).
    static var faceSlot: CGFloat { Metric.faceRow + Space.sm }
    /// Where the lines under the first start: after the face and the status glyph.
    static var titleX: CGFloat { faceSlot + Metric.glyphSlot + Space.sm }

    /// Where a card's first line sits, from the card's top.
    static func lineTop(big: Bool) -> CGFloat { big ? Metric.bigCardPadding : (Metric.outlineRow - Metric.cardLine) / 2 }

    /// What a card shows, top to bottom.
    struct Stack: Equatable {
        var big = false
        var reason = false
        var story = false

        /// The card's height, its description left out.
        var height: CGFloat {
            var height = TaskCell.lineTop(big: big) * 2 + Metric.cardLine
            if big { height += Space.xs + Metric.bigTitleLine }
            if reason { height += Metric.reasonLine }
            if story { height += Space.xs + Metric.storyLine }
            return height
        }

        /// Where the description starts, under the rest.
        var descriptionTop: CGFloat { height - TaskCell.lineTop(big: big) }
    }

    static func stack(_ model: AppModel, _ id: Int, big: Bool, description: Bool) -> Stack {
        Stack(big: big, reason: reason(model, id) != nil,
              story: big && showsStory(model, id))
    }

    /// A top-level task with subtasks: its story's progress shows under its title.
    static func showsStory(_ model: AppModel, _ id: Int) -> Bool {
        model.taskTree.parent(of: id) == nil && !model.taskTree.children(of: id).isEmpty
    }

    /// A Blocked task's reason, shown under its title; "Blocked" when no one said why.
    static func reason(_ model: AppModel, _ id: Int) -> String? {
        guard let task = model.task(id), task.blocked, task.status != .done else { return nil }
        let reason = task.blockedReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return reason.isEmpty ? "Blocked" : reason
    }

    let glyph = GlyphButton()
    let title = TitleField()
    /// The project after the key on a big card, after the title on a subtask in another project: a click picks it.
    let project = ProjectButton()
    /// The tags, as colored chips.
    let labels = LabelStripView()
    /// A block's progress, or a folded task's, at its line's end.
    let progress = BlockProgressView()
    /// A reminder that links the task, after its key (T-311).
    let reminderMark = HandButton()
    /// The fold chevron at the card's top right: all its subtasks, or only its blocked and doing ones (2026-11-10).
    let fold = HandButton()
    /// Beside the chevron: shows or hides the task's description in its card, on every card that has one (2026-11-10).
    let note = HandButton()
    private var reminderNotice: Notice?
    let key = KeyField(labelWithString: "")
    /// The tasks it's blocked by, still open: "T-268, T-269", first at the line's end.
    let blockers = BlockersView()
    /// A Blocked task's reason, under its title.
    let reason = NSTextField(labelWithString: "")
    private let reasonMark = NSImageView()
    /// A top-level task's progress, under its title.
    private(set) var storyHost: NSHostingView<AnyView>?
    private(set) var descriptionHost: NSHostingView<AnyView>?
    /// The task's PRs, issues, files, artifacts, Slack messages and web pages, at the line's end.
    let links = LinkTokensView()
    private var id: Int?
    private weak var coordinator: OutlineCoordinator?
    private weak var model: AppModel?
    private(set) var stack = Stack()
    private var shownDescription = false
    /// Its links hid for want of room, as last logged (T-377).
    private var linksDropped = false
    private var isSelectedRow: Bool { (superview as? NSTableRowView)?.isSelected ?? false }
    /// The card's end holds its chevron: the first line stops before it.
    var expandable = false { didSet { if expandable != oldValue { needsLayout = true } } }
    /// What it shows of its subtasks, and what a click on its chevron shows next.
    var foldMode: FoldMode = .all
    var foldNext: FoldMode = .all
    /// Space above the card: from the one before, the trays that close and its own tray's padding.
    var gap: CGFloat = 0 { didSet { if gap != oldValue { needsLayout = true } } }

    nonisolated override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        identifier = Self.id
        glyph.toolTip = "Change the status"
        title.isBordered = false
        title.drawsBackground = false
        title.isEditable = true
        title.isSelectable = true
        title.focusRingType = .none
        title.lineBreakMode = .byTruncatingTail
        title.usesSingleLineMode = true
        title.cell?.isScrollable = false
        title.cell?.wraps = false
        title.allowsExpansionToolTips = true
        title.placeholderString = "New task"
        title.setAccessibilityLabel("Task title")
        textField = title
        reminderMark.isBordered = false
        reminderMark.image = KitIcon.reminder.nsImage(.mark, weight: .semibold)
        reminderMark.target = self
        reminderMark.action = #selector(showReminder)
        reminderMark.isHidden = true
        fold.isBordered = false
        fold.target = self
        fold.action = #selector(toggleFold)
        fold.contentTintColor = Ink.secondaryTextNS
        note.isBordered = false
        note.target = self
        note.action = #selector(toggleNote)
        note.image = KitIcon.description.nsImage(.mark, weight: .semibold)
        note.wantsLayer = true
        note.layer?.cornerRadius = Radius.chip
        key.font = KitType.key.nsFont
        key.textColor = Ink.secondaryTextNS
        key.setAccessibilityLabel("Copy the task's line")
        // Always shown now: the hand from the start, not from when it showed.
        key.trackHandCursor()
        reason.font = KitType.secondary.nsFont
        reason.textColor = Ink.blockedTextNS
        reason.lineBreakMode = .byTruncatingTail
        reasonMark.image = KitIcon.blocked.nsImage(.mark, weight: .semibold)
        reasonMark.contentTintColor = Ink.blockedTextNS
        reasonMark.imageScaling = .scaleProportionallyDown
        for view in [glyph, key, reminderMark, fold, note, title, project, labels, blockers, links, progress, reasonMark, reason] as [NSView] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(model: AppModel, id: Int, coordinator: OutlineCoordinator, hovered: Bool) {
        guard let task = model.task(id) else { return }
        self.model = model
        self.coordinator = coordinator
        let changed = self.id == id && glyph.status != task.status
        self.id = id
        title.task = id
        title.delegate = coordinator
        let big = coordinator.isBig(id)
        title.font = big ? KitType.storyTitle.nsFont : KitType.title.nsFont
        title.textColor = task.status == .done ? Ink.secondaryTextNS : Ink.textNS
        // A title being edited keeps what's typed.
        if title.currentEditor() == nil, title.stringValue != task.title { title.stringValue = task.title }
        glyph.status = task.status
        let flow = model.taskFlow
        let state = flow.state(id)
        // The glyph is always the status (2026-11-10): Blocked shows as the red edge and its reason, blocked by as its chips.
        glyph.hold = nil
        let open = flow.openBlockers(id)
        blockers.show(open.compactMap { other in model.task(other).map { (id: other, title: $0.title) } })
        let because = Self.reason(model, id)
        reason.stringValue = because ?? ""
        reason.toolTip = because
        shownDescription = coordinator.descriptionShown(id)
        stack = Self.stack(model, id, big: big, description: shownDescription)
        if stack.story {
            let view = AnyView(StorySummary(id: id).environment(model))
            if let storyHost { storyHost.rootView = view } else {
                let host = NSHostingView(rootView: view)
                host.sizingOptions = []
                addSubview(host)
                storyHost = host
            }
        } else if let storyHost {
            storyHost.removeFromSuperview()
            self.storyHost = nil
        }
        if changed { glyph.pop() }
        glyph.onPick = { [weak model] status in model?.setStatus(id, status) }
        glyph.onNext = { [weak model] in model?.nextStatus([id]) }
        glyph.toolTip = (state == .blocked ? "Blocked, " : state == .blockedBy ? "Blocked by \(blockers.keys), " : "")
            + "\(task.status.title): click for the next status (⌘Return), ⌥-click to pick one"
        // The project on a big card; on a subtask only when it isn't its parent's: one mark per meaning.
        let parent = model.taskTree.parent(of: id)
        let own = task.project.flatMap { project in parent.map { model.project(ofTask: $0) != project } ?? true ? project : nil }
        project.show(own, color: own.map { model.labelColor(.project, $0) }, inherited: false)
        project.projects = { [weak model] in model?.allProjects ?? [] }
        project.onPick = { [weak model] choice in model?.setProject(id, choice) }
        labels.labels = task.tags.map { LabelStripView.Label(text: $0, color: model.labelColor(.tag, $0), icon: LabelStripView.tagIcon) }
        reminderNotice = model.reminder(for: .task(id))
        if let notice = reminderNotice {
            let mark = model.reminderMark(notice)
            reminderMark.contentTintColor = mark.due && notice.level == .important ? Ink.needsYouNS : Ink.secondaryTextNS
            reminderMark.toolTip = mark.help
            reminderMark.setAccessibilityLabel(mark.help)
        }
        reminderMark.isHidden = reminderNotice == nil
        fold.isHidden = !expandable
        let chevron: KitIcon = switch foldMode {
        case .hidden: .disclosure
        case .important: .partlyDisclosed
        case .all: .disclosed
        }
        fold.image = chevron.nsImage(.mark, weight: .semibold)
        let shows = switch foldMode {
        case .hidden: "Subtasks hidden"
        case .important: "Only blocked and doing subtasks"
        case .all: "All subtasks"
        }
        let next = switch foldNext {
        case .hidden: "hide them"
        case .important: "show only blocked and doing ones"
        case .all: "show all"
        }
        fold.toolTip = "\(shows): click to \(next) (← →)"
        fold.setAccessibilityLabel(fold.toolTip ?? "")
        note.isHidden = task.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        note.contentTintColor = shownDescription ? Ink.accentNS : Ink.secondaryTextNS
        note.layer?.backgroundColor = shownDescription ? Ink.markOnNS.cgColor : nil
        note.toolTip = shownDescription ? "Hide the description (⇧Return)" : "Show the description (⇧Return)"
        note.setAccessibilityLabel(note.toolTip ?? "")
        links.show(LinkTokensView.tokens(model.outputs(ofTask: id).filter { $0.taskID == nil }, model: model))
        // A block's progress, or a folded task's: every level under it.
        progress.show(!big && !model.taskTree.children(of: id).isEmpty ? flow.tally(of: id) : TaskFlow.Tally())
        key.stringValue = task.key
        key.copied = model.line(of: .task(id))
        if shownDescription {
            let view = AnyView(DescriptionBlock(id: id, root: coordinator.root).handCursors().environment(model))
            if let descriptionHost { descriptionHost.rootView = view } else {
                let host = NSHostingView(rootView: view)
                host.sizingOptions = []
                addSubview(host)
                descriptionHost = host
            }
        } else if let descriptionHost {
            descriptionHost.removeFromSuperview()
            self.descriptionHost = nil
        }
        let below = model.taskTree.subtree(of: id).filter { $0 != id }.compactMap { model.task($0) }
        var spoken = ["\(task.key) \(task.title)", task.status.title]
        if let project = task.project ?? model.project(ofTask: id) { spoken.append("project \(project)") }
        if !task.tags.isEmpty { spoken.append("tags " + task.tags.joined(separator: ", ")) }
        if !below.isEmpty { spoken.append("\(below.filter { $0.status == .done }.count) of \(below.count) subtasks done") }
        setAccessibilityLabel(spoken.joined(separator: ", "))
        needsLayout = true
    }

    /// The row's commands, for VoiceOver: what the menu has.
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard let id, let model else { return nil }
        let actions: [(String, () -> Void)] = [
            ("Open", { model.open(.task(id)) }),
            ("Next Status", { model.nextStatus([id]) }),
            ("Show or Hide Description", { model.toggleDescription(id) }),
            ("Add Subtask", { [weak self] in self?.addSubtask() }),
            ("Remind Me…", { model.beginReminder(about: .task(id)) }),
            (model.list(of: id) == .backlog ? "Move to Tasks" : "Move to Backlog", { model.toggleList(id) }),
            ("Start Session…", { model.beginStart(task: id) }),
            ("Delete", { model.deleteTasks([id]) }),
        ]
        return actions.map { name, run in NSAccessibilityCustomAction(name: name) { run(); return true } }
    }

    /// A column as wide as the list's longest key, so sibling titles share their left edge (2026-11-11).
    var keyWidth: CGFloat {
        let longest = coordinator?.longestKey ?? key.stringValue
        let text = longest.count > key.stringValue.count ? longest : key.stringValue
        return ceil((text as NSString).size(withAttributes: [.font: key.font ?? KitType.key.nsFont]).width) + Space.xs
    }

    /// Nothing shows or hides under the pointer (2026-11-10): the card reads the same.
    func setHovered(_ value: Bool) {}

    /// The links under a point in window coordinates, with their task.
    func links(at point: NSPoint) -> (routes: [ModalRoute], task: Int)? {
        guard let id, !links.isHidden else { return nil }
        let local = links.convert(point, from: nil)
        guard let routes = links.routes(at: local) else { return nil }
        return (routes, id)
    }

    /// The blocking tasks under a point in window coordinates: one chip's, or the rest behind "+2".
    func blockers(at point: NSPoint) -> [Int]? {
        guard !blockers.isHidden else { return nil }
        return blockers.ids(at: blockers.convert(point, from: nil))
    }

    /// The status glyph, the project or the key under a click, in window coordinates.
    func button(at point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let hit = hitTest(superview.convert(point, from: nil))
        return hit === glyph || hit === project || hit === key || hit === fold || hit === note ? hit : nil
    }

    /// The room the chevron and the description button take at the first line's end: both, on every card, so they line up (2026-11-10).
    private var endReserve: CGFloat { 2 * Metric.cardEndControl + Space.xs + Space.sm }

    override func layout() {
        super.layout()
        let slot = Metric.glyphSlot
        let big = stack.big
        let top = gap + Self.lineTop(big: big)
        let line = Metric.cardLine
        func centered(_ height: CGFloat) -> CGFloat { top + (line - height) / 2 }
        glyph.frame = NSRect(x: Self.faceSlot, y: centered(slot), width: slot, height: slot)
        let keyHeight = ceil(key.intrinsicContentSize.height)
        key.frame = NSRect(x: Self.titleX, y: centered(keyHeight), width: keyWidth, height: keyHeight)
        var x = key.frame.maxX + Space.sm
        if !reminderMark.isHidden {
            reminderMark.frame = NSRect(x: x - Space.xs, y: centered(slot), width: slot, height: slot)
            x += slot
        }
        if expandable { fold.frame = NSRect(x: bounds.width - Metric.cardEndControl, y: top, width: Metric.cardEndControl, height: line) }
        let side = Metric.cardEndControl
        if !note.isHidden { note.frame = NSRect(x: bounds.width - 2 * side - Space.xs, y: centered(side), width: side, height: side) }
        // The line's end, right to left; what doesn't fit hides, the title truncating first.
        var right = bounds.width - endReserve
        let minimumTitle = big ? 0 : Metric.titleMinimum
        func place(_ view: NSView, width: CGFloat, height: CGFloat) {
            let fits = width > 0 && right - width - x >= minimumTitle
            view.isHidden = !fits
            guard fits else { return }
            right -= width
            view.frame = NSRect(x: right, y: centered(height), width: width, height: height)
            right -= Space.md
        }
        place(progress, width: progress.started ? progress.naturalWidth : 0, height: line)
        links.compact = right - links.width(compact: false) - x < minimumTitle
        place(links, width: links.tokens.isEmpty ? 0 : links.width(compact: links.compact), height: line)
        let dropped = links.isHidden && !links.tokens.isEmpty
        if dropped != linksDropped, let id {
            linksDropped = dropped
            if dropped { AppLog.write("T-\(id): its links hide, \(Int(right - x)) pt left on its line\(isSelectedRow ? ", selected" : "")", to: "outline.log") }
        }
        place(blockers, width: blockers.naturalWidth, height: Metric.chipHeight + 1)
        let chipY = centered(Metric.chipHeight)
        let projectWidth = project.project == nil ? 0 : project.naturalWidth
        let tagsWidth = labels.naturalWidth
        if big {
            // The big card: its project and tags after the key, its title on the line under.
            project.isHidden = projectWidth == 0 || right - x < projectWidth
            if !project.isHidden {
                project.frame = NSRect(x: x, y: chipY, width: projectWidth, height: Metric.chipHeight)
                x = project.frame.maxX + Space.xs
            }
            labels.isHidden = tagsWidth == 0 || right - x < labels.firstWidth
            if !labels.isHidden { labels.frame = NSRect(x: x, y: chipY, width: min(tagsWidth, right - x), height: Metric.chipHeight) }
            let titleHeight = ceil(title.intrinsicContentSize.height)
            let titleTop = top + line + Space.xs
            title.frame = NSRect(x: 0, y: titleTop + (Metric.bigTitleLine - titleHeight) / 2, width: bounds.width, height: titleHeight)
        } else {
            let available = max(right - x, 40)
            let labelsWidth = projectWidth + tagsWidth + (projectWidth > 0 && tagsWidth > 0 ? Space.xs : 0)
            let editing = title.currentEditor() != nil
            let text = title.stringValue.isEmpty ? (title.placeholderString ?? "") : title.stringValue
            let natural = ceil((text as NSString).size(withAttributes: [.font: title.font ?? KitType.title.nsFont]).width) + Space.sm
            let roomForLabels = labelsWidth > 0 ? min(labelsWidth + Space.sm, max(available - minimumTitle, 0)) : 0
            let titleWidth = editing ? min(max(natural, available - roomForLabels), available) : min(natural, available - roomForLabels)
            let titleHeight = ceil(title.intrinsicContentSize.height)
            title.frame = NSRect(x: x, y: centered(titleHeight), width: max(titleWidth, 40), height: titleHeight)
            x = title.frame.maxX + Space.sm
            project.isHidden = projectWidth == 0 || right - x < projectWidth
            var tagsX = x
            if !project.isHidden {
                project.frame = NSRect(x: x, y: chipY, width: projectWidth, height: Metric.chipHeight)
                tagsX = project.frame.maxX + Space.xs
            }
            labels.isHidden = tagsWidth == 0 || right - tagsX < labels.firstWidth
            if !labels.isHidden { labels.frame = NSRect(x: tagsX, y: chipY, width: min(tagsWidth, right - tagsX), height: Metric.chipHeight) }
        }
        // Under the first line (the big card's title): a Blocked reason, the story.
        var below = top + line + (big ? Space.xs + Metric.bigTitleLine : 0)
        let underX = big ? 0 : Self.titleX
        reason.isHidden = !stack.reason
        reasonMark.isHidden = reason.isHidden
        if stack.reason {
            let height = ceil(reason.intrinsicContentSize.height)
            let mark = slot - Space.xs
            reasonMark.frame = NSRect(x: underX, y: below + (Metric.reasonLine - mark) / 2, width: mark, height: mark)
            reason.frame = NSRect(x: underX + mark + Space.xs, y: below + (Metric.reasonLine - height) / 2,
                                  width: max(bounds.width - underX - mark - Space.xs, 0), height: height)
            below += Metric.reasonLine
        }
        if let storyHost {
            below += Space.xs
            storyHost.frame = NSRect(x: 0, y: below, width: bounds.width, height: Metric.storyLine)
            below += Metric.storyLine
        }
        if let descriptionHost {
            let start = gap + stack.descriptionTop
            descriptionHost.frame = NSRect(x: underX, y: start, width: max(bounds.width - underX, 0),
                                           height: max(bounds.height - start - Self.lineTop(big: big), 0))
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The status glyph takes clicks over the line's height and the padding around it.
        let local = convert(point, from: superview)
        let area = NSRect(x: glyph.frame.minX - Space.xs / 2, y: glyph.frame.midY - Metric.outlineRow / 2, width: glyph.frame.width + Space.xs, height: Metric.outlineRow)
        if area.contains(local) { return glyph }
        // The empty part of the card drags it; the title selects on a click and edits on a double-click.
        let hit = super.hitTest(point)
        return hit === self || hit === links || hit === blockers ? nil : hit
    }

    @objc private func toggleFold() { if let id { coordinator?.stepFold(id) } }
    /// Shows or hides the description, the task selected as the click on its card does.
    @objc private func toggleNote() {
        guard let id else { return }
        coordinator?.select(id)
        model?.toggleDescription(id)
    }
    @objc private func showReminder() { if let reminderNotice { model?.showReminder(reminderNotice) } }
    private func addSubtask() {
        guard let id, let added = model?.addSubtask(to: id) else { return }
        coordinator?.beginEditing(added.id)
    }
}

/// A task's links at its card's line end, in one family (2026-11-10): a PR or an issue its state's icon, its number and,
/// for a PR, where it stands as a symbol (approved, changes requested, a draft); files, artifacts, Slack messages and web pages an icon
/// each, with a count when several. Same size, same weight, secondary: only a PR's or an issue's state colors it.
final class LinkTokensView: NSView, NSViewToolTipOwner {
    struct Token: Equatable {
        var routes: [ModalRoute]
        var icon: KitIcon?
        var tint: NSColor
        var text: String
        /// A PR's status as a symbol after its number, in its color (2026-11-10): dropped when the line is short.
        var mark: KitIcon?
        var markColor: NSColor?
        /// A line per link, whole.
        var help: String

        /// Its tooltip, in lines read at a glance (T-429): one link's whole text wrapped, several links a cut line each.
        var tip: String {
            let lines = help.split(separator: "\n").map(String.init)
            guard lines.count > 1 else { return LineCut.wrap(help) }
            return lines.map { LineCut.line($0, middle: routes.allSatisfy(\.isWeb)) }.joined(separator: "\n")
        }
    }

    /// A PR or an issue each, two of them, then "+3"; then a token per kind.
    static func tokens(_ routes: [ModalRoute], model: AppModel) -> [Token] {
        var tokens: [Token] = []
        let github = routes.filter { if case .github = $0 { true } else { false } }
        for route in github.prefix(2) {
            guard case .github(let url) = route else { continue }
            let item = model.githubItem(url)
            let status = item.flatMap(GitHubStateIcon.status)
            let mark = item.flatMap(GitHubStateIcon.statusMark)
            tokens.append(Token(routes: [route], icon: GitHubStateIcon.icon(url, item),
                                tint: item.map(GitHubStateIcon.nsColor) ?? Ink.secondaryTextNS, text: model.shortTitle(of: route),
                                mark: mark?.icon, markColor: mark?.color,
                                help: model.title(of: route) + (status.map { " · \($0.word)" } ?? "")))
        }
        if github.count > 2 {
            let rest = Array(github.dropFirst(2))
            tokens.append(Token(routes: rest, icon: nil, tint: Ink.secondaryTextNS, text: "+\(rest.count)",
                                help: rest.map(model.title(of:)).joined(separator: "\n")))
        }
        let kinds: [(KitIcon, String, (ModalRoute) -> Bool)] = [
            (.file, "File", { if case .file = $0 { true } else { false } }),
            (.artifact, "Artifact", { if case .artifact = $0 { true } else { false } }),
            (.slack, "Slack", { if case .slack = $0 { true } else { false } }),
            (.link, "Web page", { if case .web = $0 { true } else { false } }),
        ]
        for (icon, kind, matches) in kinds {
            let group = routes.filter(matches)
            guard !group.isEmpty else { continue }
            tokens.append(Token(routes: group, icon: icon, tint: Ink.secondaryTextNS, text: group.count > 1 ? "\(group.count)" : "",
                                help: group.map { "\(kind): \(model.title(of: $0))" }.joined(separator: "\n")))
        }
        return tokens
    }

    private(set) var tokens: [Token] = []
    /// Without the PRs' status: the line is short.
    var compact = false { didSet { if compact != oldValue { needsDisplay = true; refreshHints() } } }
    private var frames: [NSRect] = []

    nonisolated override var isFlipped: Bool { true }

    func show(_ tokens: [Token]) {
        guard tokens != self.tokens else { return }
        self.tokens = tokens
        needsDisplay = true
        refreshHints()
    }

    private var font: NSFont { KitType.meta.nsFont }
    private var iconSide: CGFloat { Metric.glyphSlot - Space.xs }

    private func parts(_ token: Token, compact: Bool) -> (text: String, mark: KitIcon?) {
        (token.text, compact ? nil : token.mark)
    }

    private func width(_ token: Token, compact: Bool) -> CGFloat {
        let (text, mark) = parts(token, compact: compact)
        var width: CGFloat = token.icon == nil ? 0 : iconSide
        if !text.isEmpty { width += (token.icon == nil ? 0 : Space.xs - 1) + ceil((text as NSString).size(withAttributes: [.font: font]).width) }
        if mark != nil { width += Space.xs - 1 + iconSide }
        return width
    }

    /// The tokens' width, side by side.
    func width(compact: Bool) -> CGFloat {
        guard !tokens.isEmpty else { return 0 }
        return tokens.map { width($0, compact: compact) }.reduce(0, +) + Space.md * CGFloat(tokens.count - 1)
    }

    private func layoutFrames() -> [NSRect] {
        var x: CGFloat = 0
        return tokens.map { token in
            let width = width(token, compact: compact)
            defer { x += width + Space.md }
            return NSRect(x: x, y: 0, width: width, height: bounds.height)
        }
    }

    /// The middle of the token that holds a link, in window coordinates, for the UI test.
    func windowPoint(of route: ModalRoute) -> NSPoint? {
        for (frame, token) in zip(layoutFrames(), tokens) where token.routes.contains(route) {
            return convert(NSPoint(x: frame.midX, y: frame.midY), to: nil)
        }
        return nil
    }

    /// The pointer over a window point: the hand over a token, nothing of its own elsewhere.
    func cursor(at windowPoint: NSPoint) -> NSCursor? {
        let local = convert(windowPoint, from: nil)
        return frames.contains { $0.contains(local) } && bounds.contains(local) ? .pointingHand : nil
    }

    /// The token's links under a point in this view.
    func routes(at point: NSPoint) -> [ModalRoute]? {
        for (frame, token) in zip(layoutFrames(), tokens) where frame.insetBy(dx: -Space.xs / 2, dy: 0).contains(point) { return token.routes }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        for (frame, token) in zip(layoutFrames(), tokens) {
            var x = frame.minX
            if let icon = token.icon, let image = icon.nsImage(.row, weight: .medium) {
                // The symbol's own proportions, centered in its slot, in its tint.
                let scale = min(iconSide / max(image.size.width, 1), iconSide / max(image.size.height, 1), 1)
                let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
                let rect = NSRect(x: x + (iconSide - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
                image.tinted(token.tint).draw(in: rect)
                x += iconSide + Space.xs - 1
            }
            let (text, mark) = parts(token, compact: compact)
            if !text.isEmpty {
                let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: Ink.secondaryTextNS])
                let size = string.size()
                string.draw(at: NSPoint(x: x, y: (bounds.height - size.height) / 2))
                x += ceil(size.width) + Space.xs
            }
            if let mark, let image = mark.nsImage(.row, weight: .medium) {
                let scale = min(iconSide / max(image.size.width, 1), iconSide / max(image.size.height, 1), 1)
                let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
                let rect = NSRect(x: x - 1 + (iconSide - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
                image.tinted(token.markColor ?? Ink.secondaryTextNS).draw(in: rect)
            }
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshHints()
    }

    /// A tooltip and the pointing hand over each token.
    private func refreshHints() {
        removeAllToolTips()
        frames = layoutFrames()
        for frame in frames { addToolTip(frame, owner: self, userData: nil) }
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        for frame in frames { addCursorRect(frame, cursor: .pointingHand) }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        for (frame, token) in zip(frames, tokens) where frame.contains(point) {
            return token.tip + (token.routes.count > 1 ? "\nClick to pick one" : "\nClick to open")
        }
        return ""
    }

    override func isAccessibilityElement() -> Bool { !tokens.isEmpty }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityLabel() -> String? { "Links: " + tokens.map(\.help).joined(separator: "; ") }
}

extension NSMenuItem {
    /// An item named by a link's or a task's title: one line, cut at a word (an address in the middle), the whole title in its tooltip (T-429).
    convenience init(cutting title: String, middle: Bool = false, action: Selector?) {
        let line = LineCut.line(title, middle: middle)
        self.init(title: line, action: action, keyEquivalent: "")
        if line != title { toolTip = LineCut.wrap(title) }
    }
}

extension ModalRoute {
    /// A web page, named by its address: cut in the middle.
    var isWeb: Bool { if case .web = self { true } else { false } }
}

// MARK: Faces column

/// The face of the session that matters most on the task, in its slot at the card's left (2026-11-10): a subtask's only
/// when it isn't its parent's, the slot blank then; a plain avatar when no session works on it. A click shows its
/// session's menu, or offers to start one.
final class FacesCell: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("faces-cell")
    private let faces = FaceStackView()
    let noSession = NoSessionFace()
    private var start: () -> Void = {}
    /// The session whose face shows.
    var shownSession: String? { faces.faces.first?.session }
    /// Space above the task's card, and from its top to its first line.
    var gap: CGFloat = 0 { didSet { if gap != oldValue { needsLayout = true } } }
    var lineTop: CGFloat = 0 { didSet { if lineTop != oldValue { needsLayout = true } } }

    nonisolated override var isFlipped: Bool { true }

    /// The sessions a task's face stands for, the one that matters most first; none when its parent shows the same face.
    static func sessions(_ model: AppModel, _ id: Int) -> [SessionItem] {
        let sessions = model.byImportance(model.sessions(on: id, includeEnded: true))
        guard let first = sessions.first, let parent = model.taskTree.parent(of: id) else { return sessions }
        return model.byImportance(model.sessions(on: parent, includeEnded: true)).first?.id == first.id ? [] : sessions
    }

    init() {
        super.init(frame: .zero)
        identifier = Self.id
        // One face, the session that matters most: the tooltip names them all.
        faces.limit = OutlineCoordinator.faces
        faces.showsMore = false
        faces.clickable = true
        addSubview(faces)
        noSession.toolTip = "No session on this task: click to start one"
        noSession.setAccessibilityLabel("No session")
        noSession.isHidden = true
        addSubview(noSession)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(model: AppModel, id: Int) {
        let sessions = Self.sessions(model, id)
        faces.faces = sessions.map { session in
            FaceStackView.Face(spec: session.face, badge: session.status.needsYou ? (session.status.state == .failed ? .failed : .needsYou) : nil,
                               label: "\(session.name), \(session.isRunning ? session.status.title.lowercased() : "ended")" + (session.status.isNew ? ", new" : ""),
                               working: session.isWorking, ended: !session.isRunning, session: session.id)
        }
        onMenu = { [weak model] session, point, view in
            if let menu = model?.faceMenu(session, task: id) { FaceMenu.show(menu, session, point, view) }
        }
        faces.toolTip = sessions.isEmpty ? nil : (faces.toolTip.map { $0 + "\n" } ?? "") + "Click a face for its session's menu"
        let menuPoint = { [weak self] in self.map { NSPoint(x: $0.faces.frame.minX, y: $0.faces.frame.maxY + Space.xs) } ?? .zero }
        faces.press = { [weak self] in
            guard let self, let first = sessions.first else { return }
            self.onMenu(first.id, menuPoint(), self)
        }
        faces.faceActions = sessions.map { session in
            (name: "Menu for \(session.name)", run: { [weak self] in if let self { self.onMenu(session.id, menuPoint(), self) } })
        }
        faces.isHidden = faces.faces.isEmpty
        noSession.isHidden = !model.sessions(on: id, includeEnded: true).isEmpty
        start = { [weak model] in model?.beginStart(task: id) }
        needsLayout = true
    }

    /// Nothing shows under the pointer (2026-11-10): Start Session… is in the menu.
    func setHovered(_ value: Bool) {}

    /// A click on a face: its session's menu, at a point in this cell.
    var onMenu: (String, NSPoint, NSView) -> Void = { _, _, _ in }

    override func layout() {
        super.layout()
        let side = Metric.faceRow
        faces.frame = NSRect(x: 0, y: gap + lineTop + (Metric.cardLine - side) / 2, width: faces.contentWidth, height: side)
        noSession.frame = NSRect(x: 0, y: faces.frame.minY, width: side, height: side)
    }

    /// The face takes the hit, so the hand shows over it; the rest of the cell drags the card.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if !noSession.isHidden, noSession.frame.contains(local) { return noSession }
        return !faces.isHidden && faces.frame.insetBy(dx: -Space.xs, dy: 0).contains(local) ? faces : nil
    }

    override func mouseDown(with event: NSEvent) {
        if click(event) { takeRelease() }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// A click on a face shows its session's menu at once. False when the click misses.
    func click(_ event: NSEvent) -> Bool {
        let local = convert(event.locationInWindow, from: nil)
        if !noSession.isHidden, noSession.frame.contains(local) {
            let menu = NSMenu()
            let item = NSMenuItem(title: "Start Session…", action: #selector(startSession), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            FaceMenu.show(menu, "no-session", NSPoint(x: noSession.frame.minX, y: noSession.frame.maxY + Space.xs), self)
            return true
        }
        guard !faces.isHidden, faces.frame.insetBy(dx: -Space.xs, dy: 0).contains(local),
              let session = faces.session(at: faces.convert(event.locationInWindow, from: nil)) ?? faces.faces.first?.session else { return false }
        onMenu(session, NSPoint(x: faces.frame.minX, y: faces.frame.maxY + Space.xs), self)
        return true
    }

    @objc private func startSession() { start() }
}

// MARK: Quick add

/// A field that says when it takes the keyboard: its delegate hears of an edit only from the first key typed.
class FocusField: NSTextField {
    var onFocus: () -> Void = {}

    override func becomeFirstResponder() -> Bool {
        let taken = super.becomeFirstResponder()
        // Once its field editor has the keyboard.
        if taken { DispatchQueue.main.async { [weak self] in self?.onFocus() } }
        return taken
    }
}

/// A quick-add field knows its list.
final class QuickAddField: FocusField {
    var list = TaskList.overview
}

/// "New task" under a list: Return adds it and keeps the field for the next. A Slack link copied before New Task shows at
/// its end and names it after the message (T-313).
final class QuickAddCell: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("quick-cell")
    let field = QuickAddField()
    private let plus = NSImageView()
    /// Made only while a link waits: the line comes into view on a scroll, and stays cheap there.
    private var chip: NSHostingView<AnyView>?
    private var chipURL: String?
    /// The title the linked message gave the field: replaced when the message arrives, kept once the user types.
    private var named: String?

    nonisolated override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        identifier = Self.id
        // In the status column, where the new task's glyph will be: an accent plus that invites the next one.
        plus.image = KitIcon.addTask.nsImage?.withSymbolConfiguration(.init(pointSize: Metric.glyph, weight: .medium))
        plus.contentTintColor = Ink.accentNS
        plus.setAccessibilityElement(false)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = KitType.title.nsFont
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        addSubview(plus)
        addSubview(field)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(list: TaskList, coordinator: OutlineCoordinator) {
        field.list = list
        field.delegate = coordinator
        // Its card turns solid with the keyboard.
        field.onFocus = { [weak coordinator] in coordinator?.keyboardChanged() }
        let placeholder = list == .overview ? "New Task" : "New Backlog Task"
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .font: KitType.title.nsFont, .foregroundColor: Ink.secondaryTextNS,
        ])
        field.setAccessibilityLabel(placeholder)
        let model = coordinator.model
        let pending = model.pendingTaskLink.flatMap { $0.list == list ? $0.url : nil }
        if pending != chipURL {
            chipURL = pending
            chip?.removeFromSuperview()
            chip = pending.map { url in
                let view = NSHostingView(rootView: AnyView(PendingLinkChip(url: url).environment(model)))
                addSubview(view)
                return view
            }
            needsLayout = true
        }
        guard let pending else { return named = nil }
        name(after: model.slackMessages[pending])
    }

    /// The field takes the message's first line while it's empty or still holds the last one it took.
    private func name(after message: SlackMessage?) {
        guard let line = message?.firstLine, !line.isEmpty, line != named else { return }
        let editor = field.currentEditor()
        let typed = editor?.string ?? field.stringValue
        guard typed.isEmpty || typed == named else { return }
        named = line
        if let editor {
            editor.string = line
            editor.selectAll(nil)
        } else {
            field.stringValue = line
        }
    }

    override func layout() {
        super.layout()
        let slot = Metric.glyphSlot
        // After the list's last card and the trays that close: the row's last line.
        let line = Metric.outlineQuick
        let top = bounds.height - line
        plus.frame = NSRect(x: TaskCell.faceSlot, y: top + (line - slot) / 2, width: slot, height: slot)
        let height = ceil(field.intrinsicContentSize.height)
        let x = TaskCell.titleX
        var end = bounds.width - Space.xs
        if let chip {
            let size = chip.fittingSize
            let width = min(size.width, (bounds.width - x) / 2)
            chip.frame = NSRect(x: end - width, y: top + (line - size.height) / 2, width: width, height: size.height)
            end = chip.frame.minX - Space.sm
        }
        field.frame = NSRect(x: x, y: top + (line - height) / 2, width: end - x, height: height)
    }
}

/// The Slack link the next task from a quick-add line links, and a button to drop it (T-313).
struct PendingLinkChip: View {
    let url: String
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Space.xs) {
            OutputChip(route: .slack(url), short: true, plain: true)
            Button { model.pendingTaskLink = nil } label: { Label("Don’t Link It", icon: .close).labelStyle(.iconOnly) }
                .buttonStyle(.borderless)
                .clickable()
                .help("Don’t link this Slack message")
                .uiTestAnchor("quick-add-unlink")
        }
        .fixedSize(horizontal: false, vertical: true)
        .uiTestAnchor("quick-add-link")
    }
}

// MARK: Hosted rows

/// SwiftUI in a row (headers, the filter bar, an empty line), with its clicks.
final class HostCell: NSTableCellView {
    private let host = NSHostingView(rootView: AnyView(EmptyView()))

    init() {
        super.init(frame: .zero)
        host.sizingOptions = []
        addSubview(host)
    }

    required init?(coder: NSCoder) { fatalError() }

    // The SwiftUI fills the cell whatever its row did: a header with no size shows nothing.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if host.frame != bounds { host.frame = bounds }
    }

    override func layout() {
        super.layout()
        if host.frame != bounds { host.frame = bounds }
    }

    func show(_ view: AnyView) { host.rootView = view }
}

/// "Tasks · 14 open" with Descriptions and Hide Done; "Backlog · 8 open" with its disclosure.
struct OutlineHeader: View {
    let list: TaskList
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let tree = model.taskTree
        let open = tree.top(list).filter { model.task($0)?.status != .done }.count
        let shownCount = OutlineSnapshot.matches(model, in: list).count
        let searching = !OutlineSnapshot.searchWords(model, list).isEmpty
        let filtered = list == .backlog ? model.backlogFilter.isActive || searching : searching
        let count = filtered ? "\(shownCount) of \(tree.top(list).count)" : "\(open) open"
        Group {
            if list == .overview {
                SectionHeader(title: PageSection.tasks.title, count: count, open: model.sectionOpen(.tasks), tile: (PageSection.tasks.icon, Ink.section(.tasks))) {
                    ListSearch(list: list)
                    ListToggles(list: list)
                }
            } else {
                SectionHeader(title: "Backlog", count: count, open: $model.backlogOpen, key: "⌃⌘B", tile: (.backlog, Ink.backlogTile)) {
                    ListSearch(list: list)
                    BacklogFilterMenu()
                    ListToggles(list: list)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.bottom, Space.md)
    }
}

/// A list's own Descriptions and Hide Done, as icons; Tasks' Hide Done counts its done tasks.
private struct ListToggles: View {
    let list: TaskList
    @Environment(AppModel.self) private var model

    var body: some View {
        let place = list == .overview ? "in Tasks" : "in the Backlog"
        let tree = model.taskTree
        let done = list == .overview ? tree.top(.overview).flatMap { tree.subtree(of: $0) }.filter { model.task($0)?.status == .done }.count : nil
        Toggle(isOn: model.toggle(\.allDescriptions, list)) { HeaderIcon(icon: .description) }
            .clickable()
            .help("Descriptions: show every description \(place)")
            .accessibilityLabel("Descriptions")
        // The Backlog's Status filter does what Hide Done does.
        if list == .overview {
            Toggle(isOn: model.toggle(\.hideDone, list)) { HeaderIcon(icon: .hideDone, count: done) }
                .clickable()
                .help("Hide Done: hide done tasks and subtasks \(place)")
                .accessibilityLabel("Hide Done")
        }
    }
}

/// A list's own search: the tasks whose title has it, and their parents.
private struct ListSearch: View {
    let list: TaskList
    @Environment(AppModel.self) private var model

    var body: some View {
        HeaderSearch(prompt: "Search \(list.title)", text: Binding(get: { model.listSearch[list] ?? "" },
                                                                  set: { model.listSearch[list] = $0.isEmpty ? nil : $0 }))
            .help("Show the tasks whose title has this, and their parents (Escape clears)")
            .uiTestAnchor("search:\(list.rawValue)")
    }
}

/// The Backlog's filters in its header: Status, Type, Project and Tag, each its icon and its value; Clear while one applies.
private struct BacklogFilterMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let filter = model.backlogFilter
        FilterPicker(icon: .pending, name: "Status", value: filter.status.title, active: filter.status != .open) {
            Picker("Status", selection: $model.backlogFilter.status) {
                ForEach(BacklogFilter.Status.allCases) { Text($0.title).tag($0) }
            }
        }
        FilterPicker(icon: .project, name: "Project", value: filter.project ?? "Any", active: filter.project != nil) {
            Picker("Project", selection: $model.backlogFilter.project) {
                Text("Any").tag(String?.none)
                ForEach(model.projects, id: \.self) { Text($0).tag(String?.some($0)) }
            }
        }
        FilterPicker(icon: .tag, name: "Tag", value: filter.tag ?? "Any", active: filter.tag != nil) {
            Picker("Tag", selection: $model.backlogFilter.tag) {
                Text("Any").tag(String?.none)
                ForEach(model.allTags, id: \.self) { Text($0).tag(String?.some($0)) }
            }
        }
        // Always there; off while nothing narrows the Backlog.
        let searching = !(model.listSearch[.backlog] ?? "").isEmpty
        Button { model.backlogFilter = BacklogFilter(); model.listSearch[.backlog] = nil } label: { HeaderIcon(icon: .close) }
            .disabled(!filter.isActive && !searching)
            .help("Clear the filters and the search: every open task")
            .accessibilityLabel("Clear Filters and Search")
    }
}

/// One filter: its icon and its value as a pop-up; accent while it's off its default.
struct FilterPicker<Choices: View>: View {
    let icon: KitIcon
    let name: String
    let value: String
    let active: Bool
    /// The tooltip; "Status: Open" without one.
    var help: String?
    @ViewBuilder let choices: Choices

    var body: some View {
        Menu { choices.pickerStyle(.inline).labelsHidden() } label: {
            HStack(spacing: Space.xs) {
                icon.image
                Text(value).lineLimit(1)
            }
            .foregroundStyle(active ? AnyShapeStyle(Ink.accentText) : AnyShapeStyle(.secondary))
        }
        .fixedSize()
        .clickable()
        .help(help.map { "\(name): \(value). \($0)" } ?? "\(name): \(value)")
        .accessibilityLabel("\(name), \(value)")
    }
}

/// A task's description under its row: rendered (a double-click edits it), or the editor; then its outputs as chips.
struct DescriptionBlock: View {
    let id: Int
    /// The task whose window its outline is in; nil on the page.
    var root: Int?
    /// Its outline is the one in front: the page behind a task's window shows the text while the window edits it.
    private var editable: Bool {
        if let root { return model.modal == .task(root) }
        if case .task = model.modal { return false }
        return true
    }
    /// A long description shows its first lines only; the task's modal has it all.
    static let maxLines = 20
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if editable, model.editingDescription == id {
                InlineDescriptionEditor(id: id)
            } else if let task = model.task(id) {
                let lines = task.body.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n", omittingEmptySubsequences: false)
                if task.body.isEmpty {
                    Text("No description yet. Double-click to write one.").kitType(.callout).foregroundStyle(.secondary)
                } else if lines.count > Self.maxLines {
                    MarkdownView(lines.prefix(Self.maxLines).joined(separator: "\n"), selectable: false) { index in model.toggleCheckbox(id, at: index) }
                    Text("\(lines.count - Self.maxLines) more lines: open the task to read them all.")
                        .kitType(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    MarkdownView(task.body, selectable: false) { index in model.toggleCheckbox(id, at: index) }
                }
            }
        }
        .padding(.top, Space.xs)
        .padding(.bottom, Space.md)
        .padding(.trailing, Space.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// The block's height at a width, for the row.
    @MainActor static func measure(model: AppModel, id: Int, width: CGFloat) -> CGFloat {
        let controller = NSHostingController(rootView: DescriptionBlock(id: id).environment(model).frame(width: width))
        return ceil(controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }
}

/// The description's editor in the outline. Escape and ⌘Return save and select the row; Tab saves
/// and edits the next task's title, ⇧Tab this one's; leaving saves.
extension AppModel {
    /// The outline's description editor: as tall as its text, then it scrolls.
    var descriptionEditorBox: CGFloat { MarkdownEditor.box(descriptionEditorHeight) }
}

private struct InlineDescriptionEditor: View {
    let id: Int
    @Environment(AppModel.self) private var model

    /// The model keeps the draft and the text it started from: a quit or another editor saves it (TextDraft).
    private var draft: Binding<String> {
        Binding(get: { model.outlineDraft?.text ?? "" }, set: { if model.outlineDraft?.id == id { model.outlineDraft?.text = $0 } })
    }

    var body: some View {
        MarkdownEditor(text: draft, focusOnAppear: true, caretPoint: model.editorCaret, label: "Description",
                       onHeight: { model.descriptionEditorHeight = $0 }, maxHeight: Metric.editorMaximum,
                       onCommit: { save(then: .row(id)) },
                       onCancel: { save(then: .row(id)) },
                       onEnd: { save(then: .left(id)) },
                       onTab: { backward in save(then: .title(id, by: backward ? 0 : 1)) })
            .frame(height: model.descriptionEditorBox)
            // The text stays where the rendered one was; the box is drawn around it.
            .background { RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Ink.editor).padding(-Space.xs) }
            .overlay { RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Ink.boxFrame).padding(-Space.xs) }
            .onAppear { model.editorCaret = nil }
            .uiTestAnchor("description-editor:\(id)")
    }

    /// An empty description hides again.
    private func save(then focus: OutlineFocus) {
        guard model.editingDescription == id else { return }
        // Leaving the editor saves its draft (`editingDescription`).
        model.editingDescription = nil
        if model.task(id)?.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true { model.shownDescriptions.remove(id) }
        model.outlineFocus = focus
    }
}

/// Outputs as chips that wrap: kind or PR state, the maker's face, the title; blue while new.
struct FlowChips: View {
    let routes: [ModalRoute]
    @Environment(AppModel.self) private var model

    var body: some View {
        FlowLayout(spacing: Metric.chipGap) {
            ForEach(routes, id: \.self) { route in
                OutputChip(route: route)
            }
        }
    }
}

/// One output: a file, an artifact, a PR, an issue or a linked task. Compact under a task's row.
struct OutputChip: View {
    let route: ModalRoute
    var compact = false
    /// Only what names it: T-34, #418, a file's first letters.
    var short = false
    /// Only drawn: what holds it acts on clicks (the notification center).
    var plain = false
    /// Under a task's row on the page: that task.
    var task: Int?
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: compact ? Space.xs : Metric.chipGap) {
                icon
                if !compact, let maker = model.maker(of: route) { SessionFace(maker, size: Metric.faceChip) }
                Text(short ? model.shortTitle(of: route) : model.title(of: route))
                    .lineLimit(1)
                    .foregroundStyle(compact ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            }
            .kitType(compact ? .secondary : .callout)
            .padding(.horizontal, compact ? Space.xs + 2 : Space.sm)
            .frame(height: compact ? Metric.chipHeight : Metric.rowAction)
            .background(compact ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Ink.chipFill),
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .modifier(ChipClick(route: route, task: task, active: !plain))
            // Under a task's row the outline's AppKit tracking gives the hand (`HandRegionView`).
            .clickable(task == nil)
            .help(LineCut.wrap(model.title(of: route)))
    }

    @ViewBuilder
    private var icon: some View {
        switch route {
        case .github(let url):
            GitHubStateIcon(url: url, item: model.githubItem(url)).fontWeight(.semibold)
        // The kinds' colors, as on their rows' tiles.
        case .file: KitIcon.fileTile.image.foregroundStyle(Ink.fileTile).accessibilityLabel("File")
        case .artifact: KitIcon.artifact.image.fontWeight(.semibold).foregroundStyle(Ink.artifactTile).accessibilityLabel("Artifact")
        case .web: KitIcon.link.image.fontWeight(.semibold).foregroundStyle(.secondary).accessibilityLabel("Web page")
        case .slack: KitIcon.slack.image.fontWeight(.semibold).foregroundStyle(.secondary).accessibilityLabel("Slack")
        case .task(let id): if let task = model.task(id) { TaskGlyph(status: task.status).scaleEffect(compact ? 0.86 : 1) }
        default: EmptyView()
        }
    }
}

/// A click selects a chip and a double-click opens it; under a task's row the outline shows its menu on a right-click.
private struct ChipClick: ViewModifier {
    let route: ModalRoute
    let task: Int?
    var active = true
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        if !active {
            content
        } else if let task {
            content
                .selectOpen(route.chipKey(task: task), in: .tasks) { model.open(route, push: model.modal != nil) }
                .accessibilityAction(named: "Show Menu") { FaceMenu.show(model.linkMenu(route, task: task), route.chipKey(task: task), .zero, nil) }
                .onDrag { DragItem.provider(route, line: model.line(of: route)) }
                .uiTestAnchor(route.chipKey(task: task))
        } else {
            content.selectOpen(route.selectionKey) { model.open(route, push: model.modal != nil) }
                .onDrag { DragItem.provider(route, line: model.line(of: route)) }
                .uiTestAnchor("chip:\(route.selectionKey)")
        }
    }
}

extension AppModel {
    /// A task's link as a menu, for a click on its chip.
    func linkMenu(_ route: ModalRoute, task: Int) -> NSMenu {
        NSHostingMenu(rootView: LinkMenu(route: route, task: task).environment(self))
    }
}

/// What a task's link offers: open it, its own actions, unlink it from the task, delete it.
struct LinkMenu: View {
    let route: ModalRoute
    let task: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        switch route {
        case .web: Button("Open in Browser") { model.open(route) }
        case .slack: Button("Open in Slack") { model.open(route) }
        default: Button("Open") { model.open(route, push: model.modal != nil) }
        }
        switch route {
        case .file(let id): Button("Open in Obsidian") { model.openInObsidian(model.file(id)?.path) }
        case .artifact(let url): Button("Open in Browser") { NSWorkspace.shared.open(url) }
        case .github(let url): Button("Open on GitHub") { if let link = URL(string: url) { NSWorkspace.shared.open(link) } }
        default: EmptyView()
        }
        Button("Copy") { model.copy([route]) }
        if let link = model.link(of: route) ?? route.address { Button("Copy Link") { Pasteboard.copy(link) } }
        if model.isLinked(route, to: task) {
            Divider()
            Button("Unlink from \(model.task(task)?.key ?? "the Task")") { model.unlink(route, from: task) }
        }
        switch route {
        case .file(let id):
            Divider()
            Button("Delete") { model.deleteFile(id) }
        case .artifact(let url):
            Divider()
            Button("Remove from HQ") { model.removeArtifact(url) }
        default:
            EmptyView()
        }
    }
}

/// Lays out views left to right, wrapping to the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = Self.size(of: view, within: width)
            if x > 0 && x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = Self.size(of: view, within: bounds.width)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }

    /// A chip's own width, or the row's when it's wider: then it truncates.
    private static func size(of view: LayoutSubview, within width: CGFloat) -> CGSize {
        let ideal = view.sizeThatFits(.unspecified)
        return ideal.width > width ? view.sizeThatFits(ProposedViewSize(width: width, height: nil)) : ideal
    }
}

extension AppModel {
    /// The session that made an output.
    func maker(of route: ModalRoute) -> SessionItem? {
        switch route {
        case .file(let id): session(file(id)?.sessions.last)
        case .artifact(let url): session(artifacts.first { $0.id == url }?.session)
        case .github(let url): githubItem(url).flatMap { sessions(onPullRequest: $0).first }
        default: nil
        }
    }

    /// An item's title, for chips, rows and the modal.
    func title(of route: ModalRoute) -> String {
        switch route {
        case .task(let id): task(id)?.title ?? "T-\(id)"
        case .session(let id): session(id)?.name ?? "Session"
        case .file(let id): file(id)?.title ?? id
        case .artifact(let url): artifacts.first { $0.id == url }?.title ?? url.lastPathComponent
        case .github(let url): githubItem(url).map { "#\($0.number) \($0.title)" } ?? url
        case .web(let url): Self.webName(url)
        case .slack(let url): slackMessages[url]?.title ?? (SlackLink(url)?.ts == nil ? "Slack channel" : "Slack message")
        case .start: "Start a session"
        case .closedSessions: "Closed Sessions"
        case .roles: "Roles"
        case .notifications: "Notifications"
        case .newTask: "New Task"
        case .newReminder: "New Reminder"
        case .newFile: "New File"
        case .importArtifact: "Import an Artifact"
        }
    }

    /// What names a link in a few characters, for the links line at rest: T-34, #418, a file's or an artifact's first letters.
    func shortTitle(of route: ModalRoute) -> String {
        switch route {
        case .task(let id): return task(id)?.key ?? "T-\(id)"
        case .github(let url):
            if let item = githubItem(url) { return "#\(item.number)" }
            return URL(string: url).map { "#\($0.lastPathComponent)" } ?? url
        case .web(let url): return URL(string: url)?.host().map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? url
        // Where it was said: #infra, or who wrote it in a direct message.
        case .slack(let url):
            let message = slackMessages[url]
            return message?.channel.map { "#\($0)" } ?? message?.author ?? "Slack"
        case .file, .artifact:
            let title = title(of: route)
            guard title.count > Self.shortTitleLength else { return title }
            return title.prefix(Self.shortTitleLength).trimmingCharacters(in: .whitespaces) + "…"
        default: return title(of: route)
        }
    }

    static let shortTitleLength = 12

    /// A web page by its address, without the scheme or a trailing slash: "slack.com/archives/C05/p17".
    static func webName(_ url: String) -> String {
        guard let address = URL(string: url), let host = address.host() else { return url }
        let path = address.path().hasSuffix("/") ? String(address.path().dropLast()) : address.path()
        return (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host) + path
    }
}
