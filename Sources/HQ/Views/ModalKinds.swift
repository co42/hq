import AppKit
import HQKit
import SwiftUI

/// The modal's text column: a readable width, centered, scrolling.
struct ModalPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) { content }
                .frame(maxWidth: Metric.pageWidth, alignment: .leading)
                .padding(.horizontal, Space.xxl)
                .padding(.vertical, Space.xl)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: Task

struct TaskModal: View {
    let id: Int
    @Environment(AppModel.self) private var model
    @State private var title = ""
    /// The subtasks' outline's width: the window's column.
    @State private var outlineWidth: CGFloat = 0
    @FocusState private var titleFocused: Bool

    var body: some View {
        if let task = model.task(id) {
            ModalPage {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(place(task)).kitType(.key).foregroundStyle(.secondary)
                    TextField("New task", text: $title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .kitType(.pageTitle)
                        .accessibilityLabel("Title")
                        .lineLimit(1...4)
                        .focused($titleFocused)
                        .onSubmit { commitTitle() }
                        .onChange(of: titleFocused) { if !titleFocused { commitTitle() } }
                        .onAppear { title = task.title }
                        .onChange(of: task.title) { if !titleFocused { title = task.title } }
                        .uiTestAnchor("modal-title")
                }
                // A story's progress, as on its big card.
                if !model.taskTree.children(of: id).isEmpty { StorySummary(id: id).frame(height: Metric.storyLine) }
                properties(task)
                ModalGroup(title: "On it") { onIt(task) }
                ModalGroup(title: "Description") { DescriptionCard(id: id) }
                // What it waits on and what waits on it, and the tasks linked to it: the list shows them as chips and on
                // selection only (2026-11-10).
                ModalGroup(title: "Blocked by, after and linked tasks") { TaskRelations(id: id) }
                // Its subtasks as the list shows them: the same cards, chips, fold, drag and keys (2026-11-10).
                ModalGroup(title: "Subtasks") { subtasks(task) }
                ModalGroup(title: "Files, artifacts, PRs and issues") {
                    let outputs = model.outputs(ofTask: id).filter { $0.taskID == nil }
                    if !outputs.isEmpty { OutputRows(routes: outputs, task: id) }
                    LinkButton(task: id)
                }
            }
        }
    }

    private func place(_ task: TaskItem) -> String {
        if let parent = model.task(task.parent) { return "\(task.key) · Subtask of \(parent.key) \(parent.title)" }
        return "\(task.key) · " + (task.list == .overview ? "On the overview" : "In the Backlog")
    }

    private func commitTitle() {
        guard let task = model.task(id), title != task.title else { return }
        model.setTitle(id, title)
        title = model.task(id)?.title ?? title
    }

    @ViewBuilder
    private func properties(_ task: TaskItem) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.lg, verticalSpacing: Space.md) {
            GridRow {
                label("Status")
                Picker("Status", selection: Binding(get: { task.status }, set: { model.setStatus(id, $0) })) {
                    ForEach(TaskStatus.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .clickable()
            }
            GridRow {
                label("Project")
                ProjectPicker(project: task.project) { model.setProject(id, $0) }
            }
            GridRow {
                label("Tags")
                TagList(tags: task.tags) { model.setTags(id, $0) }
                    .frame(maxWidth: 480, alignment: .leading)
            }
            GridRow {
                label("Blocked")
                BlockedProperty(id: id)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
    }

    private func label(_ text: String) -> some View {
        Text(text).kitType(.callout).foregroundStyle(.secondary).frame(width: Metric.propertyLabel, alignment: .leading)
    }

    @ViewBuilder
    private func onIt(_ task: TaskItem) -> some View {
        let sessions = task.sessions.compactMap { model.session($0) }
        FlowLayout(spacing: Space.sm) {
            ForEach(sessions) { session in
                SessionChip(session: session) { model.unlink(task: id, session: session.id) }
            }
            if sessions.isEmpty {
                Text("No session on this task.").kitType(.callout).foregroundStyle(.secondary).frame(height: Metric.boxRow)
            }
            Button("Start Session…") { model.beginStart(task: id, push: true) }
                .frame(height: Metric.boxRow)
                .help("Start a Claude session on this task (⌥⌘Return)")
        }
    }

    @ViewBuilder
    private func subtasks(_ task: TaskItem) -> some View {
        if !model.taskTree.children(of: id).isEmpty {
            TaskOutline(width: max(outlineWidth, 1), root: id)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { outlineWidth = $0 }
                .uiTestAnchor("subtask-outline")
        }
        NewSubtaskCard(id: id)
    }
}

/// The card a new subtask is typed in, as the list's new task card: dashed until typed in, then a card with its ring
/// (2026-11-10). Return adds it and keeps the card for the next; ↑ goes to the last subtask; Escape closes the window.
private struct NewSubtaskCard: View {
    let id: Int
    @Environment(AppModel.self) private var model
    @State private var typing = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        HStack(spacing: Space.sm) {
            KitIcon.addTask.image.foregroundStyle(Ink.accent).frame(width: Metric.glyphSlot).accessibilityHidden(true)
            NewSubtaskField(id: id, model: model, focus: model.newSubtaskFocus == id, typing: $typing)
        }
        .padding(.leading, Metric.cardPadding + TaskCell.faceSlot)
        .padding(.trailing, Metric.cardPadding)
        .frame(maxWidth: .infinity, minHeight: Metric.outlineQuick, maxHeight: Metric.outlineQuick, alignment: .leading)
        .background { if typing { shape.fill(Ink.card) } }
        .overlay {
            if typing {
                shape.strokeBorder(Ink.accent, lineWidth: Metric.selectionRing)
            } else {
                shape.strokeBorder(Ink.newCardLine, style: StrokeStyle(lineWidth: 1, dash: Metric.newCardDash))
            }
        }
        .contentShape(shape)
        .onTapGesture { model.newSubtaskFocus = id }
        .uiTestAnchor("new-subtask")
    }
}

/// The new subtask's field, in AppKit as the page's new task field: its keys go to its delegate first.
private struct NewSubtaskField: NSViewRepresentable {
    let id: Int
    let model: AppModel
    /// Asked to take the keyboard: ↓ on the last subtask, or a click on the card.
    let focus: Bool
    @Binding var typing: Bool

    func makeNSView(context: Context) -> FocusField {
        let field = FocusField()
        field.onFocus = { [weak coordinator = context.coordinator] in coordinator?.parent.typing = true }
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = KitType.title.nsFont
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.placeholderAttributedString = NSAttributedString(string: "New Subtask", attributes: [
            .font: KitType.title.nsFont, .foregroundColor: Ink.secondaryTextNS,
        ])
        field.setAccessibilityLabel("New Subtask")
        field.identifier = NSUserInterfaceItemIdentifier("new-subtask-field")
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: FocusField, context: Context) {
        context.coordinator.parent = self
        guard focus else { return }
        DispatchQueue.main.async {
            if model.newSubtaskFocus == id { model.newSubtaskFocus = nil }
            field.window?.makeFirstResponder(field)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NewSubtaskField
        init(_ parent: NewSubtaskField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) { parent.typing = true }
        func controlTextDidEndEditing(_ notification: Notification) { parent.typing = false }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let model = parent.model, id = parent.id
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                let text = control.stringValue.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return true }
                if let added = model.addSubtask(to: id) { model.setTitle(added.id, text) }
                control.stringValue = ""
                return true
            case #selector(NSResponder.moveUp(_:)):
                OutlineCoordinator.scoped(id)?.selectLast()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                model.closeModal()
                return true
            default:
                return false
            }
        }
    }
}

/// Blocked, in the task's properties: its reason in red with Unblock, or Block… to say it can't be done now.
private struct BlockedProperty: View {
    let id: Int
    @Environment(AppModel.self) private var model
    @State private var picking = false

    var body: some View {
        if let task = model.task(id) {
            HStack(spacing: Space.sm) {
                if task.blocked, task.status != .done {
                    KitIcon.blocked.image.foregroundStyle(Ink.blockedText)
                    Text(TaskCell.reason(model, id) ?? "Blocked, no reason").foregroundStyle(Ink.blockedText).lineLimit(2)
                    Button("Unblock") { model.unblock(id) }.help("It can be done again (B on its card)")
                } else {
                    Text(task.status == .done ? "Done" : "No").foregroundStyle(.secondary)
                    Button("Block…") { picking = true }
                        .disabled(task.status == .done)
                        .help("It can't be done now, with a reason or not (B on its card)")
                        .popover(isPresented: $picking, arrowEdge: .bottom) { HoldPicker(task: id, kind: .block) { picking = false }.environment(model) }
                }
            }
            .kitType(.callout)
            .uiTestAnchor("blocked-property")
        }
    }
}

/// What a task waits on and what waits on it, in its window (2026-11-10): the tasks it's blocked by and comes after, each
/// removable, with Blocked By… and After… to add one; the tasks it blocks and that come after it; the tasks linked to it.
/// A click on a row opens that task.
private struct TaskRelations: View {
    let id: Int
    @Environment(AppModel.self) private var model
    @State private var picking: HoldPicker.Kind?

    var body: some View {
        let task = model.task(id)
        let flow = model.taskFlow
        let linked = model.outputs(ofTask: id).compactMap(\.taskID)
        ModalBox {
            section("Blocked by", task?.blockedBy ?? [], help: "It can't go on until these are done") { model.removeLink(id, .blockedBy, $0) }
            add("Blocked By…", .blockedBy)
            section("Comes after", task?.after ?? [], help: "The order you mean: nothing moves") { model.removeLink(id, .after, $0) }
            add("After…", .after)
            section("Blocks", flow.dependents(of: id, .blockedBy), help: "These can't go on until this one is done", remove: nil)
            section("Comes before", flow.dependents(of: id, .after), help: "These come after this one", remove: nil)
            section("Linked", linked, help: "Linked to this task") { model.unlink(.task($0), from: id) }
        }
        .popover(item: $picking, arrowEdge: .bottom) { kind in HoldPicker(task: id, kind: kind) { picking = nil }.environment(model) }
    }

    @ViewBuilder
    private func section(_ title: String, _ ids: [Int], help: String, remove: ((Int) -> Void)?) -> some View {
        if !ids.isEmpty {
            Text(title).kitType(.groupLabel).foregroundStyle(.secondary)
                .padding(.horizontal, Space.md).padding(.top, Space.sm)
                .help(help)
            ForEach(ids, id: \.self) { other in row(other, remove: remove) }
        }
    }

    private func row(_ other: Int, remove: ((Int) -> Void)?) -> some View {
        HStack(spacing: Space.sm) {
            if let task = model.task(other) {
                TaskGlyph(status: task.status)
                KeyLabel(key: task.key)
                Text(task.title.isEmpty ? "New task" : task.title)
                    .foregroundStyle(task.status == .done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if task.status == .done { Text("Done").kitType(.secondary).foregroundStyle(.secondary) }
            } else {
                Text("T-\(other), deleted").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let remove {
                Button("Remove", icon: .close) { remove(other) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .clickable()
                    .foregroundStyle(.tertiary)
                    .frame(width: Metric.rowAction, height: Metric.rowAction)
                    .help("Take this link off")
            }
        }
        .kitType(.title)
        .padding(.horizontal, Space.md)
        .frame(height: Metric.boxRow)
        .selectOpen(ModalRoute.task(other).selectionKey) { model.open(.task(other), push: true) }
        .uiTestAnchor("relation:\(other)")
    }

    private func add(_ title: String, _ kind: HoldPicker.Kind) -> some View {
        HStack(spacing: Space.sm) {
            KitIcon.new.image.foregroundStyle(.tertiary).frame(width: Metric.glyphSlot).accessibilityHidden(true)
            Button(title) { picking = kind }
                .buttonStyle(.borderless)
                .clickable()
                .disabled(model.task(id)?.status == .done)
                .uiTestAnchor("relation-add:\(title)")
        }
        .kitType(.title)
        .padding(.horizontal, Space.md)
        .frame(height: Metric.boxRow)
    }
}

/// The description in the modal: rendered with Edit, checkboxes tick in place, a double-click edits at the spot. Editing
/// swaps only the text for the editor, in the same place and the same width: nothing around it moves (T-368).
private struct DescriptionCard: View {
    let id: Int
    @Environment(AppModel.self) private var model
    /// The editor's text height, and the rendered text's: the editor opens as tall as what it replaces, then grows with its text.
    @State private var editorHeight: CGFloat = 0
    @State private var renderedHeight: CGFloat = 0

    var body: some View {
        @Bindable var model = model
        let editing = model.modalEditingDescription
        HStack(alignment: .top) {
            if editing {
                MarkdownEditor(text: $model.descriptionDraft, focusOnAppear: true, caretPoint: model.editorCaret, label: "Description",
                               onHeight: { editorHeight = $0 },
                               onCommit: { model.saveModalEdits() },
                               onCancel: { model.saveModalEdits() },
                               onEnd: { model.saveModalEdits() })
                    .frame(height: max(editorHeight > 0 ? editorHeight : renderedHeight, MarkdownStyle.lineHeight(.body)))
                    .onAppear { model.editorCaret = nil }
                    .onDisappear { editorHeight = 0 }
                    .uiTestAnchor("modal-description-editor")
            } else if let body = model.task(id)?.body, !body.isEmpty {
                MarkdownView(body) { index in model.toggleCheckbox(id, at: index) }
                    .background(EditOnDoubleClick { point in edit(at: point) })
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { renderedHeight = $0 }
                    .uiTestAnchor("modal-description")
            } else {
                Text("No description yet. Double-click to write one.").kitType(.callout).foregroundStyle(.secondary)
                    .background(EditOnDoubleClick { _ in edit(at: nil) })
            }
            Spacer(minLength: Space.sm)
            // One width for Edit and Done, so the text's width never changes.
            Button {
                if editing { model.saveModalEdits() } else { edit(at: nil) }
            } label: {
                ZStack {
                    Text("Edit").opacity(editing ? 0 : 1)
                    Text("Done").opacity(editing ? 1 : 0)
                }
            }
            .accessibilityLabel(editing ? "Done" : "Edit")
            .help(editing ? "Save the description (Escape or ⌘Return); ⌘Z undoes" : "Edit the description in markdown, or double-click it")
            .uiTestAnchor("modal-edit-description")
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(radius: Radius.card)
        .overlay {
            if editing {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Ink.accent).allowsHitTesting(false)
            }
        }
    }

    /// Edits the description: the caret under a point of the rendered text, else at the end.
    private func edit(at point: CGPoint?) {
        model.editorCaret = point
        model.descriptionDraft = model.task(id)?.body ?? ""
        model.modalEditingDescription = true
    }
}

/// A session on a task: face, name and state; × unlinks it.
struct SessionChip: View {
    let session: SessionItem
    var unlink: (() -> Void)?
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                    SessionFace(session, size: Metric.faceRow + Space.xs)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(session.name).kitType(.titleStrong).lineLimit(1)
                        Text(session.reason ?? session.status.title)
                            .kitType(.secondary)
                            .foregroundStyle(session.status.needsYou ? AnyShapeStyle(session.status.state == .failed ? Ink.failedText : Ink.needsYouText) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 240, alignment: .leading)
                }
            .selectOpen(ModalRoute.session(session.id).selectionKey) { model.open(.session(session.id), push: true) }
            if let unlink {
                Button("Unlink", icon: .unlink, action: unlink)
                    .clickable()
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .clickable()
                    .foregroundStyle(.tertiary)
                    .help("Unlink this session from the task")
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .surface(radius: Radius.row)
    }
}

/// Outputs as rows: kind or face, title, kind and time; under a task, × unlinks what was linked by hand.
struct OutputRows: View {
    let routes: [ModalRoute]
    var task: Int?
    @Environment(AppModel.self) private var model

    var body: some View {
        ModalBox {
            ForEach(routes, id: \.self) { route in
                HStack(spacing: Space.sm) {
                        kindIcon(route)
                        if let maker = model.maker(of: route) { SessionFace(maker, size: Metric.faceChip) }
                        Text(model.title(of: route))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(detail(route)).kitType(.secondary).foregroundStyle(.secondary).lineLimit(1)
                        if case .github(let url) = route { OpenOnGitHubButton(url: url) }
                        if let task, model.isLinked(route, to: task) {
                            Button("Unlink", icon: .close) { model.unlink(route, from: task) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .clickable()
                                .foregroundStyle(.tertiary)
                                .frame(width: Metric.rowAction, height: Metric.rowAction)
                                .help("Unlink it from the task")
                        }
                    }
                    .kitType(.title)
                    .padding(.horizontal, Space.md)
                    .frame(height: Metric.boxRow)
                .selectOpen(route.selectionKey) { model.open(route, push: true) }
                .contextMenu { if let task { LinkMenu(route: route, task: task) } }
                .uiTestAnchor("row:\(route.selectionKey)")
            }
        }
    }

    @ViewBuilder
    private func kindIcon(_ route: ModalRoute) -> some View {
        switch route {
        case .github(let url): if let item = model.githubItem(url) { GitHubStateIcon(item: item) }
        case .file: KitIcon.file.image.foregroundStyle(.secondary).frame(width: Metric.glyphSlot).accessibilityLabel("File")
        case .artifact: KitIcon.artifact.image.foregroundStyle(.secondary).frame(width: Metric.glyphSlot).accessibilityLabel("Artifact")
        case .web: KitIcon.link.image.foregroundStyle(.secondary).frame(width: Metric.glyphSlot).accessibilityLabel("Web page")
        case .slack: KitIcon.slack.image.foregroundStyle(.secondary).frame(width: Metric.glyphSlot).accessibilityLabel("Slack")
        default: EmptyView()
        }
    }

    private func detail(_ route: ModalRoute) -> String {
        switch route {
        case .file(let id): "File · " + (model.file(id)?.modified.formatted(.relative(presentation: .named)) ?? "")
        case .artifact(let url): "Artifact · " + (model.artifacts.first { $0.id == url }?.published.formatted(.relative(presentation: .named)) ?? "")
        // A PR says where it stands, as on the task's card: "PR · Approved · 2 hours ago" (T-393).
        case .github(let url): (model.githubItem(url)?.kind == .issue ? "Issue · " : "PR · ")
            + (model.githubItem(url).flatMap(GitHubStateIcon.status).map { $0.word + " · " } ?? "")
            + (model.githubItem(url)?.updatedAt.formatted(.relative(presentation: .named)) ?? "")
        case .web: "Link · opens in the browser"
        case .slack: "Slack · opens in Slack"
        default: ""
        }
    }
}

/// Link…: a task, a file, an artifact, a PR or an issue to link to the task, searched as the user types, or a pasted address.
struct LinkButton: View {
    let task: Int
    @State private var shown = false

    var body: some View {
        Button("Link…") { shown = true }
            .help("Link a task, a file, an artifact, a pull request or a web page to this task")
            .popover(isPresented: $shown, arrowEdge: .bottom) { LinkPicker(task: task) { shown = false } }
            .uiTestAnchor("link-button")
    }
}

/// Search, or paste a link: the matches as the user types, ↑ ↓ or the pointer to move, Return or a click to link one.
/// For a task, it links there; for a form being written (New Task…, New Reminder…), `pick` takes it.
struct LinkPicker: View {
    var task: Int?
    /// A form's links so far: not offered again.
    var linked: [ModalRoute] = []
    var pick: ((ModalRoute) -> Void)?
    let done: () -> Void
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    init(task: Int, done: @escaping () -> Void) {
        self.task = task
        self.done = done
    }

    init(linked: [ModalRoute], pick: @escaping (ModalRoute) -> Void, done: @escaping () -> Void) {
        self.linked = linked
        self.pick = pick
        self.done = done
    }

    var body: some View {
        let matches = Array((task.map { Self.matches(model, task: $0, query: query) } ?? Self.matches(model, query: query, leaving: Set(linked)))
            .prefix(Self.shown))
        VStack(alignment: .leading, spacing: Space.sm) {
            TextField("Search, or paste a link", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onChange(of: query) { index = 0 }
                .onKeyPress(.downArrow) { index = min(index + 1, max(matches.count - 1, 0)); return .handled }
                .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                .uiTestAnchor("link-picker")
                .onSubmit { if matches.indices.contains(index) { choose(matches[index]) } }
            ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element) { position, route in
                        Button { choose(route) } label: {
                            HStack(spacing: Space.sm) {
                                Group {
                                    switch route {
                                    case .github(let url): if let item = model.githubItem(url) { GitHubStateIcon(item: item) }
                                    case .file: KitIcon.file.image.foregroundStyle(.secondary)
                                    case .task(let id): if let task = model.task(id) { TaskGlyph(status: task.status) }
                                    case .web: KitIcon.link.image.foregroundStyle(.secondary)
                                    case .slack: KitIcon.slack.image.foregroundStyle(.secondary)
                                    case .artifact: KitIcon.artifact.image.foregroundStyle(.secondary)
                                    default: EmptyView()
                                    }
                                }
                                .frame(width: Metric.glyphSlot)
                                Text(Self.name(route, model)).kitType(.title).lineLimit(1)
                                Spacer(minLength: 0)
                                Text(Self.kind(route, model)).kitType(.meta).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, Space.sm)
                            .frame(height: Metric.boxRow)
                            .background(position == index ? Ink.rowSelection : Color.clear,
                                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .clickable()
                        .accessibilityAddTraits(position == index ? .isSelected : [])
                        .onHover { if $0 { index = position } }
                        .id(position)
                        .uiTestAnchor("link-match:\(route.selectionKey)")
                    }
                    if matches.isEmpty {
                        Text(query.isEmpty ? "Nothing left to link." : "No match for “\(query)”.")
                            .kitType(.callout).foregroundStyle(.secondary).padding(Space.xs)
                    }
                }
            }
            .onChange(of: index) { scroller.scrollTo(index) }
            }
            .frame(height: Metric.linkPicker)
        }
        .padding(Space.md)
        .frame(width: Metric.sheetWidth)
        .onAppear { focused = true }
    }

    static let shown = 40

    /// What a task can link: not itself, nothing linked already.
    static func matches(_ model: AppModel, task: Int, query: String) -> [ModalRoute] {
        matches(model, query: query) { $0 == .task(task) || model.isLinked($0, to: task) }
    }

    /// What a form being written can link: not what it links already.
    static func matches(_ model: AppModel, query: String, leaving linked: Set<ModalRoute>) -> [ModalRoute] {
        matches(model, query: query) { linked.contains($0) }
    }

    /// A pasted address first (T-298); then the task a key names; then tasks, files, artifacts, PRs and issues whose title
    /// (or key, or PR reference) has the query, newest first. Tasks only once something is typed.
    private static func matches(_ model: AppModel, query: String, leaving: (ModalRoute) -> Bool) -> [ModalRoute] {
        let text = query.trimmingCharacters(in: .whitespaces)
        func hit(_ words: String) -> Bool { text.isEmpty || words.localizedStandardContains(text) }
        var routes: [ModalRoute] = []
        if let url = URL(string: text), url.scheme == "https" || url.scheme == "http", url.host() != nil {
            routes.append(model.artifacts.first { $0.id == url }.map { .artifact($0.id) }
                          ?? (GitHubLinks.isItem(text) ? .github(text) : SlackLink.isLink(text) ? .slack(text) : .web(text)))
        }
        if text.uppercased().hasPrefix("T-") || Int(text) != nil, let id = TaskItem.key(text), model.task(id) != nil { routes.append(.task(id)) }
        let tasks = text.isEmpty ? [] : model.tasks.filter { $0.status != .done }.sorted { $0.modified > $1.modified }
            .filter { hit("\($0.key) \($0.title)") }.map { ModalRoute.task($0.id) }
        let files = model.files.sorted { $0.modified > $1.modified }.filter { hit($0.title) }.map { ModalRoute.file($0.id) }
        let artifacts = model.artifacts.sorted { $0.published > $1.published }.filter { hit($0.title) }.map { ModalRoute.artifact($0.id) }
        let github = (model.github?.items ?? []).filter { $0.state == .open || $0.state == .draft }
            .sorted { $0.updatedAt > $1.updatedAt }.filter { hit("\($0.title) \($0.reference)") }.map { ModalRoute.github($0.url) }
        var seen = Set<ModalRoute>()
        return (routes + tasks + files + artifacts + github).filter { !leaving($0) && seen.insert($0).inserted }
    }

    static func name(_ route: ModalRoute, _ model: AppModel) -> String {
        if case .task(let id) = route, let task = model.task(id) { return "\(task.key) \(task.title)" }
        return model.title(of: route)
    }

    static func kind(_ route: ModalRoute, _ model: AppModel) -> String {
        switch route {
        case .task: "Task"
        case .file: "File"
        case .artifact: "Artifact"
        case .github(let url): model.githubItem(url).map { "\($0.kind == .issue ? "Issue" : "PR") · \($0.reference)" } ?? "Link"
        case .web: "Link"
        case .slack: "Slack"
        default: ""
        }
    }

    private func choose(_ route: ModalRoute) {
        if let task { model.link(route, to: task) } else { pick?(route) }
        done()
    }
}

// MARK: Session

struct SessionModal: View {
    let id: String
    @Environment(AppModel.self) private var model

    var body: some View {
        if let session = model.session(id) {
            ModalPage {
                HStack(spacing: Space.lg) {
                    SessionFace(session, size: Metric.faceModal)
                        .task(id: id) { model.learnBackground(id) }
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(session.name).kitType(.pageTitle).lineLimit(2)
                        Text(session.place).kitType(.secondary).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        HStack(spacing: Space.xs + 2) {
                            SessionGlyph(kind: SessionGlyphKind(session.status))
                            Text(stateLine(session))
                                .kitType(.callout)
                                .fontWeight(session.status.needsYou ? .semibold : .medium)
                                .foregroundStyle(session.status.needsYou ? AnyShapeStyle(session.status.state == .failed ? Ink.failedText : Ink.needsYouText) : AnyShapeStyle(.primary))
                        }
                        .padding(.leading, Space.xs)
                        .padding(.trailing, Space.sm + 2)
                        .frame(height: Metric.statePill + Space.xs)
                        .background(session.status.needsYou ? AnyShapeStyle(session.status.state == .failed ? Ink.failedFill : Ink.needsYouFill) : AnyShapeStyle(Ink.labelFill), in: Capsule())
                    }
                }
                if session.status.needsYou { needsYouBox(session) }
                if session.isRunning, model.backgroundHandles[id] != nil {
                    Text("Running in the background (claude --bg), in no terminal of its own: Focus brings forward a Ghostty tab that shows it, when one does. Close Session stops it.")
                        .kitType(.callout).foregroundStyle(.secondary)
                } else if session.isRunning, let tty = session.tty, !session.inGhostty {
                    Text("Running in another terminal, \(tty): HQ can't bring it forward or close it.").kitType(.callout).foregroundStyle(.secondary)
                } else if session.isRunning, session.tty == nil {
                    Text("HQ doesn't know its terminal, so it can't bring it forward: it may run in an editor or the Claude app.")
                        .kitType(.callout).foregroundStyle(.secondary)
                }
                ModalGroup(title: "Works on") {
                    ModalBox {
                        let tasks = model.tasks(of: id)
                        ForEach(tasks) { task in
                            HStack(spacing: Space.sm) {
                                TaskGlyph(status: task.status)
                                Text(task.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    .selectOpen(ModalRoute.task(task.id).selectionKey) { model.open(.task(task.id), push: true) }
                                KeyLabel(key: task.key)
                                Button("Unlink", icon: .unlink) { model.unlink(task: task.id, session: id) }
                                    .clickable()
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                    .clickable()
                                    .foregroundStyle(.tertiary)
                                    .help("Unlink this task from the session")
                            }
                            .kitType(.title)
                            .padding(.horizontal, Space.md)
                            .frame(height: Metric.boxRow)
                        }
                        if tasks.isEmpty {
                            Text("On no task yet. Drop a task on its card.")
                                .kitType(.callout).foregroundStyle(.secondary)
                                .padding(.horizontal, Space.md).frame(height: Metric.boxRow)
                        }
                    }
                }
                let outputs = model.outputs(ofSession: id)
                if !outputs.isEmpty {
                    ModalGroup(title: "Made and linked") { OutputRows(routes: outputs) }
                }
                if let message = session.lastMessage, !message.isEmpty {
                    ModalGroup(title: "Last message") {
                        MarkdownView(message)
                            .padding(Space.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .surface(radius: Radius.card)
                    }
                }
                ModalGroup(title: "Details") {
                    ModalBox {
                        CopyableValue(label: "Directory", value: session.cwd)
                        if !session.branch.isEmpty { CopyableValue(label: "Branch", value: session.branch) }
                        CopyableValue(label: "Started", value: session.started.formatted(date: .abbreviated, time: .shortened))
                        CopyableValue(label: "Session ID", value: session.id)
                    }
                }
            }
        }
    }

    private func stateLine(_ session: SessionItem) -> String {
        guard session.isRunning else { return "Ended " + (session.closedAt ?? session.status.since).formatted(.relative(presentation: .named)) }
        return "\(session.status.title) · \(Elapsed.short(from: session.status.since, to: model.now))"
    }

    @ViewBuilder
    private func needsYouBox(_ session: SessionItem) -> some View {
        let failed = session.status.state == .failed
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(session.reason ?? session.status.title)
                .kitType(.titleStrong)
                .foregroundStyle(failed ? Ink.failedText : Ink.needsYouText)
            switch session.status.state {
            case .waiting(.question):
                ForEach(Array(session.options.enumerated()), id: \.offset) { index, option in
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Text("\(index + 1)").kitType(.meta).foregroundStyle(.secondary)
                        Text(option).kitType(.body)
                    }
                }
            case .waiting(.plan):
                if let plan = session.planPath.flatMap({ try? String(contentsOfFile: $0, encoding: .utf8) }) {
                    MarkdownView(plan)
                        .padding(Space.md)
                        .background(Ink.editor, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                }
            case .waiting(.permission):
                if let input = session.toolInput { CodeBlock(text: input, copies: true) }
            case .failed:
                Text("Nothing is lost: resume the session to carry on.").kitType(.callout).foregroundStyle(.secondary)
            default:
                EmptyView()
            }
            Text("Answer in its terminal: Focus.").kitType(.secondary).foregroundStyle(.secondary)
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(glow: failed ? Ink.failed : Ink.needsYou)
    }
}

// MARK: File

struct FileModal: View {
    let file: FileItem
    @Environment(AppModel.self) private var model
    /// The editor's text height, and the rendered text's: the editor opens as tall as what it replaces, then grows with its text.
    @State private var editorHeight: CGFloat = 0
    @State private var renderedHeight: CGFloat = 0

    var body: some View {
        @Bindable var model = model
        // Editing swaps only the text for the editor: the byline, labels and title stay where they are (T-368).
        ModalPage {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(byLine).kitType(.secondary).foregroundStyle(.secondary)
                ItemLabels(project: file.project, tags: file.tags, pinned: file.pinned,
                           setProject: { model.setFileLabels(file.id, project: .some($0)) },
                           setTags: { model.setFileLabels(file.id, tags: $0) },
                           setPinned: { model.setFileLabels(file.id, pinned: $0) })
            }
            let blocks = Markdown.blocks(model.fileBody(file.id))
            if case .heading(1, _) = blocks.first {} else {
                Text(file.title).kitType(.heading1)
            }
            if model.editingFile == file.id {
                MarkdownEditor(text: $model.fileDraft, focusOnAppear: true, caretPoint: model.editorCaret, label: file.title,
                               onHeight: { editorHeight = $0 },
                               onCommit: { model.saveModalEdits() }, onCancel: { model.saveModalEdits() }, onEnd: {})
                    .frame(height: max(editorHeight > 0 ? editorHeight : renderedHeight, MarkdownStyle.lineHeight(.body)))
                    .onAppear { model.editorCaret = nil }
                    .onDisappear { editorHeight = 0 }
                    .uiTestAnchor("file-editor")
            } else {
                MarkdownView(blocks: blocks) { index in model.toggleFileCheckbox(file.id, at: index) }
                    .background(EditOnDoubleClick { point in
                        model.editorCaret = point
                        model.beginFileEdit(file.id)
                    })
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { renderedHeight = $0 }
                    .uiTestAnchor("file-text")
            }
        }
        .uiTestAnchor("file-page")
    }

    private var byLine: String {
        let when = file.modified.formatted(.relative(presentation: .named))
        guard let maker = model.session(file.sessions.last) else { return "Edited \(when)" }
        return "Written by \(maker.name) · \(when)"
    }
}

// MARK: Artifact

/// An artifact's live page. claude.ai asks to sign in once; HQ keeps that sign-in apart from the browser's.
struct ArtifactReader: View {
    let artifact: ArtifactItem
    @Environment(AppModel.self) private var model
    @State private var load = ArtifactLoad.loading

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(load == .signIn ? "Sign in to claude.ai once to see artifacts in HQ." : model.artifactDetail(artifact))
                    .kitType(.secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: Space.md)
                let item = model.artifacts.first { $0.id == artifact.id } ?? artifact
                ItemLabels(project: item.project, tags: item.tags, pinned: item.pinned,
                           setProject: { model.setArtifactLabels(item.id, project: .some($0)) },
                           setTags: { model.setArtifactLabels(item.id, tags: $0) },
                           setPinned: { model.setArtifactLabels(item.id, pinned: $0) })
                    .fixedSize()
            }
            .padding(.horizontal, Space.lg)
            .frame(height: Metric.boxRow)
            Divider()
            ArtifactWebView(url: artifact.id, standIn: Self.standIn(artifact), state: $load, reloads: model.artifactReloads,
                            onTitle: { model.setArtifactTitle(artifact.id, $0) })
                .overlay { overlay }
                .reportsLoading(load, page: artifact.id.absoluteString)
                .uiTestAnchor("artifact-page")
                // Only the page is white: the sky shows behind the line above it.
                .background(Ink.text)
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch load {
        case .failed(let message):
            ContentUnavailableView {
                Label("Can’t Load This Artifact", icon: .problem)
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { model.artifactReloads += 1 }
                Button("Open in Browser") { NSWorkspace.shared.open(artifact.id) }
            }
            .background(Ink.text)
        case .loading, .shown, .signIn:
            EmptyView()
        }
    }

    /// Test runs show a stand-in, unless HQ_WEB=1 lets them reach claude.ai.
    private static func standIn(_ artifact: ArtifactItem) -> String? {
        guard Store.isOverridden, ProcessInfo.processInfo.environment["HQ_WEB"] != "1" else { return nil }
        return SeedData.artifactPage(artifact)
    }
}

extension AppModel {
    /// The session that published an artifact, and when.
    func artifactDetail(_ artifact: ArtifactItem) -> String {
        let date = artifact.published.formatted(date: .abbreviated, time: .shortened)
        guard let name = session(artifact.session)?.name else { return date }
        return "Published by \(name) · \(date)"
    }
}

extension View {
    /// Tells the modal's Reload that this page loads.
    func reportsLoading(_ load: ArtifactLoad, page: String) -> some View {
        modifier(LoadingReport(loading: load == .loading, page: page))
    }
}

private struct LoadingReport: ViewModifier {
    let loading: Bool
    let page: String
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content
            .onChange(of: loading, initial: true) { _, loading in
                let next = loading ? page : model.loadingPage == page ? nil : model.loadingPage
                if model.loadingPage != next { model.loadingPage = next }
            }
            .onDisappear { if model.loadingPage == page { model.loadingPage = nil } }
    }
}

// MARK: GitHub

struct GitHubModal: View {
    let item: GitHubItem
    @Environment(AppModel.self) private var model
    @State private var load = ArtifactLoad.loading

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.sm) {
                    HStack(spacing: Space.xs) {
                        GitHubStateIcon(item: item)
                        Text(item.state.rawValue.capitalized).kitType(.callout)
                    }
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, Metric.lineGap)
                    .background(Ink.boxFill, in: Capsule())
                    .fixedSize()
                    Text(summary)
                        .kitType(.secondary).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: Space.md)
                    linked
                }
                if model.waitsForReview(item) {
                    HStack(spacing: Space.md) {
                        Text("\(item.author) asked for your review \(item.reviewAskedAt.formatted(.relative(presentation: .named)))")
                            .kitType(.titleStrong).foregroundStyle(Ink.needsYouText).lineLimit(1)
                        Spacer(minLength: Space.sm)
                        Button("Start Review Session…") { model.beginStart(pullRequest: item, push: true) }
                            .help("Start a Claude session that reviews this PR")
                    }
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
                    .surface(glow: Ink.needsYou)
                }
                if load == .signIn {
                    Text("Sign in to GitHub once to see pull requests here; HQ keeps it apart from your browser.")
                        .kitType(.secondary).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
            Divider()
            // At the review or comment a notification told of, else the PR (T-328).
            if let url = URL(string: model.githubPage.flatMap { $0.pr == item.url ? $0.page : nil } ?? item.url) {
                GitHubWebView(url: url, standIn: Self.standIn(item), state: $load, reloads: model.artifactReloads, onSubmit: { model.pollGitHubSoon() })
                    .overlay { overlay(url) }
                    .reportsLoading(load, page: item.url)
                    .uiTestAnchor("github-page")
                    .background(Ink.text)
            }
        }
    }

    /// "julien · retry-budget · Approved by anna · 5 checks passed": the modal's title names it.
    private var summary: String {
        var parts = [item.author]
        if let branch = item.headBranch { parts.append(branch) }
        if item.kind == .pullRequest {
            parts.append(reviewText)
            let failed = item.checkRuns.filter { $0.checks == .failed }.count
            let running = item.checkRuns.filter { $0.checks == .running }.count
            if failed > 0 {
                parts.append("\(failed) of \(item.checkRuns.count) checks failed")
            } else if running > 0 {
                parts.append("\(running) of \(item.checkRuns.count) checks running")
            } else if !item.checkRuns.isEmpty {
                parts.append("\(item.checkRuns.count) checks passed")
            }
        }
        return parts.joined(separator: " · ")
    }

    /// Its tasks and sessions, and Link to add one.
    private var linked: some View {
        HStack(spacing: Space.sm) {
            ForEach(model.tasks(linking: item.url)) { task in
                Button { model.open(.task(task.id), push: true) } label: {
                    HStack(spacing: Space.xs) {
                        TaskGlyph(status: task.status)
                        Text(task.key).kitType(.key).foregroundStyle(.secondary)
                        Text(task.title).lineLimit(1)
                    }
                    .kitType(.callout)
                    .frame(maxWidth: Metric.linkedTaskMax)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .clickable()
                .help("Open \(task.key) \(task.title)")
            }
            ForEach(model.sessions(onPullRequest: item)) { session in
                SessionFace(session, size: Metric.faceChip + Space.xs)
            }
            Menu {
                Menu("Link to Task") {
                    ForEach(model.taskTree.outline(.overview).compactMap { model.task($0) }) { task in
                        Button("\(task.key) \(task.title)") { if let url = URL(string: item.url) { model.link(task: task.id, url: url) } }
                    }
                }
                Menu("Link to Session") {
                    ForEach(model.gridSessions) { session in
                        Button(session.name) { model.link(pullRequest: item.url, session: session.id) }
                    }
                }
            } label: {
                Label("Link", icon: .link)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .clickable()
            .help("Link it to a task or a session")
        }
    }

    @ViewBuilder
    private func overlay(_ url: URL) -> some View {
        if case .failed(let message) = load {
            ContentUnavailableView {
                Label("Can’t Load This Page", icon: .problem)
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { model.artifactReloads += 1 }
                Button("Open on GitHub") { NSWorkspace.shared.open(url) }
            }
            .background(Ink.text)
        }
    }

    private var reviewText: String {
        if item.state == .draft { return "Draft" }
        switch item.review {
        case .approved: return "Approved" + (item.reviewers.isEmpty ? "" : " by \(item.reviewers.joined(separator: ", "))")
        case .changesRequested: return "Changes requested" + (item.reviewers.isEmpty ? "" : " by \(item.reviewers.joined(separator: ", "))")
        case .required, .none: return "Review required"
        }
    }

    /// Test runs show a stand-in, unless HQ_WEB=1 lets them reach github.com.
    private static func standIn(_ item: GitHubItem) -> String? {
        guard Store.isOverridden, ProcessInfo.processInfo.environment["HQ_WEB"] != "1" else { return nil }
        return SeedData.githubPage(item)
    }
}

// MARK: Start a session

struct StartSessionForm: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if let draft = model.startDraft {
            VStack(alignment: .leading, spacing: Space.lg) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.lg, verticalSpacing: Space.md) {
                    GridRow {
                        Text("Name").kitType(.callout).foregroundStyle(.secondary).frame(width: Metric.propertyLabel, alignment: .leading)
                        TextField("Session name", text: Binding(get: { draft.name }, set: { model.startDraft?.name = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { model.startFromDraft() }
                    }
                    GridRow {
                        Text("Folder").kitType(.callout).foregroundStyle(.secondary).frame(width: Metric.propertyLabel, alignment: .leading)
                        Picker("Folder", selection: Binding(get: { draft.folder }, set: { value in
                            if value == "\u{0}choose" { choose() } else { model.startDraft?.folder = value }
                        })) {
                            ForEach(folders(draft), id: \.self) { Text(($0 as NSString).abbreviatingWithTildeInPath).tag($0) }
                            Divider()
                            Text("Choose…").tag("\u{0}choose")
                        }
                        .labelsHidden()
                        .fixedSize()
                        .clickable()
                    }
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("First message").kitType(.groupLabel).foregroundStyle(.secondary)
                    MarkdownEditor(text: Binding(get: { model.startDraft?.message ?? "" }, set: { model.startDraft?.message = $0 }),
                                   focusOnAppear: true, label: "First message", inset: Space.sm, onCommit: { model.startFromDraft() }, onCancel: { model.closeModal() })
                        .frame(minHeight: Metric.messageEditor)
                        .background(Ink.editor, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Ink.boxFrame))
                        .uiTestAnchor("start-message")
                    Text("Sent as the first prompt. Add context here; the task stays as it is.")
                        .kitType(.secondary).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { model.closeModal() }
                    Button("Start") { model.startFromDraft() }
                        .buttonStyle(.glassProminent)
                        .clickable()
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Start the session in a new Ghostty tab (⌘Return)")
                        .uiTestAnchor("start-button")
                }
            }
            .padding(Space.xxl)
            .frame(maxWidth: Metric.pageWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private func folders(_ draft: StartDraft) -> [String] {
        var list = model.recentDirectories(for: draft.task)
        if !list.contains(draft.folder) { list.insert(draft.folder, at: 0) }
        return list
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { model.startDraft?.folder = url.path }
    }
}

// MARK: Closed Sessions

struct ClosedSessionsModal: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ModalPage {
            ModalGroup(title: "Closed in the last 14 days") { rows(model.closedSessions) }
        }
    }

    private func rows(_ sessions: [SessionItem]) -> some View {
        ModalBox {
            ForEach(sessions) { session in
                HStack(spacing: Space.sm) {
                    SessionFace(session, size: Metric.faceRow + Space.xs)
                    Button { model.open(.session(session.id), push: true) } label: {
                        Text(session.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .clickable()
                    Text(session.closedAt.map { "Closed " + $0.formatted(.relative(presentation: .named)) } ?? session.status.title)
                        .kitType(.secondary).foregroundStyle(.secondary).lineLimit(1)
                    Button("Resume") { model.open(session.id) }
                        .help("Resume it in a new Ghostty tab")
                }
                .kitType(.title)
                .padding(.horizontal, Space.md)
                .frame(height: Metric.boxRow + Space.xs)
            }
            if sessions.isEmpty {
                Text("None.").kitType(.callout).foregroundStyle(.secondary).padding(.horizontal, Space.md).frame(height: Metric.boxRow)
            }
        }
    }
}
