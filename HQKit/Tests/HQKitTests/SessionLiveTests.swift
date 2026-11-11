import Foundation
import Testing
@testable import HQKit

/// Hook events as Claude Code sends them (code.claude.com/docs/en/hooks): its common fields, and `agent_id` and
/// `agent_type` on events that fire inside a subagent.
enum HookFixture {
    static let session = "8c1e4f2a-5b7d-4e19-9a3c-2f6b8d0e1a47"
    static let transcript = "/Users/me/.claude/projects/-Users-me-code-registry/8c1e4f2a-5b7d-4e19-9a3c-2f6b8d0e1a47.jsonl"
    /// A subagent's id, as Claude Code names its transcript (`subagents/agent-<id>.jsonl`).
    static let agent = "a30b76807c386c37b"
    static let otherAgent = "ad533424ac1f40667"

    static func common(_ name: String, agent: String? = nil) -> String {
        var fields = #""session_id":"\#(session)","transcript_path":"\#(transcript)","cwd":"/Users/me/code/registry","#
            + #""permission_mode":"default","hook_event_name":"\#(name)","prompt_id":"550e8400-e29b-41d4-a716-446655440000""#
        if let agent { fields += #","agent_id":"\#(agent)","agent_type":"general-purpose""# }
        return fields
    }

    static func event(_ json: String, at: Date? = nil) -> HookEvent {
        var event = HookEvent(json: Data(json.utf8), pid: 4242, tty: "/dev/ttys012", inGhostty: true)!
        event.at = at
        return event
    }

    static func sessionStart(source: String) -> String {
        #"{\#(common("SessionStart")),"source":"\#(source)","model":"claude-opus-5-5"}"#
    }
    static let prompt = #"{\#(common("UserPromptSubmit")),"prompt":"Add retries to the push path"}"#
    static let question = #"{\#(common("PreToolUse")),"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Redis or Postgres?","header":"Store","multiSelect":false,"options":[{"label":"Redis","description":"Fast"},{"label":"Postgres","description":"Durable"}]}]},"tool_use_id":"toolu_01Q","effort":{"level":"high"}}"#
    static let questionAnswered = #"{\#(common("PostToolUse")),"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Redis or Postgres?"}]},"tool_response":{"answers":{"Redis or Postgres?":"Redis"}},"tool_use_id":"toolu_01Q","duration_ms":41250}"#
    static let plan = #"{\#(common("PreToolUse")),"tool_name":"ExitPlanMode","tool_input":{"plan":"1. Retry budget","planFilePath":"/Users/me/.claude/plans/retry.md"},"tool_use_id":"toolu_01P"}"#
    static func permission(agent: String? = nil) -> String {
        #"{\#(common("PermissionRequest", agent: agent)),"tool_name":"Bash","tool_input":{"command":"kubectl rollout restart deploy/api","description":"Restart the API"},"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"kubectl rollout restart:*"}],"behavior":"allow","destination":"localSettings"}]}"#
    }
    static let permissionPrompt = #"{\#(common("Notification")),"message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}"#
    static let elicitation = #"{\#(common("Elicitation")),"mcp_server_name":"linear","message":"Pick a team","mode":"form"}"#
    static func toolDone(_ tool: String = "Read", agent: String? = nil) -> String {
        #"{\#(common("PostToolUse", agent: agent)),"tool_name":"\#(tool)","tool_input":{"file_path":"/Users/me/code/registry/push.go"},"tool_response":{"type":"text","file":{"filePath":"/Users/me/code/registry/push.go","numLines":120}},"tool_use_id":"toolu_01R","duration_ms":12,"effort":{"level":"high"}}"#
    }
    static func toolFailed(agent: String? = nil) -> String {
        #"{\#(common("PostToolUseFailure", agent: agent)),"tool_name":"Bash","tool_input":{"command":"go test ./...","description":"Run tests"},"tool_use_id":"toolu_01F","error":"Exit code 1","is_interrupt":false,"duration_ms":4187}"#
    }
    static let stop = #"{\#(common("Stop")),"stop_hook_active":false,"last_assistant_message":"Retries are in. Tests pass."}"#
    static let stopFailure = #"{\#(common("StopFailure")),"error":"rate_limit","last_assistant_message":"API Error: 429"}"#
    static let preCompact = #"{\#(common("PreCompact")),"trigger":"auto","custom_instructions":""}"#
    static let postCompact = #"{\#(common("PostCompact")),"trigger":"auto"}"#
    static func sessionEnd(reason: String) -> String { #"{\#(common("SessionEnd")),"reason":"\#(reason)"}"# }
}

@Test func everyFixtureParsesAndSaysItsThread() throws {
    let all = [HookFixture.sessionStart(source: "startup"), HookFixture.prompt, HookFixture.question, HookFixture.questionAnswered,
               HookFixture.plan, HookFixture.permission(), HookFixture.permissionPrompt, HookFixture.elicitation, HookFixture.toolDone(),
               HookFixture.toolFailed(), HookFixture.stop, HookFixture.stopFailure, HookFixture.preCompact, HookFixture.postCompact,
               HookFixture.sessionEnd(reason: "clear")]
    for json in all {
        let event = try #require(HookEvent(json: Data(json.utf8)), "\(json.prefix(80))")
        #expect(event.sessionID == HookFixture.session && event.agentID == nil)
    }
    #expect(HookFixture.event(HookFixture.toolDone(agent: HookFixture.agent)).agentID == HookFixture.agent)
    #expect(HookFixture.event(HookFixture.permission(agent: HookFixture.agent)).agentID == HookFixture.agent)
    #expect(HookFixture.event(HookFixture.plan).planPath == "/Users/me/.claude/plans/retry.md")
    // The spool keeps the field, so a replay tells the threads apart too.
    let line = try #require(HookSpool.line(.init(event: HookFixture.toolDone(agent: HookFixture.agent), at: .now)))
    let replayed = try #require(HookSpool.entries(line).first)
    #expect(HookEvent(json: Data(replayed.event.utf8))?.agentID == HookFixture.agent)
}

/// A session walked through events, each a second after the last.
private struct Walk {
    var live = SessionLive(status: SessionStatus(state: .idle, since: Date(timeIntervalSince1970: 0)))
    var clock = 0.0

    mutating func send(_ json: String) {
        clock += 1
        live.apply(HookFixture.event(json), now: Date(timeIntervalSince1970: clock))
    }

    var state: SessionState { live.status.state }
}

@Test func aSubagentsToolCallsLeaveTheMainThreadsWait() {
    for (ask, answer) in [(HookFixture.question, HookFixture.questionAnswered), (HookFixture.plan, HookFixture.toolDone("ExitPlanMode")),
                          (HookFixture.permission(), HookFixture.toolDone("Bash"))] {
        var walk = Walk()
        walk.send(HookFixture.prompt)
        walk.send(ask)
        let waiting = walk.state
        let since = walk.live.status.since
        #expect(walk.live.status.needsYou)
        walk.send(HookFixture.toolDone(agent: HookFixture.agent))
        walk.send(HookFixture.toolFailed(agent: HookFixture.otherAgent))
        #expect(walk.state == waiting && walk.live.status.since == since, "a background agent's tool call ended \(waiting)")
        #expect(walk.live.status.lastActivity == Date(timeIntervalSince1970: walk.clock))
        walk.send(answer)
        #expect(walk.state == .working)
    }
}

@Test func aSubagentsPermissionEndsWithItsOwnToolCall() {
    var walk = Walk()
    walk.send(HookFixture.prompt)
    walk.send(HookFixture.permission(agent: HookFixture.agent))
    #expect(walk.state == .waiting(.permission) && walk.live.waiter == HookFixture.agent)
    walk.send(HookFixture.permissionPrompt)
    walk.send(HookFixture.toolDone())
    walk.send(HookFixture.toolDone(agent: HookFixture.otherAgent))
    #expect(walk.state == .waiting(.permission), "another thread's tool call answered the subagent's permission")
    walk.send(HookFixture.toolDone("Bash", agent: HookFixture.agent))
    #expect(walk.state == .working && walk.live.waiter == nil)
    // A main-thread permission still ends with any main-thread tool event: a rejection sends nothing.
    walk.send(HookFixture.permission())
    walk.send(HookFixture.toolFailed())
    #expect(walk.state == .working)
}

@Test func aSubagentNeitherClearsAFailureNorEndsACompaction() {
    var walk = Walk()
    walk.send(HookFixture.prompt)
    walk.send(HookFixture.stopFailure)
    walk.send(HookFixture.toolDone(agent: HookFixture.agent))
    #expect(walk.state == .failed)
    walk.send(HookFixture.prompt)
    walk.send(HookFixture.preCompact)
    walk.send(HookFixture.toolDone(agent: HookFixture.agent))
    #expect(walk.state == .compacting)
    walk.send(HookFixture.postCompact)
    #expect(walk.state == .working)
    // Done while background agents still work: their tool calls show it working again.
    walk.send(HookFixture.stop)
    walk.send(HookFixture.toolDone(agent: HookFixture.agent))
    #expect(walk.state == .working)
}

@Test func aReplayedEventOlderThanTheStateChangesNothing() {
    let start = Date(timeIntervalSince1970: 1_000)
    var live = SessionLive(status: SessionStatus(state: .idle, since: start))
    live.apply(HookFixture.event(HookFixture.prompt), now: start.addingTimeInterval(5))
    live.apply(HookFixture.event(HookFixture.stop), now: start.addingTimeInterval(10))
    let done = live.status
    // Kept by `hq hook` while HQ launched, replayed after the live Stop.
    let late = start.addingTimeInterval(4)
    live.apply(HookFixture.event(HookFixture.prompt, at: late), now: late)
    live.apply(HookFixture.event(HookFixture.permission(), at: late), now: late)
    #expect(live.status == done, "\(live.status)")
    #expect(live.status.isNew)
    // A replayed event from after the state applies.
    let after = start.addingTimeInterval(12)
    live.apply(HookFixture.event(HookFixture.prompt, at: after), now: after)
    #expect(live.status.state == .working && live.status.lastActivity == after)
}
