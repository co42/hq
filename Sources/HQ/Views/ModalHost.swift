import AppKit
import HQKit
import SwiftUI

/// The modal (DESIGN.md §8): a sheet over the page, about 88% of the window, with Close, Back,
/// what's left to look at and Next, then the kind's actions.
struct ModalHost: View {
    @Environment(AppModel.self) private var model
    /// The route and Back stack last shown: the sheet keeps them while it animates out, so it never
    /// flashes empty or jumps to another size.
    @State private var shown: (route: ModalRoute, stack: [ModalRoute])?

    private var route: ModalRoute? { model.modal ?? shown?.route }

    var body: some View {
        let route = route
        let small = route == .start || route == .hiddenAndClosed
        let size = small ? Metric.modalMin
            : CGSize(width: max(Metric.modalMin.width, (model.windowSize.width * Metric.modalShare).rounded()),
                     height: max(Metric.modalMin.height, (model.windowSize.height * Metric.modalShare).rounded()))
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
                case .start: StartSessionForm()
                case .hiddenAndClosed: HiddenClosedModal()
                case nil: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: min(size.width, max(model.windowSize.width, Metric.modalMin.width)),
               height: min(size.height, max(model.windowSize.height, Metric.modalMin.height)))
        .background(alignment: .top) {
            // The item's own sky: warm when it needs the user, blue when it's new.
            ZStack(alignment: .top) {
                Ink.content
                SkyView(mood: route.map { model.needsYou($0) ? .needsYou : model.isNew($0) ? .news : .calm } ?? .calm)
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

/// Close, Back, the title, "3 more to look at" and Next, then the kind's actions.
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
            let more = model.moreToLookAt
            if more > 0, route != .start, route != .hiddenAndClosed {
                Text("\(more) more to look at").kitType(.callout).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                Button("Next") { model.reviewNext() }
                    .buttonStyle(.glassProminent)
                    .tint(model.needsYouCount > 0 ? Ink.needsYou : Ink.accent)
                    .clickable()
                    .help("Open the next item that needs you or is new (⌘J)")
                    .uiTestAnchor("modal-next")
                    .padding(.trailing, Space.sm)
            }
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
        case .start: "Start a Session"
        case .hiddenAndClosed: "Hidden and Closed"
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
                if session.closedAt == nil {
                    Button(session.hidden ? "Show on Overview" : "Hide") { model.setHidden(id, !session.hidden) }
                        .help(session.hidden ? "Put the card back on the grid" : "Take the card off the grid; the session keeps running")
                }
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
                    Button("Delete") { model.deleteFile(id) }.help("Move the note to the Trash; Undo brings it back")
                    Button("Edit") { model.beginFileEdit(id) }.help("Edit the note in markdown (⌘E)")
                    Button("Open in Obsidian") { model.openInObsidian(file.path) }.disabled(file.path == nil)
                        .help("Open the note in Obsidian (⇧⌘O)")
                }
            }
        case .artifact(let url):
            Button("Reload", icon: .reload) { model.artifactReloads += 1 }
                .clickable()
                .labelStyle(.iconOnly)
                .help("Load the page again (⌘R)")
            Button("Open in Browser") { NSWorkspace.shared.open(url) }
                .help("Open the artifact in the browser (⇧⌘O)")
        case .github(let url):
            if let item = model.githubItem(url) {
                Button("Reload", icon: .reload) { model.artifactReloads += 1 }
                    .clickable()
                    .labelStyle(.iconOnly)
                    .help("Load the page again (⌘R)")
                if model.waitsForReview(item) {
                    Button("Mark Reviewed") { model.markReviewed(url) }
                        .help("Mark it reviewed: quiet until its next commit")
                }
                Button("Open on GitHub") { if let link = URL(string: url) { NSWorkspace.shared.open(link) } }
                    .buttonStyle(.glassProminent)
                    .clickable()
                    .help("Open it on github.com (⇧⌘O)")
            }
        case .start, .hiddenAndClosed, nil:
            EmptyView()
        }
    }
}

extension AppModel {
    /// Edit (⌘E) on a file: its markdown in the editor.
    func beginFileEdit(_ id: FileItem.ID) {
        fileDraft = fileBody(id)
        editingFile = id
    }
}
