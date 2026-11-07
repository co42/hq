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
    @State private var subtaskDraft = ""
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
                properties(task)
                ModalGroup(title: "On it") { onIt(task) }
                ModalGroup(title: "Description") { DescriptionCard(id: id) }
                ModalGroup(title: "Subtasks") { subtasks(task) }
                ModalGroup(title: "Files, artifacts, PRs and issues") {
                    let outputs = model.outputs(ofTask: id)
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
        ModalBox {
            ForEach(model.taskTree.children(of: id).compactMap { model.task($0) }) { sub in
                HStack(spacing: Space.sm) {
                    Button { model.toggleDone(sub.id) } label: { TaskGlyph(status: sub.status) }
                        .buttonStyle(.plain)
                        .clickable()
                        .help(sub.status == .done ? "Mark not done" : "Mark done")
                        .accessibilityLabel(sub.title.isEmpty ? "New task" : sub.title)
                        .accessibilityValue(sub.status.title)
                        .accessibilityAddTraits(.isToggle)
                    Text(sub.title.isEmpty ? "New task" : sub.title)
                        .foregroundStyle(sub.status == .done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .selectOpen(ModalRoute.task(sub.id).selectionKey) { model.open(.task(sub.id), push: true) }
                    KeyLabel(key: sub.key)
                }
                .kitType(.title)
                .padding(.horizontal, Space.md)
                .frame(height: Metric.boxRow)
            }
            HStack(spacing: Space.sm) {
                KitIcon.new.image.foregroundStyle(.tertiary).frame(width: Metric.glyphSlot).accessibilityHidden(true)
                TextField("Add subtask", text: $subtaskDraft)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        guard !subtaskDraft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        if let added = model.addSubtask(to: id) { model.setTitle(added.id, subtaskDraft) }
                        subtaskDraft = ""
                    }
            }
            .kitType(.title)
            .padding(.horizontal, Space.md)
            .frame(height: Metric.boxRow)
        }
    }
}

/// The description in the modal: rendered with Edit, checkboxes tick in place.
private struct DescriptionCard: View {
    let id: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Space.sm) {
            if model.modalEditingDescription {
                MarkdownEditor(text: $model.descriptionDraft, focusOnAppear: true, label: "Description",
                               onCommit: { model.saveModalEdits() },
                               onCancel: { model.saveModalEdits() },
                               onEnd: { model.saveModalEdits() })
                    .frame(minHeight: Metric.editorMin * 1.5)
                    .background(Ink.editor, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Ink.boxFrame))
                HStack {
                    Text("Markdown · Escape or ⌘Return saves, ⌘Z undoes").kitType(.secondary).foregroundStyle(.secondary)
                    Spacer()
                    Button("Done") { model.saveModalEdits() }.help("Save the description (⌘Return)")
                }
            } else {
                HStack(alignment: .top) {
                    if let body = model.task(id)?.body, !body.isEmpty {
                        MarkdownView(body) { index in model.toggleCheckbox(id, at: index) }
                    } else {
                        Text("No description yet.").kitType(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Space.sm)
                    Button("Edit") {
                        model.descriptionDraft = model.task(id)?.body ?? ""
                        model.modalEditingDescription = true
                    }
                    .help("Edit the description in markdown")
                    .uiTestAnchor("modal-edit-description")
                }
                .padding(Space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface(radius: Radius.card)
            }
        }
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
        default: EmptyView()
        }
    }

    private func detail(_ route: ModalRoute) -> String {
        switch route {
        case .file(let id): "File · " + (model.file(id)?.modified.formatted(.relative(presentation: .named)) ?? "")
        case .artifact(let url): "Artifact · " + (model.artifacts.first { $0.id == url }?.published.formatted(.relative(presentation: .named)) ?? "")
        case .github(let url): (model.githubItem(url)?.kind == .issue ? "Issue · " : "PR · ") + (model.githubItem(url)?.updatedAt.formatted(.relative(presentation: .named)) ?? "")
        case .web: "Link · opens in the browser"
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

struct LinkPicker: View {
    let task: Int
    let done: () -> Void
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        let matches = Self.matches(model, task: task, query: query)
        VStack(alignment: .leading, spacing: Space.sm) {
            TextField("Search, or paste a link", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .uiTestAnchor("link-picker")
                .onSubmit { if let first = matches.first { pick(first) } }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(matches.prefix(Self.shown), id: \.self) { route in
                        Button { pick(route) } label: {
                            HStack(spacing: Space.sm) {
                                Group {
                                    switch route {
                                    case .github(let url): if let item = model.githubItem(url) { GitHubStateIcon(item: item) }
                                    case .file: KitIcon.file.image.foregroundStyle(.secondary)
                                    case .task(let id): if let task = model.task(id) { TaskGlyph(status: task.status) }
                                    case .web: KitIcon.link.image.foregroundStyle(.secondary)
                                    case .artifact: KitIcon.artifact.image.foregroundStyle(.secondary)
                                    default: EmptyView()
                                    }
                                }
                                .frame(width: Metric.glyphSlot)
                                Text(Self.name(route, model)).kitType(.title).lineLimit(1)
                                Spacer(minLength: 0)
                                Text(Self.kind(route, model)).kitType(.meta).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, Space.xs)
                            .frame(height: Metric.boxRow)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .clickable()
                    }
                    if matches.isEmpty {
                        Text(query.isEmpty ? "Nothing left to link." : "No match for “\(query)”.")
                            .kitType(.callout).foregroundStyle(.secondary).padding(Space.xs)
                    }
                }
            }
            .frame(height: Metric.linkPicker)
        }
        .padding(Space.md)
        .frame(width: Metric.sheetWidth)
        .onAppear { focused = true }
    }

    static let shown = 40

    /// A pasted address first (T-298); then the task a key names; then tasks, files, artifacts, PRs and issues whose title
    /// (or key, or PR reference) has the query, newest first. Tasks only once something is typed. Nothing linked already.
    static func matches(_ model: AppModel, task: Int, query: String) -> [ModalRoute] {
        let text = query.trimmingCharacters(in: .whitespaces)
        func hit(_ words: String) -> Bool { text.isEmpty || words.localizedStandardContains(text) }
        var routes: [ModalRoute] = []
        if let url = URL(string: text), url.scheme == "https" || url.scheme == "http", url.host() != nil {
            routes.append(model.artifacts.first { $0.id == url }.map { .artifact($0.id) }
                          ?? (GitHubLinks.isItem(text) ? .github(text) : .web(text)))
        }
        if text.uppercased().hasPrefix("T-") || Int(text) != nil, let id = TaskItem.key(text), model.task(id) != nil { routes.append(.task(id)) }
        let tasks = text.isEmpty ? [] : model.tasks.filter { $0.status != .done }.sorted { $0.modified > $1.modified }
            .filter { hit("\($0.key) \($0.title)") }.map { ModalRoute.task($0.id) }
        let files = model.files.sorted { $0.modified > $1.modified }.filter { hit($0.title) }.map { ModalRoute.file($0.id) }
        let artifacts = model.artifacts.sorted { $0.published > $1.published }.filter { hit($0.title) }.map { ModalRoute.artifact($0.id) }
        let github = (model.github?.items ?? []).filter { $0.state == .open || $0.state == .draft }
            .sorted { $0.updatedAt > $1.updatedAt }.filter { hit("\($0.title) \($0.reference)") }.map { ModalRoute.github($0.url) }
        var seen = Set<ModalRoute>()
        return (routes + tasks + files + artifacts + github).filter { $0 != .task(task) && !model.isLinked($0, to: task) && seen.insert($0).inserted }
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
        default: ""
        }
    }

    private func pick(_ route: ModalRoute) {
        model.link(route, to: task)
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
                if session.isRunning, let tty = session.tty, !session.inGhostty {
                    Text("Running in another terminal, \(tty): HQ can't bring it forward.").kitType(.callout).foregroundStyle(.secondary)
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

    var body: some View {
        @Bindable var model = model
        if model.editingFile == file.id {
            // The page's column: the text starts and wraps where the view's does.
            MarkdownEditor(text: $model.fileDraft, focusOnAppear: true, label: file.title,
                           onCommit: { model.saveModalEdits() }, onCancel: { model.saveModalEdits() }, onEnd: {})
                .frame(maxWidth: Metric.pageWidth + Space.sm * 2)
                .padding(.horizontal, Space.xxl - Space.sm)
                .padding(.vertical, Space.xl - Space.sm)
                .frame(maxWidth: .infinity)
                .uiTestAnchor("file-editor")
        } else {
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
                MarkdownView(blocks: blocks) { index in model.toggleFileCheckbox(file.id, at: index) }
            }
            .uiTestAnchor("file-page")
        }
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
                GitHubWebView(url: url, standIn: Self.standIn(item), state: $load, reloads: model.artifactReloads)
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
                                   focusOnAppear: true, prose: true, onCommit: { model.startFromDraft() }, onCancel: { model.closeModal() })
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
