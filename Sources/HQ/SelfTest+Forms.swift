import AppKit
import HQKit

/// Start a Session's Role, Parent and History and what each entry point fills in (T-408); Roles edited in place (T-415);
/// a team in Closed Sessions, the menu bar's Focus ▸ and the Session menu's Move Under ▸ (T-411).
extension SelfTest {
    static func formsChecks(_ model: AppModel) async {
        if model.roles.isEmpty { model.roles = RoleItem.defaults }
        let lead = "f0a50000-0000-4000-8000-0000000000b1", worker = "f0a50000-0000-4000-8000-0000000000b2"
        let helper = "f0a50000-0000-4000-8000-0000000000b3", loner = "f0a50000-0000-4000-8000-0000000000b4"
        let folder = NSTemporaryDirectory() + "forms-lead"
        for (id, name, role) in [(lead, "Forms lead", "Leader"), (worker, "Forms worker", "Worker"), (helper, "Forms helper", "Worker"),
                                 (loner, "Forms loner", nil)] {
            var item = SessionItem(id: id, customName: name, status: SessionStatus(state: .idle, since: .now), cwd: id == lead ? folder : NSTemporaryDirectory(),
                                   repo: "forms", branch: "main", started: .now, order: model.nextGridOrder)
            item.role = role
            model.put(item)
        }
        model.setParent(worker, to: lead)
        model.setParent(helper, to: lead)
        defer { model.sessions.removeAll { [lead, worker, helper, loner].contains($0.id) } }

        // What each entry point fills in.
        model.beginStart(parent: lead)
        check("Start Child Session… fills in the parent, its folder and the role its sessions have",
              model.startDraft?.parent == lead && model.startDraft?.folder == folder && model.startDraft?.role == "Worker"
              && model.startDraft?.history == nil && model.startDraft?.name == "", "\(String(describing: model.startDraft))")
        model.beginStart(history: worker)
        check("Start Session from Its History… fills in that session as History, its parent, its role, and its name with ⑂",
              model.startDraft?.history == worker && model.startDraft?.parent == lead && model.startDraft?.role == "Worker"
              && model.startDraft?.name == "Forms worker ⑂", "\(String(describing: model.startDraft))")

        // Parent picked in the form: its folder and its sessions' role follow, until a role is picked.
        model.beginStart()
        model.setStartParent(lead)
        check("picking a Parent takes its folder and its sessions' role", model.startDraft?.folder == folder && model.startDraft?.role == "Worker",
              "\(String(describing: model.startDraft))")
        model.setStartRole("Leader")
        model.setStartParent(loner)
        check("a role picked stays when the Parent changes", model.startDraft?.role == "Leader" && model.startDraft?.parent == loner)
        model.setStartParent(nil)
        check("None: at the top level keeps the folder", model.startDraft?.parent == nil && model.startDraft?.folder == NSTemporaryDirectory())
        model.closeModal()

        // Move Under ▸: never itself, one of its own or its parent.
        let choices = model.moveUnderChoices(for: lead)
        check("Move Under ▸ leaves out the session, its own team and its parent",
              !choices.contains(lead) && !choices.contains(worker) && !choices.contains(helper) && choices.contains(loner)
              && !model.moveUnderChoices(for: worker).contains(lead) && model.moveUnderChoices(for: worker).contains(loner), "\(choices)")

        // The menu bar's Focus ▸: a team's sessions under their parent, stepped in.
        let rows = model.menuBarRows
        let at = rows.firstIndex { $0.session.id == lead }
        check("Focus ▸ lists a team's sessions right under their parent, one level in",
              at.map { rows.count > $0 + 2 && rows[$0 + 1].session.id == worker && rows[$0 + 2].session.id == helper
                  && rows[$0].depth == 0 && rows[$0 + 1].depth == 1 && rows[$0 + 2].depth == 1 } ?? false,
              rows.map { "\($0.session.name) \($0.depth)" }.joined(separator: ", "))
        check("an indented face is wider by its depth", MenuBarMenu.face(model.session(worker)!, depth: 1).size.width == Metric.faceMenu + Metric.menuIndent)

        // Closed Sessions (T-770): a team under the session that started it, closed or open, the latest to close first.
        let closedAt = Date.now
        for id in [lead, worker, helper] {
            guard var item = model.session(id) else { continue }
            var live = item.live
            live.end(.now)
            item.live = live
            item.closedAt = closedAt.addingTimeInterval(id == worker ? -1 : 0)
            model.put(item)
        }
        var groups = model.closedGroups
        var team = groups.first { $0.id == lead }
        check("Closed Sessions keeps a team closed together under the one that started it, the latest to close first",
              team?.rows.map(\.session.id) == [helper, worker] && team?.rows.allSatisfy { $0.depth == 1 } == true
              && !groups.contains { [worker, helper].contains($0.id) }, groups.map { "\($0.head.name): \($0.rows.map(\.session.name))" }.joined(separator: "; "))
        if var item = model.session(lead) {
            item.closedAt = nil
            item.status = SessionStatus(state: .idle, since: .now)
            model.put(item)
        }
        team = model.closedGroups.first { $0.id == lead }
        check("an open session heads its closed ones too", team?.head.isRunning == true && team?.rows.count == 2, "\(String(describing: team?.rows.map(\.session.name)))")
        // Its search (T-744): every word, in a name, a task's key or title, a role or a folder; a match keeps the rows above it.
        groups = model.closedGroups
        func search(_ query: String) -> [String] {
            model.closedGroups(groups, matching: query).groups.flatMap { [$0.head.id] + ($0.searched ? $0.rows.map(\.session.id) : []) }
        }
        model.link(task: 45, session: helper)
        let byTask = model.closedGroups(groups, matching: "t-45 forms")
        check("Closed Sessions' search finds a session by its task's key, open under its team's top session, counting the match only",
              search("t-45 forms") == [lead, helper] && byTask.found == 1, "\(search("t-45 forms")) \(byTask.found)")
        model.unlink(task: 45, session: helper)
        check("by its role and its folder, every word; a top session found alone stays folded", search("leader forms-lead") == [lead]
              && model.closedGroups(groups, matching: "worker forms").found == 2, "\(search("leader forms-lead")) \(search("worker forms"))")
        check("and nothing for words no session has, every team folded when empty",
              search("zzzz qqqq").isEmpty && search(" ") == groups.map(\.head.id) && model.closedGroups(groups, matching: " ").found == model.closedSessions.count)

        await UITest.endUndoGroup(model)
        // Roles edited in place: a rename follows to the sessions that have it; Cancel writes nothing.
        model.selectedRole = "Worker"
        model.beginRoleEdit(.name)
        model.roleEdit?.text = "Builder"
        model.commitRoleEdit()
        check("a role renamed in place keeps its pick, and its sessions follow", model.selectedRole == "Builder"
              && model.session(worker)?.role == "Builder" && model.role(named: "Worker") == nil, "\(model.roles.map(\.name))")
        model.beginRoleEdit(.line)
        model.roleEdit?.text = "Something else"
        model.cancelRoleEdit()
        check("Cancel writes nothing", model.role(named: "Builder")?.line == RoleItem.defaults[1].line)
        model.undoManager?.undo()
        await expect("Undo brings the name back", model.role(named: "Worker") != nil)
        model.selectedRole = "Worker"
    }
}
