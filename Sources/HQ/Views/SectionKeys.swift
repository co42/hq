import HQKit
import SwiftUI

/// The page's sections, in Tab order.
enum PageSection: String, CaseIterable {
    case pullRequests, sessions, files, tasks

    /// Its header's title.
    var title: String {
        switch self {
        case .pullRequests: "Pull Requests"
        case .sessions: "Sessions"
        case .files: "Files and Artifacts"
        case .tasks: "Tasks"
        }
    }

    /// Its name in the section bar.
    var shortTitle: String {
        switch self {
        case .files: "Files"
        default: title
        }
    }

    /// The symbol on its tile.
    var icon: KitIcon {
        switch self {
        case .pullRequests: .pullRequest
        case .sessions: .sessions
        case .files: .files
        case .tasks: .tasks
        }
    }
}

/// A SwiftUI section with the keyboard: arrows move the selection, Return and Space open it,
/// Tab and ⇧Tab go to the next or previous section.
struct SectionKeys: ViewModifier {
    let section: PageSection
    var focus: FocusState<PageSection?>.Binding
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused(focus, equals: section)
            .focusEffectDisabled()
            // ⇧Tab types the backtab character.
            .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")]) { press in
                model.moveSection(from: section, by: press.key == .tab && !press.modifiers.contains(.shift) ? 1 : -1)
                return .handled
            }
            .onKeyPress(.upArrow) { model.moveSelection(in: section, by: -1) ? .handled : .ignored }
            .onKeyPress(.downArrow) { model.moveSelection(in: section, by: 1) ? .handled : .ignored }
            .onKeyPress(.return) { model.openSelected(in: section) ? .handled : .ignored }
            .onKeyPress(.space) { model.openSelected(in: section) ? .handled : .ignored }
            .onChange(of: model.sectionFocus) { _, next in
                guard next == section else { return }
                model.sectionFocus = nil
                focus.wrappedValue = section
                model.selectFirst(in: section)
            }
    }
}

extension View {
    func sectionKeys(_ section: PageSection, focus: FocusState<PageSection?>.Binding) -> some View {
        modifier(SectionKeys(section: section, focus: focus))
    }
}

extension AppModel {
    /// Tab and ⇧Tab: the next or previous section with something to select, round the page. The
    /// section left keeps its selection aside, unselected, for when Tab comes back.
    @discardableResult
    func moveSection(from section: PageSection, by offset: Int) -> PageSection? {
        let all = PageSection.allCases
        guard var index = all.firstIndex(of: section) else { return nil }
        for _ in all.indices {
            index = (index + offset + all.count) % all.count
            let next = all[index]
            guard hasRows(next) else { continue }
            if next != section { selectSection(next) }
            sectionFocus = next
            return next
        }
        return nil
    }

    /// A click or Tab gives a section the page's selection: the others unselect, theirs kept aside for when Tab
    /// comes back. nil, a click on nothing: every section unselects.
    func selectSection(_ section: PageSection?) {
        for other in PageSection.allCases where other != section { park(other) }
        if selectedSection != section { selectedSection = section }
    }

    private func park(_ section: PageSection) {
        switch section {
        case .pullRequests, .files:
            guard modal == nil, let key = selectedItem, Self.section(ofItem: key) == section else { return }
            parkedItems[section] = key
            selectedItem = nil
        case .sessions:
            guard let id = selectedSession else { return }
            parkedItems[.sessions] = id
            selectedSession = nil
        case .tasks:
            // The rows unselect on the outline's next update; a chip under a row now.
            if modal == nil, selectedItem.flatMap(Self.section(ofItem:)) == .tasks { selectedItem = nil }
        }
    }

    /// The section a selection key belongs to on the page: a PR's row, a file's or an artifact's, a chip under a task.
    static func section(ofItem key: String) -> PageSection? {
        if key.hasPrefix("github:") { return .pullRequests }
        if key.hasPrefix("file:") || key.hasPrefix("artifact:") { return .files }
        if key.hasPrefix(ModalRoute.chipPrefix) { return .tasks }
        return nil
    }

    func hasRows(_ section: PageSection) -> Bool {
        if section != .tasks && folded.contains(section) { return false }
        return switch section {
        case .pullRequests, .files: !sectionRoutes(section).isEmpty
        case .sessions: !filteredGrid.isEmpty
        case .tasks: true
        }
    }

    /// The rows a SwiftUI section shows, top to bottom, left card first.
    func sectionRoutes(_ section: PageSection) -> [ModalRoute] {
        let limit = search.isEmpty ? PRCards.shown : Int.max
        switch section {
        case .pullRequests:
            func shown(_ items: [GitHubItem]) -> [ModalRoute] {
                items.filter { search.isEmpty || "\($0.title) \($0.reference) \($0.author)".localizedStandardContains(search) }
                    .prefix(limit).map { .github($0.url) }
            }
            return shown(reviewRequests) + shown(ownPullRequests)
        case .files:
            let limit = search.isEmpty && !pinnedOnly ? PRCards.shown : Int.max
            return listedFiles.prefix(limit).map { .file($0.id) } + listedArtifacts.prefix(limit).map { .artifact($0.id) }
        case .sessions, .tasks:
            return []
        }
    }

    /// The row selected when Tab last left the section, else the first. A row a click selected stays.
    func selectFirst(in section: PageSection) {
        let routes = sectionRoutes(section)
        guard selectedItem.flatMap(Self.section(ofItem:)) != section else { scrollTarget = selectedItem; return }
        let parked = parkedItems[section].flatMap { key in routes.contains { $0.selectionKey == key } ? key : nil }
        selectedItem = parked ?? routes.first?.selectionKey
        scrollTarget = selectedItem
    }

    @discardableResult
    func moveSelection(in section: PageSection, by offset: Int) -> Bool {
        let routes = sectionRoutes(section)
        guard !routes.isEmpty else { return false }
        let index = routes.firstIndex { $0.selectionKey == selectedItem }.map { min(max($0 + offset, 0), routes.count - 1) } ?? 0
        selectedItem = routes[index].selectionKey
        scrollTarget = selectedItem
        return true
    }

    func openSelected(in section: PageSection) -> Bool {
        guard let route = sectionRoutes(section).first(where: { $0.selectionKey == selectedItem }) else { return false }
        open(route)
        return true
    }
}
