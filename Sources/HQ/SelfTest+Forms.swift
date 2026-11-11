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

        // Closed Sessions: a team closed together stays together, the one that started it first.
        let closedAt = Date.now
        for id in [lead, worker, helper] {
            guard var item = model.session(id) else { continue }
            var live = item.live
            live.end(.now)
            item.live = live
            item.closedAt = closedAt.addingTimeInterval(id == worker ? -1 : 0)
            model.put(item)
        }
        let closed = model.closedRows
        let top = closed.firstIndex { $0.session.id == lead }
        check("Closed Sessions keeps a team closed together together, its sessions under it",
              top.map { closed.count > $0 + 2 && Set(closed[($0 + 1)...($0 + 2)].map(\.session.id)) == [worker, helper]
                  && closed[$0].depth == 0 && closed[$0 + 1].depth == 1 && closed[$0 + 2].depth == 1 } ?? false,
              closed.map { "\($0.session.name) \($0.depth)" }.joined(separator: ", "))

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
