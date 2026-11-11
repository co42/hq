import AppKit
import HQKit
import SwiftUI

/// Teams and roles in the forms (T-408, T-415, T-411): Start a Session's Role, Parent and History pop-ups and what each
/// entry point fills in; the Roles modal (pick, ↑ ↓, name, line and text in place, ⌘E, Restore Default, Delete with Undo,
/// New Role, Used by, Copy); the session's modal with its team; a team in Closed Sessions.
extension UITest {
    static func rolesAndForms(_ model: AppModel, _ ui: Driver) async {
        await startForm(model, ui)
        await scenario(model, ui)
        await rolesModal(model, ui)
        await scenario(model, ui)
        await sessionTeam(model, ui)
        await scenario(model, ui)
        await closedTeam(model, ui)
    }

    /// A Leader with two Workers, on top of the seed: two running sessions of the seed under a third.
    private static func makeTeam(_ model: AppModel, _ ui: Driver) async -> (lead: SessionItem, worker: SessionItem, helper: SessionItem)? {
        if model.roles.isEmpty { model.roles = RoleItem.defaults }
        let running = model.gridRoots.filter { $0.isRunning && model.team(of: $0.id).isEmpty }
        guard running.count >= 3 else { return nil }
        let (lead, worker, helper) = (running[0].id, running[1].id, running[2].id)
        for (id, role) in [(lead, "Leader"), (worker, "Worker"), (helper, "Worker")] {
            guard var item = model.session(id) else { continue }
            item.role = role
            model.put(item)
        }
        model.setParent(worker, to: lead)
        model.setParent(helper, to: lead)
        await endUndoGroup(model)
        await ui.settle(0.4)
        guard let a = model.session(lead), let b = model.session(worker), let c = model.session(helper) else { return nil }
        return (a, b, c)
    }

    /// A key pressed in the sheet, as AppKit gives it to the key window: its key equivalents first, then its first responder.
    private static func sheetKey(_ ui: Driver, _ key: Driver.Key, _ flags: NSEvent.ModifierFlags = []) async {
        let arrows: NSEvent.ModifierFlags = [.up, .down].contains(key) ? [.numericPad, .function] : []
        guard let sheet = ui.window.attachedSheet,
              let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags.union(arrows),
                                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sheet.windowNumber, context: nil,
                                           characters: key.characters, charactersIgnoringModifiers: key.characters, isARepeat: false,
                                           keyCode: key.code) else { return }
        if !sheet.performKeyEquivalent(with: event) { sheet.sendEvent(event) }
        await ui.settle(0.3)
    }

    /// Text typed into what has the sheet's keyboard, all of it replaced when `replacing`.
    private static func typeInSheet(_ ui: Driver, _ text: String, replacing: Bool = false) async {
        guard let editor = ui.window.attachedSheet?.firstResponder as? NSTextView else { return }
        if replacing { editor.selectAll(nil) }
        editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        await ui.settle(0.2)
    }

    /// The menu bar's item with a ⌘ key, the menu brought up to date first.
    private static func menuItem(_ menu: String, key: String) -> NSMenuItem? {
        guard let submenu = NSApp.mainMenu?.items.first(where: { $0.title == menu })?.submenu else { return nil }
        submenu.update()
        return submenu.items.first { $0.keyEquivalent == key && $0.keyEquivalentModifierMask == .command }
    }

    /// The menu bar item a ⌘ key runs, as choosing it does: a background run's menus take no keys.
    private static func menuKey(_ ui: Driver, _ menu: String, _ key: String) async {
        if let item = menuItem(menu, key: key), let parent = item.menu, let index = Optional(parent.index(of: item)), index >= 0 {
            if verbose { print("  menu item \(item.title), enabled \(item.isEnabled), action \(String(describing: item.action)), target \(String(describing: item.target))") }
            parent.performActionForItem(at: index)
        }
        await ui.settle(0.4)
    }

    /// What the form's pop-up called `label` shows: SwiftUI draws it, so the form marks its value with an anchor.
    private static func shown(_ ui: Driver, _ label: String) -> String? {
        let prefix = "start-\(label.lowercased())="
        return anchors.first { $0.key.hasPrefix(prefix) && $0.value.contains { $0.view?.window != nil && $0.view?.window === ui.window.attachedSheet } }
            .map { String($0.key.dropFirst(prefix.count)) }
    }

    // MARK: Start a Session

    private static func startForm(_ model: AppModel, _ ui: Driver) async {
        guard let team = await makeTeam(model, ui) else { return await check("three running sessions to make a team of", false) }

        // Start Child Session…: the parent, its folder, the role its sessions have.
        model.beginStart(parent: team.lead.id)
        await ui.until { shown(ui, "Role") != nil }
        await check("Start Child Session… opens the form with Role, Parent and History pop-ups",
                    shown(ui, "Role") != nil && shown(ui, "Parent") != nil && shown(ui, "History") != nil,
                    "\(shown(ui, "Role") ?? "-"), \(shown(ui, "Parent") ?? "-"), \(shown(ui, "History") ?? "-")")
        await check("it fills in the parent, its folder, and the role its sessions have: Worker",
                    shown(ui, "Parent") == team.lead.name && shown(ui, "Role") == "Worker" && shown(ui, "History") == "None"
                    && model.startDraft?.folder == team.lead.cwd, "\(shown(ui, "Parent") ?? "-"), \(shown(ui, "Role") ?? "-")")
        await check("the form is 720 pt wide", ui.window.attachedSheet.map { abs($0.frame.width - Metric.startSheet.width) < 1 } ?? false,
                    "\(ui.window.attachedSheet?.frame.width ?? 0)")
        let fields = ["start-name", "start-folder", "start-role", "start-parent", "start-history"]
        func edges() -> [CGFloat] { fields.compactMap { ui.anchorFrame($0)?.minX } }
        await check("every field starts on the name field's leading edge", edges().count == fields.count && Set(edges().map { $0.rounded() }).count == 1,
                    zip(fields, edges()).map { "\($0) \(String(format: "%.1f", $1))" }.joined(separator: ", "))

        // A role picked stays when the parent changes (what each pop-up's choice calls).
        model.setStartRole("Leader")
        await check("Role shows Leader once picked", shown(ui, "Role") == "Leader" && model.startDraft?.roleChosen == true)
        model.setStartParent(nil)
        await check("Parent None: at the top level, and the role picked stays",
                    shown(ui, "Parent") == "None: at the top level" && model.startDraft?.role == "Leader", "\(String(describing: model.startDraft))")
        model.startDraft?.history = team.worker.id
        await check("History shows the session picked", shown(ui, "History") == team.worker.name, shown(ui, "History") ?? "-")

        // Edit Roles… opens Roles over the form, its role picked; Back returns to the form as it was.
        model.openRoles(model.startDraft?.role, push: true)
        await check("Edit Roles… opens Roles over the form, Leader picked", model.modal == .roles && model.modalStack.last == .start
                    && model.pickedRole?.name == "Leader", "\(String(describing: model.modal)), \(model.pickedRole?.name ?? "-")")
        await ui.click(await ui.steadyAnchor("modal-back"), inSheet: true)
        await check("Back returns to the form, its picks kept", model.modal == .start && model.startDraft?.role == "Leader"
                    && model.startDraft?.history == team.worker.id && shown(ui, "Role") == "Leader")

        // Start: a session with that role and that history, at the top level.
        model.startDraft?.name = "Forms start"
        let log = model.ghosttyLog.count
        await ui.click(await ui.steadyAnchor("start-button"), inSheet: true)
        await ui.until { model.modal == nil }
        func started() -> SessionItem? { model.sessions.last { $0.name == "Forms start" } }
        await check("Start starts it with its role, at the top level, from that session's history",
                    started()?.role == "Leader" && started()?.parent == nil && model.ghosttyLog.count > log
                    && model.ghosttyLog.last?.contains("--resume \(team.worker.id) --fork-session") == true, model.ghosttyLog.last ?? "-")
        await ui.until { ui.window.attachedSheet == nil }

        // Start Session from Its History…: that session, its parent, its role and its name with ⑂.
        model.beginStart(history: team.helper.id)
        await ui.until { shown(ui, "Role") != nil }
        await check("from Start Session from Its History…: History is that session, Parent its parent, its role, ⑂",
                    shown(ui, "History") == team.helper.name && shown(ui, "Parent") == team.lead.name && shown(ui, "Role") == "Worker"
                    && model.startDraft?.name == "\(team.helper.name) ⑂", "\(String(describing: model.startDraft))")
        model.closeModal()
        await ui.until { ui.window.attachedSheet == nil }

        // From a task: its name and first message, at the top level.
        guard let task = model.addTask(to: .overview, title: "Form task") else { return await check("a task", false) }
        model.beginStart(task: task.id)
        await ui.until { shown(ui, "Role") != nil }
        await check("from a task: its name and first message, Parent None", model.startDraft?.name == "\(task.key) Form task"
                    && model.startDraft?.message.contains("hq task show \(task.key)") == true && shown(ui, "Parent") == "None: at the top level",
                    shown(ui, "Parent") ?? "-")
        model.closeModal()
    }

    // MARK: Roles

    private static func rolesModal(_ model: AppModel, _ ui: Driver) async {
        guard let team = await makeTeam(model, ui) else { return await check("three running sessions to make a team of", false) }
        await ui.click(ui.anchor("roles-button"))
        await ui.until { model.modal == .roles && ui.anchorFrame("role-page") != nil }
        await check("Roles on the Sessions header opens Roles, the first role picked", model.modal == .roles && model.pickedRole?.name == model.roles.first?.name,
                    model.pickedRole?.name ?? "-")
        await check("its list has each role and New Role", model.roles.allSatisfy { ui.anchorFrame("role:\($0.name)") != nil } && ui.anchorFrame("roles-new") != nil)

        // A click picks; ↓ and ↑ walk the list.
        await ui.click(await ui.steadyAnchor("role:Worker"), inSheet: true)
        await check("a click on a role's row picks it", model.pickedRole?.name == "Worker", model.pickedRole?.name ?? "-")
        await sheetKey(ui, .up)
        await check("↑ picks the role above", model.pickedRole?.name == "Leader", model.pickedRole?.name ?? "-")
        await sheetKey(ui, .down)
        await check("↓ picks the role below", model.pickedRole?.name == "Worker", model.pickedRole?.name ?? "-")
        await check("Used by lists the sessions that have it", ui.anchorFrame("role-user:\(team.worker.id)") != nil
                    && ui.anchorFrame("role-user:\(team.helper.id)") != nil)

        // The name: a double-click edits it in place, Return keeps it; the sessions with it follow.
        await ui.click(await ui.steadyAnchor("role-name"), count: 2, inSheet: true)
        await ui.until { ui.sheetIsTyping }
        await check("a double-click on the name edits it in place", model.roleEdit?.field == .name && ui.sheetIsTyping, ui.sheetResponder)
        await typeInSheet(ui, "Builder", replacing: true)
        await sheetKey(ui, .return)
        await check("Return renames it, and its sessions follow", model.role(named: "Builder") != nil && model.pickedRole?.name == "Builder"
                    && model.session(team.worker.id)?.role == "Builder" && model.roleEdit == nil, "\(model.roles.map(\.name))")

        // The line: the same, Escape drops it.
        await ui.click(await ui.steadyAnchor("role-line"), count: 2, inSheet: true)
        await ui.until { ui.sheetIsTyping }
        await typeInSheet(ui, "Builds one thing", replacing: true)
        await sheetKey(ui, .escape)
        await check("Escape in the line drops the edit", model.role(named: "Builder")?.line != "Builds one thing" && model.roleEdit == nil
                    && model.modal == .roles)
        await ui.click(await ui.steadyAnchor("role-line"), count: 2, inSheet: true)
        await ui.until { ui.sheetIsTyping }
        await typeInSheet(ui, "Builds one thing", replacing: true)
        await sheetKey(ui, .return)
        await check("Return keeps the line", model.role(named: "Builder")?.line == "Builds one thing")

        // The text: ⌘E (Edit Role) edits it in place; Escape saves.
        await check("Edit › Edit Role (⌘E) is on while Roles shows a role", MenuState.shared.canEditRole && menuItem("Edit", key: "e") != nil,
                    menuItem("Edit", key: "e")?.title ?? "no ⌘E")
        // A background run's menus are off: the header's Edit, which ⌘E runs, stands in.
        if ui.window.isKeyWindow && NSApp.isActive { await menuKey(ui, "Edit", "e") } else { await ui.click(await ui.steadyAnchor("role-edit"), inSheet: true) }
        await ui.until { ui.sheetIsTyping }
        await check("⌘E (Edit) edits its text in place", model.roleEdit?.field == .text && ui.anchorFrame("role-editor") != nil, ui.sheetResponder)
        await check("while editing, the header shows Cancel and Save", ui.anchorFrame("role-save") != nil && ui.anchorFrame("role-cancel") != nil
                    && ui.anchorFrame("role-delete") == nil)
        await typeInSheet(ui, "\n\nOne more line.")
        await sheetKey(ui, .escape)
        await check("Escape saves the text", model.role(named: "Builder")?.text.hasSuffix("One more line.") == true && model.roleEdit == nil
                    && model.modal == .roles)

        // Near the hook's limit, a word says so.
        model.changeRole("Builder") { $0.text = String(repeating: "Do the work well. ", count: AppModel.roleTextLimit / 18 + 2) }
        await check("a text near the hook's limit shows a warning", ui.anchorFrame("role-limit") != nil)

        // Delete, then Undo: sessions lose the chip and get it back.
        await ui.click(await ui.steadyAnchor("role-delete"), inSheet: true)
        await check("Delete removes the role and picks another; its sessions lose the chip",
                    model.role(named: "Builder") == nil && model.pickedRole != nil && model.role(named: model.session(team.worker.id)?.role) == nil)
        await endUndoGroup(model)
        model.undoManager?.undo()
        await check("Undo brings it back, and the chip", model.role(named: "Builder") != nil && model.role(named: model.session(team.worker.id)?.role) != nil)

        // Restore Default shows once a shipped role changed, and gives its text back.
        await ui.click(await ui.steadyAnchor("role:Leader"), inSheet: true)
        await check("Restore Default hides while Leader is as shipped", model.pickedRole?.name == "Leader" && ui.anchorFrame("role-restore") == nil)
        model.changeRole("Leader") { $0.text = "Lead, briefly." }
        await ui.click(await ui.steadyAnchor("role-restore"), inSheet: true)
        await check("Restore Default gives Leader its text back", model.role(named: "Leader")?.text == RoleItem.defaults[0].text
                    && ui.anchorFrame("role-restore") == nil)

        // Copy: the role's line.
        await ui.click(await ui.steadyAnchor("copy-item"), inSheet: true)
        await check("Copy gives the role's line", Pasteboard.copied == "Role Leader: \(RoleItem.defaults[0].line)", Pasteboard.copied ?? "-")

        // New Role: named at once, then its text.
        await ui.click(await ui.steadyAnchor("roles-new"), inSheet: true)
        await ui.until { ui.sheetIsTyping }
        await check("New Role adds a role, picked, its name in its field", model.pickedRole?.name.hasPrefix("New Role") == true
                    && model.roleEdit?.field == .name && ui.sheetIsTyping, "\(model.pickedRole?.name ?? "-"), \(String(describing: model.roleEdit?.field)), \(ui.sheetResponder)")
        await typeInSheet(ui, "Reviewer of forms", replacing: true)
        await sheetKey(ui, .return)
        await ui.until { model.roleEdit?.field == .text }
        await ui.until { ui.sheetResponder == "EditorTextView" }
        await check("named, its text is edited next, in place", model.pickedRole?.name == "Reviewer of forms" && model.roleEdit?.field == .text && ui.sheetResponder == "EditorTextView",
                    "\(model.pickedRole?.name ?? "-"), \(String(describing: model.roleEdit?.field)), \(ui.sheetResponder)")
        await typeInSheet(ui, "Review one form.")
        await sheetKey(ui, .return, .command)
        await check("⌘Return saves its text", model.role(named: "Reviewer of forms")?.text == "Review one form." && model.roleEdit == nil)

        // Used by: a click selects that session on the page.
        await ui.click(await ui.steadyAnchor("role:Leader"), inSheet: true)
        await ui.click(await ui.steadyAnchor("role-user:\(team.lead.id)"), inSheet: true)
        await ui.until { ui.window.attachedSheet == nil }
        await check("a face under Used by closes Roles and selects that session on the page", model.modal == nil && model.selectedSession == team.lead.id,
                    model.selectedSession ?? "-")
        await seedRoleNotes(model, ui)
    }

    /// The test vault's role notes as the seed has them: the edits above stay out of the next groups, whose vault reads
    /// would bring them back.
    private static func seedRoleNotes(_ model: AppModel, _ ui: Driver) async {
        guard let vault = model.vault else { return }
        try? FileManager.default.removeItem(at: vault.rolesDirectory)
        SeedData.fill(model, now: .now)
        model.roles = model.roles.compactMap { try? vault.create($0) }
        await endUndoGroup(model)
        model.undoManager?.removeAllActions()
        await ui.settle(0.5)
    }

    // MARK: The session's modal

    private static func sessionTeam(_ model: AppModel, _ ui: Driver) async {
        guard let team = await makeTeam(model, ui) else { return await check("three running sessions to make a team of", false) }
        model.open(.session(team.lead.id))
        await ui.until { ui.anchorFrame("team-row:\(team.worker.id)") != nil }
        await check("a session's modal lists its team, each row under the other", ui.anchorFrame("team-row:\(team.worker.id)") != nil
                    && ui.anchorFrame("team-row:\(team.helper.id)") != nil && ui.anchorFrame("session-role") != nil)
        await ui.click(await ui.steadyAnchor("team-row:\(team.worker.id)"), count: 2, inSheet: true)
        await check("a double-click on a team row opens that session over it", model.modal == .session(team.worker.id)
                    && model.modalStack.last == .session(team.lead.id), "\(String(describing: model.modal))")
        await check("its Details say who started it and its role", ui.anchorFrame("session-parent") != nil && ui.anchorFrame("session-role") != nil,
                    "parent \(ui.anchorFrame("session-parent") != nil), role \(ui.anchorFrame("session-role") != nil), \(String(describing: model.modal))")
        await ui.click(await ui.steadyAnchor("session-parent"), inSheet: true)
        await check("Started by opens the parent over it", model.modal == .session(team.lead.id) && model.modalStack.last == .session(team.worker.id))
        await ui.click(await ui.steadyAnchor("session-role"), inSheet: true)
        await check("its role opens Roles over it, that role picked", model.modal == .roles && model.pickedRole?.name == "Leader")
    }

    // MARK: Closed Sessions

    private static func closedTeam(_ model: AppModel, _ ui: Driver) async {
        guard let team = await makeTeam(model, ui) else { return await check("three running sessions to make a team of", false) }
        for (offset, id) in [team.helper.id, team.worker.id, team.lead.id].enumerated() {
            guard var item = model.session(id) else { continue }
            var live = item.live
            live.end(.now)
            item.live = live
            item.pid = nil
            item.closedAt = Date.now.addingTimeInterval(Double(offset))
            model.put(item)
        }
        model.open(.closedSessions)
        await ui.until { ui.anchorFrame("closed:\(team.helper.id)") != nil }
        func rows() -> [NSRect] { [team.lead.id, team.worker.id, team.helper.id].compactMap { ui.anchorFrame("closed:\($0)") } }
        func together() -> Bool {
            let frames = rows()
            return frames.count == 3 && abs(frames[0].minY - frames[1].maxY) < 2 && abs(frames[1].minY - frames[2].maxY) < 2
        }
        await check("Closed Sessions keeps a team closed together together: the one that started it, then its sessions right under",
                    together(), rows().map { "\(Int($0.minY))–\(Int($0.maxY))" }.joined(separator: ", "))
        await check("each has Resume", [team.lead.id, team.worker.id, team.helper.id].allSatisfy { ui.anchorFrame("resume:\($0)") != nil })
        let log = model.ghosttyLog.count
        await ui.click(await ui.steadyAnchor("resume:\(team.worker.id)"), inSheet: true)
        await check("Resume on a team's session resumes that one", model.ghosttyLog.count > log
                    && model.ghosttyLog.last?.contains("--resume \(team.worker.id)") == true, model.ghosttyLog.last ?? "-")
        // Its card joins the grid: the page holds still before the next group looks at it.
        model.closeModal()
        await ui.until { ui.window.attachedSheet == nil }
        await ui.settle(1)
    }
}
