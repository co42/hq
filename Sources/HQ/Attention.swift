import Foundation
import HQKit

/// What the page shows under items, and the PRs' review state.
extension AppModel {
    /// Mark Reviewed on a PR: quiet until its next commit.
    func markReviewed(_ url: String) {
        let old = seen["review:\(url)"]
        seen["review:\(url)"] = .now
        registerUndo("Mark Reviewed") { $0.seen["review:\(url)"] = old }
    }

    func waitsForReview(_ item: GitHubItem) -> Bool {
        item.waitsForReview(markedReviewedAt: seen["review:\(item.url)"])
    }

    func githubItem(_ url: String?) -> GitHubItem? {
        url.flatMap { url in github?.items.first { $0.url == url } }
    }

    // MARK: Outputs

    /// What a session made or linked: its files, artifacts and pull requests.
    func outputs(ofSession id: String) -> [ModalRoute] {
        let made: [ModalRoute] = files.filter { $0.sessions.contains(id) }.sorted { $0.modified > $1.modified }.map { .file($0.id) }
            + artifacts.filter { $0.session == id }.sorted { $0.published > $1.published }.map { .artifact($0.id) }
        return made + pullRequests(ofSession: id).map { .github($0.url) }
    }

    /// A task's files, artifacts, PRs and issues.
    func outputs(ofTask id: Int) -> [ModalRoute] {
        outputsIndex[id] ?? []
    }

    /// Files and artifacts the task made (newest first), its PRs and issues, the PRs its sessions opened, its linked tasks.
    private var outputsIndex: [Int: [ModalRoute]] {
        // Read what it depends on, so views that show it follow changes.
        _ = (sessions.count, tasks.count, files.count, artifacts.count, github?.fetchedAt)
        if let outputsCache { return outputsCache }
        var index: [Int: [ModalRoute]] = [:]
        for file in files.sorted(by: { $0.modified > $1.modified }) {
            for task in file.tasks { index[task, default: []].append(.file(file.id)) }
        }
        for artifact in artifacts.sorted(by: { $0.published > $1.published }) {
            for task in artifact.tasks { index[task, default: []].append(.artifact(artifact.id)) }
        }
        // A PR a session on the task opened links itself.
        var tasksOfSession: [String: [Int]] = [:]
        for task in tasks { for session in task.sessions { tasksOfSession[session, default: []].append(task.id) } }
        var opened: [Int: [String]] = [:]
        for item in github?.items ?? [] where item.kind == .pullRequest {
            for session in sessions where tasksOfSession[session.id] != nil
                && (session.links.contains(item.url) || GitHubLinks.matches(item, branch: session.branch, origin: session.origin)) {
                for task in tasksOfSession[session.id] ?? [] { opened[task, default: []].append(item.url) }
            }
        }
        var related: [Int: [Int]] = [:]
        for task in tasks {
            for other in task.related where other != task.id {
                related[task.id, default: []].append(other)
                related[other, default: []].append(task.id)
            }
        }
        for task in tasks {
            var urls = Set<String>()
            let github = (task.links.map(\.absoluteString).filter(GitHubLinks.isItem) + (opened[task.id] ?? [])).filter { urls.insert($0).inserted }
            var ids = Set<Int>()
            let linked = (related[task.id] ?? []).filter { taskIndex[$0] != nil && ids.insert($0).inserted }
            // Any other web page linked by hand (T-299).
            let web = task.links.map(\.absoluteString).filter { !GitHubLinks.isItem($0) && urls.insert($0).inserted }
            let routes = github.map { ModalRoute.github($0) } + web.map { ModalRoute.web($0) } + linked.map { ModalRoute.task($0) }
            if !routes.isEmpty { index[task.id, default: []].append(contentsOf: routes) }
        }
        outputsCache = index
        return index
    }

    /// Tasks with something under their row: files, artifacts, PRs, issues or linked tasks.
    var tasksWithOutputs: Set<Int> { Set(outputsIndex.keys) }

    // MARK: Pull requests

    /// Reviews, as its filter shows them.
    var reviewRequests: [GitHubItem] {
        allReviewRequests.filter { item in
            switch reviewFilter {
            case .notApproved: !item.approved
            case .waiting: waitsForReview(item)
            case .all: true
            }
        }
    }

    /// Every open PR that asks for the user's review, waiting or reviewed, and the others' open PRs they reviewed:
    /// the latest asked first.
    var allReviewRequests: [GitHubItem] {
        (github?.items ?? []).filter { ($0.reviewRequested || $0.reviewedByMe) && $0.kind == .pullRequest && ($0.state == .open || $0.state == .draft) }
            .sorted { ($0.reviewAskedAt, $0.number) > ($1.reviewAskedAt, $1.number) }
    }

    /// The user's open PRs, the latest updated first.
    var ownPullRequests: [GitHubItem] {
        (github?.items ?? []).filter { $0.mine && $0.kind == .pullRequest && ($0.state == .open || $0.state == .draft) && !$0.reviewRequested }
            .sorted { ($0.updatedAt, $0.number) > ($1.updatedAt, $1.number) }
    }

    /// PRs a session opened, or whose branch and repository are the session's.
    func pullRequests(ofSession id: String) -> [GitHubItem] {
        guard let session = session(id) else { return [] }
        return (github?.items ?? []).filter { item in
            session.links.contains(item.url) || GitHubLinks.matches(item, branch: session.branch, origin: session.origin)
        }
    }

    /// Tasks that link a PR or an issue.
    func tasks(linking url: String) -> [TaskItem] {
        tasks.filter { $0.links.contains { $0.absoluteString == url } }
    }

    /// The sessions on a PR: linked to it, on its branch, or on its task; ended ones too when asked, dimmed after the others.
    func sessions(onPullRequest item: GitHubItem, includeEnded: Bool = false) -> [SessionItem] {
        var seenIDs = Set<String>()
        let direct = sessions.filter { $0.links.contains(item.url) || GitHubLinks.matches(item, branch: $0.branch, origin: $0.origin) }
        let viaTask = tasks(linking: item.url).flatMap { sessions(on: $0.id, includeEnded: true) }
        return Self.openFirst((direct + viaTask).filter { seenIDs.insert($0.id).inserted }, includeEnded: includeEnded)
    }

    // MARK: Saving

    func saveAttentionSoon() {
        guard attentionSave == nil else { return }
        attentionSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            self.attentionSave = nil
            self.storage?.save(seen: self.seen)
        }
    }
}
