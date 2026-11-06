import Foundation
import Testing
@testable import HQKit

@Test func sessionAttention() {
    let now = Date.now
    #expect(SessionStatus(state: .waiting(.plan), since: now).needsYou)
    #expect(SessionStatus(state: .failed, since: now).needsYou)
    #expect(!SessionStatus(state: .done, unread: true, since: now).needsYou)
    #expect(SessionStatus(state: .done, unread: true, since: now).isNew)
    #expect(!SessionStatus(state: .done, unread: false, since: now).isNew)
    #expect(!SessionStatus(state: .working, since: now).needsYou)
}

@Test("Elapsed times stay short", arguments: [
    (20, "<1m"), (240, "4m"), (7_200, "2h"), (3 * 86_400, "3d"), (21 * 86_400, "3w"),
] as [(TimeInterval, String)])
func elapsed(_ seconds: TimeInterval, expected: String) {
    let now = Date.now
    #expect(Elapsed.short(from: now.addingTimeInterval(-seconds), to: now) == expected)
}

@Test func fuzzyMatchesInOrder() throws {
    let match = try #require(Fuzzy.match("rph", in: "registry: push hardening"))
    #expect(match.offsets == [0, 10, 15])
    #expect(Fuzzy.match("xyz", in: "registry") == nil)
    // A word start further on must not hide a match: "a" at "a" would leave no "b".
    #expect(Fuzzy.match("ab", in: "xab a")?.offsets == [1, 2])
    let start = try #require(Fuzzy.match("reg", in: "registry"))
    let middle = try #require(Fuzzy.match("reg", in: "the cdn origin aggregate"))
    #expect(start.score > middle.score)
}

// MARK: Sessions

private func event(_ name: String, _ extra: String = "") -> HookEvent {
    HookEvent(json: Data("{\"hook_event_name\":\"\(name)\",\"session_id\":\"s1\"\(extra)}".utf8))!
}

@Test func hookEventParsing() throws {
    let ask = event("PreToolUse", #","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Redis or Postgres?","options":[{"label":"Redis"},{"label":"Postgres"}]}]}"#)
    #expect(ask.question == "Redis or Postgres?")
    #expect(ask.options == ["Redis", "Postgres"])
    #expect(ask.toolSummary == nil)
    let bash = event("PermissionRequest", #","tool_name":"Bash","tool_input":{"command":"kubectl rollout restart deploy/api","description":"Restart"}"#)
    #expect(bash.toolSummary == "kubectl rollout restart deploy/api")
    #expect(event("SessionStart", #","session_title":"","source":"clear""#).title == nil)
    #expect(HookEvent(json: Data(#"{"hook_event_name":"Stop"}"#.utf8)) == nil)
    #expect(SessionState(key: SessionState.waiting(.plan).key) == .waiting(.plan))
}

@Test func artifactPublishParsing() throws {
    let text = event("PostToolUse", #","tool_name":"Artifact","tool_input":{"file_path":"/tmp/p.html"},"tool_response":"Published https:\/\/claude.ai\/code\/artifact\/3f2a-91 (private)""#)
    #expect(text.artifact == PublishedArtifact(url: "https://claude.ai/code/artifact/3f2a-91", file: "/tmp/p.html"))
    let object = event("PostToolUse", #","tool_name":"Artifact","tool_input":{"title":"Plan"},"tool_response":{"result":{"url":"https://claude.ai/artifact/abc"}}"#)
    #expect(object.artifact?.url == "https://claude.ai/artifact/abc")
    #expect(object.artifact?.title == "Plan")
    let update = event("PostToolUse", #","tool_name":"Artifact","tool_input":{"url":"https://claude.ai/artifact/abc","file_path":"p.html"},"tool_response":{}"#)
    #expect(update.artifact?.url == "https://claude.ai/artifact/abc")
    #expect(event("PostToolUse", #","tool_name":"Artifact","tool_input":{"action":"list"},"tool_response":"https://claude.ai/artifact/abc""#).artifact == nil)
    #expect(event("PostToolUse", #","tool_name":"Artifact","tool_input":{"asset":true,"url":"https://claude.ai/artifact/abc"}"#).artifact == nil)
    #expect(event("PreToolUse", #","tool_name":"Artifact","tool_input":{"url":"https://claude.ai/artifact/abc"}"#).artifact == nil)
    // A page that copies a file from another artifact is the one published, not the source, wherever the source shows.
    let copied = event("PostToolUse", #","tool_name":"Artifact","tool_input":{"file_path":"/tmp/pitch.html","files":{"logo.png":{"artifact":"https://claude.ai/artifact/SOURCE1","path":"logo.png"}}},"tool_response":{"copied":"logo.png ← https://claude.ai/artifact/SOURCE1","text":"Published /tmp/pitch.html at https://claude.ai/artifact/MADE2 (Version 1)"}"#)
    #expect(copied.artifact?.url == "https://claude.ai/artifact/MADE2")
    let noSentence = event("PostToolUse", #","tool_name":"Artifact","tool_input":{"from_url":"https://claude.ai/artifact/SOURCE1","file_path":"p.html"},"tool_response":"https://claude.ai/artifact/SOURCE1 https://claude.ai/artifact/MADE3""#)
    #expect(noSentence.artifact?.url == "https://claude.ai/artifact/MADE3")
    let page = FileManager.default.temporaryDirectory.appending(path: "hq-page-\(UUID().uuidString).html")
    try "<html><head><title>\n  Push plan </title></head></html>".write(to: page, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: page) }
    #expect(PublishedArtifact.title(ofPage: page.path) == "Push plan")
}

@Test func sessionStateMachine() {
    let start = Date(timeIntervalSince1970: 0)
    var live = SessionLive(status: SessionStatus(state: .idle, since: start))
    func send(_ name: String, _ extra: String = "", at seconds: Double = 1) {
        live.apply(event(name, extra), now: start.addingTimeInterval(seconds))
    }
    send("UserPromptSubmit")
    #expect(live.status.state == .working)
    send("PreToolUse", #","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which?"}]}"#, at: 2)
    send("PermissionRequest", #","tool_name":"AskUserQuestion""#, at: 3)
    send("Notification", #","notification_type":"permission_prompt""#, at: 9)
    #expect(live.status.state == .waiting(.question))
    #expect(live.status.since == start.addingTimeInterval(2))
    send("PostToolUse", #","tool_name":"AskUserQuestion""#, at: 20)
    #expect(live.status.state == .working)
    send("PermissionRequest", #","tool_name":"Bash","tool_input":{"command":"rm -rf build"}"#, at: 21)
    #expect(live.status.state == .waiting(.permission) && live.toolInput == "rm -rf build")
    send("PostToolUse", at: 22)
    send("PreCompact", at: 23)
    #expect(live.status.state == .compacting)
    send("PostCompact", at: 24)
    send("SessionStart", #","source":"compact""#, at: 24)
    #expect(live.status.state == .working)
    send("Stop", #","last_assistant_message":"Done.""#, at: 30)
    #expect(live.status.state == .done && live.status.isNew && !live.status.needsYou && live.lastMessage == "Done.")
    send("UserPromptSubmit", at: 40)
    #expect(!live.status.unread)
    send("StopFailure", #","error":"model_not_found""#, at: 41)
    #expect(live.status.state == .failed && live.error == "model_not_found")
    send("SessionEnd", #","reason":"prompt_input_exit""#, at: 50)
    #expect(live.status.state == .ended && live.status.lastActivity == start.addingTimeInterval(50))
}

@Test func frontMatterReadsObsidianForms() {
    let note = FrontMatter("""
    ---
    title: "Dedup layers: on push"
    status: todo # comment
    tags:
      - registry
      - "chunks"
    links: [https://github.com/a/b/pull/1, 'x, y']
    aliases: keep me
    ---
    # Body

    Text.
    """)
    #expect(note.string("title") == "Dedup layers: on push")
    #expect(note.string("status") == "todo")
    #expect(note.list("tags") == ["registry", "chunks"])
    #expect(note.list("links") == ["https://github.com/a/b/pull/1", "x, y"])
    #expect(note.body == "# Body\n\nText.")
    #expect(FrontMatter("No front matter").body == "No front matter")
    #expect(FrontMatter("tags: a, b").list("tags").isEmpty)
}

@Test func frontMatterWritesOnlyItsKeys() {
    var note = FrontMatter("---\ntitle: Old\ntags:\n  - a\n  - b\naliases: keep me\n---\nBody\n")
    note.set("tags", list: ["registry", "two words"])
    note.set("title", "New: title")
    note.set("status", "doing")
    note.set("order", nil)
    #expect(note.text == "---\ntitle: \"New: title\"\ntags: [registry, two words]\naliases: keep me\nstatus: doing\n---\nBody\n")
    let again = FrontMatter(note.text)
    #expect(again.list("tags") == ["registry", "two words"])
    #expect(again.string("title") == "New: title")
    var bare = FrontMatter(lines: [], body: "Hello")
    bare.set("title", "T")
    #expect(bare.text == "---\ntitle: T\n---\nHello")
}

@Test func claudeProcessReadsTheKernel() {
    let me = getpid()
    #expect(ClaudeProcess.path(of: me) != nil)
    #expect(!ClaudeProcess.isClaude(me))
    #expect(ClaudeProcess.ancestors(of: me).first == getppid())
    #expect(ClaudeProcess.current(["CLAUDE_PID": "\(me)"])?.pid == me)
    #expect(!ClaudeProcess.isRunningClaude(me))
}

@Test func gitInfoReadsBranchAndWorktree() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "hq-git-\(UUID().uuidString)")
    let main = root.appending(path: "registry")
    let tree = root.appending(path: "_wt/registry-push")
    let files = FileManager.default
    try files.createDirectory(at: main.appending(path: ".git/worktrees/push"), withIntermediateDirectories: true)
    try files.createDirectory(at: tree.appending(path: "src"), withIntermediateDirectories: true)
    try "ref: refs/heads/main\n".write(to: main.appending(path: ".git/HEAD"), atomically: true, encoding: .utf8)
    try "ref: refs/heads/push-hardening\n".write(to: main.appending(path: ".git/worktrees/push/HEAD"), atomically: true, encoding: .utf8)
    try "gitdir: \(main.path)/.git/worktrees/push\n".write(to: tree.appending(path: ".git"), atomically: true, encoding: .utf8)
    defer { try? files.removeItem(at: root) }
    #expect(GitInfo.describe(main.path) == ("registry", "main"))
    #expect(GitInfo.describe(tree.appending(path: "src").path) == ("registry", "push-hardening"))
    #expect(GitInfo.describe(root.path).branch == "")
}

@Test func interruptedTurnGoesIdle() throws {
    let path = NSTemporaryDirectory() + "hq-interrupt-\(UUID().uuidString).jsonl"
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let lines = [
        #"{"type":"user","message":{"role":"user","content":"Fix it"},"timestamp":"2027-01-15T08:00:00.000Z"}"#,
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"On it"}]},"timestamp":"2027-01-15T08:00:01.000Z"}"#,
        #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]},"timestamp":"2027-01-15T08:00:02.500Z"}"#,
        #"{"type":"system","subtype":"meta"}"#,
    ]
    try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: path) }
    let stopped = try #require(TranscriptInterrupt.read(path))
    #expect(abs(stopped.timeIntervalSince1970 - 1_800_000_002.5) < 0.01)
    var live = SessionLive(status: SessionStatus(state: .working, since: start))
    let changed = live.interrupt(at: stopped, now: stopped)
    #expect(changed)
    #expect(live.status.state == .idle)
    // A prompt after it: not interrupted.
    try (lines + [#"{"type":"user","message":{"role":"user","content":"Go on"},"timestamp":"2027-01-15T08:00:09.000Z"}"#])
        .joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    #expect(TranscriptInterrupt.read(path) == nil)
    // An interrupt from before the state began changes nothing.
    var later = SessionLive(status: SessionStatus(state: .working, since: stopped.addingTimeInterval(10)))
    let unchanged = later.interrupt(at: stopped, now: .now)
    #expect(!unchanged)
}

@Test func reviewedPullRequestsComeBack() throws {
    #expect(GitHubQuery.query(linked: []).contains("reviewed-by:@me -author:@me"))
    let json = #"""
    {"data":{"viewer":{"login":"alex"},"review":{"nodes":[]},"mine":{"nodes":[]},
     "reviewed":{"nodes":[{"__typename":"PullRequest","url":"https://github.com/o/r/pull/7","number":7,"title":"Done by me",
       "state":"OPEN","isDraft":false,"updatedAt":"2027-01-15T08:00:00Z","author":{"login":"noor"},
       "repository":{"nameWithOwner":"o/r"},"reviewDecision":"APPROVED",
       "latestReviews":{"nodes":[{"author":{"login":"alex"},"state":"APPROVED","submittedAt":"2027-01-15T09:00:00Z"}]},
       "commits":{"nodes":[{"commit":{"committedDate":"2027-01-15T07:00:00Z"}}]}}]}}}
    """#
    let snapshot = try GitHubQuery.parse(Data(json.utf8), linked: [])
    let item = try #require(snapshot.items.first)
    #expect(item.reviewedByMe && !item.reviewRequested && !item.waitsForReview(markedReviewedAt: nil))
}
