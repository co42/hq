import Foundation
import HQKit

// Teams and roles for sessions (T-407, T-414): `session new` under a parent, with a role and another's history;
// `session edit --parent`; `ls sessions --tree`; `ls roles`; `role show | new | edit | delete`.
extension AgentCommands {
    static let roleOutput = "{name, color, line, model, effort, builtin, changed, sessions: [session id], path}"

    static func newSessionCommand(_ args: Args, _ model: AppModel) throws -> Any {
        var task: TaskItem?
        if let ref = args.string("task") {
            guard let found = model.task(TaskItem.key(ref)) else { throw AgentError.notFound("no task \(ref). Run `hq ls tasks`") }
            task = found
        }
        let caller = model.session(args.string(sessionArg))
        let beside = try args.bool("beside") == true
        if beside, args.string("parent") != nil { throw AgentError.usage("--beside and --parent each say where it goes: give one") }
        var parent: SessionItem?
        if let ref = args.string("parent") {
            parent = try ref.trimmingCharacters(in: .whitespaces).lowercased() == "none" ? nil : findSession(ref, model, for: "--parent")
        } else if beside {
            guard let caller else { throw AgentError.usage("--beside puts it at this session's level: run it from a Claude session, or give --parent") }
            parent = model.parentSession(of: caller.id)
        } else {
            parent = caller
        }
        let role = try args.string("role").map { try findRole($0, model).name }
        let history = try args.string("history").map { try findSession($0, model, for: "--history") }
        let fallback = [history?.cwd, caller?.cwd].compactMap { $0 }.first { !$0.isEmpty } ?? args.string(cwdArg)
        guard let directory = args.string("cwd").map({ ($0 as NSString).expandingTildeInPath }) ?? fallback else {
            throw AgentError.usage("name a directory with --cwd")
        }
        guard FileManager.default.fileExists(atPath: (directory as NSString).expandingTildeInPath) else { throw AgentError.notFound("no directory \(directory)") }
        let name = try args.required("name").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AgentError.usage("give the session a name") }
        let message = args.string("message") ?? task.map { AppModel.taskPrompt($0) } ?? ""
        let window = model.windowTTY(forChildOf: parent?.id)
        let roleItem = model.role(named: role)
        let effort = args.string("effort")?.lowercased() ?? roleItem?.effort
        if let effort, !ClaudeModel.efforts.contains(effort) {
            throw AgentError.usage("--effort \(effort): one of \(ClaudeModel.efforts.joined(separator: ", "))")
        }
        let id = model.startSession(named: name, in: directory, task: task?.id, message: message, parent: parent?.id, role: role, history: history?.id,
                                    model: args.string("model") ?? roleItem?.model, effort: effort)
        var json = model.session(id)?.agentJSON(model) ?? ["id": id]
        var started = window != nil ? "a new tab in the Ghostty window of “\(parent?.name ?? "")”" : "a new Ghostty tab in \(directory)"
        if let parent { started += parent.id == caller?.id ? ", under this session: it reports to you" : ", under “\(parent.name)”" }
        if let role { started += ", as \(role)" }
        if let picked = model.session(id)?.model { started += ", on \(ClaudeModel.family(picked))\(effort.map { " \(ClaudeModel.effortTitle($0).lowercased())" } ?? "")" }
        if let history { started += ", with the conversation of “\(history.name)”" }
        json["started"] = started
        return json
    }

    static func editSessionCommand(_ args: Args, _ model: AppModel) throws -> Any {
        let session = try findSession(args.required("session"), model, for: "<session>")
        guard let ref = args.string("parent") else { throw AgentError.usage("say what to change: --parent <session>, or --parent none. Example: hq session edit 41ccc6 --parent 8092a3") }
        let target = try ref.trimmingCharacters(in: .whitespaces).lowercased() == "none" ? nil : findSession(ref, model, for: "--parent")
        let tree = model.sessionTree
        if let target, !tree.canMove(session.id, under: target.id) {
            throw AgentError.invalid(target.id == session.id ? "a session can't go under itself"
                                     : "“\(target.name)” is in the team of “\(session.name)”: a session never goes under its own team")
        }
        var json: JSONObject
        if tree.parent(of: session.id) == target?.id {
            json = session.agentJSON(model)
            json["note"] = "Nothing changed: it's \(target.map { "under “\($0.name)”" } ?? "at the top level") already"
            return json
        }
        model.setParent(session.id, to: target?.id)
        json = model.session(session.id)?.agentJSON(model) ?? [:]
        json["note"] = target.map { "Moved under “\($0.name)”" } ?? "Moved to the top level"
        return json
    }

    /// A session by its id, the start of it (6 characters or more), or its name. Not found: the error lists the open ones.
    static func findSession(_ raw: String, _ model: AppModel, for option: String) throws -> SessionItem {
        let ref = raw.trimmingCharacters(in: .whitespaces)
        if let found = model.session(ref) ?? (ref.count >= 6 ? model.session(prefix: ref) : nil) { return found }
        let named = model.sessions.filter { $0.name.caseInsensitiveCompare(ref) == .orderedSame }
        let open = named.filter { $0.closedAt == nil }
        if open.count == 1 { return open[0] }
        if open.isEmpty, named.count == 1 { return named[0] }
        let recent = model.gridSessions.sorted { model.lastActivity($0) > model.lastActivity($1) }
        let some = recent.prefix(10).map { "\($0.id.prefix(8)) \($0.name)" }
        let more = recent.count > some.count ? ", and \(recent.count - some.count) more" : ""
        let which = named.count > 1 ? "\(named.count) sessions are named \(ref): give its id" : "no session \(ref)"
        throw AgentError.notFound("\(option): \(which). Open sessions: " + (some.isEmpty ? "none" : some.joined(separator: "; ") + more) + " (hq ls sessions --tree)")
    }

    /// A role by its name, case ignored. Not found: the error lists the roles.
    static func findRole(_ raw: String, _ model: AppModel) throws -> RoleItem {
        let ref = raw.trimmingCharacters(in: .whitespaces)
        if let role = model.role(named: ref) { return role }
        let names = model.roles.map(\.name).joined(separator: ", ")
        throw AgentError.notFound("no role \(ref). " + (names.isEmpty ? "No roles yet: hq role new \"Name\" makes one" : "Roles: \(names) (hq ls roles)"))
    }

    // MARK: Roles

    static func roleShowCommand(_ args: Args, _ model: AppModel) throws -> Any {
        let role = try findRole(args.required("role"), model)
        var json = role.agentJSON(model)
        json["body"] = role.text
        let users = model.sessions(withRole: role.name)
        var text = [role.summaryLine(model), role.line.isEmpty ? "No line yet." : role.line, "", role.text.isEmpty ? "(no text yet)" : role.text]
        if !users.isEmpty {
            text += ["", "Used by:"] + users.map { "  \($0.id.prefix(8)) [\($0.status.title.lowercased())] \($0.name)" }
        }
        // `text` is the role's, as `role edit --body` takes it: show then edit gives the same role back.
        json["text"] = role.text
        json["printed"] = text.joined(separator: "\n")
        return json
    }

    static func roleNewCommand(_ args: Args, _ model: AppModel) throws -> Any {
        let name = try roleName(args.required("name"))
        if let other = model.role(named: name) { throw AgentError.invalid("a role \(other.name) exists: hq role edit \(other.name) changes it") }
        let color = try roleColor(args)
        let run = try roleRun(args)
        let role = model.newRole(named: name, color: color, line: oneLine(args.string("line") ?? ""), text: (args.string("body") ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        if run.model != nil || run.effort != nil {
            model.changeRole(role.name) { item in (item.model, item.effort) = (run.model.flatMap { $0.isEmpty ? nil : $0 }, run.effort.flatMap { $0.isEmpty ? nil : $0 }) }
        }
        guard model.role(named: role.name) != nil else { throw AgentError.invalid("the role's note couldn't be written: HQ's log says why") }
        var json = role.agentJSON(model)
        json["text"] = "Made role \(role.summaryLine(model)). Sessions get its text with hq session new --role \(role.name)"
        return json
    }

    static func roleEditCommand(_ args: Args, _ model: AppModel) throws -> Any {
        let role = try findRole(args.required("role"), model)
        let name = try args.string("name").map(roleName)
        let color = try roleColor(args)
        let line = args.string("line").map(oneLine)
        let body = args.string("body").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let run = try roleRun(args)
        guard name != nil || color != nil || line != nil || body != nil || run.model != nil || run.effort != nil else {
            throw AgentError.usage("say what to change: --name, --line, --color, --model, --effort or --body. Example: hq role edit Reviewer --line \"Reviews one PR\"")
        }
        if let name, name.caseInsensitiveCompare(role.name) != .orderedSame, let other = model.role(named: name) {
            throw AgentError.invalid("a role \(other.name) exists: pick another name")
        }
        model.changeRole(role.name) { item in
            if let name { item.name = name }
            if let color { item.color = color }
            if let line { item.line = line }
            if let body { item.text = body }
            if let picked = run.model { item.model = picked.isEmpty ? nil : picked }
            if let effort = run.effort { item.effort = effort.isEmpty ? nil : effort }
        }
        let now = model.role(named: name ?? role.name) ?? role
        let changed = [("name", now.name != role.name), ("color", now.color != role.color), ("line", now.line != role.line), ("text", now.text != role.text),
                       ("model", now.model != role.model), ("effort", now.effort != role.effort)]
            .filter(\.1).map(\.0)
        var json = now.agentJSON(model)
        json["text"] = changed.isEmpty ? "Nothing changed: role \(now.name) has that already" : "Changed role \(now.name): " + changed.joined(separator: ", ")
            + (changed.contains("text") ? ". Its sessions get it when they next start, resume or compact" : "")
        return json
    }

    static func roleDeleteCommand(_ args: Args, _ model: AppModel) throws -> Any {
        let role = try findRole(args.required("role"), model)
        let users = model.sessions(withRole: role.name).count
        let kept = users == 0 ? "" : " \(users) open session\(users == 1 ? " has" : "s have") it: \(users == 1 ? "it keeps" : "they keep") the text \(users == 1 ? "it" : "they") started with."
        guard args.confirmed else { return ["wouldDelete": role.name, "text": "Would delete role \(role.name): its note goes to the Trash.\(kept) Again with --yes to delete."] }
        model.deleteRole(role.name)
        return ["deleted": role.name, "text": "Deleted role \(role.name): its note is in the Trash.\(kept)"]
    }

    /// --model and --effort: nil when not given, "" for none (Claude Code's own); an effort it doesn't take is refused.
    private static func roleRun(_ args: Args) throws -> (model: String?, effort: String?) {
        let picked = args.string("model").map { $0.lowercased() == "none" ? "" : $0 }
        let effort = try args.string("effort").map { raw -> String in
            let effort = raw.lowercased()
            guard effort == "none" || ClaudeModel.efforts.contains(effort) else {
                throw AgentError.usage("--effort \(raw): one of \(ClaudeModel.efforts.joined(separator: ", ")), or none")
            }
            return effort == "none" ? "" : effort
        }
        return (picked, effort)
    }

    /// A role's name names its note: no slash or colon.
    private static func roleName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RoleItem.clean(name) == name, !name.isEmpty else { throw AgentError.usage("a role's name is its note's: no /, : or leading dot (\(raw))") }
        return name
    }

    private static func roleColor(_ args: Args) throws -> LabelColor? {
        try args.string("color").map { raw in
            guard let color = LabelColor(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased()) else {
                throw AgentError.usage("no color \(raw). Colors: " + LabelColor.allCases.map(\.rawValue).joined(separator: ", "))
            }
            return color
        }
    }

    private static func oneLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: Teams in lists

    /// `ls sessions --tree`: the top-level sessions, each with its team under it, depth first; with --all, closed ones too.
    static func treeRows(_ model: AppModel, all: Bool) -> [(session: SessionItem, depth: Int)] {
        let tree = all ? everyTeam(model) : model.sessionTree
        return tree.roots.flatMap { root in
            [(root, 0)] + tree.rows(under: root).map { ($0.id, $0.depth) }
        }.compactMap { id, depth in model.session(id).map { (session: $0, depth: depth) } }
    }

    /// Every session HQ remembers in its team, closed ones too.
    private static func everyTeam(_ model: AppModel) -> SessionTree {
        SessionTree(model.sessions.map { SessionTree.Node(id: $0.id, parent: $0.parent, order: $0.order, started: $0.started) })
    }

    /// `hq ctx`'s team: who started this session, and the sessions it started, with their role, state and task.
    static func teamContext(_ session: SessionItem, _ model: AppModel) -> (started: [String], team: [String], json: JSONObject) {
        var started: [String] = [], team: [String] = []
        var json: JSONObject = [:]
        if let parent = model.parentSession(of: session.id) {
            let role = model.role(named: parent.role).map { "\($0.name), " } ?? ""
            started.append("Started by: \(parent.name) (\(role)\(parent.status.title.lowercased())) · \(parent.id.prefix(8))"
                           + (parent.closedAt == nil ? ". You report to it: SendMessage, to “\(parent.name)”" : ""))
            json["startedBy"] = parent.agentJSON(model)
        }
        // Every session it started and theirs, closed ones too: a Leader resumes them (T-450).
        let rows = everyTeam(model).rows(under: session.id).compactMap { row in model.session(row.id).map { (session: $0, depth: row.depth) } }
        if !rows.isEmpty {
            let open = rows.filter { $0.session.closedAt == nil }.count
            let closed = rows.count - open
            team.append("Your sessions (\(open) open\(closed > 0 ? ", \(closed) closed: hq session resume brings one back" : ""), the open ones report to you):")
            team += rows.map { row in
                let item = row.session
                let role = model.role(named: item.role).map { " · \($0.name)" } ?? ""
                let tasks = model.tasks(of: item.id).filter { $0.status != .done }.map(\.key)
                let reason = item.closedAt == nil ? item.reason.map { " · \($0)" } ?? "" : ""
                let state = item.closedAt.map { "closed \(Elapsed.short(from: $0, to: model.now)) ago" } ?? item.status.title.lowercased()
                return String(repeating: "  ", count: row.depth) + "\(item.id.prefix(8)) [\(state)] \(item.name)\(role)"
                    + (tasks.isEmpty ? "" : " · " + tasks.joined(separator: ", ")) + reason
            }
            json["team"] = rows.map { row in
                var item = row.session.agentJSON(model)
                item["depth"] = row.depth
                return item
            }
        }
        return (started, team, json)
    }
}

extension RoleItem {
    func agentJSON(_ model: AppModel) -> JSONObject {
        var json: JSONObject = ["name": name, "color": color.rawValue, "line": line, "builtin": builtin,
                                "sessions": model.sessions(withRole: name).map(\.id)]
        if builtin { json["changed"] = model.isChangedDefault(self) }
        if let picked = self.model { json["model"] = picked }
        if let effort { json["effort"] = effort }
        if let path { json["path"] = path }
        return json
    }

    /// `Leader [indigo] · opus xhigh · ships with HQ, changed · 2 open sessions`.
    func summaryLine(_ model: AppModel) -> String {
        let users = model.sessions(withRole: name).count
        let shipped = builtin ? " · ships with HQ" + (model.isChangedDefault(self) ? ", changed" : "") : ""
        let run = [self.model, effort].compactMap(\.self).joined(separator: " ")
        return "\(name) [\(color.rawValue)]\(run.isEmpty ? "" : " · " + run)\(shipped) · \(users == 0 ? "no" : "\(users)") open session\(users == 1 ? "" : "s")"
    }
}
