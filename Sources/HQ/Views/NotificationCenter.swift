import HQKit
import SwiftUI

/// The notification center (DESIGN.md §11), a sheet like a file's: Needs You, Updates, Later, then what was done in
/// the last day. A link opens over it, so Back returns here. Keys: ↑ ↓ move, Return opens (edits a reminder that
/// links nothing), E reads or completes, L puts Later, ⌫ deletes, ⌘C copies the text.
struct NotificationCenterView: View {
    @Environment(AppModel.self) private var model
    @State private var allEarlier = false
    @State private var laterFor: String?
    @State private var editing: Notice.ID?
    @FocusState private var focused: Bool

    /// Earlier's rows before Show More.
    private static let earlierShown = 5

    var body: some View {
        let blocked = model.blockedSessions
        let needs = model.notices(in: .needsYou)
        let updates = model.notices(in: .updates)
        let later = model.notices(in: .later)
        let earlier = model.notices(in: .earlier)
        ScrollViewReader { proxy in
            ModalPage {
                if model.composingReminder {
                    ModalBox(rows: true) { ReminderEditor(notice: nil) { finishEditing() } }
                } else if blocked.isEmpty && needs.isEmpty && updates.isEmpty {
                    caughtUp
                }
                if !blocked.isEmpty || !needs.isEmpty {
                    ModalGroup(title: "Needs You · \(blocked.count + needs.count)") {
                        ModalBox(rows: true) {
                            ForEach(blocked) { session in
                                BlockedRow(session: session, selected: model.noticeSelection == key(session), active: focused)
                                    .id(key(session))
                                    .simultaneousGesture(TapGesture().onEnded { select(key(session)) })
                            }
                            ForEach(needs) { notice in row(notice) }
                        }
                    }
                }
                if !updates.isEmpty {
                    ModalGroup(title: "Updates · \(updates.count)") { ModalBox(rows: true) { ForEach(updates) { notice in row(notice) } } }
                }
                if !later.isEmpty {
                    ModalGroup(title: "Later · \(later.count)") { ModalBox(rows: true) { ForEach(later) { notice in row(notice) } } }
                }
                if !earlier.isEmpty {
                    ModalGroup(title: "Earlier") {
                        ModalBox(rows: true) {
                            ForEach(shownEarlier(earlier)) { notice in row(notice) }
                            if earlier.count > Self.earlierShown {
                                Button(allEarlier ? "Show Fewer" : "Show \(earlier.count - Self.earlierShown) More") { allEarlier.toggle() }
                                    .buttonStyle(.borderless)
                                    .clickable()
                                    .kitType(.callout)
                                    .padding(.leading, Space.sm)
                                    .frame(maxWidth: .infinity, minHeight: Metric.boxRow, alignment: .leading)
                                    .uiTestAnchor("earlier-more")
                            }
                        }
                    }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onAppear { focused = !model.composingReminder }
            .onChange(of: model.composingReminder) { if model.composingReminder { editing = nil } }
            .onKeyPress(.downArrow) { move(1, proxy); return .handled }
            .onKeyPress(.upArrow) { move(-1, proxy); return .handled }
            .onKeyPress(.return) { openSelected(); return .handled }
            .onKeyPress(.delete) {
                guard let notice = selectedNotice else { return .ignored }
                model.removeNotice(notice.id)
                return .handled
            }
            .onKeyPress(characters: .init(charactersIn: "eElL")) { press in
                guard let notice = selectedNotice else { return .ignored }
                if press.characters.lowercased() == "e" { model.setDone(notice.id, !model.isDone(notice)) } else { laterFor = notice.id.uuidString }
                return .handled
            }
            .onCopyCommand {
                guard let text = selectedText else { return [] }
                Pasteboard.copied = text
                return Store.isOverridden ? [] : [NSItemProvider(object: text as NSString)]
            }
        }
    }

    private func row(_ notice: Notice) -> some View {
        Group {
            if editing == notice.id {
                ReminderEditor(notice: notice) { finishEditing() }
            } else {
                NoticeRow(notice: notice, section: model.section(of: notice), selected: model.noticeSelection == notice.id.uuidString,
                          active: focused, edit: { edit(notice) },
                          showLater: Binding(get: { laterFor == notice.id.uuidString }, set: { laterFor = $0 ? notice.id.uuidString : nil }))
                    .simultaneousGesture(TapGesture().onEnded { select(notice.id.uuidString) })
            }
        }
        .id(notice.id.uuidString)
    }

    private func shownEarlier(_ rows: [Notice]) -> [Notice] {
        allEarlier ? rows : Array(rows.prefix(Self.earlierShown))
    }

    private var caughtUp: some View {
        HStack(spacing: Space.md) {
            KitIcon.allReviewed.image.font(.system(size: Metric.sectionTile)).foregroundStyle(Ink.done)
            VStack(alignment: .leading, spacing: Metric.lineGap) {
                Text("All caught up").kitType(.titleStrong)
                Text("Nothing needs you, nothing new since you last looked.").kitType(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
    }

    // MARK: Selection and keys

    private func key(_ session: SessionItem) -> String { "session:\(session.id)" }

    private func select(_ key: String) {
        model.noticeSelection = key
        focused = true
    }

    private func edit(_ notice: Notice) {
        model.composingReminder = false
        model.noticeSelection = notice.id.uuidString
        editing = notice.id
    }

    private func finishEditing() {
        editing = nil
        model.composingReminder = false
        focused = true
    }

    /// Rows the arrows walk, as they show.
    private var order: [String] {
        let earlier = model.notices(in: .earlier)
        return model.blockedSessions.map(key) + [NoticeSection.needsYou, .updates, .later].flatMap { model.notices(in: $0).map(\.id.uuidString) }
            + shownEarlier(earlier).map(\.id.uuidString)
    }

    private var selectedNotice: Notice? {
        guard let id = model.noticeSelection.flatMap(UUID.init(uuidString:)) else { return nil }
        return model.notices.first { $0.id == id }
    }

    private var selectedText: String? {
        if let notice = selectedNotice { return notice.text }
        guard let id = model.noticeSelection, id.hasPrefix("session:"), let session = model.session(String(id.dropFirst(8))) else { return nil }
        return "\(session.name): \(session.reason ?? session.status.title)"
    }

    private func move(_ step: Int, _ proxy: ScrollViewProxy) {
        let rows = order
        guard !rows.isEmpty else { return }
        let index = model.noticeSelection.flatMap { rows.firstIndex(of: $0) } ?? (step > 0 ? -1 : rows.count)
        model.noticeSelection = rows[min(max(index + step, 0), rows.count - 1)]
        proxy.scrollTo(model.noticeSelection)
    }

    private func openSelected() {
        guard let selected = model.noticeSelection else { return }
        if selected.hasPrefix("session:") { return model.open(String(selected.dropFirst(8))) }
        guard let notice = selectedNotice else { return }
        if notice.kind == .reminder && notice.links.isEmpty { edit(notice) } else { model.openNotice(notice) }
    }
}

// MARK: Rows

/// A session that waits on the user: its name, what it asks in full when selected, its tasks, and Focus.
/// It leaves once the session moves on.
private struct BlockedRow: View {
    let session: SessionItem
    let selected: Bool
    let active: Bool
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            NoticeDot(color: session.status.state == .failed ? Ink.failed : Ink.needsYou)
                .frame(height: Metric.boxRow - Space.sm)
            SessionFace(session, size: Metric.faceRow + Space.xs)
            VStack(alignment: .leading, spacing: Metric.lineGap) {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(session.name).kitType(.titleBold).lineLimit(1)
                    Spacer(minLength: Space.sm)
                    Text(AppModel.ago(session.status.since, now: model.now)).kitType(.meta).foregroundStyle(.secondary).fixedSize()
                }
                NoticeBody(text: session.reason ?? session.status.title, full: selected)
                let tasks = model.tasks(of: session.id).filter { $0.status != .done }
                if !tasks.isEmpty {
                    FlowLayout(spacing: Space.xs) { ForEach(tasks) { NoticeChip(route: .task($0.id), notice: nil) } }
                        .padding(.top, Space.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(session.isRunning ? "Focus" : "Resume") { model.open(session.id) }
                .buttonStyle(.glassProminent)
                .tint(Ink.needsYou)
                .clickable()
                .help("Bring its terminal forward to answer it (⌘O)")
        }
        .noticeRowStyle(selected: selected, hovering: hovering, active: active)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.open(session.id) }
        .help("\(session.name): \(session.reason ?? session.status.title)")
        .uiTestAnchor("blocked:\(session.id)")
    }
}

/// One notification, as macOS draws one: who and when, then its text (in full when selected), then what it links.
/// Unread: a dot and a bold name. Its actions show on hover and while selected; the rest is in its menu.
private struct NoticeRow: View {
    let notice: Notice
    let section: NoticeSection
    let selected: Bool
    let active: Bool
    let edit: () -> Void
    @Binding var showLater: Bool
    @Environment(AppModel.self) private var model
    @State private var hovering = false
    @State private var changingTime = false

    private var done: Bool { model.isDone(notice) }
    private var reminder: Bool { notice.kind == .reminder }

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            NoticeDot(color: done || section == .later ? nil : notice.level == .important ? Ink.needsYou : Ink.accent)
                .frame(height: Metric.boxRow - Space.sm)
            avatar
            VStack(alignment: .leading, spacing: Metric.lineGap) {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    who
                    if notice.count > 1 {
                        Text("\(notice.count) updates").kitType(.meta).foregroundStyle(.secondary)
                            .padding(.horizontal, Space.xs + 2).background(Ink.chipFill, in: Capsule()).fixedSize()
                    }
                    Spacer(minLength: Space.sm)
                    time
                }
                NoticeBody(text: notice.text, full: selected, struck: reminder && done)
                let links = notice.links.compactMap(ModalRoute.init(noticeKey:)).filter { $0 != source }
                if !links.isEmpty {
                    FlowLayout(spacing: Space.xs) { ForEach(links, id: \.self) { NoticeChip(route: $0, notice: notice) } }
                        .padding(.top, Space.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .noticeRowStyle(selected: selected, hovering: hovering, active: active)
        .overlay(alignment: .topTrailing) {
            if hovering || selected || showLater || changingTime {
                actions.padding(.top, Space.xs).padding(.trailing, Space.xs)
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { if reminder && notice.links.isEmpty { edit() } else { model.openNotice(notice) } }
        .contextMenu { menu }
        .help(notice.text)
        .uiTestAnchor("notice:\(notice.id.uuidString)")
    }

    private var source: ModalRoute? {
        switch notice.kind {
        case .session: notice.source.map(ModalRoute.session)
        case .github: notice.source.map(ModalRoute.github)
        case .reminder: nil
        }
    }

    @ViewBuilder
    private var avatar: some View {
        Group {
            switch notice.kind {
            case .session:
                if let session = model.session(notice.source) { SessionFace(session, size: Metric.faceRow + Space.xs) }
                else { KindTile(icon: .bell, tint: Ink.draftTile) }
            case .github:
                if let item = model.githubItem(notice.source) { GitHubStateIcon.tile(item) } else { KindTile(icon: .pullRequest, tint: Ink.done) }
            case .reminder: KindTile(icon: .reminder, tint: notice.level == .important ? Ink.needsYou : Ink.draftTile)
            }
        }
        .frame(width: Metric.faceRow + Space.xs)
    }

    /// The session or the PR, bold while unread: a click opens it.
    @ViewBuilder
    private var who: some View {
        let name: String = switch notice.kind {
        case .session: model.session(notice.source)?.name ?? "Claude"
        case .github: model.githubItem(notice.source)?.reference ?? notice.source.flatMap(GitHubThreads.reference) ?? "GitHub"
        case .reminder: notice.level == .important ? "Reminder · Important" : "Reminder"
        }
        let label = Text(name).kitType(done ? .title : .titleBold).lineLimit(1)
        if let source {
            Button { model.markRead(notice.id); model.open(source, push: true) } label: { label }
                .buttonStyle(.plain)
                .clickable()
                .help("Open \(name)")
        } else {
            label
        }
    }

    /// When it came; in Later, when it comes back. The When pickers open from here, so they stay while the
    /// pointer leaves the row.
    private var time: some View {
        Group {
            if section == .later, let due = notice.dueAt {
                Label(ReminderTime.describe(due, now: model.now), icon: .later)
            } else {
                Text(AppModel.ago(notice.at, now: model.now))
            }
        }
        .kitType(.meta)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
        .popover(isPresented: $showLater, arrowEdge: .bottom) {
            WhenPicker(now: model.now) { date in
                showLater = false
                model.snooze(notice.id, until: date)
            }
        }
        .popover(isPresented: $changingTime, arrowEdge: .bottom) {
            WhenPicker(now: model.now, current: notice.dueAt) { date in
                changingTime = false
                if reminder { model.editReminder(notice.id, text: notice.text, due: date, level: notice.level) } else { model.snooze(notice.id, until: date) }
            }
        }
    }

    /// Floats over the row's trailing end on hover and while selected.
    private var actions: some View {
        HStack(spacing: 0) {
            if reminder {
                Button("Edit", icon: .edit, action: edit)
                    .frame(width: Metric.rowAction, height: Metric.rowAction)
                    .help("Edit the reminder (Return)")
                    .uiTestAnchor("edit:\(notice.id.uuidString)")
            }
            if section == .later, let due = notice.dueAt {
                Button { changingTime = true } label: { Label(ReminderTime.describe(due, now: model.now), icon: .later).labelStyle(.titleAndIcon) }
                    .kitType(.meta)
                    .padding(.horizontal, Space.xs)
                    .frame(height: Metric.rowAction)
                    .help("Change when it comes back")
                    .uiTestAnchor("due:\(notice.id.uuidString)")
            } else {
                Button("Later", icon: .later) { showLater = true }
                    .frame(width: Metric.rowAction, height: Metric.rowAction)
                    .help("Put it away until later (L)")
                    .uiTestAnchor("later:\(notice.id.uuidString)")
            }
            Button(doneTitle, icon: doneIcon) { model.setDone(notice.id, !done) }
                .foregroundStyle(done && reminder ? AnyShapeStyle(Ink.done) : AnyShapeStyle(.secondary))
                .frame(width: Metric.rowAction, height: Metric.rowAction)
                .help("\(doneTitle) (E)")
                .uiTestAnchor("read:\(notice.id.uuidString)")
            Menu { menu } label: { Label("More", icon: .more) }
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: Metric.rowAction, height: Metric.rowAction)
                .help("More")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Space.xs)
        .surface(radius: Radius.control, lifted: true)
        .clickable()
    }

    private var doneTitle: String {
        reminder ? (done ? "Mark as Not Done" : "Done") : (done ? "Mark as Unread" : "Mark as Read")
    }

    private var doneIcon: KitIcon {
        reminder ? (done ? .checkPassed : .markRead) : (done ? .markUnread : .markRead)
    }

    @ViewBuilder
    private var menu: some View {
        if source != nil || !notice.links.isEmpty { Button("Open") { model.openNotice(notice) } }
        if reminder { Button("Edit…", action: edit) }
        Button(doneTitle) { model.setDone(notice.id, !done) }
        Divider()
        if section == .later {
            Button("Bring Back Now") { model.bringBack(notice.id) }
        } else {
            Menu("Later") {
                ForEach(ReminderTime.Preset.available(now: model.now), id: \.self) { preset in
                    let date = ReminderTime.date(preset, now: model.now)
                    Button("\(preset.title), \(ReminderTime.brief(date, now: model.now))") { model.snooze(notice.id, until: date) }
                }
                Divider()
                Button("Pick a Time…") { showLater = true }
            }
        }
        Button("Copy Text") { Pasteboard.copy(notice.text) }
        Divider()
        Button("Delete") { model.removeNotice(notice.id) }
    }
}

/// A row's text: two lines at rest, all of it and selectable once the row is selected.
private struct NoticeBody: View {
    let text: String
    let full: Bool
    var struck = false

    var body: some View {
        let line = Text(text)
            .kitType(.title)
            .foregroundStyle(struck ? .secondary : .primary)
            .strikethrough(struck)
            .lineLimit(full ? nil : 2)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        if full { line.textSelection(.enabled) } else { line }
    }
}

/// What a notification links: a click opens it over the center. It reads a notification, not a reminder.
private struct NoticeChip: View {
    let route: ModalRoute
    let notice: Notice?
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            if let notice, notice.kind != .reminder { model.markRead(notice.id) }
            model.open(route, push: true)
        } label: {
            OutputChip(route: route, plain: true)
        }
        .buttonStyle(.plain)
        .clickable()
        .help("Open \(model.title(of: route))")
        .uiTestAnchor("notice-chip:\(notice?.id.uuidString ?? "blocked"):\(route.selectionKey)")
    }
}

/// A reminder being written or changed, in a row's place: its words, when (the When picker), Important.
/// Return saves, Escape cancels.
struct ReminderEditor: View {
    let notice: Notice?
    let finish: () -> Void
    @Environment(AppModel.self) private var model
    @State private var text: String
    /// Nil: a reminder that came back stays where it is.
    @State private var due: Date?
    @State private var important: Bool
    @State private var picking = false
    @FocusState private var typing: Bool

    init(notice: Notice?, finish: @escaping () -> Void) {
        self.notice = notice
        self.finish = finish
        _text = State(initialValue: notice?.text ?? "")
        _due = State(initialValue: notice == nil ? ReminderTime.date(.tomorrow) : notice?.dueAt)
        _important = State(initialValue: notice.map { $0.level == .important } ?? true)
    }

    var body: some View {
        HStack(alignment: .center, spacing: Space.sm) {
            KindTile(icon: .reminder, tint: important ? Ink.needsYou : Ink.draftTile)
                .frame(width: Metric.faceRow + Space.xs)
            TextField("Remind me to…", text: $text)
                .textFieldStyle(.plain)
                .kitType(.title)
                .focused($typing)
                .onSubmit(save)
                .uiTestAnchor("reminder-text")
            Button { picking = true } label: {
                Label(due.map { ReminderTime.describe($0, now: model.now) } ?? "Now", icon: .later)
            }
            .buttonStyle(.bordered)
            .clickable()
            .fixedSize()
            .help("When it comes back")
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                WhenPicker(now: model.now, current: due) { date in
                    due = date
                    picking = false
                    typing = true
                }
            }
            .uiTestAnchor("reminder-when")
            Toggle(isOn: $important) { Label("Important", icon: important ? .importantOn : .important) }
                .toggleStyle(.button)
                .tint(Ink.needsYou)
                .clickable()
                .fixedSize()
                .help(important ? "Important: it needs you when it comes back, with a banner" : "An update when it comes back")
                .uiTestAnchor("reminder-important")
            Button("Cancel", action: finish)
                .keyboardShortcut(.cancelAction)
                .clickable()
            Button(notice == nil ? "Add" : "Save", action: save)
                .buttonStyle(.glassProminent)
                .clickable()
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .uiTestAnchor("reminder-add")
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .frame(minHeight: Metric.boxRow + Space.sm)
        .background(Ink.hoverFill, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .onAppear { typing = true }
    }

    private func save() {
        let what = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !what.isEmpty else { return }
        let level: Notice.Level = important ? .important : .update
        if let notice {
            model.editReminder(notice.id, text: what, due: due, level: level)
        } else {
            model.remind(what, at: due ?? .now, level: level)
        }
        finish()
    }
}

private extension View {
    /// A row in the center: its padding, then hover and selection as the other lists draw them.
    func noticeRowStyle(selected: Bool, hovering: Bool, active: Bool) -> some View {
        padding(.horizontal, Space.sm)
            .padding(.vertical, Space.sm)
            .frame(minHeight: Metric.boxRow + Space.sm)
            .rowHighlight(selected: selected, hovering: hovering, active: active)
            .contentShape(Rectangle())
    }
}

extension AppModel {
    /// Return or a double-click on a row: what it links first, over the center. A notification is read; a reminder
    /// waits to be completed.
    func openNotice(_ notice: Notice) {
        if notice.kind != .reminder { markRead(notice.id) }
        let first = notice.links.compactMap(ModalRoute.init(noticeKey:)).first
        switch (notice.kind, first) {
        case (_, let route?): open(route, push: true)
        case (.session, nil): if let id = notice.source, session(id) != nil { open(.session(id), push: true) }
        case (.github, nil): if let url = notice.source { open(.github(url), push: true) }
        case (.reminder, nil): break
        }
    }

    /// "just now", "11m ago", "2h ago": when a row happened, as the PR rows say it.
    static func ago(_ date: Date, now: Date) -> String {
        now.timeIntervalSince(date) < 60 ? "just now" : "\(Elapsed.short(from: date, to: now)) ago"
    }

    /// The sky over a modal: warm while what it shows needs the user.
    func mood(of route: ModalRoute?) -> SkyMood {
        switch route {
        case .notifications: importantCount > 0 ? .needsYou : .calm
        case .session(let id): session(id)?.status.needsYou == true ? .needsYou : .calm
        default: .calm
        }
    }
}
