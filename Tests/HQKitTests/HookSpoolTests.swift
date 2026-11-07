import Foundation
import Testing
@testable import HQKit

private func event(_ name: String, _ session: String = "s1", tool: String? = nil, input: [String: Any]? = nil, response: Any? = nil) -> String {
    var object: [String: Any] = ["hook_event_name": name, "session_id": session]
    if let tool { object["tool_name"] = tool }
    if let input { object["tool_input"] = input }
    if let response { object["tool_response"] = response }
    return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

@Test func spoolLinesRoundTripWithTheirTime() throws {
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    let entry = HookSpool.Entry(event: event("Stop"), pid: "42", tty: "/dev/ttys003", ghostty: "true", at: at)
    let line = try #require(HookSpool.line(entry))
    let back = HookSpool.entries(line + line, now: at.addingTimeInterval(60))
    #expect(back.count == 2 && back[0].pid == "42" && back[0].tty == "/dev/ttys003" && back[0].at == at)
    #expect(back[0].args["at"] != nil && back[0].args["ghostty"] == "true")
    #expect(HookSpool.entries(line, now: at.addingTimeInterval(8 * 86_400)).isEmpty)
    #expect(HookSpool.entries(Data("not json\n".utf8) + line, now: at).count == 1)
}

@Test func spoolDropsWhatHQNeverReads() throws {
    let big = String(repeating: "x", count: 50_000)
    let read = HookSpool.Entry(event: event("PostToolUse", tool: "Read", input: ["file_path": "/a"], response: big), at: .now)
    let line = try #require(HookSpool.line(read))
    #expect(line.count < 1_000)
    let write = HookSpool.Entry(event: event("PreToolUse", tool: "Write", input: ["file_path": "/a", "content": big]), at: .now)
    #expect(try #require(HookSpool.line(write)).count < 3_000)
    let artifact = HookSpool.Entry(event: event("PostToolUse", tool: "Artifact", input: ["file_path": "/p.html"],
                                                 response: "Published p.html at https://claude.ai/artifact/abc"), at: .now)
    let artifactLine = try #require(HookSpool.line(artifact))
    let kept = try #require(HookSpool.entries(artifactLine).first)
    let object = try JSONSerialization.jsonObject(with: Data(kept.event.utf8)) as? [String: Any]
    #expect((object?["tool_response"] as? String)?.contains("claude.ai/artifact/abc") == true)
}

@Test func spoolReplaysStateAndLastToolCalls() {
    let entries = [
        event("UserPromptSubmit"), event("PreToolUse", tool: "Bash"), event("PostToolUse", tool: "Bash"),
        event("PreToolUse", tool: "AskUserQuestion", input: ["questions": [["question": "Which?"]]]),
        event("PostToolUse", "s2", tool: "Read"), event("PostToolUse", tool: "Edit"), event("Stop"),
    ].map { HookSpool.Entry(event: $0, at: .now) }
    let kept = HookSpool.replayable(entries).map(\.event)
    #expect(kept == [entries[0], entries[3], entries[4], entries[5], entries[6]].map(\.event))
}
