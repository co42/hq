import Foundation

/// A pull request or an issue, as HQ shows it.
public struct GitHubItem: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable { case pullRequest, issue }
    public enum State: String, Sendable, Codable { case open, draft, merged, closed }
    public enum Review: String, Sendable, Codable { case approved, changesRequested, required, none }
    public enum Checks: String, Sendable, Codable { case passed, failed, running, none }

    public struct Check: Sendable, Hashable, Codable {
        public var name: String
        public var checks: Checks
        public var detail: String?

        public init(name: String, checks: Checks, detail: String? = nil) {
            self.name = name
            self.checks = checks
            self.detail = detail
        }
    }

    public var url: String
    public var kind: Kind
    public var number: Int
    /// `owner/name`.
    public var repo: String
    public var title: String
    public var author: String
    public var state: State
    public var updatedAt: Date
    public var headBranch: String?
    public var review: Review
    /// Who approved, or who asked for changes, for "Approved by noor".
    public var reviewers: [String]
    public var checks: Checks
    public var lastCommitAt: Date?
    /// The user's latest review on it.
    public var myReviewAt: Date?
    /// What the user's latest review said: approved, changes requested, or none (a comment).
    public var myReview: Review = .none
    /// When GitHub last asked the user, or a team of theirs, to review it.
    public var reviewRequestedAt: Date?
    /// GitHub asks the user to review it.
    public var reviewRequested: Bool
    public var mine: Bool
    public var body: String?
    public var checkRuns: [Check]

    public var id: String { url }

    /// Someone else's PR the user reviewed: GitHub drops their review request once they submit a review.
    public var reviewedByMe: Bool { myReviewAt != nil && !mine }

    /// Approved, by its reviews or by the user: their review is done.
    public var approved: Bool { review == .approved || myReview == .approved }

    /// When its review was asked of the user, else when they reviewed it, else its last update.
    public var reviewAskedAt: Date { reviewRequestedAt ?? myReviewAt ?? updatedAt }

    /// "registry #418".
    public var reference: String { "\(repo.split(separator: "/").last.map(String.init) ?? repo) #\(number)" }

    public init(url: String, kind: Kind, number: Int, repo: String, title: String, author: String, state: State,
                updatedAt: Date, headBranch: String? = nil, review: Review = .none, reviewers: [String] = [],
                checks: Checks = .none, lastCommitAt: Date? = nil, myReviewAt: Date? = nil,
                reviewRequested: Bool = false, mine: Bool = false, body: String? = nil, checkRuns: [Check] = []) {
        self.url = url
        self.kind = kind
        self.number = number
        self.repo = repo
        self.title = title
        self.author = author
        self.state = state
        self.updatedAt = updatedAt
        self.headBranch = headBranch
        self.review = review
        self.reviewers = reviewers
        self.checks = checks
        self.lastCommitAt = lastCommitAt
        self.myReviewAt = myReviewAt
        self.reviewRequested = reviewRequested
        self.mine = mine
        self.body = body
        self.checkRuns = checkRuns
    }

    /// Waits for the user's review: requested, open, and neither reviewed nor marked reviewed since the last commit.
    public func waitsForReview(markedReviewedAt: Date?) -> Bool {
        guard reviewRequested, state == .open || state == .draft else { return false }
        let since = lastCommitAt ?? .distantPast
        if let mine = myReviewAt, mine >= since { return false }
        if let marked = markedReviewedAt, marked >= since { return false }
        return true
    }
}

/// What one poll knows.
public struct GitHubSnapshot: Sendable, Hashable, Codable {
    public var viewer: String
    public var items: [GitHubItem]
    public var fetchedAt: Date

    public init(viewer: String, items: [GitHubItem], fetchedAt: Date) {
        self.viewer = viewer
        self.items = items
        self.fetchedAt = fetchedAt
    }
}

/// The GraphQL query and its answer.
public enum GitHubQuery {
    /// One request per poll: review requests, the open PRs the user reviewed, their own open PRs, and every linked URL.
    public static func query(linked urls: [String]) -> String {
        let resources = urls.prefix(60).enumerated().map { index, url in
            "  r\(index): resource(url: \(quoted(url))) { __typename ...pr ...issue }"
        }.joined(separator: "\n")
        return """
        query {
          viewer { login }
          review: search(query: "is:pr is:open user-review-requested:@me archived:false", type: ISSUE, first: 30) { nodes { __typename ...pr } }
          reviewed: search(query: "is:pr is:open reviewed-by:@me -author:@me archived:false", type: ISSUE, first: 30) { nodes { __typename ...pr } }
          mine: search(query: "is:pr is:open author:@me archived:false", type: ISSUE, first: 30) { nodes { __typename ...pr } }
          rateLimit { remaining resetAt }
        \(resources)
        }
        fragment pr on PullRequest {
          url number title isDraft state merged updatedAt body
          author { login } repository { nameWithOwner } headRefName reviewDecision
          latestReviews(first: 20) { nodes { author { login } state submittedAt } }
          timelineItems(itemTypes: [REVIEW_REQUESTED_EVENT], last: 10) { nodes { ... on ReviewRequestedEvent {
            createdAt requestedReviewer { __typename ... on User { login } } } } }
          commits(last: 1) { nodes { commit { committedDate statusCheckRollup { state contexts(first: 30) { nodes {
            __typename ... on CheckRun { name conclusion status } ... on StatusContext { context state } } } } } } }
        }
        \(urls.isEmpty ? "" : "fragment issue on Issue { url number title state updatedAt body author { login } repository { nameWithOwner } }")
        """
    }

    /// The URLs the answer covered, in the order of `query(linked:)`.
    public static func parse(_ data: Data, linked urls: [String], now: Date = .now) throws -> GitHubSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ParseError.notJSON }
        if root["data"] == nil, let errors = root["errors"] as? [[String: Any]] {
            throw ParseError.github(errors.compactMap { $0["message"] as? String }.joined(separator: "; "))
        }
        guard let body = root["data"] as? [String: Any] else { throw ParseError.notJSON }
        let viewer = (body["viewer"] as? [String: Any])?["login"] as? String ?? ""
        var items: [String: GitHubItem] = [:]
        func add(_ node: Any?, requested: Bool = false) {
            guard let node = node as? [String: Any], var item = item(node, viewer: viewer) else { return }
            if let known = items[item.url] { item.reviewRequested = item.reviewRequested || known.reviewRequested }
            item.reviewRequested = item.reviewRequested || requested
            items[item.url] = item
        }
        for node in ((body["review"] as? [String: Any])?["nodes"] as? [Any]) ?? [] { add(node, requested: true) }
        for node in ((body["reviewed"] as? [String: Any])?["nodes"] as? [Any]) ?? [] { add(node) }
        for node in ((body["mine"] as? [String: Any])?["nodes"] as? [Any]) ?? [] { add(node) }
        for index in urls.prefix(60).indices { add(body["r\(index)"]) }
        return GitHubSnapshot(viewer: viewer, items: items.values.sorted { $0.updatedAt > $1.updatedAt }, fetchedAt: now)
    }

    public enum ParseError: Error, Equatable {
        case notJSON
        case github(String)
    }

    static func item(_ node: [String: Any], viewer: String) -> GitHubItem? {
        guard let url = node["url"] as? String, let number = node["number"] as? Int,
              let title = node["title"] as? String else { return nil }
        let isPR = (node["__typename"] as? String) == "PullRequest" || url.contains("/pull/")
        let author = (node["author"] as? [String: Any])?["login"] as? String ?? "ghost"
        let repo = (node["repository"] as? [String: Any])?["nameWithOwner"] as? String ?? ""
        let raw = (node["state"] as? String ?? "OPEN").uppercased()
        let state: GitHubItem.State
        switch raw {
        case "MERGED": state = .merged
        case "CLOSED": state = (node["merged"] as? Bool) == true ? .merged : .closed
        default: state = (node["isDraft"] as? Bool) == true ? .draft : .open
        }
        var item = GitHubItem(url: url, kind: isPR ? .pullRequest : .issue, number: number, repo: repo, title: title,
                              author: author, state: state, updatedAt: date(node["updatedAt"]) ?? .distantPast,
                              headBranch: node["headRefName"] as? String, mine: !viewer.isEmpty && author == viewer,
                              body: node["body"] as? String)
        guard isPR else { return item }
        let reviews = ((node["latestReviews"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        let byOthers = reviews.filter { ($0["author"] as? [String: Any])?["login"] as? String != viewer }
        func authors(_ wanted: String) -> [String] {
            byOthers.filter { $0["state"] as? String == wanted }.compactMap { ($0["author"] as? [String: Any])?["login"] as? String }
        }
        switch node["reviewDecision"] as? String {
        case "APPROVED":
            item.review = .approved
            item.reviewers = authors("APPROVED")
        case "CHANGES_REQUESTED":
            item.review = .changesRequested
            item.reviewers = authors("CHANGES_REQUESTED")
        case "REVIEW_REQUIRED": item.review = .required
        default: item.review = .none
        }
        let mine = reviews.filter { ($0["author"] as? [String: Any])?["login"] as? String == viewer }
            .compactMap { review in date(review["submittedAt"]).map { (at: $0, state: review["state"] as? String) } }
            .max { $0.at < $1.at }
        item.myReviewAt = mine?.at
        item.myReview = switch mine?.state {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        default: .none
        }
        // Requests to the user, else to a team; never another user's.
        let requests = ((node["timelineItems"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        let asked = requests.compactMap { event -> (at: Date, me: Bool)? in
            let reviewer = event["requestedReviewer"] as? [String: Any]
            let me = reviewer?["login"] as? String == viewer
            guard let at = date(event["createdAt"]), me || reviewer?["__typename"] as? String == "Team" else { return nil }
            return (at, me)
        }
        item.reviewRequestedAt = (asked.contains(where: \.me) ? asked.filter(\.me) : asked).map(\.at).max()
        let commit = (((node["commits"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first?["commit"]) as? [String: Any]
        item.lastCommitAt = date(commit?["committedDate"])
        let rollup = commit?["statusCheckRollup"] as? [String: Any]
        item.checks = checks(rollup?["state"] as? String)
        let contexts = ((rollup?["contexts"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        item.checkRuns = contexts.compactMap { context in
            if let name = context["name"] as? String {
                let status = (context["status"] as? String ?? "").uppercased()
                let conclusion = (context["conclusion"] as? String ?? "").uppercased()
                let value: GitHubItem.Checks = status != "COMPLETED" ? .running
                    : ["SUCCESS", "NEUTRAL", "SKIPPED"].contains(conclusion) ? .passed : .failed
                return GitHubItem.Check(name: name, checks: value)
            }
            if let name = context["context"] as? String { return GitHubItem.Check(name: name, checks: checks(context["state"] as? String)) }
            return nil
        }
        return item
    }

    static func checks(_ state: String?) -> GitHubItem.Checks {
        switch state?.uppercased() {
        case "SUCCESS": .passed
        case "FAILURE", "ERROR": .failed
        case "PENDING", "EXPECTED": .running
        default: .none
        }
    }

    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// How PRs and issues attach to sessions and tasks.
public enum GitHubLinks {
    /// Pull request and issue URLs in text, such as `gh pr create`'s output.
    public static func urls(in text: String) -> [String] {
        var seen = Set<String>()
        return text.matches(of: pattern).map { String($0.0) }.filter { seen.insert($0).inserted }
    }

    /// True for a GitHub pull request or issue URL.
    public static func isItem(_ url: String) -> Bool {
        url.wholeMatch(of: pattern) != nil
    }

    /// A PR whose head branch and repository are the session's.
    public static func matches(_ item: GitHubItem, branch: String, origin: String?) -> Bool {
        guard item.kind == .pullRequest, let head = item.headBranch, !branch.isEmpty, head == branch,
              let origin, !origin.isEmpty else { return false }
        return item.repo.caseInsensitiveCompare(origin) == .orderedSame
    }

    nonisolated(unsafe) private static let pattern = /https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/(?:pull|issues)\/\d+/
}

extension GitInfo {
    /// `owner/name` of the `origin` remote, read from the repository's config.
    public static func origin(_ cwd: String) -> String? {
        var dir = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath).standardizedFileURL
        let files = FileManager.default
        while dir.path != "/" {
            let dotGit = dir.appending(path: ".git")
            var isDirectory: ObjCBool = false
            if files.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                var config = dotGit.appending(path: "config")
                if !isDirectory.boolValue {
                    let line = (try? String(contentsOf: dotGit, encoding: .utf8)) ?? ""
                    let path = line.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines)
                    let gitDir = URL(fileURLWithPath: path, relativeTo: dir).standardizedFileURL
                    // A worktree's config is the main repository's: <main>/.git/worktrees/<name> → <main>/.git/config.
                    config = gitDir.deletingLastPathComponent().deletingLastPathComponent().appending(path: "config")
                }
                return remote(in: (try? String(contentsOf: config, encoding: .utf8)) ?? "")
            }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    /// The origin's `owner/name`, from `git@github.com:owner/name.git` or `https://github.com/owner/name`.
    public static func remote(in config: String) -> String? {
        var inOrigin = false
        for line in config.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { inOrigin = trimmed == "[remote \"origin\"]"; continue }
            guard inOrigin, trimmed.hasPrefix("url") else { continue }
            let url = trimmed.split(separator: "=", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            guard let range = url.range(of: "github.com") else { return nil }
            var path = url[range.upperBound...].drop { $0 == ":" || $0 == "/" }
            if path.hasSuffix(".git") { path = path.dropLast(4) }
            return path.isEmpty ? nil : String(path)
        }
        return nil
    }
}
