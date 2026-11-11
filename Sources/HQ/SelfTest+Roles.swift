import Foundation
import HQKit

/// Roles (T-412, T-413): notes in hq/roles/, read at each vault scan and written by each change; Leader and Worker written
/// once; a role's text reaches its session at every SessionStart, never past what a hook can add.
extension SelfTest {
    static func roleChecks(_ model: AppModel) async {
        guard let vault = model.vault else { return check("a vault for the roles", false) }
        let folder = vault.rolesDirectory
        func url(_ name: String) -> URL { folder.appending(path: "\(name).md") }
        func note(_ name: String) -> FrontMatter? { (try? String(contentsOf: url(name), encoding: .utf8)).map { FrontMatter($0) } }
        func rescan() async {
            for _ in 0..<150 where model.vaultScanning { try? await Task.sleep(for: .milliseconds(20)) }
            model.rescanVault()
            for _ in 0..<150 where model.vaultScanning { try? await Task.sleep(for: .milliseconds(20)) }
        }
        await rescan()
        let leader = RoleItem.defaults[0]
        check("Leader and Worker are written to hq/roles/ when missing, with their color, line and text",
              note("Leader")?.string("color") == "indigo" && note("Leader")?.string("line") == leader.line && note("Leader")?.body == leader.text + "\n"
              && note("Worker")?.string("color") == "brown" && model.roles.prefix(2).map(\.name) == ["Leader", "Worker"]
              && model.roles.prefix(2).allSatisfy { $0.path != nil && $0.builtin },
              "\(model.roles.map(\.name)) \(note("Leader")?.text.prefix(80) ?? "no note")")

        // A note of the user's is a role; an edit in Obsidian reads again.
        try? "---\ncolor: pink\nline: Reviews one pull request.\naliases: [critic]\n---\nRead the diff.\n".write(to: url("Reviewer"), atomically: true, encoding: .utf8)
        await rescan()
        await expect("a note in hq/roles/ is a role: its name, color, line and text",
                     model.role(named: "Reviewer").map { $0.color == .pink && $0.line == "Reviews one pull request." && $0.text == "Read the diff." && !$0.builtin } == true,
                     "\(String(describing: model.role(named: "Reviewer")))")
        try? "---\ncolor: pink\nline: Reviews one PR, never pushes.\naliases: [critic]\n---\nRead the diff.\n".write(to: url("Reviewer"), atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(5)], ofItemAtPath: url("Reviewer").path)
        await rescan()
        await expect("a role changed in Obsidian reads again", model.role(named: "Reviewer")?.line == "Reviews one PR, never pushes.")

        // Each change writes the note; HQ owns only color and line.
        await UITest.endUndoGroup(model)
        model.changeRole("Reviewer") {
            $0.text = "Read the whole diff."
            $0.color = .teal
        }
        check("an edit writes the role's color and text, and keeps the user's keys", note("Reviewer")?.string("color") == "teal"
              && note("Reviewer")?.body == "Read the whole diff.\n" && note("Reviewer")?.list("aliases") == ["critic"], note("Reviewer")?.text ?? "no note")
        let reviewing = "7e1e0000-0000-4000-8000-0000000000a1"
        model.put(SessionItem(id: reviewing, customName: "Role reviewer", status: SessionStatus(state: .idle, since: .now), cwd: NSTemporaryDirectory(),
                              repo: "roles", branch: "main", started: .now, order: model.nextGridOrder, role: "reviewer"))
        await UITest.endUndoGroup(model)
        model.changeRole("Reviewer", "Rename Role") { $0.name = "Critic" }
        check("a rename renames the note and the role of the sessions that have it", note("Reviewer") == nil && note("Critic")?.list("aliases") == ["critic"]
              && model.role(named: "Reviewer") == nil && model.role(named: "Critic") != nil && model.session(reviewing)?.role == "Critic",
              "\(model.roles.map(\.name)) \(String(describing: model.session(reviewing)?.role))")
        await rescan()
        check("a vault read after it finds the one note", model.roles.filter { ["reviewer", "critic"].contains($0.name.lowercased()) }.map(\.name) == ["Critic"],
              "\(model.roles.map(\.name))")
        await UITest.endUndoGroup(model)
        model.changeRole("Critic") { $0.name = "Reviewer/2: draft" }
        check("a name keeps no slash or colon: it names a note", model.role(named: "Reviewer-2- draft") != nil && note("Reviewer-2- draft") != nil,
              "\(model.roles.map(\.name))")
        model.changeRole("Reviewer-2- draft") { $0.name = "Leader" }
        check("a rename onto another role's name is refused", model.role(named: "Reviewer-2- draft") != nil && note("Leader")?.body == leader.text + "\n")
        model.undoManager?.undo()
        model.undoManager?.undo()
        await expect("Undo renames it back", note("Reviewer") != nil && note("Critic") == nil && model.session(reviewing)?.role == "Reviewer",
                     "\(model.roles.map(\.name)) \(String(describing: model.session(reviewing)?.role))")

        // Delete sends the note to the Trash; Undo brings it back.
        await UITest.endUndoGroup(model)
        model.deleteRole("Reviewer")
        check("Delete moves the role's note to the Trash; its sessions keep the name, not the chip", note("Reviewer") == nil && model.role(named: "Reviewer") == nil
              && model.session(reviewing)?.role == "Reviewer")
        await rescan()
        check("and a vault read doesn't bring it back", model.role(named: "Reviewer") == nil)
        model.undoManager?.undo()
        await expect("Undo brings the note back, with the chip", note("Reviewer")?.body == "Read the whole diff.\n" && model.role(named: "Reviewer") != nil)

        // New Role and Restore Default.
        await UITest.endUndoGroup(model)
        let made = model.newRole(named: "Planner", color: .mint, line: "Writes the plan.", text: "Plan first.")
        let again = model.newRole(named: "Planner")
        check("New Role writes its note, under a name no role has", made.name == "Planner" && again.name == "Planner 2"
              && note("Planner")?.string("color") == "mint" && note("Planner")?.string("line") == "Writes the plan." && note("Planner")?.body == "Plan first.\n"
              && note("Planner 2") != nil && !(note("Planner 2")?.has("line") ?? true), "\(made.name), \(again.name)")
        model.changeRole("Leader") { $0.text = "Lead, my way." }
        check("a shipped role's text changed: Restore Default shows", model.role(named: "Leader").map(model.isChangedDefault) == true && note("Leader")?.body == "Lead, my way.\n")
        model.restoreDefault("Leader")
        check("Restore Default writes its shipped text back", note("Leader")?.body == leader.text + "\n" && model.role(named: "Leader").map(model.isChangedDefault) == false)

        // Written once: a shipped role the user deleted stays deleted.
        try? FileManager.default.removeItem(at: url("Worker"))
        await rescan()
        model.writeShippedRoles()
        check("a shipped role is written once: deleted, it isn't written again", note("Worker") == nil && model.role(named: "Worker") == nil,
              "\(model.roles.map(\.name))")
        model.newRole(named: "Worker")
        model.restoreDefault("Worker")
        check("New Role “Worker” and Restore Default bring it back", note("Worker")?.body == RoleItem.workerText + "\n" && note("Worker")?.string("color") == "brown"
              && model.roles.prefix(2).map(\.name) == ["Leader", "Worker"], "\(model.roles.map(\.name))")

        // The shipped texts name commands hq has, with options it takes.
        var unknown: [String] = []
        for role in RoleItem.defaults {
            for match in role.text.matches(of: /`hq ([a-z]+)(?: ([a-z]+))?([^`]*)`/) {
                let two = match.output.2.map { "\(match.output.1) \($0)" }
                guard let command = AgentCommands.all.first(where: { $0.name == two }) ?? AgentCommands.all.first(where: { $0.name == String(match.output.1) }) else {
                    unknown.append(String(match.output.0))
                    continue
                }
                for flag in match.output.3.matches(of: /--([a-z-]+)/) where !command.params.contains(where: { $0.name == String(flag.output.1) }) {
                    unknown.append("\(match.output.0): --\(flag.output.1)")
                }
            }
        }
        check("Leader's and Worker's texts name only commands and options hq has", unknown.isEmpty, unknown.joined(separator: ", "))

        await startTextChecks(model)

        // Leave the vault as the other checks had it.
        for name in ["Reviewer", "Planner", "Planner 2"] { model.deleteRole(name) }
        model.sessions.removeAll { $0.id == reviewing }
    }

    /// T-413: HQ's line, who started the session, and its role's text, at every SessionStart; cut to stay whole under the cap.
    private static func startTextChecks(_ model: AppModel) async {
        let lead = "7e1e0000-0000-4000-8000-0000000000b1", worker = "7e1e0000-0000-4000-8000-0000000000b2"
        let cleared = "7e1e0000-0000-4000-8000-0000000000b3", pid: Int32 = 999_911
        model.put(SessionItem(id: lead, customName: "registry: ready for more customers", status: SessionStatus(state: .idle, since: .now),
                              cwd: NSTemporaryDirectory(), repo: "roles", branch: "main", started: .now, order: model.nextGridOrder, role: "Leader"))
        model.put(SessionItem(id: worker, customName: "T-61 Retry budget", status: SessionStatus(state: .idle, since: .now), cwd: NSTemporaryDirectory(),
                              repo: "roles", branch: "main", started: .now, pid: pid, order: model.nextGridOrder, parent: lead, role: "Worker"))
        func start(_ id: String, _ source: String, pid: Int32? = nil) -> String {
            var args = ["event": "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"\(id)\",\"cwd\":\"\(NSTemporaryDirectory())\",\"source\":\"\(source)\"}"]
            if let pid { args["pid"] = "\(pid)" }
            return agent("hook", args)["context"] as? String ?? ""
        }
        let worker0 = start(worker, "startup")
        check("a Worker's start text: HQ tracks it, its leader by name and how to message it, then its role's text",
              worker0.hasPrefix("HQ tracks this session.") && worker0.contains("The session “registry: ready for more customers” (Leader) started this one: this session reports to it.")
              && worker0.contains("SendMessage, to “registry: ready for more customers”") && worker0.contains("Load the hq skill")
              && worker0.contains("This session's role is Worker: Works on one task and reports to its leader. Its text, from HQ:\n\n" + RoleItem.workerText)
              && worker0.hasSuffix(RoleItem.workerText), worker0)
        let lead0 = start(lead, "startup")
        check("a Leader's start text says it started sessions that report to it, and has the Leader's text",
              lead0.contains("This session started 1 session that reports to it") && lead0.contains(RoleItem.leaderText) && !lead0.contains("started this one"), lead0)
        var missed: [String] = []
        for source in ["resume", "compact", "fork"] where !start(worker, source).contains(RoleItem.workerText) { missed.append(source) }
        model.changeRole("Worker") { $0.text = "Report at each step." }
        if !start(worker, "compact").hasSuffix("Report at each step.") { missed.append("compact after an edit") }
        model.restoreDefault("Worker")
        // After /clear the new id keeps the role: same process, a new session id.
        let source = DispatchSource.makeProcessSource(identifier: getpid(), eventMask: .exit, queue: .main)
        source.resume()
        model.exitWatchers[pid] = source
        if !start(cleared, "clear", pid: pid).contains(RoleItem.workerText) { missed.append("clear") }
        model.exitWatchers.removeValue(forKey: pid)?.cancel()
        check("the role's text comes at start, on resume, after a compact (as it reads now), after /clear and in a fork", missed.isEmpty, missed.joined(separator: ", "))
        check("hooks.json sends every SessionStart, whatever its source, to hq hook", sessionStartHooked(), "no SessionStart without a matcher")

        // Never past what a hook can add: a long text is cut, and says so.
        model.newRole(named: "Long", text: String(repeating: "Check every line twice. ", count: 600))
        model.put(SessionItem(id: "7e1e0000-0000-4000-8000-0000000000b4", customName: "Long role", status: SessionStatus(state: .idle, since: .now),
                              cwd: NSTemporaryDirectory(), repo: "roles", branch: "main", started: .now, order: model.nextGridOrder, parent: lead, role: "Long"))
        let long = model.startContext("7e1e0000-0000-4000-8000-0000000000b4")
        check("a role's text past the cap is cut, with a note that says where to read it whole", long.utf16.count <= AppModel.hookTextLimit
              && long.hasSuffix("`hq role show Long` prints it whole.]") && long.contains("Check every line twice."), "\(long.utf16.count) characters")
        // A text at the editor's limit reaches whole, beside HQ's longest lines.
        let full = String(repeating: "x", count: AppModel.roleTextLimit)
        model.changeRole("Long") { $0.text = full }
        let keys = (0..<5).compactMap { index in
            model.addTask(to: .overview, title: "A long task title, as the user writes them sometimes, for step \(index) of the story", session: "7e1e0000-0000-4000-8000-0000000000b4")?.id
        }
        let reminders = keys.prefix(3).map { model.remind(String(repeating: "Look at the canary in eu-west again before merging. ", count: 3), at: .now.addingTimeInterval(-60),
                                                           level: .update, links: [ModalRoute.task($0).selectionKey]) }
        let whole = model.startContext("7e1e0000-0000-4000-8000-0000000000b4")
        check("a text at the role editor's limit reaches whole beside HQ's longest lines", whole.hasSuffix(full) && whole.utf16.count < AppModel.hookTextLimit,
              "\(whole.utf16.count) characters")
        for reminder in reminders { model.removeNotice(reminder.id) }
        model.deleteTasks(keys)
        model.deleteRole("Long")
        model.sessions.removeAll { [lead, worker, cleared, "7e1e0000-0000-4000-8000-0000000000b4"].contains($0.id) }
    }

    /// The bundled plugin's SessionStart hook has no matcher: startup, resume, clear, compact and fork all reach HQ.
    private static func sessionStartHooked() -> Bool {
        guard let url = Bundle.main.resourceURL?.appending(path: "Plugin/plugin/hooks/hooks.json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? JSONObject,
              let starts = (json["hooks"] as? JSONObject)?["SessionStart"] as? [JSONObject] else { return false }
        return starts.contains { ($0["matcher"] as? String ?? "").isEmpty && ($0["hooks"] as? [JSONObject])?.contains { ($0["command"] as? String)?.hasSuffix("hq hook") == true } == true }
    }
}
