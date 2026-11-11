import AppKit
import HQKit
import SwiftUI

/// Files and artifacts (DESIGN.md §6): notes on the left, published pages on the right, pinned first, newest next.
struct FilesSection: View {
    let width: CGFloat
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let files = model.listedFiles
        let artifacts = model.listedArtifacts
        let total = model.files.count + model.artifacts.count
        let filtered = model.filesFiltered
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: PageSection.files.title, count: filtered ? "\(files.count + artifacts.count) of \(total)" : "\(total)",
                          open: model.sectionOpen(.files), tile: (PageSection.files.icon, Ink.section(.files))) {
                HeaderSearch(prompt: "Search Files and Artifacts", text: $model.filesSearch)
                    .help("Show the files and artifacts whose title has this (Escape clears)")
                    .uiTestAnchor("search:files")
                Toggle(isOn: $model.pinnedOnly) { HeaderIcon(icon: model.pinnedOnly ? .pinned : .pin) }
                    .clickable()
                    .help("Pinned Only: show pinned files and artifacts only")
                    .accessibilityLabel("Pinned Only")
                Button { model.beginNewFile() } label: { HeaderIcon(icon: .new) }
                    .help("New File: write a note in the vault (⌃⌘N)")
                    .accessibilityLabel("New File")
                    .uiTestAnchor("new-file")
                Button { model.beginImport() } label: { HeaderIcon(icon: .importItem) }
                    .help("Import Artifact: add a claude.ai artifact by its link")
                    .accessibilityLabel("Import Artifact")
                    .uiTestAnchor("import-artifact")
            }
            if !model.folded.contains(.files) {
                let layout = width >= Metric.prSideBySide
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: Metric.cardGap))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: Metric.cardGap))
                layout {
                    ItemGroup(title: "Files", card: .files, routes: files.map { .file($0.id) }, total: model.files.count, filtered: filtered,
                              empty: emptyText(kind: "files"))
                    ItemGroup(title: "Artifacts", card: .artifacts, routes: artifacts.map { .artifact($0.id) }, total: model.artifacts.count,
                              filtered: filtered, empty: emptyText(kind: "artifacts"))
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func emptyText(kind: String) -> String {
        let words = [model.search, model.filesSearch].filter { !$0.isEmpty }.joined(separator: " ")
        if !words.isEmpty { return "No match for “\(words)”." }
        return model.pinnedOnly ? "No pinned \(kind)." : "No \(kind) yet."
    }
}

/// One of the two cards: its title and count, then its rows, five before "Show N More" (every one while a filter narrows them).
private struct ItemGroup: View {
    let title: String
    let card: RowCard
    let routes: [ModalRoute]
    let total: Int
    let filtered: Bool
    let empty: String
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.sm) {
                Text(title).kitType(.titleStrong)
                Text(filtered ? "\(routes.count) of \(total)" : "\(total)").kitType(.meta).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.md)
            .frame(height: Metric.boxRow + Space.xs, alignment: .center)
            if routes.isEmpty {
                Text(empty)
                    .kitType(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Space.md)
                    .frame(height: Metric.boxRow, alignment: .top)
            } else {
                VStack(spacing: 0) {
                    let rows = model.shown(routes, in: card)
                    ForEach(rows, id: \.self) { route in
                        ItemRow(route: route)
                            .id(route.selectionKey)
                            .overlay(alignment: .bottom) { if route != rows.last { RowRule() } }
                    }
                    ShowMoreButton(card: card, count: routes.count)
                }
                .padding(.horizontal, Space.xs + 2)
                .padding(.bottom, Space.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .surface()
    }
}

/// A file or an artifact on one line, as a PR row: dot, its maker's face, kind, title with its project and tags;
/// its date and a pin in the right columns.
private struct ItemRow: View {
    let route: ModalRoute
    @Environment(AppModel.self) private var model
    @State private var hovering = false
    @State private var linking = false

    var body: some View {
        let item = model.listed(route)
        HStack(spacing: Space.sm) {
            RowLead {
                Group {
                    if let maker = model.maker(of: route) { SessionFace(maker, size: Metric.faceRow, badged: false) } else { FaceStack(sessions: [], size: Metric.faceRow) }
                }
                .frame(width: Metric.faceRow, height: Metric.faceRow)
            } icon: {
                KindTile(icon: route.isFile ? .fileTile : .artifact, tint: route.isFile ? Ink.fileTile : Ink.artifactTile)
                    .accessibilityLabel(route.isFile ? "File" : "Artifact")
            }
            HStack(spacing: Space.sm) {
                HStack(spacing: Space.xs) {
                    ReminderMark(route: route)
                    Text(model.title(of: route))
                        .kitType(.title)
                        .lineLimit(1)
                }
                HStack(spacing: Space.xs) {
                    ProjectPicker(project: item.project, iconOnly: true) { model.setProject(of: route, $0) }
                    ForEach(item.tags.prefix(2), id: \.self) { tag in
                        LabelChip(text: tag, color: model.labelColor(.tag, tag), icon: .tag)
                    }
                }
                .fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.date.formatted(.relative(presentation: .named)))
                .kitType(.secondary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Metric.rowStatus, alignment: .trailing)
            Button(item.pinned ? "Unpin" : "Pin", icon: item.pinned ? .pinned : .pin) { model.setPinned(route, !item.pinned) }
                .clickable()
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .clickable()
                .foregroundStyle(item.pinned ? AnyShapeStyle(Ink.accentText) : AnyShapeStyle(.secondary))
                .frame(width: Metric.rowAction, height: Metric.rowAction)
                .opacity(item.pinned || hovering ? 1 : 0)
                .help(item.pinned ? "Unpin" : "Pin to the top")
                .frame(width: Metric.rowKey, alignment: .trailing)
        }
        .padding(.horizontal, Space.sm)
        .frame(height: Metric.itemRow)
        .background(hovering ? Ink.hoverFill : Color.clear, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .selectOpen(route.selectionKey, in: .files) { model.open(route) }
        .onDrag { DragItem.provider(route, line: model.line(of: route)) }
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .help("\(model.title(of: route))\n\(detail(item))")
        .contextMenu {
            Button("Open") { model.open(route) }
            Button(item.pinned ? "Unpin" : "Pin") { model.setPinned(route, !item.pinned) }
            Button("Link to Task…") { linking = true }
            Button("Remind Me…") { model.beginReminder(about: route) }
            Divider()
            switch route {
            case .file(let id):
                Button("Open in Obsidian") { model.openInObsidian(model.file(id)?.path) }
                Button("Copy") { model.copy([route]) }
                Divider()
                Button("Delete") { model.deleteFile(id) }
            case .artifact(let url):
                Button("Open in Browser") { NSWorkspace.shared.open(url) }
                Button("Copy") { model.copy([route]) }
                Button("Copy Link") { Pasteboard.copy(url.absoluteString) }
                Divider()
                Button("Remove from HQ") { model.removeArtifact(url) }
            default:
                EmptyView()
            }
        }
        .popover(isPresented: $linking, arrowEdge: .bottom) { TaskFinder { model.link(route, to: $0); linking = false } }
        .uiTestAnchor("item:\(route.selectionKey)")
    }

    private func detail(_ item: AppModel.ListedItem) -> String {
        let when = item.date.formatted(.relative(presentation: .named))
        guard let maker = model.maker(of: route) else { return when }
        return "\(maker.name) · \(when)"
    }
}

extension ModalRoute {
    var isFile: Bool { if case .file = self { true } else { false } }
}

extension AppModel {
    /// The page's search, the section's or Pinned Only narrows Files and Artifacts.
    var filesFiltered: Bool { !search.isEmpty || !filesSearch.isEmpty || pinnedOnly }

    /// New File… (⌃⌘N): its own small sheet, over what's open, as New Task….
    func beginNewFile() {
        guard modal != .newFile else { return }
        showWindow()
        open(.newFile, push: modal != nil)
    }

    /// File › Import Artifact…: its own small sheet, over what's open.
    func beginImport() {
        guard modal != .importArtifact else { return }
        showWindow()
        open(.importArtifact, push: modal != nil)
    }

    /// A new note by its title, opened in its modal to write in: over the item New File… was asked from, else from the page,
    /// its row selected there.
    func newFile(title: String) {
        guard let file = addFile(title: title) else { return }
        pinnedOnly = false
        filesSearch = ""
        if modal == nil { show(onPage: .file(file.id)) }
        open(.file(file.id), push: modal != nil)
        beginFileEdit(file.id)
    }

    /// An artifact Import Artifact… added: from the page, its row selected and in view.
    func show(imported artifact: ArtifactItem) {
        guard modal == nil else { return }
        pinnedOnly = pinnedOnly && artifact.pinned
        show(onPage: .artifact(artifact.id))
    }

    /// A file's or an artifact's row selected: Files and Artifacts unfolds and the page brings the row into view.
    private func show(onPage route: ModalRoute) {
        folded.remove(.files)
        selectedItem = route.selectionKey
        selectSection(.files)
        scrollTarget = route.selectionKey
    }

    /// A claude.ai artifact's link, without its share key and fragment; nil for anything else.
    static func artifactURL(_ raw: String) -> URL? {
        guard var parts = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)), parts.scheme == "https",
              parts.host == "claude.ai", parts.path.contains("/artifact/") else { return nil }
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }

    /// Adds an artifact HQ didn't capture; the same link again renames it, dates it and links the task.
    @discardableResult
    func importArtifact(_ url: URL, title: String, published: Date? = nil, task: Int? = nil) -> ArtifactItem {
        if let index = artifacts.firstIndex(where: { $0.id == url }) {
            if !title.isEmpty { artifacts[index].title = title }
            if let published { artifacts[index].published = published }
            if let task, !artifacts[index].tasks.contains(task) { artifacts[index].tasks.append(task) }
            return artifacts[index]
        }
        var artifact = ArtifactItem(id: url, title: title.isEmpty ? url.lastPathComponent : title, session: nil,
                                    published: published ?? .now, tasks: task.map { [$0] } ?? [])
        artifact.project = project(ofTask: task)
        artifacts.append(artifact)
        return artifact
    }

    /// What a file's or an artifact's row shows.
    struct ListedItem {
        var project: String?
        var tags: [String] = []
        var pinned = false
        var date = Date.distantPast
    }

    func listed(_ route: ModalRoute) -> ListedItem {
        switch route {
        case .file(let id):
            guard let file = file(id) else { return ListedItem() }
            return ListedItem(project: file.project, tags: file.tags, pinned: file.pinned, date: file.modified)
        case .artifact(let url):
            guard let artifact = artifacts.first(where: { $0.id == url }) else { return ListedItem() }
            return ListedItem(project: artifact.project, tags: artifact.tags, pinned: artifact.pinned, date: artifact.published)
        default:
            return ListedItem()
        }
    }

    /// Files for the section: pinned first, then the newest; the searches and Pinned Only apply.
    var listedFiles: [FileItem] {
        files.filter { (!pinnedOnly || $0.pinned) && (search.isEmpty || $0.searchText.localizedStandardContains(search))
            && (filesSearch.isEmpty || $0.title.localizedStandardContains(filesSearch)) }
            .sorted { ($0.pinned ? 1 : 0, $0.modified) > ($1.pinned ? 1 : 0, $1.modified) }
    }

    var listedArtifacts: [ArtifactItem] {
        artifacts.filter { (!pinnedOnly || $0.pinned) && (search.isEmpty || $0.searchText.localizedStandardContains(search))
            && (filesSearch.isEmpty || $0.title.localizedStandardContains(filesSearch)) }
            .sorted { ($0.pinned ? 1 : 0, $0.published) > ($1.pinned ? 1 : 0, $1.published) }
    }

    func setProject(of route: ModalRoute, _ project: String?) {
        switch route {
        case .file(let id): setFileLabels(id, project: .some(project))
        case .artifact(let url): setArtifactLabels(url, project: .some(project))
        default: break
        }
    }

    func setPinned(_ route: ModalRoute, _ pinned: Bool) {
        switch route {
        case .file(let id): setFileLabels(id, pinned: pinned)
        case .artifact(let url): setArtifactLabels(url, pinned: pinned)
        default: break
        }
    }
}
