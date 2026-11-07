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
    /// `gh auth token` failed this many times in a row: once can be a slow start, twice is signed out.
    private var tokenFailures = 0
    /// `gh` was looked for: polls before that would find it missing.
    private var searched = false
    private var polling = false {
        didSet { model?.githubPolling = polling }
    }
    private var observers: [NSObjectProtocol] = []
    /// Test runs and `HQ_GITHUB=fixtures`.
    static var usesFixtures: Bool {
        Store.isOverridden || ProcessInfo.processInfo.environment["HQ_GITHUB"] == "fixtures"
    }

    init(model: AppModel) {
        self.model = model
        if Self.usesFixtures { return }
        model.github = Self.loadCache()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        })
        Task { [weak self] in
            await self?.findGH()
            self?.poll()
        }
    }

    /// The fixture's poll, its dates moved to now (seed data and test runs).
    static func fixture(now: Date = .now) -> GitHubSnapshot? {
        guard var snapshot = try? GitHubQuery.parse(GitHubFixture.poll, linked: GitHubFixture.linked, now: now) else { return nil }
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

    /// Polls now, then every minute while HQ is in front and every five otherwise; slower after errors.
    func poll() {
        guard !Self.usesFixtures, searched, !polling else { return }
        polling = true
        timer?.cancel()
        Task {
            let again = await fetch()
            polling = false
            if again { pollSoon() } else { schedule() }
        }
    }

    func pollSoon() {
        guard !Self.usesFixtures else { return }
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { self?.poll() }
        }
    }

    private func schedule() {
        let base: Double = NSApp.isActive ? 60 : 300
        let delay = failures == 0 ? base : min(base * pow(2, Double(failures)), 1_800)
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
        let linked = linkedURLs()
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("HQ (macOS)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": GitHubQuery.query(linked: linked)])
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 {
                // A rotated token: ask gh once more next time.
                self.token = nil
                set(.githubSignedOut)
                failures += 1
                return false
            }
            guard status == 200 else {
                failures += 1
                if failures >= 3 { set(.githubFailing) }
                return false
            }
            let snapshot = try GitHubQuery.parse(data, linked: linked)
            failures = 0
            let changed = snapshot.viewer != model.github?.viewer || snapshot.items != model.github?.items
            if changed {
                apply(snapshot)
                Self.saveCache(snapshot)
            }
            // A poll that changed nothing leaves the page alone: only the Refresh button's tooltip says when.
            model.githubAnswered = snapshot.fetchedAt
            set(nil)
            await fetchThreads(token: token)
        } catch {
            failures += 1
            if failures >= 3 { set(.githubFailing) }
        }
        return false
    }

    /// Reviews, comments and failed checks on the user's PRs, and review requests, go to the notification center.
    func apply(_ snapshot: GitHubSnapshot) {
        guard let model else { return }
        model.noteGitHubEvents(before: model.github, after: snapshot)
        model.github = snapshot
        model.setup.githubAccount = snapshot.viewer
    }

    /// Every PR or issue a task, a session or an unread notification links.
    private func linkedURLs() -> [String] {
        guard let model else { return [] }
        var seen = Set<String>()
        let threads = model.notices.filter { $0.kind == .github && $0.readAt == nil }.compactMap(\.source)
        let urls = model.tasks.flatMap(\.links).map(\.absoluteString) + model.sessions.flatMap(\.links) + threads
        return urls.filter { GitHubLinks.isItem($0) && seen.insert($0).inserted }
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
                         links: [ModalRoute.github(thread.url).selectionKey] + model.tasks(linking: thread.url).map { ModalRoute.task($0.id).selectionKey }, at: thread.updatedAt, anchor: said?.url)
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

    private static func saveCache(_ snapshot: GitHubSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}

extension AppModel {
    /// A session printed a PR URL: ask GitHub soon.
    func pollGitHubSoon() { gitHubService?.pollSoon() }

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
