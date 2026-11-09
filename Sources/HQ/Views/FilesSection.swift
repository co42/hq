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
        let filtered = !model.search.isEmpty || !model.filesSearch.isEmpty || model.pinnedOnly
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
                NewFileButton()
                ImportArtifactButton()
            }
            if !model.folded.contains(.files) {
                let layout = width >= Metric.prSideBySide
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: Metric.cardGap))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: Metric.cardGap))
                layout {
                    ItemGroup(title: "Files", routes: files.map { .file($0.id) }, total: model.files.count, filtered: filtered,
                              empty: emptyText(kind: "files"))
                    ItemGroup(title: "Artifacts", routes: artifacts.map { .artifact($0.id) }, total: model.artifacts.count, filtered: filtered,
                              empty: emptyText(kind: "artifacts"))
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

/// New File: a note in the vault by its title, opened to write in.
private struct NewFileButton: View {
    @Environment(AppModel.self) private var model
    @State private var shown = false
    @State private var title = ""
    @FocusState private var focused: Bool

    private var ready: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Button { open() } label: { HeaderIcon(icon: .new) }
            .help("New File: write a note in the vault")
            .accessibilityLabel("New File")
            .uiTestAnchor("new-file")
            .popover(isPresented: $shown, arrowEdge: .bottom) { form }
            .onChange(of: model.newFileRequests) { open() }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("New File").kitType(.titleStrong)
            TextField("Title", text: $title)
                .focused($focused)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel") { shown = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!ready)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(Space.lg)
        .frame(width: Metric.sheetWidth)
    }

    private func open() {
        title = ""
        shown = true
        focused = true
    }

    private func save() {
        guard ready else { return }
        shown = false
        model.newFile(title: title)
    }
}

/// Import Artifact…: a claude.ai artifact HQ didn't capture, by its URL and a title.
private struct ImportArtifactButton: View {
    @Environment(AppModel.self) private var model
    @State private var shown = false
    @State private var link = ""
    @State private var title = ""
    @FocusState private var focus: Field?

    private enum Field { case link, title }

    private var url: URL? { AppModel.artifactURL(link) }
    private var ready: Bool { url != nil && !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Button { open() } label: { HeaderIcon(icon: .importItem) }
            .help("Import Artifact: add a claude.ai artifact by its link")
            .accessibilityLabel("Import Artifact")
            .uiTestAnchor("import-artifact")
            .popover(isPresented: $shown, arrowEdge: .bottom) { form }
            .onChange(of: model.importRequests) { open() }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Import an Artifact").kitType(.titleStrong)
            VStack(alignment: .leading, spacing: Space.xs) {
                TextField("https://claude.ai/artifact/…", text: $link)
                    .focused($focus, equals: .link)
                if !link.isEmpty, url == nil {
                    Text("Not a claude.ai artifact link.").kitType(.meta).foregroundStyle(Ink.failedText)
                } else if let url, model.artifacts.contains(where: { $0.id == url }) {
                    Text("Already in HQ: importing renames it.").kitType(.meta).foregroundStyle(.secondary)
                }
            }
            TextField("Title", text: $title)
                .focused($focus, equals: .title)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel") { shown = false }
                    .keyboardShortcut(.cancelAction)
                Button("Import", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!ready)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(Space.lg)
        .frame(width: Metric.sheetWidth)
    }

    /// The link on the clipboard when it's an artifact's; the title next.
    private func open() {
        let copied = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        link = AppModel.artifactURL(copied) == nil ? "" : copied
        title = link.isEmpty ? "" : AppModel.artifactURL(link).flatMap { url in model.artifacts.first { $0.id == url }?.title } ?? ""
        shown = true
        focus = link.isEmpty ? .link : .title
    }

    private func save() {
        guard ready, let url else { return }
        let artifact = model.importArtifact(url, title: title.trimmingCharacters(in: .whitespaces))
        model.pinnedOnly = model.pinnedOnly && artifact.pinned
        model.selectedItem = ModalRoute.artifact(artifact.id).selectionKey
        model.selectSection(.files)
        shown = false
    }
}

/// One of the two cards: its title and count, then its rows, five before "Show N More".
private struct ItemGroup: View {
    let title: String
    let routes: [ModalRoute]
    let total: Int
    let filtered: Bool
    let empty: String
    @State private var expanded = false

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
                    let rows = expanded ? routes : Array(routes.prefix(PRCards.shown))
                    ForEach(rows, id: \.self) { route in
                        ItemRow(route: route)
                            .id(route.selectionKey)
                            .overlay(alignment: .bottom) { if route != rows.last { RowRule() } }
                    }
                    if routes.count > PRCards.shown {
                        Button(expanded ? "Show Fewer" : "Show \(routes.count - PRCards.shown) More") { expanded.toggle() }
                            .buttonStyle(.borderless)
                            .clickable()
                            .kitType(.callout)
                            .padding(.leading, Space.sm)
                            .frame(maxWidth: .infinity, minHeight: Metric.boxRow, alignment: .leading)
                    }
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
                    if let maker = model.maker(of: route) { SessionFace(maker, size: Metric.faceRow) } else { FaceStack(sessions: [], size: Metric.faceRow) }
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
