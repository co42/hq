import AppKit
import HQKit

/// Polls GitHub for the user's pull requests and the items their tasks and sessions link (PLAN.md §5).
/// Read-only. The token comes from `gh auth token` and stays in memory. Test runs read the
/// fixture and never reach the network.
@MainActor
final class GitHubService {
    private weak var model: AppModel?
    private var token: String?
    private var timer: Task<Void, Never>?
    private var failures = 0
    /// When a poll last started: HQ back in front asks again only a minute later.
    private var lastAttempt: Date?
    /// GitHub's rate limit is nearly spent, or it said to wait: no poll before this.
    private var limitedUntil: Date?
    /// When each linked URL was last asked about: the ones past the limit take turns.
    private var asked: [String: Date] = [:]
    /// `gh auth token` failed this many times in a row: once can be a slow start, twice is signed out.
    private var tokenFailures = 0
    /// `gh` was looked for: polls before that would find it missing.
    private var searched = false
    private var polling = false {
        didSet { model?.githubPolling = polling }
    }
    private var observers: [NSObjectProtocol] = []
    /// Test runs and `HQ_GITHUB=fixtures`. A preview asks GitHub, read-only, with `HQ_GITHUB=live` (tools/preview.sh): its
    /// cache stays in its own store's folder.
    static var usesFixtures: Bool { !asksGitHub }

    static var asksGitHub: Bool {
        let mode = ProcessInfo.processInfo.environment["HQ_GITHUB"]
        return mode == "live" || (!Store.isOverridden && mode != "fixtures")
    }

    init(model: AppModel) {
        self.model = model
        if Self.usesFixtures { return }
        model.github = Self.loadCache()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollOnReturn() }
        })
        // The window back on screen after a while away: ask now (T-366).
        observers.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] note in
            let sender = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let window = self.model?.window, sender == ObjectIdentifier(window), self.onScreen else { return }
                self.pollOnReturn()
            }
        })
        Task { [weak self] in
            await self?.findGH()
            self?.poll()
        }
    }

    /// The fixture's poll, its dates moved to now (seed data and test runs).
    static func fixture(now: Date = .now) -> GitHubSnapshot? {
        guard var snapshot = try? GitHubQuery.parse([GitHubFixture.poll], linked: GitHubFixture.linked, now: now) else { return nil }
        let shift = now.timeIntervalSince(GitHubFixture.reference)
        snapshot.items = snapshot.items.map { item in
            var moved = item
            moved.updatedAt += shift
            moved.lastCommitAt = moved.lastCommitAt.map { $0 + shift }
            moved.myReviewAt = moved.myReviewAt.map { $0 + shift }
            moved.reviewRequestedAt = moved.reviewRequestedAt.map { $0 + shift }
            return moved
        }
        return snapshot
    }

    // MARK: Polling

    /// Polls now, then every two minutes while HQ's window is on screen, in front or beside another app, and every five
    /// otherwise; slower after errors (T-366: the user keeps HQ beside Ghostty).
    func poll() {
        guard !Self.usesFixtures, searched, !polling else { return }
        polling = true
        lastAttempt = .now
        timer?.cancel()
        Task {
            let again = await fetch()
            polling = false
            if again { pollSoon() } else { schedule() }
        }
    }

    /// HQ in front again, or back on screen: asks only when the last try is a minute old and nothing fails or limits it.
    private func pollOnReturn() {
        guard GitHubPoll.asksOnReturn(lastAttempt: lastAttempt, failures: failures, limitedUntil: limitedUntil, now: .now) else { return }
        poll()
    }

    /// The window shows, at least partly: the user may be looking at the PRs.
    private var onScreen: Bool {
        guard let window = model?.window else { return NSApp.isActive }
        return window.isVisible && window.occlusionState.contains(.visible)
    }

    /// In 5 s, unless GitHub fails or limits: then the back-off's retry stands.
    func pollSoon() {
        guard !Self.usesFixtures, failures == 0 || tokenFailures > 0, (limitedUntil ?? .distantPast) <= .now else { return }
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { self?.poll() }
        }
    }

    private func schedule() {
        let delay = GitHubPoll.delay(onScreen: onScreen, failures: failures, limitedUntil: limitedUntil, now: .now)
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            if !Task.isCancelled { self?.poll() }
        }
    }

    /// True: ask again in a few seconds.
    private func fetch() async -> Bool {
        guard let model else { return false }
        if token == nil { token = await Self.readToken(gh: model.setup.ghPath) }
        guard let token else {
            guard model.setup.ghPath != nil else {
                set(.githubMissing)
                failures += 1
                return false
            }
            // `gh` can fail for a moment as HQ starts: signed out only when it fails again a few seconds later.
            tokenFailures += 1
            if tokenFailures == 1 { return true }
            set(.githubSignedOut)
            failures += 1
            return false
        }
        tokenFailures = 0
        let links = model.githubLinks()
        let previous = model.github
        let known = Dictionary((previous?.items ?? []).map { ($0.url, $0.state) }, uniquingKeysWith: { first, _ in first })
        let start = Date.now
        let linked = GitHubQuery.pick(fresh: links.fresh, rest: links.rest, known: known, asked: asked, now: start)
        let left = Set(links.fresh + links.rest).subtracting(linked)
        do {
            // All or nothing: a missing answer would drop its PRs, or their review requests.
            let answers = try await withThrowingTaskGroup(of: (Data, Date?).self) { group in
                for query in GitHubQuery.queries(linked: linked) {
                    group.addTask { try await Self.post(query, token: token) }
                }
                var answers: [(Data, Date?)] = []
                for try await answer in group { answers.append(answer) }
                return answers
            }
            limitedUntil = answers.compactMap(\.1).max()
            if let limitedUntil { NSLog("HQ: GitHub's rate limit is nearly spent: next poll after %@", limitedUntil.formatted(.iso8601)) }
            // Read and compared off the main thread; the cache is written there too.
            let cache = Self.cacheURL
            let (snapshot, changed) = try await Task.detached {
                var snapshot = try GitHubQuery.parse(answers.map(\.0), linked: linked)
                snapshot.keep(left, from: previous)
                let changed = snapshot.viewer != previous?.viewer || snapshot.items != previous?.items
                if changed { Self.saveCache(snapshot, to: cache) }
                return (snapshot, changed)
            }.value
            failures = 0
            for url in linked { asked[url] = start }
            asked = asked.filter { left.contains($0.key) || linked.contains($0.key) }
            if changed { apply(snapshot) }
            // A poll that changed nothing leaves the page alone: only the Refresh button's tooltip says when.
            model.githubAnswered = snapshot.fetchedAt
            set(nil)
            await fetchThreads(token: token)
        } catch PollError.signedOut {
            // A rotated token: ask gh once more next time.
            self.token = nil
            set(.githubSignedOut)
            failures += 1
        } catch {
            if case PollError.status(_, _, let until?) = error { limitedUntil = until }
            NSLog("HQ: GitHub poll failed: %@", String(describing: error))
            failures += 1
            if failures >= 3 { set(.githubFailing) }
        }
        return false
    }

    private enum PollError: Error, CustomStringConvertible {
        case signedOut
        /// Its status, what GitHub said unless it's an HTML error page, and until when it said to wait.
        case status(Int, String, Date?)

        var description: String {
            switch self {
            case .signedOut: "HTTP 401"
            case let .status(code, said, _): said.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(said)"
            }
        }
    }

    /// One of the poll's GraphQL requests: its answer when GitHub says 200, and until when its rate limit says to wait.
    nonisolated private static func post(_ query: String, token: String) async throws -> (Data, Date?) {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("HQ (macOS)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        var headers: [String: String] = [:]
        for name in ["retry-after", "x-ratelimit-remaining", "x-ratelimit-reset"] { headers[name] = http?.value(forHTTPHeaderField: name) }
        let until = GitHubPoll.limitedUntil(status: status, headers: headers, now: .now)
        if status == 401 { throw PollError.signedOut }
        guard status == 200 else {
            let text = String(decoding: data.prefix(200), as: UTF8.self)
            throw PollError.status(status, text.hasPrefix("<") ? "" : text, until)
        }
        return (data, until)
    }

    /// Reviews, comments and failed checks on the user's PRs, and review requests, go to the notification center.
    func apply(_ snapshot: GitHubSnapshot) {
        guard let model else { return }
        model.noteGitHubEvents(before: model.github, after: snapshot)
        model.github = snapshot
        model.setup.githubAccount = snapshot.viewer
    }

    /// Mentions and comments on threads the user takes part in, outside their own PRs (the poll's query has those),
    /// within the lookback. Never a bot's or the user's own.
    private func fetchThreads(token: String) async {
        guard let model, var components = URLComponents(string: "https://api.github.com/notifications") else { return }
        let floor = model.githubFloor()
        components.queryItems = [.init(name: "participating", value: "true"), .init(name: "since", value: floor.formatted(.iso8601))]
        guard let url = components.url, let data = await get(url, token: token) else { return }
        let mine = Set((model.github?.items ?? []).filter(\.mine).map(\.url))
        var known = model.noticeStore.githubEvents
        for thread in GitHubThreads.parse(data) where !mine.contains(thread.url) && thread.updatedAt > floor {
            let key = "\(thread.url)|\(thread.reason)|\(Int(thread.updatedAt.timeIntervalSince1970))"
            guard known[key] == nil else { continue }
            known[key] = .now
            var said: (author: String, bot: Bool, text: String?, url: String?)?
            if let link = thread.latestComment.flatMap(URL.init(string:)), let body = await get(link, token: token) { said = GitHubThreads.comment(body) }
            if let said, said.bot || said.author == model.github?.viewer { continue }
            let who = said?.author ?? "Someone"
            let quote = said?.text.map { ": “\($0.count > 120 ? String($0.prefix(119)) + "…" : $0)”" } ?? ""
            let text = thread.reason == "comment" ? "\(who) commented\(quote)" : "\(who) mentioned you\(quote)"
            model.notify(text, level: .update, kind: .github, source: thread.url,
                         links: [ModalRoute.github(thread.url).selectionKey] + model.tasks(linking: thread.url).map { ModalRoute.task($0.id).selectionKey }, at: thread.updatedAt, anchor: said?.url, title: thread.title.isEmpty ? nil : thread.title)
        }
        if known != model.noticeStore.githubEvents { model.noticeStore.githubEvents = known }
    }

    private func get(_ url: URL, token: String) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("HQ (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private func set(_ problem: Problem?) {
        guard let model else { return }
        let github: [Problem] = [.githubSignedOut, .githubMissing, .githubFailing]
        if let problem {
            // Ghostty and the plugin come first; a GitHub problem never hides them.
            if model.problem == nil || github.contains(model.problem!) { model.problem = problem }
        } else if let current = model.problem, github.contains(current) {
            model.problem = nil
        }
    }

    // MARK: gh

    /// Finds `gh` with the login shell's PATH, once.
    private func findGH() async {
        let path = await Task.detached { () -> String? in
            for candidate in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"] where FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
            let found = Self.run("/bin/zsh", ["-lc", "command -v gh"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
            return found.hasPrefix("/") ? found : nil
        }.value
        model?.setup.ghPath = path
        searched = true
    }

    nonisolated private static func readToken(gh: String?) async -> String? {
        guard let gh else { return nil }
        return await Task.detached {
            let result = run(gh, ["auth", "token"])
            let token = result.out.trimmingCharacters(in: .whitespacesAndNewlines)
            guard token.isEmpty || token.contains(" ") else { return token }
            NSLog("HQ: gh auth token failed: %@", result.error.trimmingCharacters(in: .whitespacesAndNewlines))
            return nil
        }.value
    }

    /// The tool's output when it succeeds, and what it said on stderr.
    nonisolated private static func run(_ tool: String, _ arguments: [String]) -> (out: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        let errors = Pipe()
        process.standardOutput = pipe
        process.standardError = errors
        do { try process.run() } catch { return ("", error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let said = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : "", String(decoding: said, as: UTF8.self))
    }

    // MARK: Cache

    private static var cacheURL: URL { Store.directory.appending(path: "github.json") }

    private static func loadCache() -> GitHubSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(GitHubSnapshot.self, from: data)
    }

    nonisolated private static func saveCache(_ snapshot: GitHubSnapshot, to url: URL) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

extension AppModel {
    /// Every PR or issue linked, each once, newest first: `fresh` from the modal, open tasks, live sessions and unread
    /// notifications, `rest` from done tasks and closed sessions.
    func githubLinks() -> (fresh: [String], rest: [String]) {
        let newest = tasks.sorted { $0.modified > $1.modified }
        let open = newest.filter { $0.status != .done }.flatMap(\.links).map(\.absoluteString)
        let done = newest.filter { $0.status == .done }.flatMap(\.links).map(\.absoluteString)
        let live = sessions.filter(\.onGrid).flatMap(\.links)
        let closed = sessions.filter { !$0.onGrid }.sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }.flatMap(\.links)
        let threads = notices.filter { $0.kind == .github && $0.readAt == nil }.sorted { $0.at > $1.at }.compactMap(\.source)
        var seen = Set<String>()
        let fresh = (modalGitHubURLs + open + live + threads).filter { GitHubLinks.isItem($0) && seen.insert($0).inserted }
        let rest = (done + closed).filter { GitHubLinks.isItem($0) && seen.insert($0).inserted }
        return (fresh, rest)
    }

    /// A session printed a PR URL: ask GitHub soon.
    func pollGitHubSoon() {
        githubAsks += 1
        gitHubService?.pollSoon()
    }

    /// Refresh in the PR section: ask GitHub now.
    func refreshGitHub() { gitHubService?.poll() }

    /// Link to Task… / Link to Session… in a PR's modal.
    func link(pullRequest url: String, session id: String) {
        guard var item = session(id), !item.links.contains(url) else { return }
        item.links.append(url)
        put(item)
        registerUndo("Link to Session") { model in
            guard var item = model.session(id) else { return }
            item.links.removeAll { $0 == url }
            model.put(item)
        }
    }
}
