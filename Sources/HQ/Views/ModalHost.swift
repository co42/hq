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
                case .newTask(let list): NewTaskForm(list: list)
                case .newReminder: NewReminderForm(about: model.reminderAbout)
                case .newFile: NewFileForm()
                case .importArtifact: ImportArtifactForm()
                case .start: StartSessionForm()
                case .closedSessions: ClosedSessionsModal()
                case .roles: RolesModal()
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
        .environment(\.inModal, true)
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
        HStack(spacing: Space.sm) {
            Button("Close", icon: .close) { model.closeModal() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .clickable()
                .keyboardShortcut(escapes ? .cancelAction : nil)
                .help(escapes ? "Close (Escape)" : "Close")
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
                HStack(spacing: Space.sm) { ModalActions(route: route, page: page) }
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
    let page: GitHubItem?
    @Environment(AppModel.self) private var model

    var body: some View {
        switch route {
        case .task(let id):
            if let task = model.task(id) {
                CopyItemButton(route: .task(id))
                RemindMeButton(route: .task(id))
                // The rare ones in More, with their keys; the main action last and prominent, as a session's and a PR's (2026-11-11).
                Menu {
                    Button(model.list(of: id) == .backlog ? "Move to Tasks" : "Move to Backlog") { model.toggleList(id) }
                    Button("Open in Obsidian") { model.openInObsidian(task.path) }.disabled(task.path == nil)
                    Divider()
                    Button("Delete") { model.deleteTasks([id]) }
                } label: {
                    Label("More", icon: .more)
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Move to Backlog or Tasks (⇧⌘B), Open in Obsidian (⇧⌘O), Delete (⌘⌫; Undo brings it back)")
                .uiTestAnchor("task-more")
                if let session = model.byImportance(model.sessions(on: id)).first(where: \.isRunning), session.tty != nil {
                    Button("Focus") { model.open(session.id) }
                        .buttonStyle(.glassProminent)
                        .help("Bring \(session.name)’s terminal forward")
                        .uiTestAnchor("task-main-action")
                } else {
                    Button("Start Session…") { model.beginStart(task: id, push: true) }
                        .buttonStyle(.glassProminent)
                        .help("Start a Claude session on this task (⌥⌘Return)")
                        .uiTestAnchor("task-main-action")
                }
            }
        case .session(let id):
            if let session = model.session(id) {
                // What it runs on, "Opus VH · 442k", and Model ▸ Effort ▸ (T-446, T-475).
                if session.isRunning {
                    Menu { RunMenus(session: session) } label: { Text(session.modelLine ?? "Model") }
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help([session.modelHelp, model.canChangeRun(session) ? "Change its model or effort" : "Its model or effort changes while it waits for its next message"]
                            .compactMap(\.self).joined(separator: "\n"))
                        .uiTestAnchor("session-model")
                }
                CopyItemButton(route: .session(id))
                if session.isRunning, session.tty != nil {
                    Button("Close Session") { model.closeSession(id) }
                        .help("Type /exit in its terminal, then close the terminal")
                }
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
            if let item = page {
                ReloadButton(page: url)
                CopyItemButton(route: .github(url))
                RemindMeButton(route: .github(url))
                CopyLinkButton(link: url)
                // Next Review while another PR waits for the user, else Mark Reviewed (T-456).
                if let next = model.nextReview(after: url) {
                    Button("Next Review") { model.goToNextReview(from: url) }
                        .help((model.waitsForReview(item) ? "Mark it reviewed and open the next PR waiting for you: " : "Open the next PR waiting for you: ")
                              + model.title(of: .github(next.url)))
                        .uiTestAnchor("next-review")
                } else if model.waitsForReview(item) {
                    Button("Mark Reviewed") { model.markReviewed(url) }
                        .help("Mark it reviewed: quiet until its next commit")
                }
                Button("Open on GitHub") { if let link = URL(string: url) { NSWorkspace.shared.open(link) } }
                    .buttonStyle(.glassProminent)
                    .clickable()
                    .help("Open it on github.com (⇧⌘O)")
            }
        case .roles:
            // The picked role's actions, in the File modal's order; while editing, Cancel and Save.
            if let role = model.pickedRole {
                if model.roleEdit != nil {
                    Button("Cancel") { model.cancelRoleEdit() }.help("Drop the changes (Escape in a name or a line)")
                        .uiTestAnchor("role-cancel")
                    Button("Save") { model.commitRoleEdit() }
                        .buttonStyle(.glassProminent)
                        .clickable()
                        .help("Save the changes (Return in a name or a line; Escape or ⌘Return in the text)")
                        .uiTestAnchor("role-save")
                } else {
                    CopyButton(text: { model.line(ofRole: role) }, title: "Copy", icon: .copy, done: "Copied",
                               help: "Copy \u{201C}\(model.line(ofRole: role))\u{201D}", anchor: "copy-item")
                    if model.isChangedDefault(role) {
                        Button("Restore Default") { model.restoreDefault(role.name) }
                            .help("Give \(role.name) HQ’s text and line again; Undo brings yours back")
                            .uiTestAnchor("role-restore")
                    }
                    Button("Delete") { model.deleteRole(role.name, picking: true) }
                        .help("Move the role’s note to the Trash; sessions that have it keep what they started with. Undo brings it back")
                        .uiTestAnchor("role-delete")
                    Button("Edit") { model.beginRoleEdit(.text) }.help("Edit what a session with this role gets (⌘E)")
                        .uiTestAnchor("role-edit")
                    Button("Open in Obsidian") { model.openInObsidian(role.path) }.disabled(role.path == nil)
                        .help("Open the role’s note in Obsidian")
                }
            }
        case .notifications, .start, .closedSessions, .web, .slack, .newTask, .newReminder, .newFile, .importArtifact, nil:
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
    /// The PRs and issues open in the modal or under it: the poll keeps asking for them.
    var modalGitHubURLs: [String] {
        ([modal].compactMap(\.self) + modalStack).compactMap { if case .github(let url) = $0 { url } else { nil } }
    }

    /// Edit (⌘E) on a file: its markdown in the editor.
    func beginFileEdit(_ id: FileItem.ID) {
        fileDraftBase = fileBody(id)
        fileDraft = fileDraftBase
        editingFile = id
    }
}
