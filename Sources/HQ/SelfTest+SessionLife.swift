import Foundation
import HQKit

extension SelfTest {
    /// A Leader closes and resumes its team through hq (T-450): session close and session resume act on the sessions under
    /// the caller, at any depth, and refuse anything else, naming it; ctx lists every session it started, closed ones too;
    /// ls sessions --tree --all shows closed ones in their teams.
    static func cliSessionLifeChecks(_ model: AppModel) async {
        func failure(_ result: JSONObject) -> (code: String, message: String)? {
            (result["error"] as? JSONObject).map { ($0["code"] as? String ?? "", $0["message"] as? String ?? "") }
        }
        let lead = "c1a00001-0000-4000-8000-000000000001", worker = "c1b00002-0000-4000-8000-000000000002"
        let helper = "c1c00003-0000-4000-8000-000000000003", asking = "c1d00004-0000-4000-8000-000000000004"
        let stranger = "c1e00005-0000-4000-8000-000000000005", ghost = "c1f00006-0000-4000-8000-000000000006"
        let folder = NSTemporaryDirectory()
        let people: [(String, String, String?, SessionState, Int32?, String?)] = [
            (lead, "Life lead", nil, .idle, 999_801, "/dev/ttys081"), (worker, "Life worker", lead, .working, 999_802, "/dev/ttys082"),
            (helper, "Life helper", worker, .idle, 999_803, "/dev/ttys083"), (asking, "Life asking", lead, .waiting(.question), 999_804, "/dev/ttys084"),
            (stranger, "Life stranger", nil, .idle, 999_805, "/dev/ttys085"), (ghost, "Life ghost", lead, .idle, nil, nil),
        ]
        for (id, name, parent, state, pid, tty) in people {
            var item = SessionItem(id: id, customName: name, status: SessionStatus(state: state, since: .now), cwd: folder, repo: "life", branch: "main",
                                   started: .now, pid: pid, tty: tty, order: model.nextGridOrder, parent: parent, role: parent == nil ? "Leader" : "Worker")
            // A session that ran has a conversation to resume; the ghost never reported.
            if pid != nil { item.transcriptPath = "/tmp/HQ-life-\(id).jsonl" }
            model.put(item)
        }
        @discardableResult
        func close(_ id: String, from caller: String? = lead) -> JSONObject {
            agent("session close", ["session": String(id.prefix(8))].merging(caller.map { ["_session": $0] } ?? [:]) { first, _ in first })
        }
        @discardableResult
        func resume(_ id: String, from caller: String? = lead) -> JSONObject {
            agent("session resume", ["session": String(id.prefix(8))].merging(caller.map { ["_session": $0] } ?? [:]) { first, _ in first })
        }

        // session close: as Close Session, Escape while it works, its input emptied, then /exit; nothing opens in front of the user.
        var log = model.ghosttyLog.count
        let closed = close(worker)
        check("session close on a session under the caller types /exit in its terminal, Escape and its input emptied first",
              model.ghosttyLog.count == log + 1 && model.ghosttyLog.last == "escape, then clear the input, then type /exit in /dev/ttys082"
              && (closed["note"] as? String)?.hasPrefix("Closing “Life worker”: Escape to stop its turn, then its input emptied and /exit typed") == true
              && (closed["note"] as? String)?.contains("hq session resume \(worker.prefix(8))") == true && model.modal == nil,
              "\(model.ghosttyLog.suffix(1)) \(closed)")
        model.processExited(999_802)
        check("once its Claude quits, its terminal closes and it's closed, its conversation kept for a resume",
              model.ghosttyLog.last == "close /dev/ttys082" && model.session(worker)?.closedAt != nil, model.ghosttyLog.last ?? "-")
        log = model.ghosttyLog.count
        close(helper)
        model.processExited(999_803)
        check("and at any depth: a session under one the caller started", model.ghosttyLog.count == log + 2
              && model.ghosttyLog[log] == "clear the input, then type /exit in /dev/ttys083" && model.session(helper)?.closedAt != nil, "\(model.ghosttyLog.suffix(2))")
        let gone = close(ghost)
        check("one that never started goes, with nothing to resume", model.session(ghost) == nil
              && (gone["note"] as? String)?.hasPrefix("“Life ghost” never started") == true, "\(gone)")

        // Every refusal, naming the session; nothing typed.
        log = model.ghosttyLog.count
        let waits = failure(close(asking))
        check("a session that waits on the user is refused, with the reason, and gets no keys", waits?.code == "invalid"
              && waits?.message.contains("“Life asking”") == true && waits?.message.contains("waits on the user") == true
              && model.ghosttyLog.count == log && model.session(asking)?.closedAt == nil, waits?.message ?? "-")
        let foreign = failure(close(stranger))
        check("a session not under the caller is refused, naming it and where it is", foreign?.code == "not_mine"
              && foreign?.message.hasPrefix("“Life stranger” (\(stranger.prefix(8))) isn't under this session: it's at the top level") == true, foreign?.message ?? "-")
        let mine = failure(close(lead))
        check("so is the caller itself", mine?.code == "not_mine" && mine?.message.contains("it's this session") == true, mine?.message ?? "-")
        let upward = failure(close(lead, from: helper))
        let sideways = failure(close(asking, from: worker))
        check("and the session above the caller, or beside it", upward?.code == "not_mine" && sideways?.code == "not_mine"
              && sideways?.message.contains("it's under “Life lead”") == true, "\(String(describing: upward)) \(String(describing: sideways))")
        check("without a calling session it's refused: it acts on that session's team", failure(close(asking, from: nil))?.code == "usage")
        let twice = failure(close(worker))
        check("one closed already is refused, saying how to resume it", twice?.code == "invalid"
              && twice?.message.contains("closed already: hq session resume \(worker.prefix(8))") == true, twice?.message ?? "-")
        check("an unknown session is refused, naming the open ones", failure(agent("session close", ["session": "nobody-at-all", "_session": lead]))?.code == "not_found")
        check("and nothing was typed for any of them", model.ghosttyLog.count == log && model.session(stranger)?.closedAt == nil && model.session(lead)?.closedAt == nil)

        // ctx: every session the caller started and theirs, closed ones too, since when.
        let context = agent("ctx", ["_session": lead])
        let text = context["text"] as? String ?? ""
        check("hq ctx lists every session it started, closed ones too, with how long since, role and state",
              text.contains("\n  \(worker.prefix(8)) [closed <1m ago] Life worker · Worker") && text.contains("\n    \(helper.prefix(8)) [closed <1m ago] Life helper · Worker")
              && text.contains("\n  \(asking.prefix(8)) [asks] Life asking · Worker") && text.contains("(1 open, 2 closed: hq session resume brings one back")
              && (context["team"] as? [JSONObject])?.contains { $0["id"] as? String == worker && $0["closed"] as? Bool == true && $0["closedAt"] != nil } == true, text)

        // ls sessions --tree --all: closed ones in their teams; without --all, not there.
        let all = agent("ls", ["kind": "sessions", "tree": "true", "all": "true"])
        let rows = (all["sessions"] as? [JSONObject] ?? []).map { ($0["id"] as? String ?? "", $0["depth"] as? Int ?? -1) }
        let at = rows.firstIndex { $0.0 == lead }
        check("ls sessions --tree --all shows closed ones in their teams, marked closed",
              at.map { rows.indices.contains($0 + 2) && rows[$0 + 1] == (worker, 1) && rows[$0 + 2] == (helper, 2) } == true
              && AgentCLI.human(all).contains("\n  \(worker.prefix(8)) [closed] Life worker · Worker"), "\(rows.filter { $0.0.hasPrefix("c1") })")
        let open = (agent("ls", ["kind": "sessions", "tree": "true"])["sessions"] as? [JSONObject] ?? []).compactMap { $0["id"] as? String }
        check("and without --all, only the open ones", !open.contains(worker) && open.contains(asking))

        // session resume: a new tab in its parent's Ghostty window, its place in the team kept.
        let order = model.session(worker)?.order
        log = model.ghosttyLog.count
        let resumed = resume(worker)
        check("session resume opens claude --resume in a new tab of its parent's Ghostty window, its place in the team kept",
              model.ghosttyLog.count == log + 1 && model.ghosttyLog.last == "new tab in the window of /dev/ttys081, in \(folder): claude --resume \(worker)"
              && model.session(worker)?.closedAt == nil && model.session(worker)?.order == order && model.session(worker)?.parent == lead
              && (resumed["note"] as? String)?.hasPrefix("Resuming “Life worker”: claude --resume in a new tab of its parent's Ghostty window") == true,
              "\(model.ghosttyLog.suffix(1)) \(resumed)")
        log = model.ghosttyLog.count
        let running = failure(resume(asking))
        check("resuming one that runs is refused", running?.code == "invalid" && running?.message.contains("is running: nothing to resume") == true, running?.message ?? "-")
        if var item = model.session(stranger) {
            item.closedAt = .now
            item.status = SessionStatus(state: .ended, since: .now)
            model.put(item)
        }
        check("resuming one not under the caller is refused, naming it", failure(resume(stranger))?.code == "not_mine")
        check("and without a calling session", failure(resume(helper, from: nil))?.code == "usage")
        check("and nothing opened for any of them", model.ghosttyLog.count == log && model.session(stranger)?.closedAt != nil)

        // hq help: both commands, with the shape of their JSON.
        let commands = ["session close", "session resume"].compactMap { name in AgentCommands.all.first { $0.name == name } }
        check("hq help has session close and session resume, each with its JSON", commands.count == 2 && commands.allSatisfy { AgentCLI.usage($0).contains("\nJSON: {") })

        model.sessions.removeAll { [lead, worker, helper, asking, stranger, ghost].contains($0.id) }
    }
}
