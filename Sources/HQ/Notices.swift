import AppKit
import HQKit
import UserNotifications

/// One row of the notification center (DESIGN.md §11): an event the user reads once.
nonisolated struct Notice: Codable, Hashable, Identifiable, Sendable {
    enum Level: String, Codable, Sendable { case important, update }
    enum Kind: String, Codable, Sendable { case session, github, reminder }

    var id = UUID()
    var kind: Kind
    var level: Level
    /// A session's id or a PR's URL; a reminder: the session that set it, if one did.
    var source: String?
    var text: String
    /// Events merged into this row.
    var count = 1
    /// Selection keys of what it links: `task:12`, `file:<id>`, `artifact:<url>`, `github:<url>`, `session:<id>`.
    var links: [String] = []
    var at: Date
    var readAt: Date?
    /// In Later until then.
    var dueAt: Date?
    /// A GitHub review's or comment's page: opening the row opens its PR there, scrolled to it (T-328).
    var anchor: String?
}

/// Where a row shows in the center.
enum NoticeSection: CaseIterable {
    case needsYou, updates, later, earlier

    var title: String {
        switch self {
        case .needsYou: "Needs You"
        case .updates: "Updates"
        case .later: "Later"
        case .earlier: "Earlier"
        }
    }
}

/// What `notifications.json` keeps.
nonisolated struct NoticeStore: Codable, Sendable {
    var notices: [Notice] = []
    /// When the user last opened the center: the bell breathes for what came after.
    var bellSeenAt: Date = .distantPast
    /// GitHub events already turned into rows, by key, for a few days.
    var githubEvents: [String: Date] = [:]
    /// Review requests put Later, by PR URL, until when (T-319). Optional: older files have none.
    var reviewsLater: [String: Date]?
}

extension ModalRoute {
    /// A notice's link: every route's selection key, tasks and sessions included.
    init?(noticeKey key: String) {
        if key.hasPrefix("task:"), let id = Int(key.dropFirst(5)) { self = .task(id) }
        else if key.hasPrefix("session:") { self = .session(String(key.dropFirst(8))) }
        else { self.init(selectionKey: key) }
    }
}

extension AppModel {
    // MARK: Sections and counts

    /// The center is open, or something it opened is, with it to go Back to.
    var centerOpen: Bool { modal == .notifications || modalStack.contains(.notifications) }

    func section(of notice: Notice) -> NoticeSection {
        if centerOpen, let pinned = noticePins[notice.id] { return pinned }
        if let due = notice.dueAt, due > now { return .later }
        if notice.readAt != nil { return .earlier }
        return notice.level == .important ? .needsYou : .updates
    }

    /// Done means read for a notification, completed for a reminder: its `readAt` either way.
    func isDone(_ notice: Notice) -> Bool { notice.readAt != nil }

    /// Sessions that wait on the user: Needs You for as long as they wait.
    var blockedSessions: [SessionItem] {
        gridSessions.filter { $0.isRunning && $0.status.needsYou }
    }

    /// Unread rows by section, newest first; Earlier keeps what was read in the last day.
    func notices(in section: NoticeSection) -> [Notice] {
        let rows = notices.filter { self.section(of: $0) == section }
        switch section {
        case .later: return rows.sorted { ($0.dueAt ?? $0.at) < ($1.dueAt ?? $1.at) }
        case .earlier:
            let day = now.addingTimeInterval(-86_400)
            return Array(rows.filter { ($0.readAt ?? $0.at) > day }.sorted { ($0.readAt ?? $0.at) > ($1.readAt ?? $1.at) }.prefix(40))
        default: return rows.sorted { $0.at > $1.at }
        }
    }

    private func unread(_ notice: Notice) -> Bool {
        notice.readAt == nil && (notice.dueAt.map { $0 <= now } ?? true)
    }

    /// Needs You: blocked sessions, review requests that wait, and unread important rows. The Dock badge.
    var importantCount: Int { blockedSessions.count + waitingReviews.count + notices.filter { $0.level == .important && unread($0) }.count }

    /// PRs that wait for the user's review, not put Later: they stand in Needs You until reviewed (T-319).
    var waitingReviews: [GitHubItem] {
        let later = noticeStore.reviewsLater ?? [:]
        return allReviewRequests.filter { waitsForReview($0) && (later[$0.url] ?? .distantPast) <= now }
    }

    /// Review requests put Later, with when they come back.
    var laterReviews: [(item: GitHubItem, until: Date)] {
        let later = noticeStore.reviewsLater ?? [:]
        return allReviewRequests.filter(waitsForReview).compactMap { item in later[item.url].flatMap { $0 > now ? (item, $0) : nil } }
            .sorted { $0.until < $1.until }
    }

    /// Later on a review request: out of Needs You until `date`; nil brings it back now.
    func putReviewLater(_ url: String, until date: Date?) {
        let before = noticeStore.reviewsLater
        var later = (before ?? [:]).filter { entry in allReviewRequests.contains { $0.url == entry.key } }
        later[url] = date
        noticeStore.reviewsLater = later
        registerUndo(date == nil ? "Bring Back" : "Later") { $0.noticeStore.reviewsLater = before }
    }

    var updateCount: Int { notices.filter { $0.level == .update && unread($0) }.count }

    /// The bell breathes until the user opens the center after the latest thing that needs them.
    var bellBreathes: Bool {
        let latest = (blockedSessions.map(\.status.since) + waitingReviews.map(\.reviewAskedAt)
            + notices.filter { $0.level == .important && unread($0) }.map(\.at)).max()
        return latest.map { $0 > noticeStore.bellSeenAt } ?? false
    }

    /// "2 need you, 3 updates": the bell's tooltip.
    var noticeSummary: String {
        let needs = importantCount, updates = updateCount
        var parts: [String] = []
        if needs > 0 { parts.append("\(needs) need\(needs == 1 ? "s" : "") you") }
        if updates > 0 { parts.append("\(updates) update\(updates == 1 ? "" : "s")") }
        return parts.isEmpty ? "Nothing new" : parts.joined(separator: ", ")
    }

    // MARK: The center

    /// ⌘J, the bell, a banner: the center, fresh.
    /// The open reminder that links an item, the one due first: its mark on the item's row (T-311).
    func reminder(for route: ModalRoute) -> Notice? {
        _ = noticeStore.notices.count
        if reminderMarks == nil {
            var marks: [String: [Notice]] = [:]
            for notice in notices where notice.kind == .reminder && notice.readAt == nil {
                for key in notice.links { marks[key, default: []].append(notice) }
            }
            reminderMarks = marks.mapValues { $0.sorted { ($0.dueAt ?? .distantPast) < ($1.dueAt ?? .distantPast) } }
        }
        return reminderMarks?[route.selectionKey]?.first
    }

    /// A reminder's mark: due (it came back), and what its tooltip says.
    func reminderMark(_ notice: Notice) -> (due: Bool, help: String) {
        let due = notice.dueAt.map { $0 <= now } ?? true
        let when = due ? "due" : ReminderTime.describe(notice.dueAt ?? now, now: now)
        return (due, "Reminder, \(when): \(notice.text). Click to see it in the notifications")
    }

    /// A reminder's mark clicked: the center, on that reminder.
    func showReminder(_ notice: Notice) {
        openCenter()
        noticeSelection = notice.id.uuidString
    }

    func openCenter() {
        if modal == .notifications { return }
        if modalStack.contains(.notifications) {
            modalStack.removeAll()
            modal = .notifications
            return
        }
        noticePins = [:]
        noticeSelection = nil
        noticeStore.bellSeenAt = .now
        open(.notifications)
    }

    /// New Reminder… (⌃⌘R, +, the menu bar and Dock menus): its own small sheet, over what's open.
    func beginReminder() {
        guard modal != .newReminder else { return }
        open(.newReminder, push: modal != nil)
    }

    // MARK: Adding

    /// A session (`hq notify`) or HQ tells the user something. A session's unread row at that level takes it in.
    /// `at`: when it happened, a GitHub review's or comment's own time; a session's notification happens now.
    @discardableResult
    func notify(_ text: String, level: Notice.Level, kind: Notice.Kind = .session, source: String?, links: [String] = [],
                count: Int = 1, at happened: Date = .now, anchor: String? = nil) -> Notice {
        if kind != .reminder, source != nil, let index = notices.firstIndex(where: { $0.kind == kind && $0.source == source && $0.level == level && unread($0) && $0.dueAt == nil }) {
            var row = notices[index]
            row.text = text
            row.count += count
            row.links = links + row.links.filter { !links.contains($0) }
            row.at = max(row.at, happened)
            if happened >= row.at, let anchor { row.anchor = anchor }
            notices[index] = row
            if level == .important { banner(row) }
            return row
        }
        let row = Notice(kind: kind, level: level, source: source, text: text, count: count, links: links, at: happened, anchor: anchor)
        notices.append(row)
        if level == .important { banner(row) }
        return row
    }

    /// A reminder: in Later until `due`, then Needs You or Updates by its level.
    @discardableResult
    func remind(_ text: String, at due: Date, level: Notice.Level, source: String? = nil, links: [String] = []) -> Notice {
        let row = Notice(kind: .reminder, level: level, source: source, text: text, links: links, at: .now, dueAt: due)
        notices.append(row)
        registerUndo("Add Reminder") { $0.notices.removeAll { $0.id == row.id } }
        scheduleDue()
        for case .slack(let url) in links.compactMap(ModalRoute.init(noticeKey:)) { resolveSlack(url) }
        return row
    }

    /// What a session's notice links when it names nothing: its open tasks, and what it made or opened since its last notice.
    func defaultLinks(forSession id: String) -> [String] {
        let since = notices.filter { $0.kind == .session && $0.source == id }.map(\.at).max() ?? .distantPast
        let tasks = tasks(of: id).filter { $0.status != .done }.map { ModalRoute.task($0.id).selectionKey }
        let files = files.filter { $0.sessions.contains(id) && $0.modified > since }.sorted { $0.modified > $1.modified }
            .map { ModalRoute.file($0.id).selectionKey }
        let pages = artifacts.filter { $0.session == id && $0.published > since }.sorted { $0.published > $1.published }
            .map { ModalRoute.artifact($0.id).selectionKey }
        let prs = pullRequests(ofSession: id).filter { $0.state == .open || $0.state == .draft }.map { ModalRoute.github($0.url).selectionKey }
        var seen = Set<String>()
        return (tasks + files + pages + prs).filter { seen.insert($0).inserted }
    }

    // MARK: Acting on rows

    func markRead(_ id: Notice.ID) { setDone(id, true) }

    /// Read or unread, completed or not (E). While the center shows, the row stays where it is.
    func setDone(_ id: Notice.ID, _ done: Bool) {
        guard let index = notices.firstIndex(where: { $0.id == id }), isDone(notices[index]) != done else { return }
        let before = notices[index]
        pin(before)
        notices[index].readAt = done ? .now : nil
        // Dealt with before its time: it doesn't come back.
        if done { notices[index].dueAt = nil }
        let name = before.kind == .reminder ? (done ? "Complete Reminder" : "Uncomplete Reminder") : (done ? "Mark Read" : "Mark Unread")
        registerUndo(name) { model in
            if let index = model.notices.firstIndex(where: { $0.id == id }) { model.notices[index] = before }
        }
        scheduleDue()
    }

    /// Later: out of sight until `date`, then back unread at its level.
    func snooze(_ id: Notice.ID, until date: Date) {
        guard let index = notices.firstIndex(where: { $0.id == id }) else { return }
        let before = notices[index]
        noticePins[id] = nil
        notices[index].dueAt = date
        notices[index].readAt = nil
        registerUndo("Later") { model in
            if let index = model.notices.firstIndex(where: { $0.id == id }) { model.notices[index] = before }
        }
        scheduleDue()
    }

    /// Now, on a row in Later: back at once.
    func bringBack(_ id: Notice.ID) {
        guard let index = notices.firstIndex(where: { $0.id == id }) else { return }
        let before = notices[index]
        noticePins[id] = nil
        notices[index].dueAt = nil
        notices[index].readAt = nil
        notices[index].at = .now
        registerUndo("Bring Back") { model in
            if let index = model.notices.firstIndex(where: { $0.id == id }) { model.notices[index] = before }
        }
    }

    /// A reminder's words, time and level. No time, or one that has passed: it's due now.
    func editReminder(_ id: Notice.ID, text: String, due: Date?, level: Notice.Level) {
        guard let index = notices.firstIndex(where: { $0.id == id }) else { return }
        let before = notices[index]
        noticePins[id] = nil
        notices[index].text = text
        notices[index].level = level
        notices[index].readAt = nil
        if let due, due > .now {
            notices[index].dueAt = due
        } else if notices[index].dueAt != nil {
            notices[index].dueAt = nil
            notices[index].at = .now
        }
        registerUndo("Edit Reminder") { model in
            if let index = model.notices.firstIndex(where: { $0.id == id }) { model.notices[index] = before }
        }
        scheduleDue()
    }

    /// While the center shows, a row acted on keeps its place.
    private func pin(_ notice: Notice) {
        guard centerOpen, noticePins[notice.id] == nil else { return }
        noticePins[notice.id] = section(of: notice)
    }

    func removeNotice(_ id: Notice.ID) {
        guard let row = notices.first(where: { $0.id == id }) else { return }
        notices.removeAll { $0.id == id }
        registerUndo("Remove") { $0.notices.append(row) }
    }

    // MARK: Due rows

    /// Rows whose time came: unread again at their time, a banner for the important ones. Then waits for the next.
    func fireDue() {
        let now = Date.now
        var next = notices
        var fired: [Notice] = []
        for index in next.indices {
            guard let due = next[index].dueAt, due <= now else { continue }
            next[index].dueAt = nil
            next[index].at = due
            next[index].readAt = nil
            fired.append(next[index])
        }
        if !fired.isEmpty {
            notices = next
            for row in fired where row.level == .important { banner(row) }
        }
        scheduleDue()
    }

    func scheduleDue() {
        dueTimer?.cancel()
        guard let next = notices.compactMap(\.dueAt).min() else { return }
        dueTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow + 0.5)))
            guard !Task.isCancelled else { return }
            self?.fireDue()
        }
    }

    // MARK: Store

    func loadNotices() {
        let url = Store.directory.appending(path: "notifications.json")
        if let data = try? Data(contentsOf: url), let store = try? Self.noticeDecoder.decode(NoticeStore.self, from: data) {
            noticeStore = store
        }
        // Read rows go after two weeks.
        let cutoff = Date.now.addingTimeInterval(-14 * 86_400)
        noticeStore.notices.removeAll { ($0.readAt ?? .distantFuture) < cutoff }
        // GitHub keys outlast the longest lookback, so raising it never notifies twice.
        let keep = Date.now.addingTimeInterval(-Double(Self.lookbackChoices.max() ?? 30) * 86_400)
        noticeStore.githubEvents = noticeStore.githubEvents.filter { $0.value > keep }
        fireDue()
    }

    func saveNoticesSoon() {
        guard noticeSave == nil else { return }
        noticeSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            self.noticeSave = nil
            let url = Store.directory.appending(path: "notifications.json")
            if let data = try? Self.noticeEncoder.encode(self.noticeStore) { try? data.write(to: url, options: .atomic) }
        }
    }

    nonisolated static let noticeEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    nonisolated static let noticeDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: Banners

    /// A macOS banner for what needs the user. Never in a test run: those keep it in `ghosttyLog`.
    func banner(_ row: Notice) {
        let title: String = switch row.kind {
        case .session: session(row.source).map { "\($0.name) needs you" } ?? "A session needs you"
        case .github: githubItem(row.source).map(\.reference) ?? row.source.flatMap(GitHubThreads.reference) ?? "GitHub"
        case .reminder: "Reminder"
        }
        postBanner(id: row.id.uuidString, title: title, body: row.text)
    }

    /// A session started to wait on the user: a banner, unless they are already looking at its terminal.
    func sessionBlocked(_ id: String) {
        guard let item = session(id), item.isRunning, item.status.needsYou else { return }
        let since = item.status.since
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, let item = self.session(id), item.status.needsYou, item.status.since == since else { return }
            let tty = Store.isOverridden ? nil : await Task.detached { [setup] () -> String? in
                guard setup.ghosttyAllowed, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Ghostty.bundleID else { return nil }
                return try? Ghostty.focusedTTY()
            }.value
            guard tty == nil || tty != item.tty else { return }
            self.postBanner(id: "\(id)-\(since.timeIntervalSince1970)", title: "\(item.name) needs you", body: item.reason ?? item.status.title)
        }
    }

    private func postBanner(id: String, title: String, body: String) {
        if Store.isOverridden { return ghosttyLog.append("banner \(title): \(body)") }
        let center = UNUserNotificationCenter.current()
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }
}

/// A click on a banner opens the center; while HQ is in front, its bell says it already.
final class BannerDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var model: AppModel?

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            NSApp.activate()
            model?.openCenter()
        }
    }
}
