import AppKit
import HQKit
import SwiftUI

/// The one page (DESIGN.md §4): the day's title, then pull requests, sessions, files and artifacts, tasks and the
/// Backlog, top to bottom, on a canvas with the sky at its top; the section bar sits in the toolbar.
struct CockpitView: View {
    @Environment(AppModel.self) private var model
    /// The scroll view's visible width: a legacy scroller takes some of the window's.
    @State private var visible: CGFloat = 0
    /// The SwiftUI section with the keyboard.
    @FocusState private var keyboard: PageSection?
    /// Each section's top in the scroll view, and the section in view: only the section bar reads it, so scrolling never redraws the page.
    @State private var tops = SectionTops()

    /// The column's leading inset and width: centered on the 4 pt grid, at most `pageMax` wide.
    static func column(_ visible: CGFloat) -> (inset: CGFloat, width: CGFloat) {
        let margin = visible < Metric.narrowWindow ? Metric.pageMarginNarrow : Metric.pageMargin
        let inset = max(margin, ((visible - Metric.pageMax) / 2 / 4).rounded(.down) * 4)
        return (inset, max(min(visible - inset * 2, Metric.pageMax), 0))
    }

    var body: some View {
        @Bindable var model = model
        let column = Self.column(visible)
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl + Space.xs) {
                    PageTitle()
                    PullRequestsSection(width: column.width)
                        .sectionKeys(.pullRequests, focus: $keyboard)
                        .modifier(SectionTop(section: .pullRequests, tops: tops))
                    SessionsSection(width: column.width)
                        .modifier(SectionTop(section: .sessions, tops: tops))
                    FilesSection(width: column.width)
                        .sectionKeys(.files, focus: $keyboard)
                        .modifier(SectionTop(section: .files, tops: tops))
                    TasksSection(width: column.width)
                        .modifier(SectionTop(section: .tasks, tops: tops))
                }
                .frame(width: column.width, alignment: .leading)
                .padding(.leading, column.inset)
                .padding(.top, Metric.pageTitleTop)
                .padding(.bottom, Space.section)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { model.selectSection(nil) }
                .gridArea("page", inset: 0)
                .handCursors()
                .controlSize(Zoom.controlSize(model.zoom))
                .id(model.zoom)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onScrollGeometryChange(for: CGFloat.self) { $0.visibleRect.width } action: { _, width in
                if abs(width - visible) >= 1 { visible = width }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height > geometry.visibleRect.height + 1 && geometry.visibleRect.maxY >= geometry.contentSize.height - 2
            } action: { _, bottom in
                tops.atBottom = bottom
                tops.update()
            }
            // The keyboard selected a row out of view: the page brings it in.
            .onChange(of: model.scrollTarget) { _, target in
                guard let target else { return }
                model.scrollTarget = nil
                scroller.scrollTo(target)
            }
            .safeAreaBar(edge: .top, spacing: 0) {
                if let problem = model.problem {
                    InlineBanner(message: problem.message, detail: problem.detail, actionTitle: problem.fixTitle) { model.fix(problem) }
                        .frame(width: column.width)
                        .padding(.leading, column.inset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Space.sm)
                }
            }
            // One row (T-326): the section bar sits in the toolbar, while the window has room for it.
            .toolbar {
                CockpitToolbar(tops: tops, sections: model.windowSize.width >= Metric.sectionBarWindow) { section in
                    tops.hold(section)
                    withAnimation(Motion.glide) { scroller.scrollTo(SectionTop.id(section), anchor: .top) }
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { model.windowSize = $0 }
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Ink.content
                SkyView(mood: model.skyMood)
            }
            .ignoresSafeArea()
        }
        .navigationTitle("HQ")
        .toolbar(removing: .title)
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search")
        .sheet(isPresented: Binding(get: { model.modal != nil }, set: { if !$0 { model.closeModal() } })) {
            ModalHost()
        }
        .sheet(isPresented: $model.showSetup) { SetupSheet().handCursors() }
    }
}

/// Where each section starts in the scroll view, unobserved, and the section in view, which the section bar observes.
@Observable final class SectionTops {
    @ObservationIgnored var tops: [PageSection: CGFloat] = [:]
    /// The page scrolls and shows its end: the last section can't reach the line.
    @ObservationIgnored var atBottom = false
    /// A click on the bar holds its section while the page scrolls there.
    @ObservationIgnored private var heldUntil = Date.distantPast
    var current: PageSection = .pullRequests

    /// The section in view: the last one whose top passed under the section bar, or the last section at the page's end.
    func update() {
        guard Date.now >= heldUntil else { return }
        let line = Metric.skyHeight / 3
        let now = atBottom ? PageSection.tasks : PageSection.allCases.last { (tops[$0] ?? .infinity) <= line } ?? .pullRequests
        if now != current { current = now }
    }

    func hold(_ section: PageSection) {
        current = section
        heldUntil = .now + Motion.holdSeconds
    }
}

/// Reports a section's top as the page scrolls; the section bar follows the section in view.
private struct SectionTop: ViewModifier {
    let section: PageSection
    let tops: SectionTops

    static func id(_ section: PageSection) -> String { "section:\(section.rawValue)" }

    func body(content: Content) -> some View {
        content
            .id(Self.id(section))
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY } action: { top in
                tops.tops[section] = top
                tops.update()
            }
    }
}

/// The page's title: the day, big, and one quiet line on what's going on.
private struct PageTitle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(model.now.formatted(.dateTime.weekday(.wide)))
                    .kitType(.largeTitle)
                Text(model.now.formatted(.dateTime.day().month(.wide)))
                    .kitType(.largeTitleLight)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Text(model.daySummary)
                .kitType(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .frame(height: Metric.pageTitle, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .gridProbe("page-title", area: "page")
    }
}

/// The section bar, in the toolbar (DESIGN.md §3): every section, the one in view highlighted. A click scrolls to it.
private struct SectionBar: View {
    let tops: SectionTops
    let go: (PageSection) -> Void
    @Environment(AppModel.self) private var model
    @Namespace private var glide

    var body: some View {
        let current = tops.current
        GlassEffectContainer {
            HStack(spacing: Metric.lineGap) {
                ForEach(PageSection.allCases, id: \.self) { section in
                    Button { go(section) } label: {
                        HStack(spacing: Space.xs + 2) {
                            section.icon.image
                                .imageScale(.small)
                                .fontWeight(.semibold)
                                .foregroundStyle(current == section ? AnyShapeStyle(Ink.section(section)) : AnyShapeStyle(.secondary))
                            Text(section.shortTitle)
                                .kitType(current == section ? .titleStrong : .title)
                                .foregroundStyle(current == section ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        }
                        .padding(.horizontal, Space.md)
                        .frame(height: Metric.sectionBarItem)
                        .background {
                            if current == section {
                                Capsule()
                                    .fill(Ink.barSelection)
                                    .matchedGeometryEffect(id: "current", in: glide)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help("Go to \(section.title)")
                    .accessibilityLabel(section.title)
                    .accessibilityAddTraits(current == section ? .isSelected : [])
                }
            }
            .padding(Metric.lineGap)
            // Not interactive: a bar this wide stretching on each click reads as wobble.
            .glassEffect(.regular, in: Capsule())
            .animation(Motion.glide, value: current)
        }
        .fixedSize()
    }
}

/// The toolbar (DESIGN.md §3), one row: the bell and New, the section bar in the middle while it fits, the search on the
/// trailing side.
struct CockpitToolbar: ToolbarContent {
    let tops: SectionTops
    let sections: Bool
    let go: (PageSection) -> Void
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        if sections {
            ToolbarItem(id: "sections", placement: .principal) {
                SectionBar(tops: tops, go: go)
                    .uiTestAnchor("section-bar")
            }
            // Its own glass, with the section in view highlighted inside it.
            .sharedBackgroundVisibility(.hidden)
        }
        ToolbarItem(id: "bell", placement: .navigation) {
            NotificationBell(needs: model.importantCount, updates: model.updateCount, breathing: model.bellBreathes) { model.openCenter() }
                .help("\(model.noticeSummary). Open the notifications (⌘J)")
                .toolbarClickable()
                .uiTestAnchor("bell")
        }
        // Right of the bell at every width, the section bar there or not.
        ToolbarItem(id: "new", placement: .navigation) {
            Menu {
                Button("New Task…") { model.beginTask(.overview) }
                Button("New File…") { model.beginNewFile() }
                Button("New Session…") { model.beginStart() }
                Button("New Reminder…") { model.beginReminder() }
            } label: {
                Label("New", icon: .new)
            }
            .menuIndicator(.hidden)
            .toolbarClickable()
            .uiTestAnchor("new")
            .help("New task (⌘N), file, session or reminder (⌃⌘R)")
        }
    }
}

extension AppModel {
    /// The sky's mood: warm while something needs the user, calm otherwise.
    var skyMood: SkyMood { importantCount > 0 ? .needsYou : .calm }

    /// "4 sessions need you · 2 reviews wait · 3 working · 8 tasks open": one line under the day, what needs the user first
    /// (2026-11-11).
    var daySummary: String {
        let needYou = gridSessions.filter { $0.isRunning && $0.status.needsYou }.count
        let working = gridSessions.filter { $0.isRunning && ($0.status.state == .working || $0.status.state == .compacting) }.count
        let waiting = reviewRequests.filter(waitsForReview).count
        let open = taskTree.top(.overview).filter { task($0)?.status != .done }.count
        var parts: [String] = []
        if needYou > 0 { parts.append("\(needYou) session\(needYou == 1 ? " needs" : "s need") you") }
        if waiting > 0 { parts.append("\(waiting) review\(waiting == 1 ? " waits" : "s wait")") }
        if working > 0 { parts.append("\(working) working") }
        if open > 0 { parts.append("\(open) task\(open == 1 ? "" : "s") open") }
        return parts.isEmpty ? "A quiet day: nothing running, nothing open." : parts.joined(separator: " · ")
    }
}


// MARK: Sessions

struct SessionsSection: View {
    let width: CGFloat
    @Environment(AppModel.self) private var model

    var body: some View {
        let shown = model.filteredGrid
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: PageSection.sessions.title, count: model.search.isEmpty ? "\(shown.count)" : "\(shown.count) of \(model.gridSessions.count)",
                          open: model.sectionOpen(.sessions), tile: (PageSection.sessions.icon, Ink.section(.sessions))) {
                let closed = model.closedSessions.count
                Button { model.open(.closedSessions) } label: { HeaderIcon(icon: .closedSessions, count: closed) }
                    .disabled(closed == 0)
                    .help("Closed Sessions: resume one closed in the last 14 days")
                    .accessibilityLabel("Closed Sessions, \(closed)")
                Button { model.beginStart() } label: { HeaderIcon(icon: .new) }
                    .help("New Session: start a Claude session in Ghostty (⇧⌘N)")
                    .accessibilityLabel("New Session")
            }
            .gridProbe("sessions-header", area: "page")
            if model.folded.contains(.sessions) {
                EmptyView()
            } else if model.gridSessions.isEmpty {
                EmptySection(title: "No Sessions", message: "Sessions you start with the hq plugin show up here.") {
                    Button("New Session…") { model.beginStart() }
                }
            } else if shown.isEmpty {
                EmptySection(title: "No Matching Sessions", message: "No session matches “\(model.search)”.") { EmptyView() }
            } else {
                SessionGrid(sessions: shown, width: width)
            }
        }
    }
}

/// An empty state where the content would be, at the content's width.
struct EmptySection<Actions: View>: View {
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: Metric.lineGap) {
                Text(title).kitType(.titleStrong)
                Text(message).kitType(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.sm)
            actions
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
        .gridProbe("empty-\(title)", area: "page")
    }
}

extension AppModel {
    /// The grid, filtered by the search field.
    var filteredGrid: [SessionItem] {
        guard !search.isEmpty else { return gridSessions }
        return gridSessions.filter { $0.searchText.localizedStandardContains(search) }
    }

    /// A list's quick-add line takes the keyboard (its list unfolds first).
    func focusQuickAdd(_ list: TaskList) {
        closeModal()
        showWindow()
        if list == .backlog { backlogOpen = true } else { folded.remove(.tasks) }
        quickAddFocus = list
    }

    /// File › New Task… (⌘N, ⌥⌘N for the Backlog): its own small sheet, over what's open (T-332).
    func beginTask(_ list: TaskList) {
        if case .newTask = modal { return }
        showWindow()
        open(.newTask(list), push: modal != nil)
    }

    /// A task New Task… added: its list unfolds and its row is selected, so the user sees where it went.
    func show(newTask id: Int, in list: TaskList) {
        if list == .backlog { backlogOpen = true } else { folded.remove(.tasks) }
        outlineFocus = .row(id)
    }
}
