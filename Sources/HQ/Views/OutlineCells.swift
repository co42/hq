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

    override func drawSelection(in dirtyRect: NSRect) {
        let active = (window?.firstResponder as? NSView).map { $0.isDescendant(of: superview ?? self) } ?? false
        fill(active ? Ink.rowSelectionNS : Ink.rowSelectionInactiveNS)
    }

    override func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {
        fill(Ink.rowDropNS)
    }

    private func fill(_ color: NSColor) {
        color.setFill()
        var rect = bounds
        rect.origin.y += gap
        rect.size.height -= gap
        // Inside the list's card, concentric with it.
        NSBezierPath(roundedRect: rect.insetBy(dx: Space.xs + 2, dy: 1), xRadius: Radius.row, yRadius: Radius.row).fill()
    }

    override func layout() {
        super.layout()
        spanCells()
        placeDisclosure()
    }

    /// The disclosure on the title's line, under the gap: AppKit leaves it where it was when a row's gap changes.
    private func placeDisclosure() {
        guard isTask, let button = subviews.first(where: { $0.identifier == NSOutlineView.disclosureButtonIdentifier }) else { return }
        let line = Metric.outlineRow
        let y = isFlipped ? gap : bounds.height - gap - line
        if button.frame.minY != y || button.frame.height != line {
            button.frame = NSRect(x: button.frame.minX, y: y, width: button.frame.width, height: line)
        }
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        // Scrolls while edited, truncates with an ellipsis otherwise.
        cell?.isScrollable = true
        let accepted = super.becomeFirstResponder()
        if accepted, let task { (delegate as? OutlineCoordinator)?.titleFocused(task) }
        if !accepted { cell?.isScrollable = false }
        return accepted
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        cell?.isScrollable = false
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

/// A task's progress: a quiet ring that fills green as what's under it gets done, a green disc when all is.
final class ProgressRingView: NSView {
    /// Everything under the task, every level, by status.
    private(set) var counts: [TaskStatus: Int] = [:]
    var total: Int { counts.values.reduce(0, +) }
    /// Clockwise from twelve, most finished first; todo is the track left over.
    private static let segments: [(status: TaskStatus, word: String)] = [(.done, "done"), (.review, "in review"), (.doing, "doing"), (.todo, "to do")]

    override var isFlipped: Bool { true }

    func show(_ statuses: [TaskStatus]) {
        let counts = Dictionary(statuses.map { ($0, 1) }, uniquingKeysWith: +)
        guard counts != self.counts else { return }
        self.counts = counts
        toolTip = total == 0 ? nil : Self.segments.compactMap { part in counts[part.status].map { "\($0) \(part.word)" } }.joined(separator: ", ")
        setAccessibilityLabel(toolTip)
        needsDisplay = true
    }

    override func isAccessibilityElement() -> Bool { total > 0 }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }

    override func draw(_ dirtyRect: NSRect) {
        guard total > 0, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let side = Metric.glyph
        let stroke = Metric.glyphStroke
        let rect = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        let ring = rect.insetBy(dx: stroke / 2, dy: stroke / 2)
        if counts[.done] == total {
            ctx.setFillColor(Ink.doneNS.cgColor)
            ctx.fillEllipse(in: rect)
            return
        }
        ctx.setLineWidth(stroke)
        ctx.setStrokeColor(Ink.quietMarkNS.cgColor)
        ctx.strokeEllipse(in: ring)
        // Flipped: angles turn clockwise, from twelve o'clock.
        var start = -CGFloat.pi / 2
        for (status, color) in [(TaskStatus.done, Ink.doneNS), (.review, Ink.needsYouNS), (.doing, Ink.doingNS)] {
            guard let count = counts[status], count > 0 else { continue }
            let end = start + 2 * .pi * CGFloat(count) / CGFloat(total)
            ctx.setStrokeColor(color.cgColor)
            ctx.addArc(center: CGPoint(x: ring.midX, y: ring.midY), radius: ring.width / 2, startAngle: start, endAngle: end, clockwise: false)
            ctx.strokePath()
            start = end
        }
    }
}

/// A small capsule: orange "Review: …", blue "2 new", or a quiet project with its symbol.
final class PillView: NSView {
    enum Tone { case needsYou, new, quiet }
    var text = "" {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
            // Only a pill that shows tracks the pointer.
            if text.isEmpty != oldValue.isEmpty { trackHandCursor(!text.isEmpty) }
        }
    }
    var tone = Tone.quiet { didSet { needsDisplay = true } }
    var icon: NSImage? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    private var attributes: [NSAttributedString.Key: Any] {
        let color: NSColor = switch tone {
        case .needsYou: Ink.needsYouTextNS
        case .new: Ink.unreadTextNS
        case .quiet: Ink.secondaryTextNS
        }
        let font = tone == .quiet ? KitType.secondary.nsFont : KitType.groupLabel.nsFont
        return [.font: font, .foregroundColor: color]
    }

    override var intrinsicContentSize: NSSize {
        let text = (self.text as NSString).size(withAttributes: attributes)
        let iconWidth = icon == nil ? 0 : Metric.glyphSlot - Space.xs + Space.xs
        let padding = tone == .quiet ? 0 : Metric.pillPadding * 2
        return NSSize(width: ceil(text.width) + iconWidth + padding, height: Metric.chipHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds
        if tone != .quiet {
            (tone == .needsYou ? Ink.needsYouFillNS : Ink.unreadFillNS).setFill()
            NSBezierPath(roundedRect: rect, xRadius: Radius.chip, yRadius: Radius.chip).fill()
        }
        var x: CGFloat = tone == .quiet ? 0 : Metric.pillPadding
        if let icon {
            let side = Metric.pillIcon
            let tinted = icon
            tinted.isTemplate = true
            NSGraphicsContext.saveGraphicsState()
            let imageRect = NSRect(x: x, y: (rect.height - side) / 2, width: side, height: side)
            tinted.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            Ink.secondaryTextNS.set()
            imageRect.fill(using: .sourceAtop)
            NSGraphicsContext.restoreGraphicsState()
            x += side + Space.xs
        }
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(with: NSRect(x: x, y: (rect.height - size.height) / 2, width: rect.width - x, height: size.height),
                                options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        if let onClick { onClick(); takeRelease() } else { super.mouseDown(with: event) }
    }

    override func cursorUpdate(with event: NSEvent) {
        if onClick != nil { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }

    override func isAccessibilityElement() -> Bool { !text.isEmpty }
    override func accessibilityRole() -> NSAccessibility.Role? { onClick == nil ? .staticText : .button }
    override func accessibilityLabel() -> String? { text }
    override func accessibilityPerformPress() -> Bool { onClick?(); return onClick != nil }
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

    override var isFlipped: Bool { true }

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

    /// The chips that fit the frame.
    var drawnWidth: CGFloat {
        var x: CGFloat = 0
        for label in labels {
            let next = x + width(label)
            if next > bounds.width + 0.5 { break }
            x = next + Space.xs
        }
        return max(x - Space.xs, 0)
    }

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
                let color = label.color?.textNS ?? Ink.quietMarkNS
                let tinted = NSImage(size: iconRect.size, flipped: false) { rect in
                    icon.draw(in: rect)
                    color.set()
                    rect.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
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
/// A task's key: a click copies the key and the title, as Copy Key and Title does, and it turns the accent color a moment.
final class KeyField: NSTextField {
    var copied = ""
    private var flashes = 0

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
            self.toolTip = Self.help
        }
        takeRelease()
    }

    static let help = "Click to copy the key and the title"
}

final class TaskCell: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("task-cell")
    /// Where the title and the description start: after the status glyph.
    static var titleX: CGFloat { Metric.glyphSlot + Space.sm }
    let glyph = GlyphButton()
    let title = TitleField()
    /// The project after the title: a click picks it.
    let project = ProjectButton()
    /// The tags, as colored chips.
    let labels = LabelStripView()
    /// After the labels, the description's toggle: when the task has one, and under the pointer to write one.
    let note = HandButton()
    let review = PillView()
    /// Everything under it, as a ring that fills as it gets done.
    let progress = ProgressRingView()
    /// It has a description: the toggle shows at rest.
    private var hasNote = false
    /// Its row is selected: the key shows, as under the pointer.
    private var selected: Bool { (superview as? NSTableRowView)?.isSelected ?? false }
    let key = KeyField(labelWithString: "")
    private var actions: [NSButton] = []
    private(set) var descriptionHost: NSHostingView<AnyView>?
    /// The task's PRs, files, artifacts and linked tasks, on one line under the title.
    private(set) var linksHost: NSHostingView<AnyView>?
    private var shownLinks: (task: Int, routes: [ModalRoute])?
    private let chipFrames = ChipFrames()
    private var hovered = false
    private var id: Int?
    private weak var coordinator: OutlineCoordinator?
    private weak var model: AppModel?
    private var shownDescription = false
    /// Space above the line: top-level tasks after the first in their list.
    var gap: CGFloat = 0 { didSet { if gap != oldValue { needsLayout = true } } }

    override var isFlipped: Bool { true }

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
        note.isBordered = false
        note.image = KitIcon.description.nsImage(.mark, weight: .semibold)
        note.contentTintColor = Ink.secondaryTextNS
        note.target = self
        note.action = #selector(toggleDescription)
        key.font = KitType.key.nsFont
        key.textColor = Ink.secondaryTextNS
        key.alignment = .right
        key.toolTip = KeyField.help
        key.setAccessibilityLabel("Copy key and title")
        review.tone = .needsYou
        for (icon, help, action) in [(KitIcon.new, "Add a subtask (⇧N)", #selector(addSubtask)),
                                     (.toBacklog, "Move to the Backlog (⇧⌘B)", #selector(toggleList)),
                                     (.trash, "Delete the task (⌘⌫)", #selector(deleteTask))] {
            let button = HandButton()
            button.isBordered = false
            button.image = icon.nsImage(.row, weight: .medium)
            button.contentTintColor = Ink.secondaryTextNS
            button.toolTip = help
            button.setAccessibilityLabel(String(help.prefix { $0 != "(" }).trimmingCharacters(in: .whitespaces))
            button.target = self
            button.action = action
            button.isHidden = true
            actions.append(button)
        }
        for view in [glyph, title, project, labels, note, review, progress, key] as [NSView] + actions { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(model: AppModel, id: Int, coordinator: OutlineCoordinator, hovered: Bool) {
        guard let task = model.task(id) else { return }
        self.model = model
        self.coordinator = coordinator
        let changed = self.id == id && glyph.status != task.status
        self.id = id
        self.hovered = hovered
        title.task = id
        title.delegate = coordinator
        let topLevel = task.parent == nil
        title.font = topLevel ? KitType.titleStrong.nsFont : KitType.title.nsFont
        title.textColor = task.status == .done ? Ink.secondaryTextNS : Ink.textNS
        // A title being edited keeps what's typed.
        if title.currentEditor() == nil, title.stringValue != task.title { title.stringValue = task.title }
        glyph.status = task.status
        if changed { glyph.pop() }
        glyph.onPick = { [weak model] status in model?.setStatus(id, status) }
        glyph.onNext = { [weak model] in model?.nextStatus([id]) }
        glyph.toolTip = "\(task.status.title): click for the next status (⌘Return), ⌥-click to pick one"
        project.show(task.project, color: task.project.map { model.labelColor(.project, $0) },
                     inherited: task.project == nil && model.project(ofTask: id) != nil)
        project.projects = { [weak model] in model?.allProjects ?? [] }
        project.onPick = { [weak model] choice in model?.setProject(id, choice) }
        labels.labels = task.tags.map { LabelStripView.Label(text: $0, color: model.labelColor(.tag, $0), icon: LabelStripView.tagIcon) }
        hasNote = !task.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        review.text = task.status == .review ? "Review" + (task.review.map { ": \($0)" } ?? "") : ""
        // Quiet in the Backlog: it waits for later, not for the user.
        let tone: PillView.Tone = model.needsYou(.task(id)) ? .needsYou : .quiet
        if review.tone != tone { review.tone = tone }
        review.onClick = { [weak model] in model?.open(.task(id)) }
        review.toolTip = task.review
        let outputs = model.outputs(ofTask: id)
        if outputs.isEmpty {
            linksHost?.removeFromSuperview()
            linksHost = nil
            shownLinks = nil
        } else if shownLinks?.task != id || shownLinks?.routes != outputs || linksHost == nil {
            // The chips follow the model themselves; a new view only when the links change.
            shownLinks = (id, outputs)
            chipFrames.frames = [:]
            let view = AnyView(LinksLine(task: id, routes: outputs, frames: chipFrames).handCursors().environment(model))
            if let linksHost { linksHost.rootView = view } else {
                let host = NSHostingView(rootView: view)
                host.sizingOptions = []
                addSubview(host)
                linksHost = host
            }
        }
        // Every level under it, done over all.
        let below = model.taskTree.subtree(of: id).filter { $0 != id }.compactMap { model.task($0) }
        progress.show(below.map(\.status))
        key.stringValue = task.key
        key.copied = "\(task.key) \(task.title)"
        let inBacklog = model.list(of: id) == .backlog
        actions[1].image = (inBacklog ? KitIcon.toTasks : KitIcon.toBacklog).nsImage(.row)
        actions[1].toolTip = inBacklog ? "Move to Tasks (⇧⌘B)" : "Move to the Backlog (⇧⌘B)"
        actions[1].setAccessibilityLabel(inBacklog ? "Move to Tasks" : "Move to Backlog")
        shownDescription = coordinator.descriptionShown(id)
        note.contentTintColor = shownDescription ? Ink.accentNS : hasNote ? Ink.secondaryTextNS : Ink.quietMarkNS
        note.toolTip = shownDescription ? "Hide the description (⇧Return)" : hasNote ? "Show the description (⇧Return)" : "Write a description (⇧Return)"
        note.setAccessibilityLabel(shownDescription ? "Hide the description" : hasNote ? "Show the description" : "Write a description")
        if shownDescription {
            let view = AnyView(DescriptionBlock(id: id).handCursors().environment(model))
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
        var spoken = ["\(task.key) \(task.title)", task.status.title]
        if model.needsYou(.task(id)) { spoken.append("needs you") } else if model.isNew(.task(id)) { spoken.append("new") }
        if task.status == .review, let reason = task.review { spoken.append("review: \(reason)") }
        if let project = task.project ?? model.project(ofTask: id) { spoken.append("project \(project)") }
        if !task.tags.isEmpty { spoken.append("tags " + task.tags.joined(separator: ", ")) }
        if !below.isEmpty { spoken.append("\(below.filter { $0.status == .done }.count) of \(below.count) subtasks done") }
        setAccessibilityLabel(spoken.joined(separator: ", "))
        needsLayout = true
    }

    /// The hover actions, and the row's other commands, for VoiceOver.
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard let id, let model else { return nil }
        let actions: [(String, () -> Void)] = [
            ("Open", { model.open(.task(id)) }),
            ("Next Status", { model.nextStatus([id]) }),
            ("Show or Hide Description", { model.toggleDescription(id) }),
            ("Add Subtask", { [weak self] in self?.addSubtask() }),
            (model.list(of: id) == .backlog ? "Move to Tasks" : "Move to Backlog", { model.toggleList(id) }),
            ("Start Session…", { model.beginStart(task: id) }),
            ("Delete", { model.deleteTasks([id]) }),
        ]
        return actions.map { name, run in NSAccessibilityCustomAction(name: name) { run(); return true } }
    }

    /// The key's text and the label's insets, whole: T-106 as wide as T-99 plus a digit.
    var keyWidth: CGFloat {
        ceil((key.stringValue as NSString).size(withAttributes: [.font: key.font ?? KitType.key.nsFont]).width) + Space.xs
    }

    func setHovered(_ value: Bool) {
        hovered = value
        needsLayout = true
    }

    /// The link chip under a point in window coordinates, with its task.
    func link(at point: NSPoint) -> (route: ModalRoute, task: Int)? {
        guard let linksHost, let id else { return nil }
        let local = linksHost.convert(point, from: nil)
        guard linksHost.bounds.contains(local), let route = chipFrames.route(at: local) else { return nil }
        return (route, id)
    }

    /// The status glyph or the project under a click, in window coordinates.
    func button(at point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let hit = hitTest(superview.convert(point, from: nil))
        return hit === glyph || hit === project || hit === key ? hit : nil
    }

    override func layout() {
        super.layout()
        let line = Metric.outlineRow
        let slot = Metric.glyphSlot
        // A gap above a top-level task sets the groups apart; the line sits under it.
        let top = gap
        let centered = top + (line - slot) / 2
        glyph.frame = NSRect(x: 0, y: centered, width: slot, height: slot)
        let titleX = Self.titleX
        var right = bounds.width - Space.xs
        func place(_ view: NSView, width: CGFloat, height: CGFloat = Metric.chipHeight, visible: Bool = true) {
            view.isHidden = !visible
            guard visible else { return }
            right -= width
            view.frame = NSRect(x: right, y: top + (line - height) / 2, width: width, height: height)
            right -= Space.sm
        }
        for button in actions.reversed() {
            place(button, width: Metric.rowAction, height: Metric.rowAction, visible: hovered)
            if hovered { right += Space.sm - 2 }
        }
        if hovered { right -= Space.xs }
        // The key, and the empty slots that act, show under the pointer or on a selected row: at rest a row tells its story.
        let active = hovered || selected
        place(key, width: keyWidth, height: ceil(key.intrinsicContentSize.height), visible: active)
        // What doesn't fit hides, the title truncating first: the progress ring, then labels, then the description mark.
        let minimumTitle = Metric.titleMinimum
        let reviewWidth = review.text.isEmpty ? 0 : min(review.intrinsicContentSize.width, Metric.reviewPillMax)
        let progressWidth = progress.total == 0 ? 0 : Metric.glyphSlot
        let trailing = [reviewWidth, progressWidth].filter { $0 > 0 }.reduce(0) { $0 + $1 + Space.sm }
        let showProgress = progressWidth > 0 && right - trailing - titleX >= minimumTitle
        place(progress, width: progressWidth, height: Metric.glyphSlot, visible: showProgress)
        place(review, width: reviewWidth, visible: reviewWidth > 0)
        let available = max(right - titleX, 40)
        let projectWidth = project.project == nil && !active ? 0 : project.naturalWidth
        let tagsWidth = labels.naturalWidth
        let labelsWidth = projectWidth + tagsWidth + (projectWidth > 0 && tagsWidth > 0 ? Space.xs : 0)
        let editing = title.currentEditor() != nil
        let text = title.stringValue.isEmpty ? (title.placeholderString ?? "") : title.stringValue
        let natural = ceil((text as NSString).size(withAttributes: [.font: title.font ?? KitType.title.nsFont]).width) + Space.sm
        let roomForLabels = labelsWidth > 0 ? min(labelsWidth + Space.sm, max(available - minimumTitle, 0)) : 0
        let titleWidth = editing ? min(max(natural, available - roomForLabels), available) : min(natural, available - roomForLabels)
        let titleHeight = ceil(title.intrinsicContentSize.height)
        title.frame = NSRect(x: titleX, y: top + (line - titleHeight) / 2, width: max(titleWidth, 40), height: titleHeight)
        var x = title.frame.maxX + Space.sm
        let chipY = top + (line - Metric.chipHeight) / 2
        project.isHidden = projectWidth == 0 || right - x < projectWidth
        var tagsX = x
        if !project.isHidden {
            project.frame = NSRect(x: x, y: chipY, width: projectWidth, height: Metric.chipHeight)
            x += projectWidth + Space.sm
            tagsX = project.frame.maxX + Space.xs
        }
        labels.isHidden = tagsWidth == 0 || right - tagsX < labels.firstWidth
        if !labels.isHidden {
            labels.frame = NSRect(x: tagsX, y: chipY, width: min(tagsWidth, right - tagsX), height: Metric.chipHeight)
            x = tagsX + labels.drawnWidth + Space.sm
        }
        note.isHidden = !(hasNote || shownDescription || hovered) || editing || right - x < Metric.rowAction
        if !note.isHidden {
            note.frame = NSRect(x: x - Space.xs, y: top + (line - Metric.rowAction) / 2, width: Metric.rowAction, height: Metric.rowAction)
        }
        var below = top + line
        if let linksHost {
            linksHost.frame = NSRect(x: titleX, y: below, width: bounds.width - titleX - Space.xs, height: Metric.linksLine)
            below += Metric.linksLine
        }
        if let descriptionHost {
            descriptionHost.frame = NSRect(x: titleX, y: below, width: bounds.width - titleX, height: max(bounds.height - below, 0))
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The status glyph takes clicks over the line's height and the gap around it.
        let local = convert(point, from: superview)
        let area = NSRect(x: glyph.frame.minX - Space.xs / 2, y: gap, width: glyph.frame.width + Space.xs, height: Metric.outlineRow)
        if area.contains(local) { return glyph }
        // The empty part of the row drags it; the title selects on a click and edits on a double-click.
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    @objc private func toggleDescription() { if let id { model?.toggleDescription(id) } }
    @objc private func addSubtask() {
        guard let id, let added = model?.addSubtask(to: id) else { return }
        coordinator?.beginEditing(added.id)
    }
    @objc private func toggleList() { if let id { model?.toggleList(id) } }
    @objc private func deleteTask() { if let id { model?.deleteTasks([id]) } }
}

// MARK: Faces column

/// Grip on hover, the attention dot, and the faces of the sessions on the task: a click on them starts a session.
final class FacesCell: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("faces-cell")
    private let grip = GripView()
    private let dot = DotView()
    private let faces = FaceStackView()
    /// Space above the task's line.
    var gap: CGFloat = 0 { didSet { if gap != oldValue { needsLayout = true } } }

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        identifier = Self.id
        grip.isHidden = true
        grip.toolTip = "Drag to move"
        // One face, the session that matters most: the tooltip names them all.
        faces.limit = OutlineCoordinator.faces
        faces.showsMore = false
        faces.clickable = true
        for view in [grip, dot, faces] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(model: AppModel, id: Int, folded: Bool) {
        // One face: the session that matters most; the tooltip names them all.
        let sessions = model.byImportance(model.sessions(on: id, withSubtasks: folded, includeEnded: true))
        faces.faces = sessions.map { session in
            FaceStackView.Face(spec: session.face, badge: session.status.needsYou ? (session.status.state == .failed ? .failed : .needsYou) : nil,
                               label: "\(session.name), \(session.isRunning ? session.status.title.lowercased() : "ended")" + (session.status.isNew ? ", new" : ""),
                               working: session.isWorking, ended: !session.isRunning, session: session.id)
        }
        let route = ModalRoute.task(id)
        onStart = { [weak model] in model?.beginStart(task: id) }
        onMenu = { [weak model] session, point, view in
            if let menu = model?.faceMenu(session, task: id) { FaceMenu.show(menu, session, point, view) }
        }
        faces.toolTip = (faces.toolTip.map { $0 + "\n" } ?? "") + (sessions.isEmpty ? "Click to start a session (⌥⌘Return)"
            : "Click a face for its session's menu")
        let menuPoint = { [weak self] in self.map { NSPoint(x: $0.faces.frame.minX, y: $0.faces.frame.maxY + Space.xs) } ?? .zero }
        faces.press = { [weak self] in
            guard let self else { return }
            if let first = sessions.first { self.onMenu(first.id, menuPoint(), self) } else { self.onStart() }
        }
        faces.faceActions = sessions.map { session in
            (name: "Menu for \(session.name)", run: { [weak self] in if let self { self.onMenu(session.id, menuPoint(), self) } })
        } + [(name: "Start Session…", run: { [weak model] in model?.beginStart(task: id) })]
        dot.color = model.needsYou(route) ? Ink.needsYouNS : model.isNew(route) ? Ink.unreadNS : nil
        dot.setAccessibilityLabel(model.needsYou(route) ? "Needs you" : model.isNew(route) ? "New" : nil)
        faces.isHidden = faces.faces.isEmpty && !hovered
        needsLayout = true
    }

    private var hovered = false

    /// Under the pointer: the grip, and the dashed square that starts a session when nobody is on the task.
    func setHovered(_ value: Bool) {
        hovered = value
        grip.isHidden = !value
        faces.isHidden = faces.faces.isEmpty && !value
    }

    /// Start Session… for the task.
    var onStart: () -> Void = {}
    /// A click on a face: its session's menu, at a point in this cell.
    var onMenu: (String, NSPoint, NSView) -> Void = { _, _, _ in }

    override func layout() {
        super.layout()
        let line = Metric.outlineRow
        grip.frame = NSRect(x: 0, y: gap + (line - Metric.glyphSlot) / 2, width: Space.md, height: Metric.glyphSlot)
        // The faces sit against the task, the dot just before them.
        let facesX = bounds.width - Space.xs - faces.contentWidth
        faces.frame = NSRect(x: facesX, y: gap, width: faces.contentWidth, height: line)
        dot.frame = NSRect(x: facesX - Space.xs - Metric.attentionDot, y: gap + (line - Metric.attentionDot) / 2,
                           width: Metric.attentionDot, height: Metric.attentionDot)
    }

    /// The faces start a session; the rest of the cell drags the row. The face stack takes the hit, so the
    /// hand shows over it; its clicks go on to this cell.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return faces.frame.insetBy(dx: -Space.xs, dy: 0).contains(local) ? faces : nil
    }

    override func mouseDown(with event: NSEvent) {
        if click(event) { takeRelease() }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// A click on a face shows its session's menu at once; the empty square starts a session. False when the click misses.
    func click(_ event: NSEvent) -> Bool {
        let local = convert(event.locationInWindow, from: nil)
        guard faces.frame.insetBy(dx: -Space.xs, dy: 0).contains(local) else { return false }
        if let session = faces.session(at: faces.convert(event.locationInWindow, from: nil)) {
            onMenu(session, NSPoint(x: faces.frame.minX, y: faces.frame.maxY + Space.xs), self)
        } else if faces.faces.isEmpty {
            onStart()
        }
        return true
    }

}

/// Six dots: where to grab a row.
final class GripView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Ink.quietMarkNS.setFill()
        for row in 0..<3 {
            for column in 0..<2 {
                let x = bounds.midX - 2.5 + CGFloat(column) * 4
                let y = bounds.midY - 4.5 + CGFloat(row) * 4
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 1.8, height: 1.8)).fill() // grid: ok drawn mark
            }
        }
    }
}

/// An orange or blue dot, or nothing.
final class DotView: NSView {
    var color: NSColor? { didSet { needsDisplay = true; setAccessibilityElement(color != nil) } }

    override func accessibilityRole() -> NSAccessibility.Role? { .image }

    override func draw(_ dirtyRect: NSRect) {
        guard let color else { return }
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

// MARK: Quick add

/// A quick-add field knows its list.
final class QuickAddField: NSTextField {
    var list = TaskList.overview
}

/// "New task" under a list: Return adds it and keeps the field for the next.
final class QuickAddCell: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("quick-cell")
    let field = QuickAddField()
    private let plus = NSImageView()

    override var isFlipped: Bool { true }

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
        let placeholder = list == .overview ? "New Task" : "New Backlog Task"
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .font: KitType.title.nsFont, .foregroundColor: Ink.secondaryTextNS,
        ])
        field.setAccessibilityLabel(placeholder)
    }

    override func layout() {
        super.layout()
        let slot = Metric.glyphSlot
        // The last line of its list's card: the card's padding below it.
        let line = bounds.height - Metric.listCardPadding
        plus.frame = NSRect(x: 0, y: (line - slot) / 2, width: slot, height: slot)
        let height = ceil(field.intrinsicContentSize.height)
        let x = TaskCell.titleX
        field.frame = NSRect(x: x, y: (line - height) / 2, width: bounds.width - x - Space.xs, height: height)
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
    /// A long description shows its first lines only; the task's modal has it all.
    static let maxLines = 20
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if model.editingDescription == id {
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
private struct InlineDescriptionEditor: View {
    let id: Int
    @Environment(AppModel.self) private var model
    @State private var draft = ""

    var body: some View {
        MarkdownEditor(text: $draft, focusOnAppear: true, label: "Description",
                       onCommit: { save(then: .row(id)) },
                       onCancel: { save(then: .row(id)) },
                       onEnd: { save(then: .left(id)) },
                       onTab: { backward in save(then: .title(id, by: backward ? 0 : 1)) })
            .frame(height: Metric.editorMin)
            .background(Ink.editor, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Ink.boxFrame))
            .onAppear { draft = model.task(id)?.body ?? "" }
            .uiTestAnchor("description-editor:\(id)")
    }

    /// An empty description hides again.
    private func save(then focus: OutlineFocus) {
        guard model.editingDescription == id else { return }
        model.editingDescription = nil
        model.setDescription(id, draft)
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.shownDescriptions.remove(id) }
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
    /// Under a task's row on the page: that task.
    var task: Int?
    @Environment(AppModel.self) private var model

    var body: some View {
        let fresh = model.isNew(route)
        HStack(spacing: compact ? Space.xs : Metric.chipGap) {
                icon
                if !compact, let maker = model.maker(of: route) { SessionFace(maker, size: Metric.faceChip) }
                Text(model.title(of: route))
                    .lineLimit(1)
                    .fontWeight(fresh ? .semibold : .regular)
                    .foregroundStyle(fresh ? AnyShapeStyle(Ink.unreadText) : AnyShapeStyle(compact ? .secondary : .primary))
            }
            .kitType(compact ? .secondary : .callout)
            .padding(.horizontal, compact ? Space.xs + 2 : Space.sm)
            .frame(height: compact ? Metric.chipHeight : Metric.rowAction)
            .background(fresh ? AnyShapeStyle(Ink.unreadFill) : compact ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Ink.chipFill),
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .modifier(ChipClick(route: route, task: task))
            .accessibilityValue(fresh ? "New" : "")
            .onDrag { DragItem.provider(route, title: model.title(of: route)) }
            .clickable()
            .help(model.title(of: route))
            .uiTestAnchor(task.map { route.chipKey(task: $0) } ?? "chip:\(route.selectionKey)")
    }

    @ViewBuilder
    private var icon: some View {
        switch route {
        case .github(let url):
            if let item = model.githubItem(url) { GitHubStateIcon(item: item).fontWeight(.semibold) } else { KitIcon.pullRequest.image.fontWeight(.semibold) }
        // The kinds' colors, as on their rows' tiles.
        case .file: KitIcon.fileTile.image.foregroundStyle(Ink.fileTile).accessibilityLabel("File")
        case .artifact: KitIcon.artifact.image.fontWeight(.semibold).foregroundStyle(Ink.artifactTile).accessibilityLabel("Artifact")
        case .task(let id): if let task = model.task(id) { TaskGlyph(status: task.status).scaleEffect(compact ? 0.86 : 1) }
        default: EmptyView()
        }
    }
}

/// A click selects a chip and a double-click opens it; under a task's row the outline shows its menu on a right-click.
private struct ChipClick: ViewModifier {
    let route: ModalRoute
    let task: Int?
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        if let task {
            content
                .selectOpen(route.chipKey(task: task), in: .tasks) { model.open(route, push: model.modal != nil) }
                .accessibilityAction(named: "Show Menu") { FaceMenu.show(model.linkMenu(route, task: task), route.chipKey(task: task), .zero, nil) }
        } else {
            content.selectOpen(route.selectionKey) { model.open(route, push: model.modal != nil) }
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
        Button("Open") { model.open(route, push: model.modal != nil) }
        switch route {
        case .file(let id):
            Button("Open in Obsidian") { model.openInObsidian(model.file(id)?.path) }
        case .artifact(let url):
            Button("Open in Browser") { NSWorkspace.shared.open(url) }
            Button("Copy Link") { Pasteboard.copy(url.absoluteString) }
        case .github(let url):
            Button("Open on GitHub") { if let link = URL(string: url) { NSWorkspace.shared.open(link) } }
            Button("Copy Link") { Pasteboard.copy(url) }
        default:
            EmptyView()
        }
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

/// A task's links under its title: small chips on one line, as many as fit, then "+n".
struct LinksLine: View {
    let task: Int
    let routes: [ModalRoute]
    /// Where each chip sits, for the outline's right-click.
    let frames: ChipFrames

    var body: some View {
        OneLineLayout(spacing: Space.sm) {
            ForEach(routes, id: \.self) { route in
                OutputChip(route: route, compact: true, task: task)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ChipFrames.space)) } action: { frames.frames[route] = $0 }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(.named(ChipFrames.space))
    }
}

/// The link chips' frames in their line, top-left origin like the line's flipped host.
@MainActor
final class ChipFrames {
    nonisolated static let space = "links"
    var frames: [ModalRoute: CGRect] = [:]

    func route(at point: CGPoint) -> ModalRoute? { frames.first { $0.value.contains(point) }?.key }
}

/// Views left to right on one line; those that don't fit aren't shown.
struct OneLineLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            // The first always shows, truncated if it must; the others only whole.
            let width = x == bounds.minX ? min(size.width, bounds.width) : size.width
            if x + width > bounds.maxX + 0.5 {
                view.place(at: CGPoint(x: bounds.maxX + 10_000, y: bounds.minY), proposal: .zero)
                x = bounds.maxX + 1
                continue
            }
            view.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: size.height))
            x += width + spacing
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
        case .start: "Start a session"
        case .closedSessions: "Closed Sessions"
        }
    }
}
