import AppKit
import HQKit
import SwiftUI

/// The modal (DESIGN.md §8): a sheet over the page, about 88% of the window, with Close, Back and the kind's actions.
struct ModalHost: View {
    @Environment(AppModel.self) private var model
    /// The route and Back stack last shown: the sheet keeps them while it animates out, so it never
    /// flashes empty or jumps to another size.
    @State private var shown: (route: ModalRoute, stack: [ModalRoute])?
    /// The content takes Escape itself: a form's Cancel, the center's reminder editor.
    @State private var contentEscapes = false
    /// The PR or issue last shown: a poll that no longer brings it leaves its page as it was.
    @State private var kept: GitHubItem?

    private var route: ModalRoute? { model.modal ?? shown?.route }

    var body: some View {
        let route = route
        let page: GitHubItem? = if case .github(let url) = route { model.githubItem(url) ?? (kept?.url == url ? kept : nil) } else { nil }
        let small = route == .closedSessions
        // Never bigger than the window, at any zoom (T-544); a form's fields scroll there, its buttons stay (T-564).
        let room = CGSize(width: model.windowSize.width > 0 ? model.windowSize.width : Metric.modalMin.width,
                          height: model.windowSize.height > 0 ? model.windowSize.height : Metric.modalMin.height)
        let size = switch route {
        case .start: Metric.startSheet
        case .newTask: Metric.taskSheet
        case .newReminder: Metric.reminderSheet
        case .newFile: Metric.fileSheet
        case .importArtifact: Metric.importSheet
        default: small ? Metric.modalMin : CGSize(width: max(Metric.modalMin.width, (model.windowSize.width * Metric.modalShare).rounded()),
                                                  height: max(Metric.modalMin.height, (model.windowSize.height * Metric.modalShare).rounded()))
        }
        VStack(spacing: 0) {
            ModalHeader(route: route, page: page, stack: model.modal == nil ? shown?.stack ?? [] : model.modalStack, escapes: !contentEscapes)
            Group {
                switch route {
                case .task(let id): if model.task(id) != nil { TaskModal(id: id).id(id) } else { gone }
                case .session(let id): if model.session(id) != nil { SessionModal(id: id).id(id) } else { gone }
                case .file(let id): if let file = model.file(id) { FileModal(file: file).id(id) } else { gone }
                case .artifact(let url):
                    if let artifact = model.artifacts.first(where: { $0.id == url }) { ArtifactReader(artifact: artifact).id(url) } else { gone }
                case .github(let url): if let page { GitHubModal(item: page).id(url) } else { gone }
                // A web page or a Slack link opens outside HQ, never here.
                case .web, .slack: gone
                case .newTask(let status): NewTaskForm(status: status)
                case .newReminder: NewReminderForm(about: model.reminderAbout)
                case .newFile: NewFileForm()
                case .importArtifact: ImportArtifactForm()
                case .start: StartSessionForm()
                case .closedSessions: ClosedSessionsModal()
                case .roles: RolesModal()
                case .notifications: NotificationCenterView()
                case .archive: ArchiveView()
                case .archivedTask(let id): ArchivedTaskView(id: id).id(id)
                case .block(let block): ExpandedBlockView(block: block).id(block.id)
                case nil: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: min(size.width, room.width), height: min(size.height, room.height))
        .background(alignment: .top) {
            // The item's own sky: warm while it needs the user.
            ZStack(alignment: .top) {
                Ink.content
                SkyView(mood: model.mood(of: route))
                    .opacity(0.7)
            }
        }
        .environment(\.inModal, true)
        .environment(\.modalRoute, route)
        .onPreferenceChange(OwnsEscape.self) { contentEscapes = $0 }
        .noInitialFocus()
        .handCursors()
        .controlSize(Zoom.controlSize(model.zoom))
        .id(model.zoom)
        .gridArea("modal", inset: 0)
        .onChange(of: page, initial: true) { _, page in if let page { kept = page } }
        .onChange(of: model.modal, initial: true) { _, next in
            if let next {
                shown = (next, model.modalStack)
            } else {
                model.modalSelection = nil
                // Once the sheet is gone, nothing is drawn: a host SwiftUI keeps around stays cheap.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.6))
                    if model.modal == nil { shown = nil }
                }
            }
        }
        .onChange(of: model.modalStack) { _, next in
            if let modal = model.modal { shown = (modal, next) }
        }
    }

    private var gone: some View {
        ContentUnavailableView("This Item Is Gone", icon: .trash)
            .onAppear { Snapshot.goneShown += 1 }
    }
}

extension EnvironmentValues {
    /// Inside the modal: a row selects there, not on the page.
    @Entry var inModal = false
    /// The modal's item: its page keeps its scroll for Back (T-490).
    @Entry var modalRoute: ModalRoute?
}

/// The modal's content takes Escape itself (a form's Cancel goes back, an inline editor cancels): the header's Close doesn't.
struct OwnsEscape: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// Close, Back, the title, then the kind's actions.
private struct ModalHeader: View {
    let route: ModalRoute?
    /// The PR or issue shown, kept when a poll drops it.
    let page: GitHubItem?
    let stack: [ModalRoute]
    /// Escape closes the modal, unless its content takes Escape.
    let escapes: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        // An expanded block over a note or a task: Escape goes back to it, as a form over an item does (T-490).
        let escapesBack: Bool = if case .block = route, !stack.isEmpty { escapes } else { false }
        HStack(spacing: Space.sm) {
            Button("Close", icon: .close) { model.closeModal() }
                .labelStyle(.iconOnly)
                .buttonStyle(ModalButtonStyle(circle: true))
                .clickable()
                .keyboardShortcut(escapes && !escapesBack ? .cancelAction : nil)
                .help(escapes && !escapesBack ? "Close (Escape)" : "Close")
                .uiTestAnchor("modal-close")
            if let previous = stack.last {
                Button { model.back() } label: {
                    HStack(spacing: Space.xs) {
                        KitIcon.back.image
                        Text(backTitle(previous)).lineLimit(1).truncationMode(.tail)
                    }
                    .frame(maxWidth: 220).fixedSize(horizontal: true, vertical: false)
                }
                .keyboardShortcut(escapesBack ? .cancelAction : nil)
                .help("Back to \(model.title(of: previous)) (\(escapesBack ? "Escape" : "⌘["))")
                .uiTestAnchor("modal-back")
            }
            Text(title)
                .kitType(.header)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, Space.xs)
            Spacer(minLength: Space.sm)
            // The kind's actions float as one glass group, as a toolbar's do.
            GlassEffectContainer(spacing: Space.sm) {
                HStack(spacing: Space.sm) { ModalActions(route: route, page: page) }
            }
        }
        // One height for every control: buttons, menus and icons (2026-11-18, T-569).
        .buttonStyle(ModalButtonStyle())
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .padding(.horizontal, Metric.modalEdge)
        .frame(height: Metric.modalHeader)
    }

    private var title: String {
        switch route {
        case .task(let id): model.task(id)?.key ?? "Task"
        case .session: "Session"
        case .file: "File"
        case .artifact: "Artifact"
        case .github: page.map { $0.kind == .issue ? "Issue \($0.reference)" : "Pull Request \($0.reference)" } ?? "GitHub"
        case .web: "Link"
        case .slack: "Slack"
        case .newTask: "New Task"
        case .newReminder: "New Reminder"
        case .newFile: "New File"
        case .importArtifact: "Import an Artifact"
        case .start: "Start a Session"
        case .closedSessions: "Closed Sessions"
        case .roles: "Roles"
        case .notifications: "Notifications"
        case .archive: "Archive"
        case .archivedTask(let id): "T-\(id)"
        case .block(let block): block.title
        case nil: ""
        }
    }

    private func backTitle(_ route: ModalRoute) -> String {
        switch route {
        case .task(let id): "T-\(id) \(model.title(of: route))"
        default: model.title(of: route)
        }
    }
}

/// The open item's actions (DESIGN.md §8): icons, one prominent action, then ⋯, its right-click menu.
private struct ModalActions: View {
    let route: ModalRoute?
    let page: GitHubItem?
    @Environment(AppModel.self) private var model

    var body: some View {
        switch route {
        case .task(let id):
            if model.task(id) != nil {
                RemindMeButton(route: .task(id))
                CopyItemButton(route: .task(id))
                if let session = model.byImportance(model.sessions(on: id)).first(where: \.isRunning), session.tty != nil {
                    Button("Focus") { model.open(session.id) }
                        .buttonStyle(ModalButtonStyle(prominent: true))
                        .help("Bring \(session.name)’s terminal forward")
                        .uiTestAnchor("task-main-action")
                } else {
                    Button("Start Session…") { model.beginStart(task: id, push: true) }
                        .buttonStyle(ModalButtonStyle(prominent: true))
                        .help("Start a Claude session on this task (⌥⌘Return)")
                        .uiTestAnchor("task-main-action")
                }
                ModalMore(anchor: "task-more") { TaskMenu(ids: [id]) }
            }
        case .session(let id):
            if let session = model.session(id) {
                // What it runs on, "Opus VH · 442k" (T-446, T-475); Model ▸ and Effort ▸ are in ⋯.
                if session.isRunning, let line = session.modelLine {
                    Text(line)
                        .kitType(.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .help(session.modelHelp ?? "")
                        .uiTestAnchor("session-model")
                }
                Button("Randomize Face", icon: .randomize) { model.randomizeFace(id) }
                    .labelStyle(.iconOnly)
                    .clickable()
                    .help("Give it another face")
                    .uiTestAnchor("randomize-face")
                CopyItemButton(route: .session(id))
                Button(session.isRunning ? "Focus" : "Resume") { model.open(id) }
                    .disabled(session.isRunning && session.tty == nil)
                    .buttonStyle(ModalButtonStyle(prominent: true))
                    .clickable()
                    .help(session.isRunning ? "Bring its terminal forward (⌘O)" : "Resume it in a new Ghostty tab (⌘O)")
                    .uiTestAnchor("session-main-action")
                ModalMore(anchor: "session-more") { SessionMenu(session: session) }
            }
        case .file(let id):
            if model.file(id) != nil {
                if model.editingFile == id {
                    Button("Cancel") { model.editingFile = nil }.help("Drop the changes")
                    Button("Save") { model.saveModalEdits() }
                        .buttonStyle(ModalButtonStyle(prominent: true))
                        .clickable()
                        .help("Save the changes (Escape or ⌘Return)")
                } else {
                    RemindMeButton(route: .file(id))
                    CopyItemButton(route: .file(id))
                    Button("Edit") { model.beginFileEdit(id) }
                        .buttonStyle(ModalButtonStyle(prominent: true))
                        .clickable()
                        .help("Edit the note in markdown (⌘E)")
                        .uiTestAnchor("file-edit")
                    ModalMore(anchor: "file-more") { OutputMenu(route: .file(id)) }
                }
            }
        case .artifact(let url):
            ReloadButton(page: url.absoluteString)
            RemindMeButton(route: .artifact(url))
            CopyItemButton(route: .artifact(url))
            Button("Open in Browser") { NSWorkspace.shared.open(url) }
                .buttonStyle(ModalButtonStyle(prominent: true))
                .clickable()
                .help("Open the artifact in the browser (⇧⌘O)")
                .uiTestAnchor("artifact-main-action")
            ModalMore(anchor: "artifact-more") { OutputMenu(route: .artifact(url)) }
        case .github(let url):
            if let item = page {
                ReloadButton(page: url)
                RemindMeButton(route: .github(url))
                CopyItemButton(route: .github(url))
                // Next Review while Reviews lists another PR, else Open on GitHub (T-456).
                if let next = model.nextReview(after: url) {
                    Button("Next Review") { model.goToNextReview(from: url) }
                        .buttonStyle(ModalButtonStyle(prominent: true))
                        .clickable()
                        .help("Open the next PR of Reviews: \(model.title(of: .github(next.url)))")
                        .uiTestAnchor("next-review")
                } else {
                    Button("Open on GitHub") { if let link = URL(string: url) { NSWorkspace.shared.open(link) } }
                        .buttonStyle(ModalButtonStyle(prominent: true))
                        .clickable()
                        .help("Open it on github.com (⇧⌘O)")
                }
                ModalMore(anchor: "github-more") { PullRequestMenu(item: item) }
            }
        case .roles:
            // The picked role's actions, in the File modal's order; while editing, Cancel and Save.
            if let role = model.pickedRole {
                if model.roleEdit != nil {
                    Button("Cancel") { model.cancelRoleEdit() }.help("Drop the changes (Escape in a name or a line)")
                        .uiTestAnchor("role-cancel")
                    Button("Save") { model.commitRoleEdit() }
                        .buttonStyle(ModalButtonStyle(prominent: true))
                        .clickable()
                        .help("Save the changes (Return in a name or a line; Escape or ⌘Return in the text)")
                        .uiTestAnchor("role-save")
                } else {
                    CopyButton(text: { model.line(ofRole: role) }, title: "Copy", icon: .copy, done: "Copied",
                               help: "Copy \u{201C}\(model.line(ofRole: role))\u{201D}", anchor: "copy-item")
                    Button("Edit") { model.beginRoleEdit(.text) }
                        .buttonStyle(ModalButtonStyle(prominent: true))
                        .clickable()
                        .help("Edit what a session with this role gets (⌘E)")
                        .uiTestAnchor("role-edit")
                    ModalMore(anchor: "role-more") { RoleMenu(role: role) }
                }
            }
        case .archivedTask(let id):
            // Read only: Copy, Unarchive (its story, for a task under one), prominent, then ⋯.
            let story = model.archiveShown?.index.entry(id)?.root ?? id
            CopyItemButton(route: .archivedTask(id))
            Button(story == id ? "Unarchive" : "Unarchive T-\(story)", icon: .unarchive) { model.unarchiveFromWindow(story) }
                .labelStyle(.titleAndIcon)
                .buttonStyle(ModalButtonStyle(prominent: true))
                .clickable()
                .help("Bring it back to Tasks, at the end of the list (⌃⌘A)")
                .uiTestAnchor("unarchive-task")
            ModalMore(anchor: "archived-more") { ArchivedMenu(id: id) }
        case .block(let block):
            ExpandedActions(block: block)
        case .archive, .notifications, .start, .closedSessions, .web, .slack, .newTask, .newReminder, .newFile, .importArtifact, nil:
            EmptyView()
        }
    }
}

/// ⋯ at the far right of a header: the item's right-click menu, from the same builder; its pickers open under it.
private struct ModalMore<Items: View>: View {
    let anchor: String
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu { items() } label: { KitIcon.more.image }
            .accessibilityLabel("More")
            .fixedSize()
            .help("More")
            .menuPicks()
            .uiTestAnchor(anchor)
    }
}

/// An expanded block's actions (T-490): a table's row count and Copy, a diagram's zoom and Copy Source.
private struct ExpandedActions: View {
    let block: ExpandedBlock
    @Environment(AppModel.self) private var model

    var body: some View {
        switch block.content {
        case .table(let layout):
            let rows = layout.cells.count - 1
            Text(rows == 1 ? "1 row" : "\(rows.formatted()) rows").kitType(.secondary).foregroundStyle(.secondary)
                .uiTestAnchor("expanded-rows")
            CopyButton(text: { layout.markdown }, title: "Copy", icon: .copy, done: "Copied", help: "Copy the table as markdown", anchor: "copy-table")
        case .diagram(let source):
            zoomControls
            CopyButton(text: { source }, title: "Copy Source", icon: .copy, done: "Copied", help: "Copy the diagram’s Mermaid source", anchor: "copy-source")
        case .image:
            zoomControls
        }
    }

    /// Zoom Out, the zoom in % (a click fits), Zoom In: a diagram's and a picture's.
    @ViewBuilder
    private var zoomControls: some View {
        let zoom = model.diagramZoom
        Button("Zoom Out", icon: .zoomOut) { zoom.step(-1) }
            .labelStyle(.iconOnly)
            .clickable()
            .help("Zoom Out (⌘−)")
        Button { zoom.fit() } label: {
            // As wide at every zoom: the glass doesn't move.
            ZStack {
                Text("400%").hidden()
                Text("\(Int((zoom.scale * 100).rounded()))%")
            }
            .monospacedDigit()
        }
        .clickable()
        .help("Zoom to Fit (⌘9)")
        .uiTestAnchor("diagram-zoom")
        Button("Zoom In", icon: .zoomIn) { zoom.step(1) }
            .labelStyle(.iconOnly)
            .clickable()
            .help("Zoom In (⌘+)")
    }
}

/// Loads the page again; it turns while the page loads.
private struct ReloadButton: View {
    let page: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let loading = model.loadingPage == page
        Button("Reload", icon: .reload) { model.artifactReloads += 1 }
            .clickable()
            .labelStyle(.iconOnly)
            .symbolEffect(.rotate, isActive: loading)
            .help(loading ? "Loading…" : "Load the page again (⌘R)")
            .accessibilityValue(loading ? "Loading" : "")
            .uiTestAnchor("reload")
    }
}

/// Copy (T-358): the open item's line, its kind, key and title, for a session or a note; a checkmark says it's done.
private struct CopyItemButton: View {
    let route: ModalRoute
    @Environment(AppModel.self) private var model

    var body: some View {
        CopyButton(text: { model.line(of: route) }, title: "Copy", icon: .copy, done: "Copied",
                   help: "Copy \u{201C}\(model.line(of: route))\u{201D}", anchor: "copy-item")
    }
}

/// Remind Me… (T-343): a reminder linked to the open item.
private struct RemindMeButton: View {
    let route: ModalRoute
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Remind Me…", icon: .reminder) { model.beginReminder(about: route) }
            .clickable()
            .labelStyle(.iconOnly)
            .help("Set a reminder linked to it")
            .uiTestAnchor("item-remind-me")
    }
}

/// An icon button that copies; a checkmark says it's done. As wide either way: the glass doesn't move.
private struct CopyButton: View {
    let text: () -> String
    let title: String
    let icon: KitIcon
    let done: String
    let help: String
    let anchor: String
    @State private var copied = false

    var body: some View {
        Button {
            Pasteboard.copy(text())
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(Motion.copiedSeconds))
                copied = false
            }
        } label: {
            Label {
                Text(title)
            } icon: {
                ZStack {
                    icon.image.hidden()
                    KitIcon.copied.image.hidden()
                    (copied ? KitIcon.copied : icon).image
                        .contentTransition(.symbolEffect(.replace))
                }
            }
        }
        .clickable()
        .labelStyle(.iconOnly)
        .help(copied ? "Copied" : help)
        .accessibilityLabel(copied ? done : title)
        .uiTestAnchor(anchor)
    }
}

extension AppModel {
    /// The PRs and issues open in the modal or under it: the poll keeps asking for them.
    var modalGitHubURLs: [String] {
        ([modal].compactMap(\.self) + modalStack).compactMap { if case .github(let url) = $0 { url } else { nil } }
    }

    /// Edit (⌘E) on a file: its markdown in the editor.
    func beginFileEdit(_ id: FileItem.ID) {
        guard let body = fileBody(id) else {
            Task { await loadFileBody(id); if fileBody(id) != nil { beginFileEdit(id) } }
            return
        }
        fileDraftBase = body
        fileDraft = fileDraftBase
        editingFile = id
    }
}
