import AppKit
import HQKit
import SwiftUI

/// The Archive (DESIGN.md §8, T-471): a big search field with the keyboard, then a card per archived story, the newest
/// archived first, under This Week, Last Week and the months; what's under a story that the search found shows under
/// its card. Unarchive and More float over a card on hover and while it's selected, as a notification's actions do.
struct ArchiveView: View {
    @Environment(AppModel.self) private var model
    @State private var limit = ArchiveView.page
    @State private var slow = false
    @State private var found = Found()

    /// Stories shown before Show More: the page stays light with any Archive.
    static let page = 50

    private var selected: Int? {
        get { model.archiveSelection }
        nonmutating set { model.archiveSelection = newValue }
    }

    var body: some View {
        @Bindable var model = model
        let shown = model.archiveShown
        let matches = found.matches(shown?.searcher, model.archiveQuery)
        let visible = Array(matches.prefix(limit))
        ScrollViewReader { proxy in
            ModalPage {
                field(count: shown?.searcher.count, found: matches.count)
                if shown == nil {
                    if slow { LoadingLine(title: "Loading the archive…").uiTestAnchor("archive-loading") }
                } else if shown?.searcher.count == 0 {
                    AllClear(title: "Nothing archived yet", icon: .archive,
                             line: "Done stories come here \(AppModel.archiveDelayName(model.archiveDelayDays)) after they're done.")
                        .surface()
                        .uiTestAnchor("archive-empty")
                } else if matches.isEmpty {
                    AllClear(title: "No archived task has “\(model.archiveQuery.trimmingCharacters(in: .whitespaces))”", icon: .search)
                        .surface()
                        .uiTestAnchor("archive-none")
                } else {
                    // One lazy stack: only the cards on screen are made, and a card keeps its view when a search moves it.
                    LazyVStack(alignment: .leading, spacing: Space.sm) {
                        ForEach(Array(groups(visible).enumerated()), id: \.element.title) { place, group in
                            Section {
                                ForEach(group.matches, id: \.story.id) { match in
                                    ArchiveCard(match: match, query: model.archiveQuery, selected: selected == match.story.id, active: true)
                                        .simultaneousGesture(TapGesture().onEnded { selected = match.story.id })
                                }
                            } header: {
                                Text("\(group.title) · \(group.matches.count)").kitType(.groupLabel).foregroundStyle(.secondary)
                                    .padding(.top, place == 0 ? 0 : Space.xl - Space.sm)
                            }
                        }
                    }
                    if matches.count > visible.count {
                        Button("Show \(min(Self.page, matches.count - visible.count)) More") { limit += Self.page }
                            .buttonStyle(.borderless)
                            .clickable()
                            .kitType(.callout)
                            .uiTestAnchor("archive-more")
                    }
                }
            }
            .onChange(of: model.archiveQuery) {
                limit = Self.page
                selectFirst()
            }
            // Results in, or a story gone: a selection that isn't among them goes to the first found.
            .onChange(of: model.archiveShown?.searcher.id) {
                if let id = selected, visibleNow.contains(where: { $0.story.id == id }) { return }
                selectFirst()
            }
            .onChange(of: selected) { if let id = selected { proxy.scrollTo(id, anchor: nil) } }
        }
        .onAppear {
            model.loadArchive()
            if selected == nil { selectFirst() }
            DispatchQueue.main.async { NotificationCenter.default.post(name: .focusArchive, object: nil) }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.2))
                slow = true
            }
        }
        .preference(key: OwnsEscape.self, value: true)
    }

    /// The stories shown now, for the keys.
    private var visibleNow: [ArchiveIndex.Match] {
        Array(found.matches(model.archiveShown?.searcher, model.archiveQuery).prefix(limit))
    }

    /// The last search's results: a keystroke searches once, however often the page redraws.
    private final class Found {
        private var searcher: ArchiveIndex.Searcher?
        private var query: String?
        private var last: [ArchiveIndex.Match] = []

        func matches(_ searcher: ArchiveIndex.Searcher?, _ query: String) -> [ArchiveIndex.Match] {
            guard let searcher else { return [] }
            if query != self.query || searcher.id != self.searcher?.id {
                last = searcher.search(query)
                self.query = query
                self.searcher = searcher
            }
            return last
        }
    }

    /// The big search field, the keyboard in it: every word, in a story or a task under it.
    private func field(count: Int?, found: Int) -> some View {
        @Bindable var model = model
        return HStack(spacing: Space.sm) {
            KitIcon.search.image.foregroundStyle(.secondary)
            // Quick Open's field: ↑ ↓ move the selection, Return opens, Escape clears, then closes.
            QuickOpenField(text: $model.archiveQuery, prompt: count.flatMap { $0 > 0 ? "Search \($0) archived \($0 == 1 ? "story" : "stories")" : nil } ?? "Search the Archive",
                           label: "Search the Archive", focus: .focusArchive) { command in
                switch command {
                case .up: move(-1, in: visibleNow)
                case .down: move(1, in: visibleNow)
                case .open, .show: openSelected()
                case .cancel: if model.archiveQuery.isEmpty { model.closeModal() } else { model.archiveQuery = "" }
                }
            }
            .uiTestAnchor("archive-search")
            Text(model.archiveQuery.isEmpty ? "titles, keys, projects, #tags" : "\(found) of \(count ?? 0)")
                .kitType(.meta)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, Space.md)
        .frame(height: Metric.archiveField)
        .surface(radius: Radius.row)
    }

    private struct Group {
        var title: String
        var matches: [ArchiveIndex.Match]
    }

    /// By when each was archived: This Week, Last Week, then each month; each title made once.
    private func groups(_ matches: [ArchiveIndex.Match]) -> [Group] {
        var groups: [Group] = []
        var last: ArchiveIndex.Group?
        let calendar = Calendar.current
        for match in matches {
            let group = ArchiveIndex.group(match.story.archived, now: model.now, calendar: calendar)
            if group == last, !groups.isEmpty {
                groups[groups.count - 1].matches.append(match)
                continue
            }
            last = group
            let title = switch group {
            case .thisWeek: "This Week"
            case .lastWeek: "Last Week"
            case .month: match.story.archived.formatted(.dateTime.month(.wide).year())
            }
            groups.append(Group(title: title, matches: [match]))
        }
        return groups
    }

    /// A typed search selects the first story it finds, for Return.
    private func selectFirst() {
        selected = model.archiveQuery.isEmpty ? nil : found.matches(model.archiveShown?.searcher, model.archiveQuery).first?.story.id
    }

    private func move(_ step: Int, in visible: [ArchiveIndex.Match]) {
        let ids = visible.map(\.story.id)
        guard !ids.isEmpty else { return }
        guard let current = selected, let index = ids.firstIndex(of: current) else {
            selected = step > 0 ? ids.first : ids.last
            return
        }
        selected = ids[min(max(index + step, 0), ids.count - 1)]
    }

    private func openSelected() {
        guard let id = selected else { return }
        model.open(.archivedTask(id), push: true)
    }
}

/// One archived story: its glyph, key, title, project and tags; how many tasks under it and the day it was done, where
/// Unarchive and More float on hover; the tasks under it the search found, three, then how many more.
private struct ArchiveCard: View {
    let match: ArchiveIndex.Match
    let query: String
    let selected: Bool
    let active: Bool
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        let story = match.story
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                TaskGlyph(status: story.status)
                Text(story.key).kitType(.key).foregroundStyle(.secondary)
                Text(story.title).kitType(.body).lineLimit(1).truncationMode(.tail)
                if let project = story.project { LabelChip(text: project, color: model.labelColor(.project, project), icon: .project) }
                ForEach(story.tags.prefix(2), id: \.self) { tag in LabelChip(text: tag, color: model.labelColor(.tag, tag), icon: .tag) }
                Spacer(minLength: Space.sm)
                HStack(spacing: Space.md) {
                    if match.count > 0 { Text("\(match.count) \(match.count == 1 ? "task" : "tasks")") }
                    Text(story.done.map { "Done \($0.formatted(.dateTime.day().month(.abbreviated)))" }
                         ?? "Archived \(story.archived.formatted(.dateTime.day().month(.abbreviated)))")
                }
                .kitType(.meta)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .opacity(hovering || selected ? 0 : 1)
            }
            ForEach(match.under.prefix(3), id: \.id) { task in
                HStack(spacing: Space.sm) {
                    TaskGlyph(status: task.status).scaleEffect(0.85)
                    Text(task.key).kitType(.key).foregroundStyle(.secondary)
                    Text(task.title).kitType(.secondary).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.leading, Metric.glyphSlot + Space.sm)
            }
            if match.under.count > 3 {
                Text("+\(match.under.count - 3) more").kitType(.meta).foregroundStyle(.tertiary)
                    .padding(.leading, Metric.glyphSlot + Space.sm)
            }
        }
        .listCard(selected: selected, active: active)
        .overlay(alignment: .topTrailing) {
            if hovering || selected { actions.padding(.top, Space.xs).padding(.trailing, Space.xs) }
        }
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.open(.archivedTask(story.id), push: true) } // lint: ok the Archive's cards keep their own selection
        .contextMenu { menu }
        .help("\(story.key) \(story.title)")
        .uiTestAnchor("archived:\(story.id)")
    }

    private var actions: some View {
        HStack(spacing: 0) {
            Button("Unarchive", icon: .unarchive) { model.unarchiveFromWindow(match.story.id) }
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, Space.xs)
                .frame(height: Metric.rowAction)
                .help("Bring it back to Tasks, at the end of the list (⌃⌘A)")
                .uiTestAnchor("unarchive:\(match.story.id)")
            Menu { menu } label: { Label("More", icon: .more) }
                .labelStyle(.iconOnly)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: Metric.rowAction, height: Metric.rowAction)
                .help("More")
        }
        .buttonStyle(.borderless)
        .kitType(.meta)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Space.xs)
        .surface(radius: Radius.control, lifted: true)
        .clickable()
    }

    @ViewBuilder
    private var menu: some View {
        let id = match.story.id
        Button("Open") { model.open(.archivedTask(id), push: true) }
        Button("Unarchive") { model.unarchiveFromWindow(id) }
        Divider()
        Button("Copy") { model.copy([.archivedTask(id)]) }
        Button("Open in Obsidian") { model.openInObsidian(model.vault?.archivedURL(id).path) }
        Divider()
        Button("Delete") { model.deleteArchived(id) }
    }
}

/// An archived task's window (T-471): as a task's, read only. Its key and when it was archived, its glyph and title,
/// its project and tags, the tasks under it, its description from its note (read when it opens), its links.
struct ArchivedTaskView: View {
    let id: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        let index = model.archiveShown?.index
        if let entry = index?.entry(id) {
            ModalPage {
                VStack(alignment: .leading, spacing: Space.md) {
                    HStack(spacing: Space.sm) {
                        Text(entry.key).kitType(.key).foregroundStyle(.secondary)
                        Label("Archived \(entry.archived.formatted(.dateTime.day().month(.wide)))"
                              + (entry.done.map { " · done \($0.formatted(.dateTime.day().month(.wide)))" } ?? ""), icon: .archive)
                            .kitType(.meta)
                            .padding(.horizontal, Space.sm)
                            .padding(.vertical, Space.xs)
                            .background(Ink.chipFill, in: Capsule())
                        if entry.root != entry.id, let story = index?.entry(entry.root) {
                            Text("Under")
                            Button("\(story.key) \(story.title)") { model.open(.archivedTask(story.id), push: true) }
                                .buttonStyle(.link)
                                .lineLimit(1)
                        }
                    }
                    .kitType(.key)
                    .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                        TaskGlyph(status: entry.status).scaleEffect(1.35)
                        Text(entry.title).kitType(.pageTitle).textSelection(.enabled)
                    }
                    HStack(spacing: Space.xs) {
                        if let project = entry.project { LabelChip(text: project, color: model.labelColor(.project, project), icon: .project) }
                        ForEach(entry.tags, id: \.self) { tag in LabelChip(text: tag, color: model.labelColor(.tag, tag), icon: .tag) }
                    }
                }
                let under = (index?.entries ?? []).filter { $0.parent == id && $0.root == entry.root }.sorted { $0.id < $1.id }
                if !under.isEmpty {
                    ModalGroup(title: "Subtasks · \(under.count)") {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            ForEach(under, id: \.id) { task in
                                Button { model.open(.archivedTask(task.id), push: true) } label: {
                                    HStack(spacing: Space.sm) {
                                        TaskGlyph(status: task.status)
                                        Text(task.key).kitType(.key).foregroundStyle(.secondary)
                                        Text(task.title).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                    }
                                }
                                .buttonStyle(.plain)
                                .clickable()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Metric.cardPadding)
                        .surface()
                    }
                }
                ModalGroup(title: "Description") {
                    Group {
                        if let note = model.archiveShown?.notes[id] {
                            if note.body.isEmpty { Text("No description.").foregroundStyle(.secondary) } else { MarkdownView(note.body) }
                        } else {
                            LoadingLine(title: "Loading the task…")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Metric.cardPadding)
                    .surface()
                }
                if let links = model.archiveShown?.notes[id]?.links, !links.isEmpty {
                    ModalGroup(title: "Links") {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            ForEach(links, id: \.self) { link in Link(link.absoluteString, destination: link).lineLimit(1).truncationMode(.middle) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Metric.cardPadding)
                        .surface()
                    }
                }
            }
            .onAppear { model.loadArchivedNote(id) }
            .uiTestAnchor("archived-task:\(id)")
        } else if model.archiveShown == nil {
            LoadingLine(title: "Loading the archive…").padding(Space.xxl).onAppear { model.loadArchive() }
        } else {
            ContentUnavailableView("This Item Is Gone", icon: .trash)
        }
    }
}
