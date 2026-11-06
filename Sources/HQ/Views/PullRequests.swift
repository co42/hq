import AppKit
import HQKit
import SwiftUI

/// Pull requests (DESIGN.md §6): what waits for the user's review, and their own, side by side.
struct PullRequestsSection: View {
    let width: CGFloat
    @Environment(AppModel.self) private var model

    var body: some View {
        let waiting = filtered(model.reviewRequests)
        let mine = filtered(model.ownPullRequests)
        let total = model.reviewRequests.count + model.ownPullRequests.count
        let shown = waiting.count + mine.count
        VStack(alignment: .leading, spacing: Space.md) {
            SectionHeader(title: PageSection.pullRequests.title, count: model.search.isEmpty ? "\(total)" : "\(shown) of \(total)",
                          open: model.sectionOpen(.pullRequests), tile: (PageSection.pullRequests.icon, Ink.section(.pullRequests))) {
                if let fetched = model.github?.fetchedAt {
                    // When GitHub last answered: in the tooltip, not on the page. A spinner on it while HQ asks.
                    Button { model.refreshGitHub() } label: {
                        HeaderIcon(icon: .reload)
                            .opacity(model.githubPolling ? 0 : 1)
                            .overlay { if model.githubPolling { ProgressView().controlSize(.small) } }
                    }
                    .disabled(model.githubPolling)
                    .help("Refresh: ask GitHub now. \(Self.updated(fetched, now: model.now)); HQ asks every minute while it's in front")
                    .accessibilityLabel(model.githubPolling ? "Refreshing" : "Refresh")
                }
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
                    PRGroup(title: "Waiting for your review", items: waiting, total: model.reviewRequests.count,
                            empty: searching ? "No match for “\(model.search)”." : "Nothing waits for your review.", filtered: searching,
                            allReviewed: !searching) {
                        @Bindable var model = model
                        // Always there: what the user reviewed shows here even when nothing waits.
                        Toggle("Show Reviewed", isOn: $model.showReviewed)
                            .toggleStyle(.button)
                            .controlSize(.small)
                            .clickable()
                            .help("Also list the open pull requests you already reviewed")
                    }
                    PRGroup(title: "Yours", items: mine, total: model.ownPullRequests.count,
                            empty: searching ? "No match for “\(model.search)”." : "No open pull requests.", filtered: searching)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Updated just now", "Updated 3 minutes ago".
    static func updated(_ fetched: Date, now: Date) -> String {
        guard now.timeIntervalSince(fetched) >= 60 else { return "Updated just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Updated " + formatter.localizedString(for: fetched, relativeTo: now)
    }

    private func filtered(_ items: [GitHubItem]) -> [GitHubItem] {
        guard !model.search.isEmpty else { return items }
        return items.filter { "\($0.title) \($0.reference) \($0.author)".localizedStandardContains(model.search) }
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

/// One of the two cards: a title with its count, then its rows.
struct PRGroup<Accessory: View>: View {
    let title: String
    let items: [GitHubItem]
    let total: Int
    let empty: String
    var filtered = false
    /// Empty and not searching: the user has reviewed everything.
    var allReviewed = false
    /// On the title's line, trailing.
    @ViewBuilder var accessory: Accessory
    @State private var expanded = false
    @Environment(AppModel.self) private var model

    /// Rows shown before "Show N More": the page stays short with many open PRs.
    static var shown: Int { PRCards.shown }
    static var minHeight: CGFloat { PRCards.minHeight }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.sm) {
                Text(title).kitType(.titleStrong)
                Text(filtered ? "\(items.count) of \(total)" : "\(total)").kitType(.meta).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                accessory
            }
            .padding(.horizontal, Space.md)
            .frame(height: Metric.boxRow + Space.xs, alignment: .center)
            if items.isEmpty, allReviewed {
                AllReviewed()
            } else if items.isEmpty {
                Text(empty)
                    .kitType(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Space.md)
                    .frame(height: Metric.boxRow, alignment: .top)
            } else {
                let rows = expanded || filtered ? items : Array(items.prefix(Self.shown))
                VStack(spacing: 0) {
                    ForEach(rows) { item in
                        PRRow(item: item)
                            .id(ModalRoute.github(item.url).selectionKey)
                            .overlay(alignment: .bottom) { if item.id != rows.last?.id { RowRule() } }
                    }
                    if items.count > Self.shown, !filtered {
                        Button(expanded ? "Show Fewer" : "Show \(items.count - Self.shown) More") { expanded.toggle() }
                            .buttonStyle(.borderless)
                            .clickable()
                            .kitType(.callout)
                            .padding(.leading, Space.sm + Metric.attentionDot + Space.sm)
                            .frame(maxWidth: .infinity, minHeight: Metric.boxRow, alignment: .leading)
                            .help(expanded ? "Show the first \(Self.shown) only" : "Show every pull request in this group")
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

extension PRGroup where Accessory == EmptyView {
    init(title: String, items: [GitHubItem], total: Int, empty: String, filtered: Bool = false, allReviewed: Bool = false) {
        self.init(title: title, items: items, total: total, empty: empty, filtered: filtered, allReviewed: allReviewed) { EmptyView() }
    }
}

/// The size every card of rows shares: PRs, files and artifacts.
enum PRCards {
    /// Rows shown before "Show N More": the page stays short with many open PRs.
    static let shown = 5
    /// As tall as a full card, its title, five rows and "Show N More": side by side or alone, the cards match.
    static var minHeight: CGFloat { Metric.boxRow + Space.xs + CGFloat(shown) * Metric.prRow + Metric.boxRow + Space.xs }
    /// The same for one-line rows: files and artifacts.
    static var itemMinHeight: CGFloat { Metric.boxRow + Space.xs + CGFloat(shown) * Metric.itemRow + Metric.boxRow + Space.xs }
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

/// The left of every PR, file and artifact row (DESIGN.md §6): the dot, one face against the kind's icon.
/// The rows of the three cards line up.
struct RowLead<Faces: View, Icon: View>: View {
    /// Where a row's text starts: the row's padding, the dot and face, the icon.
    static var textInset: CGFloat { Space.sm + Metric.attentionDot + Space.xs + Metric.faceRow + Space.sm + Metric.kindTile + Space.sm }

    let needsYou: Bool
    let isNew: Bool
    @ViewBuilder var faces: Faces
    @ViewBuilder var icon: Icon

    var body: some View {
        HStack(spacing: Space.sm) {
            HStack(spacing: Space.xs) {
                AttentionDot(needsYou: needsYou, isNew: isNew)
                faces
            }
            .frame(width: Metric.attentionDot + Space.xs + Metric.faceRow, alignment: .trailing)
            icon.frame(width: Metric.kindTile)
        }
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
        let fresh = model.isNew(.github(item.url))
        let task = model.tasks(linking: item.url).first
        let sessions = AppModel.byImportance(model.sessions(onPullRequest: item, includeEnded: true))
        HStack(spacing: Space.sm) {
                RowLead(needsYou: waits, isNew: fresh) {
                    FaceStack(sessions: Array(sessions.prefix(1)), size: Metric.faceRow, limit: 1)
                        .overlay { if sessions.isEmpty { ClickTarget { model.beginStart(pullRequest: item) } } }
                        .help(sessions.isEmpty ? "Start a review session" : sessions.map(\.name).joined(separator: "\n") + "\nClick the face for its session's menu")
                } icon: {
                    GitHubStateIcon.tile(item)
                }
                VStack(alignment: .leading, spacing: Metric.lineGap) {
                    Text(item.title)
                        .kitType(waits || fresh ? .titleStrong : .title)
                        .lineLimit(1)
                    Text("\(item.reference) · \(item.author)")
                        .kitType(.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
        .onDrag { DragItem.provider(.github(item.url), title: item.title) }
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
            Button("Copy Link") { Pasteboard.copy(item.url) }
        }
        .popover(isPresented: $linking, arrowEdge: .bottom) { TaskFinder { model.link(.github(item.url), to: $0); linking = false } }
        .uiTestAnchor("pr:\(item.number)")
    }

    /// "Waiting for you", "Reviewed", "Draft", "Approved by noor".
    static func reviewText(_ item: GitHubItem, waits: Bool) -> String {
        func by(_ what: String) -> String { item.reviewers.isEmpty ? what : "\(what) by \(item.reviewers.joined(separator: ", "))" }
        if item.reviewRequested || item.reviewedByMe { return waits ? "Waiting for you" : "Reviewed" }
        if item.state == .draft { return "Draft" }
        switch item.review {
        case .approved: return by("Approved")
        case .changesRequested: return by("Changes requested")
        case .required, .none: return "Review required"
        }
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
            waits ? AnyShapeStyle(Ink.needsYouText) : AnyShapeStyle(.secondary)
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
