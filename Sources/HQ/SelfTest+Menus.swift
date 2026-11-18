import AppKit
import HQKit
import SwiftUI

/// Every item's menu in the plan's order (T-540, DESIGN.md §18 Context menus): a sibling that drifts fails.
extension SelfTest {
    static func menuChecks(_ model: AppModel) {
        let tree = model.taskTree
        let open = model.tasks.filter { $0.status != .done && !$0.blocked }
        if let story = open.first(where: { tree.parent(of: $0.id) == nil && !tree.children(of: $0.id).isEmpty }) {
            menu("a task's menu", TaskMenu(ids: [story.id]), model, ["Open", "Start Session…", "Add Subtask", "—", "Status ▸", "Project ▸",
                 "Links ▸", "—", "Show ▸", "Remind Me…", "Copy", "—", "Archive", "Delete"])
            menu("its Show menu", TaskMenu(ids: [story.id]), model, ["Description", "Subtasks", "Only Blocked and Doing"], in: "Show")
            menu("its Links menu", TaskMenu(ids: [story.id]), model, ["Link…", "—", "Blocked By ▸", "After ▸", "—", "Block…"], in: "Links")
        } else {
            check("the seed has an open story with subtasks", false)
        }
        if let subtask = open.first(where: { tree.parent(of: $0.id) != nil }) {
            menu("a subtask's menu: no Archive", TaskMenu(ids: [subtask.id]), model, ["Open", "Start Session…", "Add Subtask", "—", "Status ▸",
                 "Project ▸", "Links ▸", "—", "Show ▸", "Remind Me…", "Copy", "—", "Delete"])
        }
        let tops = open.filter { tree.parent(of: $0.id) == nil }.prefix(2).map(\.id)
        if tops.count == 2 {
            menu("several tasks' menu", TaskMenu(ids: tops), model, ["Status ▸", "Project ▸", "—", "Show ▸", "Copy", "—", "Archive 2", "Delete 2 Tasks"])
        }
        if let session = model.gridRoots.first(where: { $0.isRunning && $0.tty != nil && $0.startTrouble == nil && model.team(of: $0.id).isEmpty }) {
            menu("a running session's menu", SessionMenu(session: session), model, ["Focus", "Restart Session", "Start ▸", "—", "Model ▸",
                 "Effort ▸", "Team ▸", "—", "Copy ▸", "—", "Close Session"])
            menu("its Copy menu", SessionMenu(session: session), model, ["Copy", "Copy Resume Command", "Copy Session ID"], in: "Copy")
        } else {
            check("the seed has a running session alone on its card", false)
        }
        if let closed = model.sessions.first(where: { !$0.isRunning && $0.startTrouble == nil && model.sessionTree.parent(of: $0.id) == nil }) {
            menu("a closed session's menu", SessionMenu(session: closed), model, ["Resume", "Start ▸", "—", "Team ▸", "—", "Copy ▸"])
        }
        if let item = model.github?.items.first(where: { $0.kind == .pullRequest && !model.inNeedsYou($0) }) {
            menu("a PR's menu", PullRequestMenu(item: item), model, ["Open", "Open on GitHub", "Start Review Session…", "—", "Link to Task…", "—",
                 "Remind Me…", "Copy ▸"])
        }
        if let review = model.waitingReviews.first {
            menu("a PR's menu in Needs You: Dismiss", PullRequestMenu(item: review), model, ["Open", "Open on GitHub", "Start Review Session…",
                 "Dismiss", "—", "Link to Task…", "—", "Remind Me…", "Copy ▸"])
            menu("a review request's menu", ReviewMenu(item: review, later: nil) {}, model, ["Review", "Open on GitHub", "Start Review Session…",
                 "Dismiss", "—", "Link to Task…", "—", "Later ▸", "Copy ▸"])
            menu("a review put away", ReviewMenu(item: review, later: .now) {}, model, ["Review", "Open on GitHub", "Start Review Session…",
                 "Dismiss", "—", "Link to Task…", "—", "Bring Back Now", "Copy ▸"])
        } else {
            check("the seed has a review that waits", false)
        }
        if let file = model.files.first(where: { $0.path != nil }) {
            let pin = model.listed(.file(file.id)).pinned ? "Unpin" : "Pin"
            menu("a file's menu", OutputMenu(route: .file(file.id)), model, ["Open", "Open in Obsidian", "—", "Link to Task…", pin, "—",
                 "Remind Me…", "Copy", "—", "Delete"])
            if let task = file.tasks.first {
                menu("a file's chip on its task", LinkMenu(route: .file(file.id), task: task), model, ["Open", "Open in Obsidian", "—",
                     "Remind Me…", "Copy", "—", "Unlink from T-\(task)", "Delete"])
            }
        }
        if let artifact = model.artifacts.first {
            let pin = model.listed(.artifact(artifact.id)).pinned ? "Unpin" : "Pin"
            menu("an artifact's menu", OutputMenu(route: .artifact(artifact.id)), model, ["Open", "Open in Browser", "—", "Link to Task…", pin,
                 "—", "Remind Me…", "Copy ▸", "—", "Remove from HQ"])
        }
        if let role = model.roles.first(where: { !model.isChangedDefault($0) }) {
            menu("a role's menu", RoleMenu(role: role), model, ["Edit", "Open in Obsidian", "—", "Rename", "Color ▸", "—", "Copy", "—", "Delete"])
        }
    }

    /// Its titles, a separator as "—" and a submenu as "Title ▸"; `in` reads that submenu's.
    private static func menu(_ name: String, _ view: some View, _ model: AppModel, _ expected: [String], in submenu: String? = nil) {
        let menu = NSHostingMenu(rootView: view.environment(model))
        menu.update()
        let shown = submenu.map { title in menu.items.first { $0.title == title }?.submenu ?? NSMenu() } ?? menu
        shown.update()
        let titles = shown.items.filter { !$0.isHidden }.map { $0.isSeparatorItem ? "—" : $0.hasSubmenu ? "\($0.title) ▸" : $0.title }
        check("\(name) in order", titles == expected, titles.joined(separator: " | "))
    }
}
