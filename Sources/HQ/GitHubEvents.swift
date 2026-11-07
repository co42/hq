import Foundation
import HQKit

/// What GitHub tells the user (DESIGN.md §11): on their PRs, reviews, comments and failed checks; on others', a review
/// asked of them. Never a bot's or their own; one row per PR; nothing older than the lookback.
extension AppModel {
    func noteGitHubEvents(before: GitHubSnapshot?, after: GitHubSnapshot, now: Date = .now) {
        let floor = githubFloor(now: now)
        let old = Dictionary((before?.items ?? []).map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        var known = noticeStore.githubEvents
        for item in after.items where item.kind == .pullRequest && (item.state == .open || item.state == .draft) {
            var events: [(key: String, text: String, at: Date)] = []
            if item.mine {
                for activity in item.activity where !activity.bot && activity.author != after.viewer && activity.at > floor {
                    events.append(("\(item.url)|\(activity.kind.rawValue)|\(activity.author)|\(Int(activity.at.timeIntervalSince1970))",
                                   Self.describe(activity), activity.at))
                }
                if item.checks == .failed, let previous = old[item.url], previous.checks != .failed {
                    let failed = item.checkRuns.filter { $0.checks == .failed }.map(\.name)
                    events.append(("\(item.url)|checks|\(Int((item.lastCommitAt ?? now).timeIntervalSince1970))",
                                   "Checks failed" + (failed.isEmpty ? "" : ": " + failed.prefix(3).joined(separator: ", ")), now))
                }
            } else if item.reviewRequested, let asked = item.reviewRequestedAt, asked > floor {
                events.append(("\(item.url)|asked|\(Int(asked.timeIntervalSince1970))", "\(item.author) asked for your review", asked))
            }
            let fresh = events.filter { known[$0.key] == nil }.sorted { $0.at < $1.at }
            guard let latest = fresh.last else { continue }
            for event in fresh { known[event.key] = now }
            let tasks = tasks(linking: item.url).map { ModalRoute.task($0.id).selectionKey }
            notify(latest.text, level: .update, kind: .github, source: item.url, links: [ModalRoute.github(item.url).selectionKey] + tasks,
                   count: fresh.count)
        }
        if known != noticeStore.githubEvents { noticeStore.githubEvents = known }
    }

    /// Events older than the lookback (Settings › GitHub) never notify. Their keys last 30 days, longer than any lookback, so nothing notifies twice.
    func githubFloor(now: Date = .now) -> Date {
        now.addingTimeInterval(-Double(githubLookback) * 86_400)
    }

    /// "noor approved your PR", "theo asked for changes: “Split the GC job”", "lea commented: “LGTM”".
    static func describe(_ activity: GitHubItem.Activity) -> String {
        let said = activity.text.map { ": “\($0.count > 120 ? String($0.prefix(119)) + "…" : $0)”" } ?? ""
        switch activity.kind {
        case .approved: return "\(activity.author) approved your PR" + said
        case .changesRequested: return "\(activity.author) asked for changes" + said
        case .reviewed: return "\(activity.author) reviewed your PR" + said
        case .commented: return "\(activity.author) commented" + said
        }
    }
}
