import AppKit
import HQKit
import SwiftUI

// Every item's menu, one builder per kind: its right-click menu and its window's ⋯ (DESIGN.md §18 Context menus).
// Four groups at most: create or go · set · view, remind, copy · remove.

/// A picker a menu item opens: the menu's host shows it in a popover, else the outline under the task's row.
enum MenuPick: Identifiable {
    case link(Int)
    case hold(Int, HoldPicker.Kind)
    case newProject([Int])
    case linkToTask(ModalRoute)

    var id: String {
        switch self {
        case .link(let id): "link:\(id)"
        case .hold(let id, let kind): "hold:\(id):\(kind)"
        case .newProject(let ids): "project:\(ids)"
        case .linkToTask(let route): "task:\(route.selectionKey)"
        }
    }
}

/// Shows a menu's picker; one host's stays the same for its views.
struct MenuPicker: Equatable {
    let show: (MenuPick) -> Void

    static func == (_: MenuPicker, _: MenuPicker) -> Bool { true }
}

extension EnvironmentValues {
    /// Where a menu's pickers open: set by the view that hosts the menu.
    @Entry var menuPick: MenuPicker?
}

extension View {
    /// Hosts the pickers its menus open, in a popover under it.
    func menuPicks() -> some View { modifier(MenuPicks()) }
}

private struct MenuPicks: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var pick: MenuPick?

    func body(content: Content) -> some View {
        content
            .environment(\.menuPick, MenuPicker { pick = $0 })
            .popover(item: $pick, arrowEdge: .bottom) { shown in
                Group {
                    switch shown {
                    case .link(let id): LinkPicker(task: id) { pick = nil }
                    case .hold(let id, let kind): HoldPicker(task: id, kind: kind) { pick = nil }
                    case .newProject(let ids):
                        NewProjectField { name in
                            pick = nil
                            if let name { for id in ids { model.setProject(id, name) } }
                        }
                    case .linkToTask(let route): TaskFinder { model.link(route, to: $0); pick = nil }
                    }
                }
                .environment(model)
            }
    }
}

/// What every builder shares: its picker, and whether it shows in its item's own window.
private struct MenuContext {
    let model: AppModel
    let menuPick: MenuPicker?
    let modalRoute: ModalRoute?

    func pick(_ pick: MenuPick) {
        if let menuPick { menuPick.show(pick) } else { model.showPick(pick) }
    }

    /// The menu is its item's window's ⋯: Open would open what is open.
    func inOwnWindow(_ route: ModalRoute) -> Bool { modalRoute == route && model.modal == route }
}

private struct ContextReader<Content: View>: View {
    @ViewBuilder let content: (MenuContext) -> Content
    @Environment(AppModel.self) private var model
    @Environment(\.menuPick) private var menuPick
    @Environment(\.modalRoute) private var modalRoute

    var body: some View { content(MenuContext(model: model, menuPick: menuPick, modalRoute: modalRoute)) }
}

/// A choice in a menu, checked when it is the current one.
private func choice(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
    Toggle(title, isOn: Binding(get: { on }, set: { _ in action() }))
}

// MARK: Tasks

/// A task's menu, or what applies to several selected rows.
struct TaskMenu: View {
    let ids: [Int]
    @Environment(AppModel.self) private var model

    var body: some View {
        ContextReader { context in
            if ids.count > 1 {
                several(context)
            } else if let id = ids.first, let task = model.task(id) {
                one(task, context)
            }
        }
    }

    @ViewBuilder
    private func one(_ task: TaskItem, _ context: MenuContext) -> some View {
        let id = task.id
        let own = context.inOwnWindow(.task(id))
        let tree = model.taskTree
        let top = tree.parent(of: id) == nil
        let hasSubtasks = !tree.children(of: id).isEmpty
        if !own { Button("Open") { model.open(.task(id)) } }
        if let outside = model.outsideTitle(.task(id)) { Button(outside) { model.openOutside(.task(id)) } }
        Button("Start Session…") { model.beginStart(task: id, push: own) }
        Button("Add Subtask") { if let added = model.addSubtask(to: id) { model.outlineFocus = .title(added.id, by: 0) } }
        Divider()
        statusMenu([task])
        projectMenu([task], context)
        Menu("Links") {
            Button("Link…") { context.pick(.link(id)) }
            Divider()
            holdMenu("Blocked By", task.blockedBy, task, .blockedBy, context)
            holdMenu("After", task.after, task, .after, context)
            Divider()
            if task.blocked {
                // In its window, the Blocked row's reason takes the keyboard.
                Button("Edit Reason…") {
                    if context.inOwnWindow(.task(id)) { model.reasonFocus = id } else { context.pick(.hold(id, .block)) }
                }
                Button("Unblock") { model.unblock(id) }
            } else {
                Button("Block…") { context.pick(.hold(id, .block)) }.disabled(task.status == .done)
            }
        }
        Divider()
        if !own {
            Menu("Show") {
                choice("Description", model.descriptionShownInOutline(id)) { model.toggleDescription(id) }
                if hasSubtasks {
                    let shown = model.fold[id] != .hidden
                    choice("Subtasks", shown) { model.foldTasks([id], shown ? .hidden : .all) }
                    if top { choice("Only Blocked and Doing", model.storyFilter.contains(id)) { model.filterStory(id) } }
                }
            }
        }
        Button("Remind Me…") { model.beginReminder(about: .task(id)) }
        Button("Copy") { model.copy([.task(id)]) }
        Divider()
        if top { Button("Archive") { model.archive([id]) } }
        Button("Delete") { model.deleteTasks([id]) }
    }

    /// Blocked By ▸ or After ▸: the tasks it waits on, checked (a click takes one off), then Add….
    private func holdMenu(_ title: String, _ others: [Int], _ task: TaskItem, _ kind: HoldPicker.Kind, _ context: MenuContext) -> some View {
        Menu(title) {
            ForEach(others, id: \.self) { other in
                choice("T-\(other) \(model.task(other)?.title ?? "")", true) { model.removeLink(task.id, kind == .after ? .after : .blockedBy, other) }
            }
            if !others.isEmpty { Divider() }
            Button("Add…") { context.pick(.hold(task.id, kind)) }.disabled(task.status == .done)
        }
    }

    /// Several selected rows: what applies to all of them.
    @ViewBuilder
    private func several(_ context: MenuContext) -> some View {
        let tasks = ids.compactMap { model.task($0) }
        let ids = tasks.map(\.id)
        statusMenu(tasks)
        projectMenu(tasks, context)
        Divider()
        Menu("Show") {
            choice("Descriptions", ids.allSatisfy(model.descriptionShownInOutline)) { model.toggleDescriptions(ids) }
            let parents = ids.filter { !model.taskTree.children(of: $0).isEmpty }
            if !parents.isEmpty {
                let shown = parents.allSatisfy { model.fold[$0] != .hidden }
                choice("Subtasks", shown) { model.foldTasks(parents, shown ? .hidden : .all) }
            }
        }
        Button("Copy") { model.copy(ids.map { .task($0) }) }
        Divider()
        if ids.allSatisfy({ model.taskTree.parent(of: $0) == nil }) { Button("Archive \(ids.count)") { model.archive(ids) } }
        Button("Delete \(ids.count) Tasks") { model.deleteTasks(ids) }
    }

    private func statusMenu(_ tasks: [TaskItem]) -> some View {
        Menu("Status") {
            ForEach(TaskStatus.allCases) { status in
                choice(status.title, tasks.allSatisfy { $0.status == status }) { for task in tasks { model.setStatus(task.id, status) } }
            }
        }
    }

    private func projectMenu(_ tasks: [TaskItem], _ context: MenuContext) -> some View {
        Menu("Project") {
            choice("None", tasks.allSatisfy { $0.project == nil }) { for task in tasks { model.setProject(task.id, nil) } }
            ForEach(model.projects, id: \.self) { name in
                choice(name, tasks.allSatisfy { $0.project == name }) { for task in tasks { model.setProject(task.id, name) } }
            }
            Divider()
            Button("New Project…") { context.pick(.newProject(tasks.map(\.id))) }
        }
    }
}

// MARK: Sessions

/// A session's menu: a card's or a team row's context menu, a click on its face anywhere, its window's ⋯ (DESIGN.md §5, §10).
struct SessionMenu: View {
    let session: SessionItem
    /// From a task's faces: another session on that task.
    var task: Int?
    /// From a PR's face: another session on that PR.
    var pullRequest: GitHubItem?
    @Environment(AppModel.self) private var model

    var body: some View {
        let tree = model.sessionTree
        let top = tree.parent(of: session.id) == nil
        let team = model.team(of: session.id, in: tree)
        Button(session.isRunning ? "Focus" : "Resume") { model.open(session.id) }
        if session.isRunning {
            Button("Restart Session") { model.restartSession(session.id) }
                .disabled(model.promptBlocked(session) != nil)
                .help(model.promptBlocked(session) ?? "Quits its Claude and resumes it in the same tab, its conversation kept: it picks up a newly installed Claude Code")
            Button("Clear Conversation") { model.clearConversation(session.id) }
                .disabled(model.promptBlocked(session) != nil)
                .help(model.promptBlocked(session) ?? "Types /clear: it starts afresh on its card; the conversation before goes to Closed Sessions")
        }
        if session.startTrouble == .didntStart {
            Button("Start Again") { model.startAgain(session.id) }
        }
        Menu("Start") {
            Button("Child Session…") { model.beginStart(parent: session.id) }
                .disabled(!session.isRunning)
            Button("From Its History…") { model.beginStart(history: session.id) }
            if let task, let item = model.task(task) {
                Button("Another Session on \(item.key)…") { model.beginStart(task: task) }
            }
            if let pullRequest {
                Button("Another Session on \(pullRequest.reference)…") { model.beginStart(pullRequest: pullRequest) }
            }
        }
        Divider()
        if session.isRunning { RunMenus(session: session) }
        Menu("Team") {
            if top && !team.isEmpty {
                Button(model.openTeam == session.id ? "Hide Its Sessions" : "Show Its Sessions") { model.toggleTeam(session.id) }
            }
            let choices = Set(model.moveUnderChoices(for: session.id))
            let rows = model.sessionRows.filter { choices.contains($0.session.id) }
            Menu("Move Under") {
                ForEach(rows, id: \.session.id) { row in
                    Button { model.setParent(session.id, to: row.session.id) } label: {
                        Label { Text(MenuAction.short(row.session.name)) } icon: { Image(nsImage: MenuBarMenu.face(row.session, depth: row.depth)) }
                    }
                }
            }
            .disabled(rows.isEmpty)
            Button("Make Root") { model.setParent(session.id, to: nil) }
                .disabled(top)
        }
        Divider()
        Menu("Copy") {
            Button("Copy") { model.copy([.session(session.id)]) }
            Button("Copy Resume Command") { Pasteboard.copy(session.resumeCommand) }
            Button("Copy Session ID") { Pasteboard.copy(session.id) }
        }
        let closes = (session.isRunning && session.tty != nil) || session.startTrouble != nil
        let teamOpen = top && !team.isEmpty ? model.openSessions(ofTeam: session.id).count : 0
        if closes || teamOpen > 0 { Divider() }
        if closes {
            Button("Close Session") { model.closeSession(session.id) }
                .help(session.startTrouble == .notReporting ? "Removes the card; its Claude keeps running in its tab, where /exit quits it" : "")
        }
        if teamOpen > 0 {
            Button("Close Team (\(teamOpen) session\(teamOpen == 1 ? "" : "s"))…") { model.closeTeam(session.id) }
        }
    }
}

// MARK: Pull requests

/// A PR's or an issue's menu: its row in Pull Requests and its window's ⋯.
struct PullRequestMenu: View {
    let item: GitHubItem
    @Environment(AppModel.self) private var model

    var body: some View {
        ContextReader { context in
            let route = ModalRoute.github(item.url)
            if !context.inOwnWindow(route) { Button("Open") { model.open(route) } }
            Button("Open on GitHub") { model.openOutside(route) }
            Button("Start Review Session…") { model.beginStart(pullRequest: item, push: context.inOwnWindow(route)) }
            if model.inNeedsYou(item) {
                Button("Dismiss") { model.dismissReview(item.url) }
            } else if model.isDismissedReview(item) {
                Button("Bring Back") { model.bringBackReview(item.url) }
            }
            Divider()
            Button("Link to Task…") { context.pick(.linkToTask(route)) }
            Divider()
            Button("Remind Me…") { model.beginReminder(about: route) }
            CopyMenu(route: route)
        }
    }
}

/// A review request's menu in Needs You.
struct ReviewMenu: View {
    let item: GitHubItem
    /// When it comes back, while put away.
    let later: Date?
    /// Put away until a time picked in the card’s picker.
    let pickTime: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        ContextReader { context in
            let route = ModalRoute.github(item.url)
            Button("Review") { model.open(route, push: true) }
            Button("Open on GitHub") { model.openOutside(route) }
            Button("Start Review Session…") { model.beginStart(pullRequest: item, push: true) }
            Button("Dismiss") { model.dismissReview(item.url) }
            Divider()
            Button("Link to Task…") { context.pick(.linkToTask(route)) }
            Divider()
            if later != nil {
                Button("Bring Back Now") { model.putReviewLater(item.url, until: nil) }
            } else {
                LaterMenu(pickTime: pickTime) { model.putReviewLater(item.url, until: $0) }
            }
            CopyMenu(route: route)
        }
    }
}

/// Later ▸: the presets with their time, then Pick a Time….
struct LaterMenu: View {
    let pickTime: () -> Void
    let set: (Date) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu("Later") {
            ForEach(ReminderTime.Preset.available(now: model.now), id: \.self) { preset in
                let date = ReminderTime.date(preset, now: model.now)
                Button("\(preset.title), \(ReminderTime.brief(date, now: model.now))") { set(date) }
            }
            Divider()
            Button("Pick a Time…", action: pickTime)
        }
    }
}

/// Copy, plain, or Copy ▸ with Copy Link when the item has a link.
private struct CopyMenu: View {
    let route: ModalRoute
    @Environment(AppModel.self) private var model

    var body: some View {
        if let link = model.link(of: route) ?? route.address {
            Menu("Copy") {
                Button("Copy") { model.copy([route]) }
                Button("Copy Link") { Pasteboard.copy(link) }
            }
        } else {
            Button("Copy") { model.copy([route]) }
        }
    }
}

// MARK: Files and artifacts

/// A file's or an artifact's menu: its row in Files and its window's ⋯.
struct OutputMenu: View {
    let route: ModalRoute
    @Environment(AppModel.self) private var model

    var body: some View {
        ContextReader { context in
            let pinned = model.listed(route).pinned
            if !context.inOwnWindow(route) { Button("Open") { model.open(route) } }
            if let outside = model.outsideTitle(route) { Button(outside) { model.openOutside(route) } }
            Divider()
            Button("Link to Task…") { context.pick(.linkToTask(route)) }
            Button(pinned ? "Unpin" : "Pin") { model.setPinned(route, !pinned) }
            Divider()
            Button("Remind Me…") { model.beginReminder(about: route) }
            CopyMenu(route: route)
            Divider()
            switch route {
            case .file(let id): Button("Delete") { model.deleteFile(id) }
            case .artifact(let url): Button("Remove from HQ") { model.removeArtifact(url) }
            default: EmptyView()
            }
        }
    }
}

/// A task's link, on its chip and its row in the task's window: open it, its own actions, unlink it, delete it.
struct LinkMenu: View {
    let route: ModalRoute
    let task: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        let output: Bool = switch route { case .file, .artifact, .github: true; default: false }
        let github: GitHubItem? = if case .github(let url) = route { model.githubItem(url) } else { nil }
        switch route {
        case .web: Button("Open in Browser") { model.open(route) }
        case .slack: Button("Open in Slack") { model.open(route) }
        default:
            Button("Open") { model.open(route, push: model.modal != nil) }
            if let outside = model.outsideTitle(route) { Button(outside) { model.openOutside(route) } }
        }
        if let github {
            Button("Start Review Session…") { model.beginStart(pullRequest: github, push: model.modal != nil) }
            if model.inNeedsYou(github) {
                Button("Dismiss") { model.dismissReview(github.url) }
            } else if model.isDismissedReview(github) {
                Button("Bring Back") { model.bringBackReview(github.url) }
            }
        }
        Divider()
        if output { Button("Remind Me…") { model.beginReminder(about: route) } }
        CopyMenu(route: route)
        let linked = model.isLinked(route, to: task)
        let removable: Bool = switch route { case .file, .artifact: true; default: false }
        if linked || removable { Divider() }
        if linked { Button("Unlink from \(model.task(task)?.key ?? "the Task")") { model.unlink(route, from: task) } }
        switch route {
        case .file(let id): Button("Delete") { model.deleteFile(id) }
        case .artifact(let url): Button("Remove from HQ") { model.removeArtifact(url) }
        default: EmptyView()
        }
    }
}

// MARK: Archive and roles

/// An archived story's or task's menu: its card in the Archive and its window's ⋯.
struct ArchivedMenu: View {
    let id: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        ContextReader { context in
            let story = model.archiveShown?.index.entry(id)?.root ?? id
            if !context.inOwnWindow(.archivedTask(id)) { Button("Open") { model.open(.archivedTask(id), push: true) } }
            Button("Open in Obsidian") { model.openInObsidian(model.vault?.archivedURL(id).path) }
            Button(story == id ? "Unarchive" : "Unarchive T-\(story)") { model.unarchiveFromWindow(story) }
            Divider()
            Button("Copy") { model.copy([.archivedTask(id)]) }
            Divider()
            Button("Delete") { model.deleteArchived(story) }
        }
    }
}

/// A role's menu: its row and the Roles window's ⋯.
struct RoleMenu: View {
    let role: RoleItem
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Edit") { model.pickRole(role.name); model.beginRoleEdit(.text) }
        Button("Open in Obsidian") { model.openInObsidian(role.path) }.disabled(role.path == nil)
        Divider()
        Button("Rename") { model.pickRole(role.name); model.beginRoleEdit(.name) }
        RoleColorMenu(role: role)
        Divider()
        Button("Copy") { Pasteboard.copy(model.line(ofRole: role)) }
        Divider()
        if model.isChangedDefault(role) {
            Button("Restore Default") { model.restoreDefault(role.name) }
        }
        Button("Delete") { model.deleteRole(role.name, picking: role.name == model.pickedRole?.name) }
    }
}

/// Color ▸ for a role, the current one checked: its row's and its chip's menu.
struct RoleColorMenu: View {
    let role: RoleItem
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu("Color") {
            ForEach(LabelColor.allCases) { color in
                Toggle(isOn: Binding(get: { role.color == color }, set: { _ in model.changeRole(role.name, "Change Color") { $0.color = color } })) {
                    Label { Text(color.title) } icon: { Image(nsImage: color.swatch) }
                }
            }
        }
    }
}

// MARK: Actions the menus share

extension AppModel {
    /// A menu's picker with no host for it: under the task's row in the outline that shows it.
    func showPick(_ pick: MenuPick) {
        switch pick {
        case .link(let id): showLinkPicker(id)
        case .hold(let id, let kind): showHoldPicker(id, kind)
        case .newProject(let ids): showNewProject(ids)
        case .linkToTask: break
        }
    }

    /// The PR is in Needs You: it waits for the user's review, not dismissed nor put away for later.
    func inNeedsYou(_ item: GitHubItem) -> Bool { waitingReviews.contains { $0.url == item.url } }
}
