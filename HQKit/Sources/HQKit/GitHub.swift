import Foundation

/// A pull request or an issue, as HQ shows it.
public struct GitHubItem: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable { case pullRequest, issue }
    public enum State: String, Sendable, Codable { case open, draft, merged, closed }
    public enum Review: String, Sendable, Codable { case approved, changesRequested, required, none }
    public enum Checks: String, Sendable, Codable { case passed, failed, running, none }

    /// A review or a comment someone left.
    public struct Activity: Sendable, Hashable, Codable {
        public enum Kind: String, Sendable, Codable { case approved, changesRequested, reviewed, commented }
        public var kind: Kind
        public var author: String
        public var bot: Bool
        public var at: Date
        /// Its first line, if it says something.
        public var text: String?
        /// Its page: the PR's, at the review or comment (T-328).
        public var url: String?

        public init(kind: Kind, author: String, bot: Bool = false, at: Date, text: String? = nil, url: String? = nil) {
            self.kind = kind
            self.author = author
            self.bot = bot
            self.at = at
            self.text = text
            self.url = url
        }
    }

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
    /// Its latest reviews and comments, newest last: what the notification center tells about.
    public var activity: [Activity] = []

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

    /// Waits for the user's review: requested, open, and neither reviewed nor marked reviewed since the last commit or
    /// the last time their review was asked.
    public func waitsForReview(markedReviewedAt: Date?) -> Bool {
        guard reviewRequested, state == .open || state == .draft else { return false }
        let since = max(lastCommitAt ?? .distantPast, reviewRequestedAt ?? .distantPast)
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

    /// Linked items a poll didn't ask about keep what the last one knew; the ones it answered win.
    public mutating func keep(_ urls: Set<String>, from previous: GitHubSnapshot?) {
        let answered = Set(items.map(\.url))
        let kept = (previous?.items ?? []).filter { urls.contains($0.url) && !answered.contains($0.url) }
        guard !kept.isEmpty else { return }
        items = (items + kept).sorted { ($0.updatedAt, $0.url) > ($1.updatedAt, $1.url) }
    }
}

/// When the poller asks GitHub: its pace, its back-off and GitHub's rate limit.
public enum GitHubPoll {
    /// Fewer GraphQL points left than this: polls wait for the limit's reset.
    public static let lowRemaining = 100
    /// HQ back in front or on screen asks again only after this long.
    public static let returnFloor: TimeInterval = 60

    /// The next poll: in 2 minutes while HQ shows, 5 otherwise; doubled per failure up to 30 minutes; never before a
    /// limit lifts.
    public static func delay(onScreen: Bool, failures: Int, limitedUntil: Date?, now: Date) -> TimeInterval {
        let base: Double = onScreen ? 120 : 300
        let delay = failures == 0 ? base : min(base * pow(2, Double(failures)), 1_800)
        guard let limitedUntil else { return delay }
        return max(delay, limitedUntil.timeIntervalSince(now) + 1)
    }

    /// HQ back in front or on screen asks only when the last try is a minute old, the last one didn't fail and no limit
    /// holds: while it fails, only the back-off's retry and Refresh ask.
    public static func asksOnReturn(lastAttempt: Date?, failures: Int, limitedUntil: Date?, now: Date) -> Bool {
        guard failures == 0, (limitedUntil ?? .distantPast) <= now else { return false }
        return lastAttempt.map { now.timeIntervalSince($0) >= returnFloor } ?? true
    }

    /// Until when an answer's headers say to wait: `retry-after` on a refusal, else the reset of a nearly spent limit.
    public static func limitedUntil(status: Int, headers: [String: String], now: Date) -> Date? {
        if status == 403 || status == 429, let seconds = headers["retry-after"].flatMap(Double.init) { return now.addingTimeInterval(seconds) }
        guard let remaining = headers["x-ratelimit-remaining"].flatMap(Int.init), remaining < lowRemaining,
              let reset = headers["x-ratelimit-reset"].flatMap(Double.init) else { return nil }
        let date = Date(timeIntervalSince1970: reset)
        return date > now ? date : nil
    }
}

/// The GraphQL queries and their answers.
public enum GitHubQuery {
    /// Linked URLs one poll asks about.
    public static let linkedLimit = 60
    /// Linked URLs per request: 30 take GitHub about 4 s.
    public static let linkedPerRequest = 20
    /// A merged or closed item is asked again after this long.
    public static let finalRecheck: TimeInterval = 86_400

    /// The linked URLs a poll asks about, at most `linkedLimit`: the never-read and `fresh` ones first, in all but one
    /// request; then the others, least recently asked first, so each comes in turn; a merged or closed one waits a day.
    public static func pick(fresh: [String], rest: [String], known: [String: GitHubItem.State], asked: [String: Date], now: Date) -> [String] {
        var seen = Set<String>()
        let all = (fresh + rest).filter { seen.insert($0).inserted }
        let live = Set(fresh)
        func final(_ url: String) -> Bool { known[url] == .merged || known[url] == .closed }
        let unread = all.filter { known[$0] == nil && asked[$0] == nil }
        let first = Array((unread + all.filter { known[$0] != nil && live.contains($0) && !final($0) }).prefix(linkedLimit - linkedPerRequest))
        let chosen = Set(first)
        let others = all.enumerated()
            .filter { !chosen.contains($0.element) && (!final($0.element) || asked[$0.element].map { now.timeIntervalSince($0) >= finalRecheck } ?? true) }
            .sorted { (asked[$0.element] ?? .distantPast, $0.offset) < (asked[$1.element] ?? .distantPast, $1.offset) }
            .map(\.element)
        return first + others.prefix(linkedLimit - first.count)
    }

    /// One poll's requests, sent together: review requests, the open PRs the user reviewed and their own open PRs,
    /// each alone, then the linked URLs 20 at a time.
    public static func queries(linked urls: [String]) -> [String] {
        let searches = [
            "viewer { login }\n  review: search(query: \"is:pr is:open user-review-requested:@me archived:false\", type: ISSUE, first: 30) { nodes { __typename ...pr } }",
            "reviewed: search(query: \"is:pr is:open reviewed-by:@me -author:@me archived:false\", type: ISSUE, first: 30) { nodes { __typename ...pr } }",
            "mine: search(query: \"is:pr is:open author:@me archived:false\", type: ISSUE, first: 30) { nodes { __typename ...pr } }",
        ].map { "query {\n  \($0)\n}\n\(prFragment)" }
        let linked = Array(urls.prefix(linkedLimit).enumerated())
        let batches = stride(from: 0, to: linked.count, by: linkedPerRequest).map { start in
            let fields = linked[start..<min(start + linkedPerRequest, linked.count)].map { index, url in
                "  r\(index): resource(url: \(quoted(url))) { __typename ...pr ...issue }"
            }.joined(separator: "\n")
            // GitHub refuses a fragment the query doesn't use: only these declare `issue`.
            return "query {\n\(fields)\n}\n\(prFragment)\n\(issueFragment)"
        }
        return searches + batches
    }

    static let issueFragment = "fragment issue on Issue { url number title state updatedAt body author { login } repository { nameWithOwner } }"

    static let prFragment = """
        fragment pr on PullRequest {
          url number title isDraft state merged updatedAt body
          author { login } repository { nameWithOwner } headRefName reviewDecision
          latestReviews(first: 20) { nodes { author { __typename login } state submittedAt bodyText url } }
          comments(last: 5) { nodes { author { __typename login } createdAt bodyText url } }
          timelineItems(itemTypes: [REVIEW_REQUESTED_EVENT], last: 10) { nodes { ... on ReviewRequestedEvent {
            createdAt requestedReviewer { __typename ... on User { login } } } } }
          commits(last: 1) { nodes { commit { committedDate statusCheckRollup { state contexts(first: 30) { nodes {
            __typename ... on CheckRun { name conclusion status } ... on StatusContext { context state } } } } } } }
        }
        """

    /// The answers to `queries(linked:)`, in any order, read as one: `urls` are the linked URLs they covered.
    public static func parse(_ answers: [Data], linked urls: [String], now: Date = .now) throws -> GitHubSnapshot {
        var body: [String: Any] = [:]
        for data in answers {
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ParseError.notJSON }
            guard let part = root["data"] as? [String: Any] else {
                let errors = (root["errors"] as? [[String: Any]])?.compactMap { $0["message"] as? String } ?? []
                throw errors.isEmpty ? ParseError.notJSON : ParseError.github(errors.joined(separator: "; "))
            }
            body.merge(part) { first, _ in first }
        }
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
        for index in urls.prefix(linkedLimit).indices { add(body["r\(index)"]) }
        // Ties by URL: the same answer reads in the same order.
        return GitHubSnapshot(viewer: viewer, items: items.values.sorted { ($0.updatedAt, $0.url) > ($1.updatedAt, $1.url) }, fetchedAt: now)
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
        let comments = ((node["comments"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        item.activity = (reviews.compactMap { review -> GitHubItem.Activity? in
            guard let at = date(review["submittedAt"]) else { return nil }
            let kind: GitHubItem.Activity.Kind = switch review["state"] as? String {
            case "APPROVED": .approved
            case "CHANGES_REQUESTED": .changesRequested
            default: .reviewed
            }
            return activity(kind, review, at: at)
        } + comments.compactMap { comment in
            date(comment["createdAt"]).map { activity(.commented, comment, at: $0) }
        }).sorted { $0.at < $1.at }
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

    static func activity(_ kind: GitHubItem.Activity.Kind, _ node: [String: Any], at: Date) -> GitHubItem.Activity {
        let author = node["author"] as? [String: Any]
        let login = author?["login"] as? String ?? "ghost"
        let line = (node["bodyText"] as? String)?.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) }
        return GitHubItem.Activity(kind: kind, author: login, bot: author?["__typename"] as? String == "Bot" || login.hasSuffix("[bot]"),
                                   at: at, text: line?.isEmpty == false ? line : nil, url: node["url"] as? String)
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
        return try? iso.parse(text)
    }

    private static let iso = Date.ISO8601FormatStyle()

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

/// GitHub's notifications for threads the user takes part in: mentions and replies, where the PR query can't see them.
public enum GitHubThreads {
    public struct Thread: Sendable, Hashable {
        public var reason: String
        /// The PR's or issue's page.
        public var url: String
        public var title: String
        public var updatedAt: Date
        /// The API URL of the comment that made it unread.
        public var latestComment: String?
    }

    /// What a reply or a mention is worth telling: a PR or an issue, mentioned or answered.
    public static func parse(_ data: Data) -> [Thread] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let reason = entry["reason"] as? String, ["mention", "team_mention", "comment"].contains(reason),
                  let subject = entry["subject"] as? [String: Any], let api = subject["url"] as? String,
                  let url = page(api), let updated = GitHubQuery.date(entry["updated_at"]) else { return nil }
            return Thread(reason: reason, url: url, title: subject["title"] as? String ?? "", updatedAt: updated,
                          latestComment: subject["latest_comment_url"] as? String)
        }
    }

    /// A comment's author, whether a bot wrote it, and its first line.
    public static func comment(_ data: Data) -> (author: String, bot: Bool, text: String?, url: String?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let user = json["user"] as? [String: Any], let login = user["login"] as? String else { return nil }
        let line = (json["body"] as? String)?.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) }
        return (login, user["type"] as? String == "Bot" || login.hasSuffix("[bot]"), line?.isEmpty == false ? line : nil, json["html_url"] as? String)
    }

    /// `https://api.github.com/repos/acme/registry/pulls/418` → `https://github.com/acme/registry/pull/418`.
    public static func page(_ api: String) -> String? {
        guard let range = api.range(of: "https://api.github.com/repos/") else { return nil }
        let parts = api[range.upperBound...].split(separator: "/")
        guard parts.count == 4, ["pulls", "issues"].contains(parts[2]) else { return nil }
        return "https://github.com/\(parts[0])/\(parts[1])/\(parts[2] == "pulls" ? "pull" : "issues")/\(parts[3])"
    }

    /// "registry #418" from its page.
    public static func reference(_ url: String) -> String? {
        let parts = url.split(separator: "/")
        guard parts.count >= 6, let number = Int(parts[5]) else { return nil }
        return "\(parts[3]) #\(number)"
    }
}
