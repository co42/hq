import Foundation
import HQKit

/// Roles (T-412, T-413): notes in hq/roles/, read at each vault scan and written by each change; the shipped roles written
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
        let shipped = ["Leader", "Builder", "Planner", "Investigator", "Reviewer", "Operator"]
        let miswritten = RoleItem.defaults.filter { role in
            guard let note = note(role.name) else { return true }
            return note.string("color") != role.color.rawValue || note.string("line") != role.line || note.body != role.text + "\n"
                || note.string("model") != role.model || note.string("effort") != role.effort
        }
        check("the six shipped roles are written to hq/roles/ when missing, with their color, line, text, model and effort, in their order",
              RoleItem.defaults.map(\.name) == shipped && miswritten.isEmpty && model.roles.prefix(6).map(\.name) == shipped
              && model.roles.prefix(6).allSatisfy { $0.path != nil && $0.builtin && !model.isChangedDefault($0) },
              "\(model.roles.map(\.name)) miswritten: \(miswritten.map(\.name))")
        check("Leader, Builder, Planner, Investigator, Reviewer and Operator ship in their colors, models and efforts",
              RoleItem.defaults.map { "\($0.color.rawValue) \($0.model ?? "-") \($0.effort ?? "-")" }
                == ["indigo opus xhigh", "brown opus high", "purple fable max", "teal opus xhigh", "pink opus xhigh", "orange opus xhigh"])

        // A note of the user's is a role; an edit in Obsidian reads again.
        try? "---\ncolor: pink\nline: Reviews one pull request.\naliases: [critic]\n---\nRead the diff.\n".write(to: url("Tester"), atomically: true, encoding: .utf8)
        await rescan()
        await expect("a note in hq/roles/ is a role: its name, color, line and text",
                     model.role(named: "Tester").map { $0.color == .pink && $0.line == "Reviews one pull request." && $0.text == "Read the diff." && !$0.builtin } == true,
                     "\(String(describing: model.role(named: "Tester")))")
        try? "---\ncolor: pink\nline: Reviews one PR, never pushes.\naliases: [critic]\n---\nRead the diff.\n".write(to: url("Tester"), atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(5)], ofItemAtPath: url("Tester").path)
        await rescan()
        await expect("a role changed in Obsidian reads again", model.role(named: "Tester")?.line == "Reviews one PR, never pushes.")

        // Each change writes the note; HQ owns only color and line.
        await UITest.endUndoGroup(model)
        model.changeRole("Tester") {
            $0.text = "Read the whole diff."
            $0.color = .teal
        }
        check("an edit writes the role's color and text, and keeps the user's keys", note("Tester")?.string("color") == "teal"
              && note("Tester")?.body == "Read the whole diff.\n" && note("Tester")?.list("aliases") == ["critic"], note("Tester")?.text ?? "no note")
        let reviewing = "7e1e0000-0000-4000-8000-0000000000a1"
        model.put(SessionItem(id: reviewing, customName: "Role reviewer", status: SessionStatus(state: .idle, since: .now), cwd: NSTemporaryDirectory(),
                              repo: "roles", branch: "main", started: .now, order: model.nextGridOrder, role: "tester"))
        await UITest.endUndoGroup(model)
        model.changeRole("Tester", "Rename Role") { $0.name = "Critic" }
        check("a rename renames the note and the role of the sessions that have it", note("Tester") == nil && note("Critic")?.list("aliases") == ["critic"]
              && model.role(named: "Tester") == nil && model.role(named: "Critic") != nil && model.session(reviewing)?.role == "Critic",
              "\(model.roles.map(\.name)) \(String(describing: model.session(reviewing)?.role))")
        await rescan()
        check("a vault read after it finds the one note", model.roles.filter { ["tester", "critic"].contains($0.name.lowercased()) }.map(\.name) == ["Critic"],
              "\(model.roles.map(\.name))")
        await UITest.endUndoGroup(model)
        model.changeRole("Critic") { $0.name = "Tester/2: draft" }
        check("a name keeps no slash or colon: it names a note", model.role(named: "Tester-2- draft") != nil && note("Tester-2- draft") != nil,
              "\(model.roles.map(\.name))")
        model.changeRole("Tester-2- draft") { $0.name = "Leader" }
        check("a rename onto another role's name is refused", model.role(named: "Tester-2- draft") != nil && note("Leader")?.body == leader.text + "\n")
        model.undoManager?.undo()
        model.undoManager?.undo()
        await expect("Undo renames it back", note("Tester") != nil && note("Critic") == nil && model.session(reviewing)?.role == "Tester",
                     "\(model.roles.map(\.name)) \(String(describing: model.session(reviewing)?.role))")

        // Delete sends the note to the Trash; Undo brings it back.
        await UITest.endUndoGroup(model)
        model.deleteRole("Tester")
        check("Delete moves the role's note to the Trash; its sessions keep the name, not the chip", note("Tester") == nil && model.role(named: "Tester") == nil
              && model.session(reviewing)?.role == "Tester")
        await rescan()
        check("and a vault read doesn't bring it back", model.role(named: "Tester") == nil)
        model.undoManager?.undo()
        await expect("Undo brings the note back, with the chip", note("Tester")?.body == "Read the whole diff.\n" && model.role(named: "Tester") != nil)

        // New Role and Restore Default.
        await UITest.endUndoGroup(model)
        let made = model.newRole(named: "Scout", color: .mint, line: "Writes the plan.", text: "Plan first.")
        let again = model.newRole(named: "Scout")
        check("New Role writes its note, under a name no role has", made.name == "Scout" && again.name == "Scout 2"
              && note("Scout")?.string("color") == "mint" && note("Scout")?.string("line") == "Writes the plan." && note("Scout")?.body == "Plan first.\n"
              && note("Scout 2") != nil && !(note("Scout 2")?.has("line") ?? true), "\(made.name), \(again.name)")
        model.changeRole("Leader") { $0.text = "Lead, my way." }
        check("a shipped role's text changed: Restore Default shows", model.role(named: "Leader").map(model.isChangedDefault) == true && note("Leader")?.body == "Lead, my way.\n")
        model.restoreDefault("Leader")
        check("Restore Default writes its shipped text back", note("Leader")?.body == leader.text + "\n" && model.role(named: "Leader").map(model.isChangedDefault) == false)

        // Written once: a shipped role the user deleted stays deleted.
        try? FileManager.default.removeItem(at: url("Builder"))
        await rescan()
        model.writeShippedRoles()
        check("a shipped role is written once: deleted, it isn't written again", note("Builder") == nil && model.role(named: "Builder") == nil,
              "\(model.roles.map(\.name))")
        model.newRole(named: "Builder")
        model.restoreDefault("Builder")
        check("New Role “Builder” and Restore Default bring it back", note("Builder")?.body == RoleItem.builderText + "\n" && note("Builder")?.string("color") == "brown"
              && model.roles.prefix(2).map(\.name) == ["Leader", "Builder"], "\(model.roles.map(\.name))")

        await workerMigrationChecks(model, url: url, note: note, rescan: rescan)

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
        check("the shipped texts name only commands and options hq has", unknown.isEmpty, unknown.joined(separator: ", "))

        await startTextChecks(model)

        // A checkbox in a role's text ticks in place, one Undo, as a description's (T-469 item 8).
        await UITest.endUndoGroup(model)
        model.changeRole("Tester") { $0.text = "- [ ] Read the diff\n- [ ] Run it" }
        await UITest.endUndoGroup(model)
        model.toggleRoleCheckbox("Tester", at: 1)
        await UITest.endUndoGroup(model)
        check("a checkbox in a role's text ticks in place", model.role(named: "Tester")?.text == "- [ ] Read the diff\n- [x] Run it",
              model.role(named: "Tester")?.text ?? "no role")
        model.undoManager?.undo()
        check("and Undo unticks it", model.role(named: "Tester")?.text == "- [ ] Read the diff\n- [ ] Run it", model.role(named: "Tester")?.text ?? "no role")
        // A notification's text: inline marks only; tooltips and banners without them (item 8).
        check("a notification's text drops its marks where it can't draw them",
              MarkdownLine.plain("Retry **budget** in `cli`, see [the plan](https://example.com) and _why_") == "Retry budget in cli, see the plan and why",
              MarkdownLine.plain("Retry **budget** in `cli`, see [the plan](https://example.com) and _why_"))

        // Leave the vault as the other checks had it.
        for name in ["Tester", "Scout", "Scout 2"] { model.deleteRole(name) }
        model.sessions.removeAll { $0.id == reviewing }
    }

    /// Worker became Builder, once per vault: the Worker note HQ wrote is renamed, its text and line updated where they were
    /// Worker's shipped ones; one the user deleted leaves Builder deleted; a Builder of the user's leaves both alone; a Worker
    /// note still in iCloud makes Builder wait.
    private static func workerMigrationChecks(_ model: AppModel, url: (String) -> URL, note: (String) -> FrontMatter?, rescan: () async -> Void) async {
        let key = "roles.shipped"
        let shippedBefore = Prefs.defaults.stringArray(forKey: key) ?? []
        let workerPath = url("Worker").path, builderPath = url("Builder").path
        let placeholder = url("Worker").deletingLastPathComponent().appending(path: ".Worker.md.icloud")
        guard let builder = RoleItem.shipped(named: "Builder") else { return check("Builder ships with HQ", false) }
        let session = "7e1e0000-0000-4000-8000-0000000000c1"
        func shipped() -> Set<String> { Set(Prefs.defaults.stringArray(forKey: key) ?? []) }
        // A vault from before the rename: Worker written by HQ (with this text and line, or deleted), Builder never.
        func vaultBefore(worker text: String?, line: String = RoleItem.workerLines[0], builderOfTheUser: String? = nil) async {
            for name in ["Builder", "Worker"] { try? FileManager.default.removeItem(at: url(name)) }
            if let text {
                try? "---\ncolor: brown\nline: \(line)\nmodel: opus\neffort: high\n---\n\(text)\n".write(to: url("Worker"), atomically: true, encoding: .utf8)
            }
            if let builderOfTheUser {
                try? "---\ncolor: green\nline: Mine.\n---\n\(builderOfTheUser)\n".write(to: url("Builder"), atomically: true, encoding: .utf8)
            }
            Prefs.defaults.set(shipped().subtracting([builderPath]).union([workerPath]).sorted(), forKey: key)
            model.put(SessionItem(id: session, customName: "Migrated worker", status: SessionStatus(state: .idle, since: .now), cwd: NSTemporaryDirectory(),
                                  repo: "roles", branch: "main", started: .now, order: model.session(session)?.order ?? model.nextGridOrder, role: "Worker"))
            await rescan()
        }

        await vaultBefore(worker: RoleItem.workerTexts[0])
        check("a Worker note HQ wrote at v14, unchanged, becomes Builder: Builder's text and line, its sessions with it",
              note("Worker") == nil && note("Builder")?.body == builder.text + "\n" && note("Builder")?.string("line") == builder.line
              && model.role(named: "Worker") == nil && model.role(named: "Builder").map { !model.isChangedDefault($0) && $0.builtin } == true
              && model.session(session)?.role == "Builder" && shipped().contains(builderPath),
              "\(model.roles.map(\.name)) \(note("Builder")?.text.prefix(120) ?? "no Builder note")")
        await rescan()
        check("and it runs once: a vault read after it leaves Builder as it is", note("Builder")?.body == builder.text + "\n" && note("Worker") == nil)

        await vaultBefore(worker: "Report to me at each step.")
        check("a Worker whose text the user changed becomes Builder with their text, Builder's line, and Restore Default offered",
              note("Worker") == nil && note("Builder")?.body == "Report to me at each step.\n" && note("Builder")?.string("line") == builder.line
              && model.role(named: "Builder").map(model.isChangedDefault) == true && model.session(session)?.role == "Builder",
              note("Builder")?.text ?? "no Builder note")

        await vaultBefore(worker: RoleItem.workerTexts[3], line: "My line.")
        check("a line the user changed stays theirs; an unchanged v16 text takes Builder's",
              note("Builder")?.string("line") == "My line." && note("Builder")?.body == builder.text + "\n", note("Builder")?.text ?? "no Builder note")

        await vaultBefore(worker: nil)
        check("Worker deleted by the user: Builder counts as deleted, not written", note("Builder") == nil && model.role(named: "Builder") == nil
              && shipped().contains(builderPath), "\(model.roles.map(\.name))")
        await rescan()
        check("and stays deleted at the next vault read", note("Builder") == nil && model.role(named: "Builder") == nil)

        await vaultBefore(worker: RoleItem.workerTexts[3], builderOfTheUser: "My own builder.")
        check("a Builder note of the user's: both stay as they are", note("Builder")?.body == "My own builder.\n" && note("Builder")?.string("line") == "Mine."
              && note("Worker")?.body == RoleItem.workerTexts[3] + "\n" && model.session(session)?.role == "Worker" && model.role(named: "Worker") != nil,
              "\(model.roles.map(\.name))")

        try? "".write(to: placeholder, atomically: true, encoding: .utf8)
        await vaultBefore(worker: nil)
        check("a Worker note still in iCloud: Builder waits, nothing written or recorded", note("Builder") == nil && !shipped().contains(builderPath),
              "\(model.roles.map(\.name))")

        // Leave the vault as the other checks had it: Builder shipped and as it ships, no Worker.
        try? FileManager.default.removeItem(at: placeholder)
        for name in ["Builder", "Worker"] { try? FileManager.default.removeItem(at: url(name)) }
        Prefs.defaults.set(shippedBefore, forKey: key)
        await rescan()
        model.newRole(named: "Builder")
        model.restoreDefault("Builder")
        model.sessions.removeAll { $0.id == session }
    }

    /// T-413: HQ's line, who started the session, and its role's text, at every SessionStart; cut to stay whole under the cap.
    private static func startTextChecks(_ model: AppModel) async {
        let lead = "7e1e0000-0000-4000-8000-0000000000b1", worker = "7e1e0000-0000-4000-8000-0000000000b2"
        let cleared = "7e1e0000-0000-4000-8000-0000000000b3", pid: Int32 = 999_911
        model.put(SessionItem(id: lead, customName: "registry: ready for more customers", status: SessionStatus(state: .idle, since: .now),
                              cwd: NSTemporaryDirectory(), repo: "roles", branch: "main", started: .now, order: model.nextGridOrder, role: "Leader"))
        model.put(SessionItem(id: worker, customName: "T-61 Retry budget", status: SessionStatus(state: .idle, since: .now), cwd: NSTemporaryDirectory(),
                              repo: "roles", branch: "main", started: .now, pid: pid, order: model.nextGridOrder, parent: lead, role: "Builder"))
        func start(_ id: String, _ source: String, pid: Int32? = nil) -> String {
            var args = ["event": "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"\(id)\",\"cwd\":\"\(NSTemporaryDirectory())\",\"source\":\"\(source)\"}"]
            if let pid { args["pid"] = "\(pid)" }
            return agent("hook", args)["context"] as? String ?? ""
        }
        let worker0 = start(worker, "startup")
        check("a Builder's start text: HQ tracks it, its leader by name and how to message it, then its role's text",
              worker0.hasPrefix("HQ tracks this session.") && worker0.contains("The session “registry: ready for more customers” (Leader) started this one: this session reports to it.")
              && worker0.contains("SendMessage, to “registry: ready for more customers”") && worker0.contains("Load the hq skill")
              && worker0.contains("This session's role is Builder: \(RoleItem.shipped(named: "Builder")?.line ?? "-") Its text, from HQ:\n\n" + RoleItem.builderText)
              && worker0.hasSuffix(RoleItem.builderText), worker0)
        let lead0 = start(lead, "startup")
        check("a Leader's start text says it started sessions that report to it, and has the Leader's text",
              lead0.contains("This session started 1 session that reports to it") && lead0.contains(RoleItem.leaderText) && !lead0.contains("started this one"), lead0)
        var missed: [String] = []
        for source in ["resume", "compact", "fork"] where !start(worker, source).contains(RoleItem.builderText) { missed.append(source) }
        model.changeRole("Builder") { $0.text = "Report at each step." }
        if !start(worker, "compact").hasSuffix("Report at each step.") { missed.append("compact after an edit") }
        model.restoreDefault("Builder")
        // After /clear the new id keeps the role: same process, a new session id.
        let source = DispatchSource.makeProcessSource(identifier: getpid(), eventMask: .exit, queue: .main)
        source.resume()
        model.exitWatchers[pid] = source
        if !start(cleared, "clear", pid: pid).contains(RoleItem.builderText) { missed.append("clear") }
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
            model.addTask(status: .todo, title: "A long task title, as the user writes them sometimes, for step \(index) of the story", session: "7e1e0000-0000-4000-8000-0000000000b4")?.id
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
