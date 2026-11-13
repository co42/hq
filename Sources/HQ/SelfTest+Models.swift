import AppKit
import HQKit

/// v15: a session's model, effort and context (T-446, T-475).
extension SelfTest {
    static func modelChecks(_ model: AppModel) async {
        let lead = "5e1f0446-0000-4000-8000-000000000001"
        let folder = NSTemporaryDirectory()
        model.put(SessionItem(id: lead, customName: "Model lead", status: SessionStatus(state: .idle, since: .now), cwd: folder, repo: "hq", branch: "main",
                              started: .now, tty: "/dev/ttys046", order: model.nextGridOrder, role: "Leader"))
        defer { model.sessions.removeAll { $0.id == lead || $0.parent == lead } }

        // Shipped defaults: Leader on Opus, very high; Worker on Opus, high.
        check("Leader and Worker ship on Opus, very high and high", model.role(named: "Leader").map { ($0.model, $0.effort) } ?? (nil, nil) == ("opus", "xhigh")
              && model.role(named: "Worker").map { ($0.model, $0.effort) } ?? (nil, nil) == ("opus", "high"))

        // hq session new: its role's model and effort by default, or what it says.
        let worker = agent("session new", ["name": "Model worker", "role": "Worker", "_session": lead])
        check("session new starts on its role's model and effort", model.ghosttyLog.last?.contains("--model 'opus' --effort 'high'") == true
              && (worker["started"] as? String)?.contains("on Opus high") == true, model.ghosttyLog.last ?? "-")
        _ = agent("session new", ["name": "Model trivial", "role": "Worker", "model": "sonnet", "effort": "medium", "_session": lead])
        check("--model and --effort win over the role's", model.ghosttyLog.last?.contains("--model 'sonnet' --effort 'medium'") == true, model.ghosttyLog.last ?? "-")
        let bad = agent("session new", ["name": "Model bad", "effort": "huge", "_session": lead])
        check("an effort Claude Code doesn't take is refused", bad["ok"] as? Bool == false && "\(bad["error"] ?? "")".contains("xhigh"), "\(bad)")

        // Start a Session: the role's, until the user picks.
        model.beginStart(parent: lead)
        model.setStartRole("Leader")
        check("Start a Session takes its role's model and effort", model.startDraft?.model == "opus" && model.startDraft?.effort == "xhigh")
        model.startDraft?.effort = "low"
        model.startDraft?.modelChosen = true
        model.setStartRole("Worker")
        check("and keeps the ones the user picked", model.startDraft?.effort == "low")
        model.closeModal()

        // Its last reply says what it runs on and what its context holds.
        let path = folder + "model-transcript-\(UUID().uuidString).jsonl"
        let reply = #"{"type":"assistant","effort":"xhigh","message":{"model":"claude-opus-5-5","usage":{"input_tokens":2,"cache_creation_input_tokens":1032,"cache_read_input_tokens":440864,"output_tokens":143}}}"#
        try? (reply + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        _ = agent("hook", ["event": "{\"hook_event_name\":\"Stop\",\"session_id\":\"\(lead)\",\"cwd\":\"\(folder)\",\"transcript_path\":\"\(path)\"}"])
        let read = model.session(lead)
        check("a reply's model, effort and context reach its card (T-475)", read?.model == "claude-opus-5-5" && read?.effort == "xhigh"
              && read?.contextTokens == 442_041 && read?.modelLine == "Opus VH · 442k", "\(read?.modelLine ?? "-")")

        // Model ▸ and Effort ▸: typed in its terminal while it waits for its next message, never while it works.
        model.changeRun(lead, model: "sonnet")
        check("Model ▸ types /model in its terminal, its input emptied first", model.ghosttyLog.last == "clear the input, then type /model sonnet in /dev/ttys046"
              && model.session(lead)?.model == "sonnet", model.ghosttyLog.last ?? "-")
        // The transcript changes (the command's own line): its last reply is older, HQ's change stays until a newer one.
        _ = agent("hook", ["event": "{\"hook_event_name\":\"Stop\",\"session_id\":\"\(lead)\",\"cwd\":\"\(folder)\",\"transcript_path\":\"\(path)\"}"])
        check("a reply older than the change doesn't undo it", model.session(lead)?.model == "sonnet", model.session(lead)?.model ?? "-")
        let newer = #"{"type":"assistant","effort":"xhigh","timestamp":""# + Date.now.addingTimeInterval(1).formatted(.iso8601) + #"","message":{"model":"claude-sonnet-5-5","usage":{"input_tokens":5}}}"#
        try? (reply + "\n" + newer + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        _ = agent("hook", ["event": "{\"hook_event_name\":\"Stop\",\"session_id\":\"\(lead)\",\"cwd\":\"\(folder)\",\"transcript_path\":\"\(path)\"}"])
        check("a reply after it says what it runs on again", model.session(lead)?.model == "claude-sonnet-5-5" && model.session(lead)?.runChangedAt == nil,
              model.session(lead)?.model ?? "-")
        if var item = model.session(lead) {
            item.live.apply(HookEvent(name: "UserPromptSubmit", sessionID: lead), now: .now)
            model.put(item)
        }
        let log = model.ghosttyLog.count
        model.changeRun(lead, effort: "low")
        check("never while it works", model.ghosttyLog.count == log && model.session(lead)?.effort == "xhigh", model.ghosttyLog.last ?? "-")

        // hq role edit: --model and --effort, none for Claude Code's own.
        _ = agent("role edit", ["role": "Worker", "model": "sonnet", "effort": "low"])
        let edited = model.role(named: "Worker")
        _ = agent("role edit", ["role": "Worker", "model": "none", "effort": "none"])
        let cleared = model.role(named: "Worker")
        model.restoreDefault("Worker")
        check("role edit sets a role's model and effort, none clears them", edited?.model == "sonnet" && edited?.effort == "low"
              && cleared?.model == nil && cleared?.effort == nil && model.role(named: "Worker")?.effort == "high")
    }
}
