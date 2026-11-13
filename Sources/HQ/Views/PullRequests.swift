import AppKit
import HQKit
import SwiftUI

/// Pull requests (DESIGN.md §6): what waits for the user's review, and their own, side by side.
struct PullRequestsSection: View {
    let width: CGFloat
    @Environment(AppModel.self) private var model

    var body: some View {
        let waiting = model.searched(model.reviewRequests)
        let mine = model.searched(model.ownPullRequests)
        let total = model.reviewRequests.count + model.ownPullRequests.count
        let shown = waiting.count + mine.count
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: PageSection.pullRequests.title, count: model.search.isEmpty ? "\(total)" : "\(shown) of \(total)",
                          open: model.sectionOpen(.pullRequests), tile: (PageSection.pullRequests.icon, Ink.section(.pullRequests))) {
                if model.github != nil { RefreshButton() }
                Button { NSWorkspace.shared.open(URL(string: "https://github.com/pulls")!) } label: { HeaderIcon(icon: .openExternal) }
                    .help("Open your pull requests on github.com")
                    .accessibilityLabel("Open GitHub")
            }
            if model.folded.contains(.pullRequests) {
                EmptyView()
            } else if model.github == nil {
                EmptySection(title: setupTitle, message: setupMessage) {
                    if model.setup.ghPath != nil || model.problem == .githubSignedOut {
                        Button("Copy Command") { Pasteboard.copy("gh auth login") }
                    }
                }
            } else {
                let layout = width >= Metric.prSideBySide
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: Metric.cardGap))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: Metric.cardGap))
                let searching = !model.search.isEmpty
                layout {
                    PRGroup(title: "Reviews", card: .reviews, items: waiting, total: model.reviewRequests.count,
                            empty: searching ? "No match for “\(model.search)”." : "Nothing waits for your review.", filtered: searching,
                            allReviewed: !searching) {
                        @Bindable var model = model
                        // Always there: it brings back what it hides.
                        FilterPicker(icon: .filter, name: "Reviews", value: model.reviewFilter.title + (model.reviewDrafts ? " + Drafts" : ""),
                                     active: model.reviewFilter != .notApproved || model.reviewDrafts,
                                     help: model.reviewFilter.help + (model.reviewDrafts ? ", drafts included" : ", drafts left out")) {
                            Picker("Reviews", selection: $model.reviewFilter) {
                                ForEach(ReviewFilter.allCases) { Text($0.title).tag($0) }
                            }
                            Divider()
                            Toggle("Show Drafts", isOn: $model.reviewDrafts)
                        }
                    }
                    PRGroup(title: "Yours", card: .yours, items: mine, total: model.ownPullRequests.count,
                            empty: searching ? "No match for “\(model.search)”." : "No open pull requests.", filtered: searching)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Updated just now", "Updated 3 minutes ago".
    /// When GitHub last answered: in the tooltip, not on the page. It turns while HQ asks.
    /// Its own view: a poll that changed nothing redraws only this.
    private struct RefreshButton: View {
        @Environment(AppModel.self) private var model

        var body: some View {
            let fetched = model.githubUpdated ?? model.now
            Button { model.refreshGitHub() } label: {
                HeaderIcon(icon: .reload)
                    .symbolEffect(.rotate, isActive: model.githubPolling)
            }
            .disabled(model.githubPolling)
            .help("Refresh: ask GitHub now. \(PullRequestsSection.updated(fetched, now: model.now)); HQ asks every two minutes while it's on screen")
            .accessibilityLabel(model.githubPolling ? "Refreshing" : "Refresh")
        }
    }

    static func updated(_ fetched: Date, now: Date) -> String {
        guard now.timeIntervalSince(fetched) >= 60 else { return "Updated just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Updated " + formatter.localizedString(for: fetched, relativeTo: now)
    }

    private var setupTitle: String {
        switch model.problem {
        case .githubMissing: "GitHub CLI isn’t installed"
        case .githubSignedOut: "GitHub CLI is signed out"
        default: "Waiting for GitHub"
        }
    }

    private var setupMessage: String {
        switch model.problem {
        case .githubMissing: "Install it with brew install gh, then run gh auth login."
        case .githubSignedOut: "Run gh auth login in a terminal; your pull requests show up a minute later."
        default: "Your pull requests show up after the first answer."
        }
    }
}

/// One of the two cards: a title with its count, then its rows, five before "Show N More" (every one while the search narrows them).
struct PRGroup<Accessory: View>: View {
    let title: String
    let card: RowCard
    let items: [GitHubItem]
    let total: Int
    let empty: String
    var filtered = false
    /// Empty and not searching: the user has reviewed everything.
    var allReviewed = false
    /// On the title's line, trailing.
    @ViewBuilder var accessory: Accessory
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.sm) {
                Text(title).kitType(.titleStrong)
                Text(filtered ? "\(items.count) of \(total)" : "\(total)").kitType(.meta).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                // As the sections' controls, shorter: as far from the card's edge as from its top.
                accessory
                    .buttonStyle(HeaderButtonStyle(compact: true))
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .padding(.trailing, -Space.xs)
            }
            .padding(.horizontal, Space.md)
            .frame(height: Metric.boxRow + Space.xs, alignment: .center)
            if items.isEmpty, allReviewed {
                AllClear(title: "All reviewed")
            } else if items.isEmpty {
                Text(empty)
                    .kitType(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Space.md)
                    .frame(height: Metric.boxRow, alignment: .top)
            } else {
                let rows = model.shown(items, in: card)
                VStack(spacing: 0) {
                    ForEach(rows) { item in
                        PRRow(item: item)
                            .id(ModalRoute.github(item.url).selectionKey)
                            .overlay(alignment: .bottom) { if item.id != rows.last?.id { RowRule() } }
                    }
                    ShowMoreButton(card: card, count: items.count)
                }
                .padding(.horizontal, Space.xs + 2)
                .padding(.bottom, Space.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .surface()
    }
}

extension PRGroup where Accessory == EmptyView {
    init(title: String, card: RowCard, items: [GitHubItem], total: Int, empty: String, filtered: Bool = false, allReviewed: Bool = false) {
        self.init(title: title, card: card, items: items, total: total, empty: empty, filtered: filtered, allReviewed: allReviewed) { EmptyView() }
    }
}

/// What every card of rows shares: PRs, files and artifacts.
enum PRCards {
    /// Rows shown before "Show N More": the page stays short with many open PRs.
    static let shown = 5
}

/// The page's cards of rows, each opened past its first five on its own.
enum RowCard: String {
    case reviews, yours, files, artifacts

    /// What its rows are, for the tooltip of "Show N More".
    var rows: String {
        switch self {
        case .reviews, .yours: "pull request"
        case .files: "file"
        case .artifacts: "artifact"
        }
    }
}

/// "Show N More" under a card's first five rows, "Show Fewer" once open; nothing while a filter shows them all.
struct ShowMoreButton: View {
    let card: RowCard
    /// The card's rows, shown or not.
    let count: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        if count > PRCards.shown, !model.cardFiltered(card) {
            let open = model.expandedCards.contains(card)
            Button(open ? "Show Fewer" : "Show \(count - PRCards.shown) More") { model.toggleExpanded(card) }
                .buttonStyle(.borderless)
                .clickable()
                .kitType(.callout)
                .help(open ? "Show the first \(PRCards.shown) only" : "Show every \(card.rows) in this card")
                .uiTestAnchor("show-more:\(card.rawValue)")
                .padding(.leading, Space.sm)
                .frame(maxWidth: .infinity, minHeight: Metric.boxRow, alignment: .leading)
        }
    }
}

extension AppModel {
    /// The PRs the page's search leaves: title, reference or author.
    func searched(_ items: [GitHubItem]) -> [GitHubItem] {
        guard !search.isEmpty else { return items }
        return items.filter { "\($0.title) \($0.reference) \($0.author)".localizedStandardContains(search) }
    }

    /// A filter narrows the card: it shows every row it leaves.
    func cardFiltered(_ card: RowCard) -> Bool {
        switch card {
        case .reviews, .yours: !search.isEmpty
        case .files, .artifacts: filesFiltered
        }
    }

    /// Every row of a card, shown or not, top to bottom.
    func cardRoutes(_ card: RowCard) -> [ModalRoute] {
        switch card {
        case .reviews: searched(reviewRequests).map { .github($0.url) }
        case .yours: searched(ownPullRequests).map { .github($0.url) }
        case .files: listedFiles.map { .file($0.id) }
        case .artifacts: listedArtifacts.map { .artifact($0.id) }
        }
    }

    /// The rows a card shows, which the keys walk too: all of them while a filter narrows it or Show More opened it, else the first five.
    func shown<Row>(_ rows: [Row], in card: RowCard) -> [Row] {
        cardFiltered(card) || expandedCards.contains(card) ? rows : Array(rows.prefix(PRCards.shown))
    }

    /// Show N More or Show Fewer; a selected row Show Fewer hides gives the selection to the last row still shown.
    func toggleExpanded(_ card: RowCard) {
        guard expandedCards.remove(card) != nil else {
            expandedCards.insert(card)
            return
        }
        let rows = cardRoutes(card)
        if let index = rows.firstIndex(where: { $0.selectionKey == selectedItem }), index >= PRCards.shown {
            selectedItem = rows[PRCards.shown - 1].selectionKey
        }
    }
}

/// Opens a PR or an issue in the browser.
struct OpenOnGitHubButton: View {
    let url: String

    var body: some View {
        Button("Open on GitHub", icon: .openExternal) { if let link = URL(string: url) { NSWorkspace.shared.open(link) } }
            .clickable()
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .clickable()
            .foregroundStyle(.secondary)
            .frame(width: Metric.rowAction, height: Metric.rowAction)
            .help("Open on GitHub")
    }
}

/// A hairline between rows in a card, starting where the rows' text starts.
struct RowRule: View {
    var body: some View {
        Ink.rowRule
            .frame(height: 1)
            .padding(.leading, RowLead<EmptyView, EmptyView>.textInset)
            .padding(.trailing, Space.sm)
            .allowsHitTesting(false)
    }
}

/// The left of every PR, file and artifact row (DESIGN.md §6): one face against the kind's icon.
/// The rows of the three cards line up.
struct RowLead<Faces: View, Icon: View>: View {
    /// Where a row's text starts: the row's padding, the face, the icon.
    static var textInset: CGFloat { Space.sm + Metric.faceRow + Space.sm + Metric.kindTile + Space.sm }

    @ViewBuilder var faces: Faces
    @ViewBuilder var icon: Icon

    var body: some View {
        HStack(spacing: Space.sm) {
            faces.frame(width: Metric.faceRow)
            icon.frame(width: Metric.kindTile)
        }
    }
}

/// "registry #418 · julien · asked 2h ago". Its own view: the clock's tick redraws only this line.
private struct PRByline: View {
    let item: GitHubItem
    @Environment(AppModel.self) private var model

    var body: some View {
        Text("\(item.reference) · \(item.author) · \(PRRow.when(item, now: model.now))")
            .kitType(.secondary)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// A PR row: its title in the middle; its status and its task's key in fixed columns on the right.
struct PRRow: View {
    let item: GitHubItem
    @Environment(AppModel.self) private var model
    @State private var hovering = false
    @State private var linking = false

    var body: some View {
        let waits = model.waitsForReview(item)
        let task = model.tasks(linking: item.url).first
        let sessions = model.byImportance(model.sessions(onPullRequest: item, includeEnded: true))
        HStack(spacing: Space.sm) {
                RowLead {
                    // As a task's faces: a click shows the first session's menu, or starts one.
                    FaceStack(sessions: Array(sessions.prefix(1)), size: Metric.faceRow, limit: 1)
                        .overlay {
                            ClickTarget { view in
                                if let first = sessions.first, let menu = model.faceMenu(first.id, pullRequest: item) {
                                    FaceMenu.showUnder(view, menu, first.id)
                                } else {
                                    model.beginStart(pullRequest: item)
                                }
                            }
                        }
                        .help(sessions.isEmpty ? "Start a session on it" : sessions.map(\.name).joined(separator: "\n") + "\nClick the face for its session's menu")
                        .uiTestAnchor("pr-face:\(item.number)")
                } icon: {
                    GitHubStateIcon.tile(item)
                }
                VStack(alignment: .leading, spacing: Metric.lineGap) {
                    HStack(spacing: Space.xs) {
                        ReminderMark(route: .github(item.url))
                        Text(item.title)
                            .kitType(waits ? .titleStrong : .title)
                            .lineLimit(1)
                    }
                    PRByline(item: item)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: Metric.lineGap) {
                    reviewLine(waits: waits)
                    checksLine
                }
                .frame(width: Metric.rowStatus, alignment: .leading)
                ZStack(alignment: .trailing) {
                    Color.clear
                    if let task { KeyLabel(key: task.key) }
                }
                .frame(width: Metric.rowKey)
            }
            .padding(.horizontal, Space.sm)
            .frame(height: Metric.prRow)
            .background(hovering ? Ink.hoverFill : Color.clear, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .selectOpen(ModalRoute.github(item.url).selectionKey, in: .pullRequests) { model.open(.github(item.url)) }
        .onDrag { DragItem.provider(.github(item.url), line: model.line(of: .github(item.url))) }
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .help("\(item.title) (\(item.reference))")
        .contextMenu {
            Button("Show Details") { model.open(.github(item.url)) }
            Button("Open on GitHub") { if let url = URL(string: item.url) { NSWorkspace.shared.open(url) } }
            if waits { Button("Mark Reviewed") { model.markReviewed(item.url) } }
            Divider()
            Button("Start Review Session…") { model.beginStart(pullRequest: item) }
            Button("Link to Task…") { linking = true }
            Button("Remind Me…") { model.beginReminder(about: .github(item.url)) }
            Divider()
            Button("Copy") { model.copy([.github(item.url)]) }
            Button("Copy Link") { Pasteboard.copy(item.url) }
        }
        .popover(isPresented: $linking, arrowEdge: .bottom) { TaskFinder { model.link(.github(item.url), to: $0); linking = false } }
        .uiTestAnchor("pr:\(item.number)")
    }

    /// "Waiting for you", "Approved by you", "You asked for changes", "Reviewed", "Draft", "Approved by noor".
    static func reviewText(_ item: GitHubItem, waits: Bool) -> String {
        func by(_ what: String) -> String { item.reviewers.isEmpty ? what : "\(what) by \(item.reviewers.joined(separator: ", "))" }
        if item.reviewRequested || item.reviewedByMe {
            if waits { return "Waiting for you" }
            if item.myReview == .approved { return "Approved by you" }
            if item.review == .approved { return by("Approved") }
            if item.myReview == .changesRequested { return "You asked for changes" }
            return "Reviewed"
        }
        if item.state == .draft { return "Draft" }
        switch item.review {
        case .approved: return by("Approved")
        case .changesRequested: return by("Changes requested")
        case .required, .none: return "Review required"
        }
    }

    /// "asked 2h ago" in Reviews, "updated just now" in Yours.
    static func when(_ item: GitHubItem, now: Date) -> String {
        let (what, date): (String, Date) = item.mine ? ("updated", item.updatedAt)
            : item.reviewRequestedAt.map { ("asked", $0) } ?? item.myReviewAt.map { ("reviewed", $0) } ?? ("updated", item.updatedAt)
        return now.timeIntervalSince(date) < 60 ? "\(what) just now" : "\(what) \(Elapsed.short(from: date, to: now)) ago"
    }

    static func checksText(_ item: GitHubItem) -> String {
        switch item.checks {
        case .passed: "Checks passed"
        case .failed: "Checks failed"
        case .running: "Checks running"
        case .none: "No checks"
        }
    }

    private func reviewLine(waits: Bool) -> some View {
        let color: AnyShapeStyle = if item.reviewRequested || item.reviewedByMe {
            waits ? AnyShapeStyle(Ink.needsYouText) : item.approved ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
        } else if item.state == .draft {
            AnyShapeStyle(.secondary)
        } else {
            switch item.review {
            case .approved: AnyShapeStyle(.primary)
            case .changesRequested: AnyShapeStyle(Ink.failedText)
            case .required, .none: AnyShapeStyle(.secondary)
            }
        }
        return Text(Self.reviewText(item, waits: waits))
            .foregroundStyle(color)
            .fontWeight(waits ? .semibold : .regular)
            .kitType(.secondary)
            .lineLimit(1)
    }

    private var checksLine: some View {
        HStack(spacing: Space.xs) {
            switch item.checks {
            case .passed:
                KitIcon.checkPassed.image.foregroundStyle(Ink.done).accessibilityHidden(true)
                Text(Self.checksText(item)).foregroundStyle(.secondary)
            case .failed:
                KitIcon.checkFailed.image.foregroundStyle(Ink.failed).accessibilityHidden(true)
                Text(Self.checksText(item)).foregroundStyle(Ink.failedText)
            case .running:
                KitIcon.checkRunning.image.foregroundStyle(.secondary).accessibilityHidden(true)
                Text(Self.checksText(item)).foregroundStyle(.secondary)
            case .none:
                Text(Self.checksText(item)).foregroundStyle(.secondary)
            }
        }
        .kitType(.secondary)
        .imageScale(.small)
        .lineLimit(1)
    }

}
