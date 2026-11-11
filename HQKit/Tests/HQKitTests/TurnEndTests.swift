import Foundation
import Testing
@testable import HQKit

/// Every way a turn ends without a Stop: what the transcript's end says, and what Claude Code's own session record says.
enum TurnEndFixture {
    static let session = "8c1e4f2a-5b7d-4e19-9a3c-2f6b8d0e1a47"
    static let prompt = #"{"type":"user","message":{"role":"user","content":"test"},"timestamp":"2027-01-15T08:00:00.000Z","isSidechain":false}"#
    static let request = #"{"type":"api-request","timestamp":"2027-01-15T08:00:00.050Z"}"#
    static let meta = [#"{"type":"last-prompt"}"#, #"{"type":"permission-mode"}"#, #"{"type":"frame-link","timestamp":"2027-01-15T08:00:00.100Z"}"#]
    static let answer = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"On it"}]},"timestamp":"2027-01-15T08:00:01.000Z"}"#
    static let toolUse = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_01","name":"Bash","input":{}}]},"timestamp":"2027-01-15T08:00:01.000Z"}"#
    static let refused = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_01","content":"The user doesn't want to proceed with this tool use.","is_error":true}]},"timestamp":"2027-01-15T08:00:02.400Z"}"#
    static func interrupted(_ text: String) -> String {
        #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"\#(text)"}]},"timestamp":"2027-01-15T08:00:02.500Z"}"#
    }
    static let queued = [#"{"type":"queue-operation","operation":"enqueue","timestamp":"2027-01-15T08:00:01.500Z","content":"and the docs"}"#,
                         #"{"type":"queue-operation","operation":"remove","timestamp":"2027-01-15T08:00:02.000Z","content":"and the docs"}"#]

    /// Each ending, with the time the transcript says the turn stopped, or nil when it can't tell.
    static let endings: [(name: String, lines: [String], stopped: TimeInterval?)] = [
        ("Esc before any answer", [prompt, request] + meta, nil),
        ("Esc while Claude thinks", [prompt, request, answer, request] + meta, nil),
        ("Esc mid-answer", [prompt, request, answer, interrupted("[Request interrupted by user]")], 2.5),
        ("Ctrl+C mid-answer", [prompt, request, answer, interrupted("[Request interrupted by user]")] + meta, 2.5),
        ("Esc on a tool use", [prompt, toolUse, refused, interrupted("[Request interrupted by user for tool use]")], 2.5),
        ("a cancelled queued prompt", [prompt, request, toolUse] + queued + meta, nil),
    ]

    static func write(_ lines: [String]) throws -> String {
        let path = NSTemporaryDirectory() + "hq-turn-\(UUID().uuidString).jsonl"
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    static func record(_ status: String, at time: Date, session: String = session) throws -> String {
        let path = NSTemporaryDirectory() + "hq-claude-\(UUID().uuidString).json"
        let millis = Int(time.timeIntervalSince1970 * 1000)
        try #"{"pid":4242,"sessionId":"\#(session)","status":"\#(status)","statusUpdatedAt":\#(millis),"updatedAt":\#(millis)}"#
            .write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }
}

@Test(arguments: TurnEndFixture.endings.indices)
func turnEndingWithoutStopGoesIdle(_ index: Int) throws {
    let ending = TurnEndFixture.endings[index]
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    let transcript = try TurnEndFixture.write(ending.lines)
    defer { try? FileManager.default.removeItem(atPath: transcript) }
    let stopped = TranscriptInterrupt.read(transcript)
    #expect(stopped?.timeIntervalSince1970 == ending.stopped.map { 1_800_000_000 + $0 }, "\(ending.name): the transcript says \(String(describing: stopped))")
    // Whatever the transcript says, Claude Code's record says idle: the session leaves Working once both held a moment.
    let idle = base.addingTimeInterval(2.5)
    let record = try TurnEndFixture.record("idle", at: idle)
    defer { try? FileManager.default.removeItem(atPath: record) }
    let said = try #require(ClaudeSessionFile.idleSince(record, sessionID: TurnEndFixture.session), "\(ending.name)")
    #expect(abs(said.timeIntervalSince(idle)) < 0.01)
    var live = SessionLive(status: SessionStatus(state: .working, since: base))
    let early = live.claudeIdle(since: said, now: idle.addingTimeInterval(1))
    #expect(!early, "\(ending.name): a Stop just behind still wins")
    let ended = live.claudeIdle(since: said, now: idle.addingTimeInterval(4))
    #expect(ended, "\(ending.name)")
    #expect(live.status.state == .idle)
}

@Test func claudeRecordOnlyEndsAWorkingTurn() throws {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    let busy = try TurnEndFixture.record("busy", at: base)
    let waiting = try TurnEndFixture.record("waiting", at: base)
    let other = try TurnEndFixture.record("idle", at: base, session: "another-session")
    defer { for path in [busy, waiting, other] { try? FileManager.default.removeItem(atPath: path) } }
    #expect(ClaudeSessionFile.idleSince(busy, sessionID: TurnEndFixture.session) == nil)
    #expect(ClaudeSessionFile.idleSince(waiting, sessionID: TurnEndFixture.session) == nil)
    #expect(ClaudeSessionFile.idleSince(other, sessionID: TurnEndFixture.session) == nil, "a pid reused by another session")
    #expect(ClaudeSessionFile.idleSince("/nonexistent/4242.json", sessionID: TurnEndFixture.session) == nil)
    // A prompt just sent: Claude's record may still say idle from before it. Working holds until Claude had time to say busy.
    var fresh = SessionLive(status: SessionStatus(state: .working, since: base.addingTimeInterval(100)))
    let tooSoon = fresh.claudeIdle(since: base, now: base.addingTimeInterval(101))
    #expect(!tooSoon)
    // A question, a plan or a permission waits on the user: Claude's idle doesn't end it.
    var asking = SessionLive(status: SessionStatus(state: .waiting(.plan), since: base))
    let answered = asking.claudeIdle(since: base, now: base.addingTimeInterval(60))
    #expect(!answered)
    // A Stop already came: done stays done.
    var done = SessionLive(status: SessionStatus(state: .done, since: base))
    let undone = done.claudeIdle(since: base, now: base.addingTimeInterval(60))
    #expect(!undone)
}
