import AppKit
import HQKit
import SwiftUI

/// The modal (DESIGN.md §8): a sheet over the page, about 88% of the window, with Close, Back and the kind's actions.
struct ModalHost: View {
    @Environment(AppModel.self) private var model
    /// The route and Back stack last shown: the sheet keeps them while it animates out, so it never
    /// flashes empty or jumps to another size.
    @State private var shown: (route: ModalRoute, stack: [ModalRoute])?

    private var route: ModalRoute? { model.modal ?? shown?.route }

    var body: some View {
        let route = route
        let small = route == .start || route == .closedSessions
        let size = if case .newTask = route { Metric.taskSheet } else if route == .newReminder { Metric.reminderSheet } else if small { Metric.modalMin } else {
            CGSize(width: max(Metric.modalMin.width, (model.windowSize.width * Metric.modalShare).rounded()),
                     height: max(Metric.modalMin.height, (model.windowSize.height * Metric.modalShare).rounded()))
        }
        VStack(spacing: 0) {
            ModalHeader(route: route, stack: model.modal == nil ? shown?.stack ?? [] : model.modalStack)
            Group {
                switch route {
                case .task(let id): if model.task(id) != nil { TaskModal(id: id).id(id) } else { gone }
                case .session(let id): if model.session(id) != nil { SessionModal(id: id).id(id) } else { gone }
                case .file(let id): if let file = model.file(id) { FileModal(file: file).id(id) } else { gone }
                case .artifact(let url):
                    if let artifact = model.artifacts.first(where: { $0.id == url }) { ArtifactReader(artifact: artifact).id(url) } else { gone }
                case .github(let url): if let item = model.githubItem(url) { GitHubModal(item: item).id(url) } else { gone }
                // A web page or a Slack link opens outside HQ, never here.
                case .web, .slack: gone
                case .newTask(let list): NewTaskForm(list: list)
                case .newReminder: NewReminderForm(about: model.reminderAbout)
                case .start: StartSessionForm()
                case .closedSessions: ClosedSessionsModal()
                case .notifications: NotificationCenterView()
                case nil: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: min(size.width, max(model.windowSize.width, Metric.modalMin.width)),
               height: min(size.height, max(model.windowSize.height, Metric.modalMin.height)))
        .background(alignment: .top) {
            // The item's own sky: warm while it needs the user.
            ZStack(alignment: .top) {
                Ink.content
                SkyView(mood: model.mood(of: route))
                    .opacity(0.7)
            }
        }
        .noInitialFocus()
        .handCursors()
        .controlSize(Zoom.controlSize(model.zoom))
        .id(model.zoom)
        .gridArea("modal", inset: 0)
        .onChange(of: model.modal, initial: true) { _, next in
            if let next {
                shown = (next, model.modalStack)
            } else {
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
    }
}

/// Close, Back, the title, then the kind's actions.
private struct ModalHeader: View {
    let route: ModalRoute?
    let stack: [ModalRoute]
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Space.sm) {
            Button("Close", icon: .close) { model.closeModal() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .clickable()
                .keyboardShortcut(.cancelAction)
                .help("Close (Escape)")
                .uiTestAnchor("modal-close")
            if let previous = stack.last {
                Button { model.back() } label: {
                    HStack(spacing: Space.xs) {
                        KitIcon.back.image
                        Text(backTitle(previous)).lineLimit(1).truncationMode(.tail)
                    }
                    .frame(maxWidth: 220)
                }
                .buttonStyle(.glass)
                .help("Back to \(model.title(of: previous)) (⌘[)")
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
                HStack(spacing: Space.sm) { ModalActions(route: route) }
                    .buttonStyle(.glass)
            }
        }
        .padding(.horizontal, Metric.modalEdge)
        .frame(height: Metric.modalHeader)
    }

    private var title: String {
        switch route {
        case .task(let id): model.task(id)?.key ?? "Task"
        case .session: "Session"
        case .file: "File"
        case .artifact: "Artifact"
        case .github(let url): model.githubItem(url).map { $0.kind == .issue ? "Issue \($0.reference)" : "Pull Request \($0.reference)" } ?? "GitHub"
        case .web: "Link"
        case .slack: "Slack"
        case .newTask: "New Task"
        case .newReminder: "New Reminder"
        case .start: "Start a Session"
        case .closedSessions: "Closed Sessions"
        case .notifications: "Notifications"
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

/// The open item's actions, one prominent at most.
private struct ModalActions: View {
    let route: ModalRoute?
    @Environment(AppModel.self) private var model

    var body: some View {
        switch route {
        case .task(let id):
            if let task = model.task(id) {
                CopyItemButton(route: .task(id))
                RemindMeButton(route: .task(id))
                Button("Delete") { model.deleteTasks([id]) }
                    .help("Move the task’s note to the Trash; Undo brings it back")
                Button(model.list(of: id) == .backlog ? "Move to Tasks" : "Move to Backlog") { model.toggleList(id) }
                    .help(model.list(of: id) == .backlog ? "Put it on the overview (⇧⌘B)" : "Move it to the Backlog (⇧⌘B)")
                Button("Open in Obsidian") { model.openInObsidian(task.path) }
                    .disabled(task.path == nil)
                    .help("Open the task’s note in Obsidian (⇧⌘O)")
            }
        case .session(let id):
            if let session = model.session(id) {
                CopyItemButton(route: .session(id))
                if session.isRunning, session.tty != nil {
                    Button("Close Session") { model.closeSession(id) }
                        .help("Type /exit in its terminal, then close the terminal")
                }
                Button("Fork Session") { model.forkSession(id) }
                    .help("A new session with this one’s conversation, in a new Ghostty tab")
                Button(session.isRunning ? "Focus" : "Resume") { model.open(id) }
                    .disabled(session.isRunning && session.tty == nil)
                    .buttonStyle(.glassProminent)
                    .clickable()
                    .help(session.isRunning ? "Bring its terminal forward (⌘O)" : "Resume it in a new Ghostty tab (⌘O)")
            }
        case .file(let id):
            if let file = model.file(id) {
                if model.editingFile == id {
                    Button("Cancel") { model.editingFile = nil }.help("Drop the changes")
                    Button("Save") { model.saveModalEdits() }
                        .buttonStyle(.glassProminent)
                        .clickable()
                        .help("Save the changes (Escape or ⌘Return)")
                } else {
                    CopyItemButton(route: .file(id))
                    RemindMeButton(route: .file(id))
                    Button("Delete") { model.deleteFile(id) }.help("Move the note to the Trash; Undo brings it back")
                    Button("Edit") { model.beginFileEdit(id) }.help("Edit the note in markdown (⌘E)")
                    Button("Open in Obsidian") { model.openInObsidian(file.path) }.disabled(file.path == nil)
                        .help("Open the note in Obsidian (⇧⌘O)")
                }
            }
        case .artifact(let url):
            ReloadButton(page: url.absoluteString)
            CopyItemButton(route: .artifact(url))
            RemindMeButton(route: .artifact(url))
            CopyLinkButton(link: url.absoluteString)
            Button("Open in Browser") { NSWorkspace.shared.open(url) }
                .help("Open the artifact in the browser (⇧⌘O)")
        case .github(let url):
            if let item = model.githubItem(url) {
                ReloadButton(page: url)
                CopyItemButton(route: .github(url))
                RemindMeButton(route: .github(url))
                CopyLinkButton(link: url)
                if model.waitsForReview(item) {
                    Button("Mark Reviewed") { model.markReviewed(url) }
                        .help("Mark it reviewed: quiet until its next commit")
                }
                Button("Open on GitHub") { if let link = URL(string: url) { NSWorkspace.shared.open(link) } }
                    .buttonStyle(.glassProminent)
                    .clickable()
                    .help("Open it on github.com (⇧⌘O)")
            }
        case .notifications, .start, .closedSessions, .web, .slack, .newTask, .newReminder, nil:
            EmptyView()
        }
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

/// Copies the open item's link.
private struct CopyLinkButton: View {
    let link: String

    var body: some View {
        CopyButton(text: { link }, title: "Copy Link", icon: .link, done: "Link Copied", help: "Copy the link (⇧⌘C)", anchor: "copy-link")
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
    /// Edit (⌘E) on a file: its markdown in the editor.
    func beginFileEdit(_ id: FileItem.ID) {
        fileDraft = fileBody(id)
        editingFile = id
    }
}
