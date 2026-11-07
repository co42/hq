import Foundation

/// A Claude Code hook event, as `hq hook` forwards it: the hook's JSON plus where Claude runs.
public struct HookEvent: Sendable, Hashable {
    public var name: String
    public var sessionID: String
    public var cwd: String?
    public var transcriptPath: String?
    /// SessionStart: startup, resume, clear or compact.
    public var source: String?
    /// SessionEnd: clear, prompt_input_exit, other…
    public var reason: String?
    public var toolName: String?
    /// The tool input in one line: a command, a path, a URL.
    public var toolSummary: String?
    public var question: String?
    public var options: [String] = []
    public var planPath: String?
    public var notificationType: String?
    public var lastMessage: String?
    public var error: String?
    /// Claude's session title (`-n`, or its own).
    public var title: String?
    public var prompt: String?
    /// A page the Artifact tool published (PostToolUse).
    public var artifact: PublishedArtifact?
    /// Pull requests the session opened (`gh pr create` in a PostToolUse of Bash).
    public var pullRequests: [String] = []
    /// Claude's process and terminal, added by `hq hook`.
    public var pid: Int32?
    public var tty: String?
    public var inGhostty: Bool?
    /// When it happened, for an event HQ replays from `HookSpool`; nil: now.
    public var at: Date?

    public init(name: String, sessionID: String) {
        self.name = name
        self.sessionID = sessionID
    }

    /// Nil when the JSON has no event name or session id.
    public init?(json: Data, pid: Int32? = nil, tty: String? = nil, inGhostty: Bool? = nil) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let name = object["hook_event_name"] as? String,
              let sessionID = object["session_id"] as? String, !sessionID.isEmpty else { return nil }
        self.init(name: name, sessionID: sessionID)
        cwd = object["cwd"] as? String
        transcriptPath = object["transcript_path"] as? String
        source = object["source"] as? String
        reason = object["reason"] as? String
        toolName = object["tool_name"] as? String
        let input = object["tool_input"] as? [String: Any]
        toolSummary = Self.summary(input) ?? (object["message"] as? String).flatMap { name == "Elicitation" ? $0 : nil }
        if let first = (input?["questions"] as? [[String: Any]])?.first {
            question = first["question"] as? String
            options = (first["options"] as? [[String: Any]])?.compactMap { $0["label"] as? String } ?? []
        }
        planPath = input?["planFilePath"] as? String
        notificationType = object["notification_type"] as? String
        lastMessage = object["last_assistant_message"] as? String
        error = object["error"] as? String
        title = (object["session_title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        prompt = object["prompt"] as? String
        if name == "PostToolUse", toolName == "Artifact" {
            artifact = PublishedArtifact(input: input ?? [:], response: object["tool_response"])
        }
        if name == "PostToolUse", toolName == "Bash", (input?["command"] as? String)?.contains("gh pr create") == true {
            pullRequests = GitHubLinks.urls(in: Self.text(object["tool_response"])).filter { $0.contains("/pull/") }
        }
        self.pid = pid
        self.tty = tty
        self.inGhostty = inGhostty
    }

    /// A tool response as text, whatever its shape.
    static func text(_ value: Any?) -> String {
        if let string = value as? String { return string }
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return "" }
        return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\\/", with: "/")
    }

    /// The part of a tool's input that says what it does.
    static func summary(_ input: [String: Any]?) -> String? {
        guard let input, !input.isEmpty else { return nil }
        for key in ["command", "file_path", "notebook_path", "url", "query", "pattern", "description"] {
            if let value = input[key] as? String, !value.isEmpty { return value }
        }
        guard input["questions"] == nil, input["planFilePath"] == nil,
              let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]) else { return nil }
        return String(String(decoding: data, as: UTF8.self).prefix(500))
    }
}

/// What the Artifact tool published, read best effort: its tool's input and response are not a contract.
public struct PublishedArtifact: Sendable, Hashable {
    public var url: String
    public var title: String?
    /// The local page it published, to read its `<title>` from.
    public var file: String?

    public init(url: String, title: String? = nil, file: String? = nil) {
        self.url = url
        self.title = title
        self.file = file
    }

    /// Nil for anything but publishing a page: reads, lists, asset uploads, deletes.
    public init?(input: [String: Any], response: Any?) {
        let action = input["action"] as? String ?? "publish"
        guard action == "publish", input["asset"] as? Bool != true else { return nil }
        let text = response.flatMap { value -> String? in
            if let string = value as? String { return string }
            guard JSONSerialization.isValidJSONObject(value) else { return nil }
            return (try? JSONSerialization.data(withJSONObject: value)).map { String(decoding: $0, as: UTF8.self) }
        } ?? ""
        // The page it made or updated: never one it only read from (copied files and assets, the type it starts from).
        let clean = text.replacingOccurrences(of: "\\/", with: "/")
        let sources = Self.sources(in: input)
        let published = Self.publishedURL(in: clean).flatMap { sources.contains($0) ? nil : $0 }
        guard let url = published ?? (input["url"] as? String).flatMap(Self.firstURL)
                ?? Self.urls(in: clean).first(where: { !sources.contains($0) }) else { return nil }
        self.init(url: url, title: (input["title"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                  file: (input["file_path"] as? String).flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Every claude.ai artifact link in a text, in order.
    static func urls(in text: String) -> [String] {
        text.matches(of: #/https://claude\.ai/(?:[A-Za-z0-9_-]+/)*artifacts?/[A-Za-z0-9_-]+/#).map { String($0.output) }
    }

    /// "Published <file> at <link>": the page a publish made or updated.
    static func publishedURL(in text: String) -> String? {
        text.firstMatch(of: #/Published [^\n]*? at (https://claude\.ai/(?:[A-Za-z0-9_-]+/)*artifacts?/[A-Za-z0-9_-]+)/#).map { String($0.output.1) }
    }

    /// Artifacts a publish only reads from: the ones its files and assets are copied from, the type it starts from.
    static func sources(in input: [String: Any]) -> Set<String> {
        let text = ["files", "from_url", "type_url"].compactMap { input[$0] }.map { part -> String in
            if let string = part as? String { return string }
            guard JSONSerialization.isValidJSONObject(part), let data = try? JSONSerialization.data(withJSONObject: part) else { return "" }
            return String(decoding: data, as: UTF8.self)
        }.joined(separator: " ").replacingOccurrences(of: "\\/", with: "/")
        return Set(urls(in: text))
    }

    /// claude.ai/artifact/…, claude.ai/code/artifact/…, claude.ai/public/artifacts/…
    static func firstURL(in text: String) -> String? {
        guard let range = text.range(of: #"https://claude\.ai/(?:[A-Za-z0-9_-]+/)*artifacts?/[A-Za-z0-9_-]+"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    /// The page's own title: an HTML `<title>`, or a Markdown file's first heading.
    public static func title(ofPage path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: (path as NSString).expandingTildeInPath) else { return nil }
        defer { try? handle.close() }
        let text = String(decoding: (try? handle.read(upToCount: 65_536)) ?? Data(), as: UTF8.self)
        if let range = text.range(of: #"(?is)<title[^>]*>(.*?)</title>"#, options: .regularExpression) {
            let title = text[range].replacingOccurrences(of: #"(?is)</?title[^>]*>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }
        let heading = text.split(separator: "\n").first { $0.hasPrefix("# ") }
        return heading.map { $0.dropFirst(2).trimmingCharacters(in: .whitespaces) }
    }
}

extension SessionState {
    /// How the state is stored: "waiting:permission", "done", …
    public var key: String {
        switch self {
        case .waiting(let reason): "waiting:\(reason.rawValue)"
        case .failed: "failed"
        case .done: "done"
        case .working: "working"
        case .compacting: "compacting"
        case .idle: "idle"
        case .ended: "ended"
        }
    }

    public init?(key: String) {
        switch key {
        case "failed": self = .failed
        case "done": self = .done
        case "working": self = .working
        case "compacting": self = .compacting
        case "idle": self = .idle
        case "ended": self = .ended
        default:
            guard key.hasPrefix("waiting:"), let reason = WaitReason(rawValue: String(key.dropFirst(8))) else { return nil }
            self = .waiting(reason)
        }
    }

    var waitsOnQuestionOrPlan: Bool { self == .waiting(.question) || self == .waiting(.plan) }
}

/// A session's live state and what it waits on, moved by hook events (PLAN.md §6).
public struct SessionLive: Sendable, Hashable {
    public var status: SessionStatus
    /// The state before a compaction, to go back to after it.
    public var beforeCompact: SessionState?
    public var tool: String?
    public var toolInput: String?
    public var question: String?
    public var options: [String] = []
    public var planPath: String?
    public var error: String?
    public var lastMessage: String?

    public init(status: SessionStatus) {
        self.status = status
    }

    public mutating func apply(_ event: HookEvent, now: Date) {
        status.lastActivity = now
        let state = status.state
        switch event.name {
        case "SessionStart":
            // An automatic compaction mid-turn ends with SessionStart(compact): the turn goes on.
            if event.source != "compact" { set(.idle, now) }
        case "UserPromptSubmit":
            status.unread = false
            set(.working, now)
        case "PreToolUse":
            switch event.toolName {
            case "AskUserQuestion":
                question = event.question
                options = event.options
                set(.waiting(.question), now)
            case "ExitPlanMode":
                planPath = event.planPath
                set(.waiting(.plan), now)
            default:
                set(.working, now)
            }
        case "PostToolUse", "PostToolUseFailure":
            set(.working, now)
        case "PermissionRequest", "Elicitation":
            // AskUserQuestion and ExitPlanMode raise one too: they stay a question or a plan.
            guard !state.waitsOnQuestionOrPlan else { break }
            tool = event.toolName ?? (event.name == "Elicitation" ? "an MCP tool" : nil)
            toolInput = event.toolSummary
            set(.waiting(.permission), now)
        case "Notification":
            guard event.notificationType == "permission_prompt", !state.waitsOnQuestionOrPlan,
                  state != .waiting(.permission) else { break }
            set(.waiting(.permission), now)
        case "Stop":
            lastMessage = event.lastMessage ?? lastMessage
            status.unread = true
            set(.done, now)
        case "StopFailure":
            error = event.error
            lastMessage = event.lastMessage ?? lastMessage
            set(.failed, now)
        case "PreCompact":
            if state != .compacting { beforeCompact = state }
            set(.compacting, now)
        case "PostCompact":
            set(beforeCompact ?? .idle, now)
            beforeCompact = nil
        case "SessionEnd":
            // After /clear the conversation goes on under a new id; this one can be resumed.
            set(.ended, now)
        default:
            break
        }
    }

    /// The process exited without a SessionEnd.
    public mutating func end(_ now: Date) {
        set(.ended, now)
    }

    /// Esc or Ctrl+C stopped the turn at `time`: Claude Code sends no Stop then. A working or waiting session goes idle.
    @discardableResult
    public mutating func interrupt(at time: Date, now: Date) -> Bool {
        guard time >= status.since.addingTimeInterval(-1) else { return false }
        switch status.state {
        case .working, .waiting:
            tool = nil
            toolInput = nil
            question = nil
            options = []
            set(.idle, now)
            return true
        default:
            return false
        }
    }

    private mutating func set(_ state: SessionState, _ now: Date) {
        guard status.state != state else { return }
        status.state = state
        status.since = now
    }
}

/// The repository and branch of a directory, read from `.git` without running git.
public enum GitInfo {
    public static func describe(_ cwd: String) -> (repo: String, branch: String) {
        var dir = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath).standardizedFileURL
        let fallback = dir.lastPathComponent
        let files = FileManager.default
        while dir.path != "/" {
            let dotGit = dir.appending(path: ".git")
            var isDirectory: ObjCBool = false
            if files.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                var gitDir = dotGit
                var repo = dir.lastPathComponent
                if !isDirectory.boolValue {
                    // A worktree: "gitdir: <main>/.git/worktrees/<name>".
                    let line = (try? String(contentsOf: dotGit, encoding: .utf8)) ?? ""
                    guard line.hasPrefix("gitdir:") else { return (repo, "") }
                    let path = line.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines)
                    gitDir = URL(fileURLWithPath: path, relativeTo: dir).standardizedFileURL
                    let parts = gitDir.pathComponents
                    if let index = parts.lastIndex(of: ".git"), index > 0 { repo = parts[index - 1] }
                }
                return (repo, branch(gitDir))
            }
            dir.deleteLastPathComponent()
        }
        return (fallback, "")
    }

    private static func branch(_ gitDir: URL) -> String {
        let head = ((try? String(contentsOf: gitDir.appending(path: "HEAD"), encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("ref: refs/heads/") { return String(head.dropFirst(16)) }
        return String(head.prefix(7))
    }
}

/// When the user stopped the last turn (Esc, Ctrl+C), read best effort from the end of a transcript:
/// its last message is Claude Code's "[Request interrupted by user…]". The format is internal to Claude Code.
public enum TranscriptInterrupt {
    public static func read(_ path: String, tail: Int = 32_768) -> Date? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(tail) ? size - UInt64(tail) : 0)
        let text = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
        for line in text.split(separator: "\n").reversed() where line.contains(#""type":"user""#) || line.contains(#""type":"assistant""#) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = object["type"] as? String, type == "user" || type == "assistant" else { continue }
            if object["isSidechain"] as? Bool == true || object["isMeta"] as? Bool == true { continue }
            guard type == "user", let message = object["message"] as? [String: Any] else { return nil }
            let content = message["content"]
            let first = (content as? String) ?? ((content as? [[String: Any]])?.first?["text"] as? String) ?? ""
            guard first.hasPrefix("[Request interrupted by user") else { return nil }
            return (object["timestamp"] as? String).flatMap(Self.date) ?? .now
        }
        return nil
    }

    private static func date(_ text: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text))
    }
}

/// A session's titles, read best effort from its transcript: the user's /rename (`custom-title`) and Claude's own
/// (`ai-title`). The format is internal to Claude Code.
public enum TranscriptTitle {
    public struct Titles: Equatable, Sendable {
        public var renamed: String?
        public var claude: String?

        public init(renamed: String? = nil, claude: String? = nil) {
            self.renamed = renamed
            self.claude = claude
        }
    }

    /// The titles in the end of the transcript.
    public static func read(_ path: String, tail: Int = 65_536) -> Titles {
        guard let handle = FileHandle(forReadingAtPath: path) else { return Titles() }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(tail) ? size - UInt64(tail) : 0)
        let text = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
        var titles = Titles()
        for line in text.split(separator: "\n") where line.contains("-title\"") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            switch object["type"] as? String {
            case "custom-title": titles.renamed = object["customTitle"] as? String ?? titles.renamed
            case "ai-title": titles.claude = object["aiTitle"] as? String ?? titles.claude
            default: break
            }
        }
        return titles
    }

    /// The last /rename anywhere in the transcript, however long ago.
    public static func lastRename(_ path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped) else { return nil }
        let marker = Data("\"custom-title\"".utf8)
        var end = data.endIndex
        while let found = data.range(of: marker, options: .backwards, in: data.startIndex..<end) {
            let start = data[..<found.lowerBound].lastIndex(of: 10).map { $0 + 1 } ?? data.startIndex
            let stop = data[found.upperBound...].firstIndex(of: 10) ?? data.endIndex
            if let object = try? JSONSerialization.jsonObject(with: data[start..<stop]) as? [String: Any],
               object["type"] as? String == "custom-title", let title = object["customTitle"] as? String {
                return title
            }
            end = found.lowerBound
        }
        return nil
    }
}
