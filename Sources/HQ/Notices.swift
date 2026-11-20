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
    /// A PR's or an issue's title, as it was when it notified: the row shows it after the reference (T-360).
    var title: String?
    /// The texts this row had before newer ones of the same source replaced them, newest first (T-511).
    var replaced: [String]?
    /// What its button does: Restart Idle Sessions on the row that says a newer Claude Code is installed (T-454).
    var action: Action?

    enum Action: String, Codable, Sendable { case restartIdle }
}

/// One face in the toolbar's who waits (DESIGN.md §3): a session that waits or pinged, or a due important reminder.
struct WaitingItem: Identifiable, Equatable {
    var session: SessionItem?
    /// Its badge: the session's wait, a ping; nil for a reminder, which shows its tile.
    var glyph: SessionGlyphKind?
    var at: Date
    var pings: [Notice] = []

    var id: String { session.map { "session:\($0.id)" } ?? pings.first.map { "notice:\($0.id.uuidString)" } ?? "" }

    /// Its name, as the center's card says it.
    var name: String {
        if let session { return session.name }
        return glyph == nil ? "Reminder" : "Claude"
    }

    /// What it asks: the session's reason while it waits, else the latest ping's text.
    var what: String {
        if let session, session.isRunning, session.status.needsYou { return session.reason ?? session.status.title }
        return pings.first.map { MarkdownLine.plain($0.text) } ?? ""
    }

    /// Its tooltip: who, what, and what a click does.
    var help: String {
        let click = session?.isRunning == true ? "Click to focus its terminal" : "Click to see it in the notifications"
        return "\(name): \(what)\n\(click)"
    }
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
    /// Rows the last read couldn't decode: the file then goes aside before HQ saves over it.
    var dropped = 0

    enum CodingKeys: String, CodingKey { case notices, bellSeenAt, githubEvents, reviewsLater }
}

extension NoticeStore {
    /// Every key may be missing, and a row that doesn't decode costs that row only: a field added later, or a new
    /// case an older build doesn't know, never empties the reminders.
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if var rows = try? c.nestedUnkeyedContainer(forKey: .notices) {
            while !rows.isAtEnd {
                if let row = try? rows.decode(Notice.self) {
                    notices.append(row)
                } else {
                    _ = try? rows.decode(Skipped.self)
                    dropped += 1
                }
            }
        }
        bellSeenAt = (try? c.decodeIfPresent(Date.self, forKey: .bellSeenAt)) ?? .distantPast
        githubEvents = (try? c.decodeIfPresent([String: Date].self, forKey: .githubEvents)) ?? [:]
        reviewsLater = try? c.decodeIfPresent([String: Date].self, forKey: .reviewsLater)
    }

    /// Reads past one row.
    private struct Skipped: Decodable { nonisolated init(from decoder: Decoder) {} }
}

extension Notice {
    /// Only what a row can't do without is required: its kind, level, text and time.
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        kind = try c.decode(Kind.self, forKey: .kind)
        level = try c.decode(Level.self, forKey: .level)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        text = try c.decode(String.self, forKey: .text)
        count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 1
        links = (try? c.decodeIfPresent([String].self, forKey: .links)) ?? []
        at = try c.decode(Date.self, forKey: .at)
        readAt = try? c.decodeIfPresent(Date.self, forKey: .readAt)
        dueAt = try? c.decodeIfPresent(Date.self, forKey: .dueAt)
        anchor = try? c.decodeIfPresent(String.self, forKey: .anchor)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
    }
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

    /// Where a row shows, at once: a row read, done, put Later or edited moves there while the center shows (T-365).
    func section(of notice: Notice) -> NoticeSection {
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

    /// PRs that wait for the user's review, neither dismissed nor put Later: they stand in Needs You until reviewed (T-319), a reminder on them or not.
    var waitingReviews: [GitHubItem] {
        let later = noticeStore.reviewsLater ?? [:]
        return allReviewRequests.filter { waitsForReview($0) && !dismissed($0) && (later[$0.url] ?? .distantPast) <= now }
    }

    /// Review requests put Later, with when they come back.
    var laterReviews: [(item: GitHubItem, until: Date)] {
        let later = noticeStore.reviewsLater ?? [:]
        return allReviewRequests.filter { waitsForReview($0) && !dismissed($0) }.compactMap { item in later[item.url].flatMap { $0 > now ? (item, $0) : nil } }
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

    /// Who waits on the user, for the toolbar (DESIGN.md §3, T-655): the sessions that wait, the unread pings and the due
    /// important reminders, newest first; one item per session, its wait over its pings. Reviews stay out.
    var waitingItems: [WaitingItem] {
        var items = blockedSessions.map { WaitingItem(session: $0, glyph: SessionGlyphKind($0.status), at: $0.status.since) }
        for notice in notices.filter({ $0.level == .important && unread($0) }).sorted(by: { $0.at > $1.at }) {
            let session = notice.kind == .session ? self.session(notice.source) : nil
            if let session, let index = items.firstIndex(where: { $0.session?.id == session.id }) {
                items[index].pings.append(notice)
                items[index].at = max(items[index].at, notice.at)
            } else {
                items.append(WaitingItem(session: session, glyph: notice.kind == .reminder ? nil : .ping, at: notice.at, pings: [notice]))
            }
        }
        return items.sorted { $0.at > $1.at }
    }

    /// A session's pings the user hasn't read: its important notifications.
    func unreadPings(of id: SessionItem.ID) -> [Notice] {
        notices.filter { $0.kind == .session && $0.source == id && $0.level == .important && unread($0) }
    }

    /// A face in who waits clicked: a running session's terminal, its pings read; else the center on its row.
    func focusWaiting(_ item: WaitingItem) {
        if let session = item.session, session.isRunning {
            for ping in item.pings { markRead(ping.id, by: "a click on its face") }
            open(session.id)
        } else {
            openCenter()
            noticeSelection = item.pings.first.map(\.id.uuidString) ?? item.session.map { "session:\($0.id)" }
        }
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
        return (due, "Reminder, \(when): \(MarkdownLine.plain(notice.text)). Click to see it in the notifications")
    }

    /// A reminder's mark clicked: the center, on that reminder.
    func showReminder(_ notice: Notice) {
        openCenter()
        noticeSelection = notice.id.uuidString
    }

    /// A banner clicked: HQ in front on the center; window.log says how long each step took (T-683).
    /// Where each banner click went, for the self-test.
    static var bannerOpened: [String] = []

    /// T-690: its item. A session's terminal for a session that waits or pinged (HQ stays behind, its pings read); a
    /// review's PR window; anything else the center, on its row.
    func openFromBanner(clicked: Double, opens: String? = nil) {
        let reached = CACurrentMediaTime()
        let ms = { (seconds: Double) in Int(seconds * 1000) }
        let notice = opens.flatMap { $0.hasPrefix("notice:") ? UUID(uuidString: String($0.dropFirst(7))) : nil }.flatMap { id in notices.first { $0.id == id } }
        let sessionID = opens.flatMap { $0.hasPrefix("session:") ? String($0.dropFirst(8)) : nil } ?? (notice?.kind == .session ? notice?.source : nil)
        if let sessionID, let item = session(sessionID), item.isRunning {
            if let notice { markRead(notice.id, by: "a click on its banner") }
            open(sessionID)
            Self.bannerOpened.append("terminal \(sessionID)")
            return AppLog.write("banner click: on the main thread after \(ms(reached - clicked)) ms, focusing \(item.name)'s terminal", to: "window.log")
        }
        if !Store.background { NSApp.activate() }
        let activated = CACurrentMediaTime()
        let what: String
        if let opens, opens.hasPrefix("review:") {
            let url = String(opens.dropFirst(7))
            open(.github(url))
            what = "its PR"
            Self.bannerOpened.append("review \(url)")
        } else {
            openCenter()
            noticeSelection = notice.map(\.id.uuidString) ?? opens.flatMap { $0.hasPrefix("session:") ? $0 : nil }
            what = "the center"
            Self.bannerOpened.append("center \(noticeSelection ?? "-")")
        }
        Task {
            for _ in 0..<500 where window?.attachedSheet == nil { try? await Task.sleep(for: .milliseconds(20)) }
            AppLog.write("banner click: on the main thread after \(ms(reached - clicked)) ms, activated in \(ms(activated - reached)) ms, "
                         + "\(what) \(window?.attachedSheet == nil ? "not shown" : "shown") after \(ms(CACurrentMediaTime() - clicked)) ms", to: "window.log")
        }
    }

    func openCenter() {
        if modal == .notifications { return }
        if modalStack.contains(.notifications) {
            modalStack.removeAll()
            modal = .notifications
            return
        }
        noticeSelection = nil
        noticeStore.bellSeenAt = .now
        open(.notifications)
    }

    /// New Reminder… (⌃⌘R, +, the menu bar and Dock menus): its own small sheet, over what's open.
    func beginReminder() {
        guard modal != .newReminder else { return }
        reminderAbout = nil
        open(.newReminder, push: modal != nil)
    }

    /// Remind Me… on a task, a PR, a file or an artifact (T-343): New Reminder with the item linked, its title the
    /// reminder's words until the user types theirs.
    func beginReminder(about route: ModalRoute) {
        guard modal != .newReminder else { return }
        reminderAbout = route
        open(.newReminder, push: modal != nil)
    }

    // MARK: Adding

    /// How many replaced texts a row keeps.
    static let replacedKept = 9

    /// A session (`hq notify`) or HQ tells the user something. A session's unread row at that level takes it in.
    /// `at`: when it happened, a GitHub review's or comment's own time; a session's notification happens now.
    @discardableResult
    func notify(_ text: String, level: Notice.Level, kind: Notice.Kind = .session, source: String?, links: [String] = [],
                count: Int = 1, at happened: Date = .now, anchor: String? = nil, title: String? = nil, action: Notice.Action? = nil) -> Notice {
        if kind != .reminder, source != nil, let index = notices.firstIndex(where: { $0.kind == kind && $0.source == source && $0.level == level && unread($0) && $0.dueAt == nil }) {
            var row = notices[index]
            if row.text != text { row.replaced = Array(([row.text] + (row.replaced ?? [])).prefix(Self.replacedKept)) }
            row.text = text
            row.count += count
            row.links = links + row.links.filter { !links.contains($0) }
            row.at = max(row.at, happened)
            if happened >= row.at, let anchor { row.anchor = anchor }
            if let title { row.title = title }
            if let action { row.action = action }
            notices[index] = row
            if level == .important { banner(row) }
            return row
        }
        var row = Notice(kind: kind, level: level, source: source, text: text, count: count, links: links, at: happened, anchor: anchor, title: title)
        row.action = action
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

    /// `by`: what read it, in notices.log for a ping.
    func markRead(_ id: Notice.ID, by: String = "the center") { setDone(id, true, by: by) }

    /// Read or unread, completed or not (E). The row moves to its section at once; the selection goes on to the next.
    func setDone(_ id: Notice.ID, _ done: Bool, by: String = "the center") {
        guard let index = notices.firstIndex(where: { $0.id == id }), isDone(notices[index]) != done else { return }
        let before = notices[index]
        if done, before.level == .important, before.kind == .session {
            AppLog.write("ping read by \(by): \(noticeLogName(before))", to: "notices.log")
        }
        handOnSelection(from: id)
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
        handOnSelection(from: id)
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

    /// A selected row about to move away hands the selection to the row after it, else the one before, as they show:
    /// E, E, E goes down the list (T-365).
    private func handOnSelection(from id: Notice.ID) {
        guard noticeSelection == id.uuidString else { return }
        let sections: [NoticeSection] = earlierOpen ? [.needsYou, .updates, .later, .earlier] : [.needsYou, .updates, .later]
        let rows = sections.flatMap { notices(in: $0) }.map(\.id)
        guard let index = rows.firstIndex(of: id) else { return }
        let next = index + 1 < rows.count ? rows[index + 1] : index > 0 ? rows[index - 1] : nil
        noticeSelection = next?.uuidString
    }

    func removeNotice(_ id: Notice.ID) {
        guard let row = notices.first(where: { $0.id == id }) else { return }
        handOnSelection(from: id)
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
        // No file: nothing yet. A file that doesn't decode, whole or a row of it, goes aside before HQ saves over it.
        if let data = try? Data(contentsOf: url) { // io: ok HQ's own file, once at launch
            let store = try? Self.noticeDecoder.decode(NoticeStore.self, from: data)
            if store == nil || store?.dropped ?? 0 > 0 {
                if let aside = Store.moveAside(url) { movedAside.append(aside.path) }
                problem = .movedAside
            }
            if let store { noticeStore = store }
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
            self.saveNoticesNow()
        }
    }

    /// Writes `notifications.json` now: a second after a change, and at quit.
    func saveNoticesNow() {
        noticeSave?.cancel()
        noticeSave = nil
        let url = Store.directory.appending(path: "notifications.json")
        do {
            try Self.noticeEncoder.encode(noticeStore).write(to: url, options: .atomic)
        } catch {
            AppLog.write("couldn't save the notifications: \(error.localizedDescription)", to: "store.log")
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

    /// A macOS banner with its sound for what needs the user (DESIGN.md §11, T-657), HQ in front or not; a session's
    /// ping none while its terminal has the focus. Never in a test run: those keep it in `ghosttyLog`.
    func banner(_ row: Notice) {
        let title: String = switch row.kind {
        case .session: session(row.source).map { "\($0.name) needs you" } ?? "A session needs you"
        case .github: githubItem(row.source).map(\.reference) ?? row.source.flatMap(GitHubThreads.reference) ?? "GitHub"
        case .reminder: "Reminder"
        }
        let body = MarkdownLine.plain(row.text)
        let opens = "notice:\(row.id.uuidString)"
        guard row.kind == .session, let tty = session(row.source)?.tty else {
            return postBanner(id: row.id.uuidString, title: title, body: body, opens: opens, why: row.kind == .session ? "no terminal known" : nil)
        }
        Task { [weak self] in
            guard let self else { return }
            if await self.looksAtTerminal(tty) { return self.noBanner(title, opens: opens) }
            self.postBanner(id: row.id.uuidString, title: title, body: body, opens: opens, why: self.notLooking(tty))
        }
    }

    /// A notification as notices.log names it: its kind, source and first words.
    func noticeLogName(_ row: Notice) -> String {
        let from = row.kind == .session ? session(row.source)?.name ?? row.source ?? "?" : row.source ?? "-"
        return "\(row.kind) \(from) \(row.id.uuidString.prefix(8)): \(LineCut.line(MarkdownLine.plain(row.text), width: 80))"
    }

    /// A session started to wait on the user: a banner, unless its terminal has the focus.
    func sessionBlocked(_ id: String) {
        guard let item = session(id), item.isRunning, item.status.needsYou else { return }
        let since = item.status.since
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.bannerDelay))
            guard let self, let item = self.session(id), item.status.needsYou, item.status.since == since else { return }
            if await self.looksAtTerminal(item.tty) { return self.noBanner("\(item.name) needs you", opens: "session:\(id)") }
            self.postBanner(id: "\(id)-\(since.timeIntervalSince1970)", title: "\(item.name) needs you", body: item.reason ?? item.status.title,
                            opens: "session:\(id)", why: self.notLooking(item.tty))
        }
    }

    /// A banner left out: its terminal has the focus. A test run keeps it in `ghosttyLog`.
    private func noBanner(_ title: String, opens: String) {
        AppLog.write("banner skipped: \(title) → \(opens): its terminal has the focus", to: "notices.log")
        if Store.isOverridden { ghosttyLog.append("no banner \(title): its terminal has the focus") }
    }

    /// Why the user doesn't look at the terminal on `tty`, for notices.log.
    func notLooking(_ tty: String?) -> String {
        if tty == nil { return "no terminal known" }
        if !(setup.ghosttyAllowed || Ghostty.faked) { return "no access to Ghostty" }
        return Ghostty.inFront ? "another terminal has the focus" : "Ghostty isn't in front"
    }

    /// How long a session waits before its banner: an answer within it needs none.
    static var bannerDelay: TimeInterval = 2

    /// The terminal on `tty` really has the focus: Ghostty is the app in front, and it's the focused terminal of its front
    /// window's selected tab. Merely on screen isn't enough.
    func looksAtTerminal(_ tty: String?) async -> Bool {
        guard let tty, setup.ghosttyAllowed || Ghostty.faked, Ghostty.inFront else { return false }
        return await Task.detached { try? Ghostty.focusedTTY() }.value == tty
    }

    /// `opens`: what a click on it opens, "session:<id>", "review:<url>" or "notice:<id>" (T-690). `why`: why it shows, in notices.log.
    func postBanner(id: String, title: String, body: String, opens: String, why: String? = nil) {
        let line = "\(title) → \(opens)\(why.map { ": \($0)" } ?? "")"
        if Store.isOverridden {
            AppLog.write("banner shown: \(line)", to: "notices.log")
            return ghosttyLog.append("banner \(title): \(body) → \(opens)")
        }
        let center = UNUserNotificationCenter.current()
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else {
                return AppLog.write("banner skipped: \(line); HQ may not post notifications", to: "notices.log")
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = ["opens": opens]
            do {
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
                AppLog.write("banner shown: \(line)", to: "notices.log")
            } catch {
                AppLog.write("banner skipped: \(line); macOS refused it: \(error.localizedDescription)", to: "notices.log")
            }
        }
    }
}

/// A click on a banner opens its item (T-690). HQ in front shows it too, with its sound (T-657).
final class BannerDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var model: AppModel?

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        Self.presentation
    }

    /// How a banner shows while HQ is in front: as when it isn't.
    nonisolated static let presentation: UNNotificationPresentationOptions = [.banner, .sound, .list]

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let clicked = CACurrentMediaTime()
        let opens = response.notification.request.content.userInfo["opens"] as? String
        await MainActor.run { model?.openFromBanner(clicked: clicked, opens: opens) }
    }
}
