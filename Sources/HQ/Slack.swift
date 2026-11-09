import AppKit
import HQKit
import Security

/// Who a Slack token is for: Settings › Slack shows it.
struct SlackAccount: Codable, Hashable {
    var user: String
    var team: String
}

/// The Slack user token (Settings › Slack), in the Keychain. Test runs keep it in memory.
enum SlackToken {
    private static let service = "io.github.co42.hq.slack"
    private static let account = "token"
    private static var testToken: String?

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        guard !Store.isOverridden else { return testToken }
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Nil or empty removes it.
    static func save(_ token: String?) {
        guard !Store.isOverridden else { testToken = token; return }
        SecItemDelete(query as CFDictionary)
        guard let token, !token.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// The Slack link on the clipboard, for New Task… and New Reminder… (T-313, T-333): it comes with each, until × drops
/// that copy.
@MainActor
enum SlackClipboard {
    /// The last copy HQ read, and the Slack link in it.
    private static var read: (change: Int, url: String?)?
    /// The copy whose link the user dropped with ×.
    private static var dropped: Int?
    /// Test runs: what the clipboard holds and its change count, instead of the user's pasteboard.
    static var testText: String?
    static var testChange = 0

    /// The pasteboard is read once per copy, and only when it holds a link, so macOS asks about pasting only then.
    static func link() async -> String? {
        let change = Store.isOverridden ? testChange : NSPasteboard.general.changeCount
        guard change != dropped else { return nil }
        if let read, read.change == change { return read.url }
        let url = await Self.url(change)
        read = (change, url)
        return url
    }

    /// × on the copied link: that copy no longer comes.
    static func drop(_ url: String) {
        if let read, read.url == url { dropped = read.change }
    }

    private static func url(_ change: Int) async -> String? {
        if Store.isOverridden { return testText.flatMap { SlackLink.find(in: $0)?.url } }
        let pasteboard = NSPasteboard.general
        guard let patterns = try? await pasteboard.detectedPatterns(for: [\.probableWebURL, \.links]), !patterns.isEmpty,
              pasteboard.changeCount == change, let text = pasteboard.string(forType: .string) else { return nil }
        return SlackLink.find(in: text)?.url
    }
}

/// Reads Slack for what its links show (PLAN.md §5): who wrote a linked message, where, its first line, once per link.
/// Read-only, with the user token from Settings › Slack. It doesn't follow conversations. Test runs never reach the network.
@MainActor
final class SlackService {
    private weak var model: AppModel?
    private var token: String?
    /// Links asked about since launch: one try each.
    private var asked: Set<String> = []
    private var users: [String: String] = [:]
    private var observer: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        guard !Store.isOverridden else { return }
        let cache = Self.loadCache()
        model.slackMessages = cache?.messages ?? [:]
        model.slackAccount = cache?.account
        token = SlackToken.load()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resolveLinked() }
        }
        guard token != nil else { return }
        Task { [weak self] in
            await self?.checkAccount()
            self?.resolveLinked()
        }
    }

    /// Settings › Slack: a new token, checked at once; nil signs out.
    func setToken(_ value: String?) async {
        let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        SlackToken.save(clean)
        token = clean?.isEmpty == false ? clean : nil
        asked = []
        await checkAccount()
        resolveLinked()
    }

    func checkAccount() async {
        guard let model else { return }
        if Store.isOverridden {
            model.slackAccount = token.map { _ in Self.fixtureAccount }
            return
        }
        guard token != nil else {
            model.slackAccount = nil
            model.slackError = nil
            return saveCache()
        }
        do {
            let reply = try await call("auth.test", [:])
            model.slackAccount = SlackAccount(user: reply["user"] as? String ?? "", team: reply["team"] as? String ?? "")
            model.slackError = nil
        } catch {
            model.slackAccount = nil
            model.slackError = Self.words(error)
        }
        saveCache()
    }

    /// Every Slack link on a task or a reminder that isn't read yet.
    func resolveLinked() {
        guard let model, token != nil else { return }
        let onTasks = model.tasks.flatMap(\.links).map(\.absoluteString)
        let onNotices = model.notices.flatMap(\.links).compactMap(ModalRoute.init(noticeKey:)).compactMap { route -> String? in
            if case .slack(let url) = route { url } else { nil }
        }
        for url in onTasks + onNotices where SlackLink.isLink(url) { resolve(url) }
    }

    /// Reads the message a link points to, once: its channel, its author, its text.
    func resolve(_ url: String) {
        guard let model, model.slackMessages[url] == nil, let link = SlackLink(url) else { return }
        if Store.isOverridden {
            model.slackMessages[url] = Self.fixtures[url]
            return
        }
        guard token != nil, asked.insert(url).inserted else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let message = try await self.read(link)
                self.model?.slackMessages[url] = message
                self.saveCache()
            } catch {
                AppLog.write("slack: \(url): \(Self.words(error))", to: "slack.log")
            }
        }
    }

    private func read(_ link: SlackLink) async throws -> SlackMessage {
        let info = try await call("conversations.info", ["channel": link.channel])["channel"] as? [String: Any]
        // A direct message is named by who wrote in it.
        let direct = info?["is_im"] as? Bool == true || info?["is_mpim"] as? Bool == true
        let channel = direct ? nil : info?["name"] as? String
        guard let ts = link.ts else { return SlackMessage(channel: channel, author: nil, text: "") }
        let range = ["channel": link.channel, "latest": ts, "oldest": ts, "inclusive": "true"]
        let reply = if let thread = link.threadTS, link.isReply {
            try await call("conversations.replies", range.merging(["ts": thread, "limit": "10"]) { $1 })
        } else {
            try await call("conversations.history", range.merging(["limit": "1"]) { $1 })
        }
        let message = (reply["messages"] as? [[String: Any]])?.first { $0["ts"] as? String == ts }
        var author = message?["username"] as? String ?? (message?["bot_profile"] as? [String: Any])?["name"] as? String
        if let user = message?["user"] as? String { author = try await name(of: user) }
        return SlackMessage(channel: channel, author: author, text: message?["text"] as? String ?? "")
    }

    private func name(of user: String) async throws -> String? {
        if let known = users[user] { return known }
        let profile = (try await call("users.info", ["user": user])["user"] as? [String: Any])
        let details = profile?["profile"] as? [String: Any]
        let name = [details?["display_name"], details?["real_name"], profile?["name"]].compactMap { $0 as? String }.first { !$0.isEmpty }
        users[user] = name
        return name
    }

    private func call(_ method: String, _ parameters: [String: String]) async throws -> [String: Any] {
        guard let token, var components = URLComponents(string: "https://slack.com/api/\(method)") else { throw SlackError.signedOut }
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw SlackError.answer("bad request") }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SlackError.answer("not JSON") }
        guard json["ok"] as? Bool == true else { throw SlackError.answer(json["error"] as? String ?? "refused") }
        return json
    }

    private static func words(_ error: Error) -> String {
        switch error {
        case SlackError.signedOut: "No token"
        case SlackError.answer("invalid_auth"), SlackError.answer("not_authed"): "Slack refused the token"
        case SlackError.answer("token_revoked"), SlackError.answer("account_inactive"): "The token was revoked"
        case SlackError.answer(let code): "Slack said \(code)"
        default: error.localizedDescription
        }
    }

    // MARK: Fixtures

    /// A message link that seed data and test runs show, and what it says.
    static let fixtureLink = "https://example.slack.com/archives/C0EXAMPLE1/p1762500000000100"
    static let fixtures: [String: SlackMessage] = [
        fixtureLink: SlackMessage(channel: "registry", author: "Julien", text: "Can you check the eu-west upload retries before Monday?\nThe canary is red again."),
    ]
    static let fixtureAccount = SlackAccount(user: "tester", team: "Example")

    // MARK: Cache

    private struct Cache: Codable {
        var account: SlackAccount?
        var messages: [String: SlackMessage]
    }

    private static var cacheURL: URL { Store.directory.appending(path: "slack.json") }

    private static func loadCache() -> Cache? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private func saveCache() {
        guard let model, !Store.isOverridden,
              let data = try? JSONEncoder().encode(Cache(account: model.slackAccount, messages: model.slackMessages)) else { return }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }
}

enum SlackError: Error, Equatable {
    case signedOut
    case answer(String)
}

extension AppModel {
    /// A Slack link was linked: read what it shows, once.
    func resolveSlack(_ url: String) { slackService?.resolve(url) }

    /// Settings › Slack.
    func setSlackToken(_ token: String?) {
        Task { await slackService?.setToken(token) }
    }

    /// As a click on the link does (T-335): Slack's page takes it to the app, at the message, the thread or the channel.
    /// Handed to the Slack app directly, it only comes forward. Test runs only note it.
    func openInSlack(_ url: String) {
        guard let address = URL(string: url) else { return }
        guard !Store.isOverridden else { return slackLog.append(url) }
        NSWorkspace.shared.open(address)
    }

    /// New Task… and New Reminder…: the Slack link on the clipboard comes with them, until × drops it (T-313).
    func copiedSlackLink() async -> String? {
        guard let url = await SlackClipboard.link() else { return nil }
        resolveSlack(url)
        return url
    }

    /// × on a link that came from the clipboard: that copy comes no more.
    func dropCopiedLink(_ url: String) { SlackClipboard.drop(url) }

    /// What a task or a reminder made from a Slack link is called when nothing is typed: the message's first line.
    func name(fromSlack url: String) -> String {
        let line = slackMessages[url]?.firstLine ?? ""
        return line.isEmpty ? title(of: .slack(url)) : line
    }
}

/// A Slack link pasted in a list's New Task line: the task added there next links it.
struct PendingTaskLink: Equatable {
    var url: String
    var list: TaskList
}
