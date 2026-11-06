import Foundation
import HQKit

/// Orange (needs the user) and blue (new) on every surface (DESIGN.md §11).
extension AppModel {
    // MARK: Changes and seen

    /// Claude or GitHub changed an item. The user's own changes never make anything blue, and clear its blue.
    func noteChange(_ key: String, by who: String? = nil) {
        guard let by = who ?? actor else {
            // The user changed it: they have seen it.
            if isNew(key: key) { seen[key] = .now }
            return
        }
        changes[key] = Change(at: .now, by: by)
    }

    func isNew(key: String) -> Bool {
        guard let change = changes[key] else { return false }
        return change.at > (seen[key] ?? .distantPast)
    }

    func markSeen(_ route: ModalRoute) {
        if case .session(let id) = route { markSessionSeen(id) }
        if let key = route.seenKey, isNew(key: key) { seen[key] = .now }
    }

    /// Mark All Seen (⇧⌘J): every blue item. Orange stays until its state changes.
    func markAllSeen() {
        let now = Date.now
        let before = (seen, sessions)
        registerUndo("Mark All Seen") { model in
            model.seen = before.0
            for old in before.1 { if var item = model.session(old.id), item.status.unread != old.status.unread { item.status.unread = old.status.unread; model.put(item) } }
        }
        var next = seen
        for (key, change) in changes where change.at > (next[key] ?? .distantPast) { next[key] = now }
        if next != seen { seen = next }
        for session in sessions where session.status.isNew { markSessionSeen(session.id) }
    }

    /// Mark Reviewed on a PR: quiet until its next commit.
    func markReviewed(_ url: String) {
        let old = seen["review:\(url)"]
        seen["review:\(url)"] = .now
        registerUndo("Mark Reviewed") { $0.seen["review:\(url)"] = old }
    }

    // MARK: Orange and blue

    /// A task in the Backlog is for later: never orange or blue.
    func isLater(_ id: Int) -> Bool { list(of: id) == .backlog }

    func needsYou(_ route: ModalRoute) -> Bool {
        switch route {
        case .session(let id): session(id)?.status.needsYou ?? false
        case .task(let id): task(id)?.status == .review && !isLater(id)
        case .github(let url): githubItem(url).map(waitsForReview) ?? false
        default: false
        }
    }

    func isNew(_ route: ModalRoute) -> Bool {
        switch route {
        case .session(let id): return session(id)?.status.isNew ?? false
        case .task(let id): return !isLater(id) && isNew(key: "task:T-\(id)")
        case .github(let url):
            // The user's PRs and the issues their tasks link to; a review request is orange, not blue.
            guard let item = githubItem(url), item.mine || item.kind == .issue else { return false }
            return isNew(key: "gh:\(url)")
        default: return route.seenKey.map(isNew(key:)) ?? false
        }
    }

    func waitsForReview(_ item: GitHubItem) -> Bool {
        item.waitsForReview(markedReviewedAt: seen["review:\(item.url)"])
    }

    func githubItem(_ url: String?) -> GitHubItem? {
        url.flatMap { url in github?.items.first { $0.url == url } }
    }

    /// Orange: sessions that wait on the user, tasks in Review in Tasks, PRs that wait for their review. The Dock badge.
    var needsYouCount: Int { attentionQueue.filter(needsYou).count }

    var newCount: Int { attentionQueue.filter { isNew($0) && !needsYou($0) }.count }

    /// "2 sessions wait for you, 1 task in Review, 3 pull requests wait for your review": what the counts are made of.
    var attentionSummary: String {
        let queue = attentionQueue
        func kind(_ route: ModalRoute) -> String {
            switch route {
            case .session: "session"
            case .task: "task"
            case .github: "pull request"
            case .file: "file"
            case .artifact: "artifact"
            default: "item"
            }
        }
        func counted(_ routes: [ModalRoute]) -> String {
            var counts: [(String, Int)] = []
            for route in routes {
                let name = kind(route)
                if let index = counts.firstIndex(where: { $0.0 == name }) { counts[index].1 += 1 } else { counts.append((name, 1)) }
            }
            return counts.map { "\($0.1) \($0.0)\($0.1 == 1 ? "" : "s")" }.joined(separator: ", ")
        }
        let needs = queue.filter(needsYou)
        let fresh = queue.filter { isNew($0) && !needsYou($0) }
        var lines: [String] = []
        if !needs.isEmpty { lines.append("Need you: \(counted(needs)): sessions that wait, tasks in Review, pull requests that wait for your review.") }
        if !fresh.isEmpty { lines.append("New: \(counted(fresh)) Claude or GitHub changed since you last looked.") }
        lines.append("The Backlog never counts. Review Next (⌘J) goes through them in page order.")
        return lines.joined(separator: "\n")
    }

    // MARK: Review Next

    /// Every item on the page, top to bottom: the PR rows, each card then its tasks and outputs, the files and
    /// artifacts, then Tasks (each task then its outputs). Not the Backlog.
    var pageOrder: [ModalRoute] {
        var routes: [ModalRoute] = []
        var seenRoutes = Set<ModalRoute>()
        func add(_ route: ModalRoute) { if seenRoutes.insert(route).inserted { routes.append(route) } }
        for item in reviewRequests + ownPullRequests { add(.github(item.url)) }
        for session in gridSessions {
            add(.session(session.id))
            for task in tasks(of: session.id) { add(.task(task.id)) }
            for output in outputs(ofSession: session.id) { add(output) }
        }
        for file in files.sorted(by: { ($0.pinned ? 1 : 0, $0.modified) > ($1.pinned ? 1 : 0, $1.modified) }) { add(.file(file.id)) }
        for artifact in artifacts.sorted(by: { ($0.pinned ? 1 : 0, $0.published) > ($1.pinned ? 1 : 0, $1.published) }) { add(.artifact(artifact.id)) }
        for id in taskTree.outline(.overview) {
            add(.task(id))
            for output in outputs(ofTask: id) { add(output) }
        }
        // PRs no row shows still count.
        for item in github?.items ?? [] where waitsForReview(item) { add(.github(item.url)) }
        return routes
    }

    /// Orange and blue items, in page order.
    var attentionQueue: [ModalRoute] {
        // Read what it depends on, so views that show it follow changes.
        _ = (sessions.count, tasks.count, files.count, artifacts.count, github?.fetchedAt, seen.count, changes.count)
        if let attentionCache { return attentionCache }
        let queue = pageOrder.filter { needsYou($0) || isNew($0) }
        attentionCache = queue
        return queue
    }

    /// Review Next (⌘J): the next orange or blue item after the one open, in page order.
    func reviewNext() {
        let order = pageOrder
        let queue = attentionQueue
        guard !queue.isEmpty else { return }
        let position = modal.flatMap { order.firstIndex(of: $0) } ?? -1
        let next = queue.first { (order.firstIndex(of: $0) ?? 0) > position && $0 != modal } ?? queue.first { $0 != modal } ?? queue[0]
        open(next)
    }

    /// "3 more to look at", with the open item left out.
    var moreToLookAt: Int {
        attentionQueue.filter { $0 != modal }.count
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
            let routes = github.map { ModalRoute.github($0) } + linked.map { ModalRoute.task($0) }
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
            self.storage?.save(changes: self.changes)
        }
    }
}
