import Foundation

/// Hook events HQ missed while it was off (`pending-hooks.jsonl`): `hq hook` adds one compact line each, HQ replays
/// them at launch. Lines carry what the CLI would have sent, and when.
public enum HookSpool {
    /// In HQ's data folder.
    public static let fileName = "pending-hooks.jsonl"
    /// Past this, events are dropped: a night of tool calls fits well under it.
    public static let maxBytes = 4 << 20
    /// Older lines aren't replayed.
    public static let maxAge: TimeInterval = 7 * 86_400

    public struct Entry: Equatable, Sendable {
        public var event: String
        public var pid: String?
        public var tty: String?
        public var ghostty: String?
        public var at: Date

        public init(event: String, pid: String? = nil, tty: String? = nil, ghostty: String? = nil, at: Date) {
            self.event = event
            self.pid = pid
            self.tty = tty
            self.ghostty = ghostty
            self.at = at
        }

        /// The hook command's arguments, as the CLI sends them, with the event's time.
        public var args: [String: String] {
            var args = ["event": event, "at": at.formatted(.iso8601)]
            if let pid { args["pid"] = pid }
            if let tty { args["tty"] = tty }
            if let ghostty { args["ghostty"] = ghostty }
            return args
        }
    }

    /// One line for the file: the event without what HQ never reads (tool output, file contents, long messages).
    public static func line(_ entry: Entry) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(entry.event.utf8)) as? [String: Any],
              let compact = try? JSONSerialization.data(withJSONObject: compacted(object)) else { return nil }
        var record: [String: Any] = ["event": String(decoding: compact, as: UTF8.self), "at": entry.at.timeIntervalSince1970]
        if let pid = entry.pid { record["pid"] = pid }
        if let tty = entry.tty { record["tty"] = tty }
        if let ghostty = entry.ghostty { record["ghostty"] = ghostty }
        guard var data = try? JSONSerialization.data(withJSONObject: record) else { return nil }
        data.append(0x0A)
        return data
    }

    /// The file's lines, oldest first; broken lines and lines older than `maxAge` are skipped.
    public static func entries(_ data: Data, now: Date = .now) -> [Entry] {
        data.split(separator: 0x0A).compactMap { line in
            guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let event = record["event"] as? String, let seconds = record["at"] as? Double else { return nil }
            let at = Date(timeIntervalSince1970: seconds)
            guard now.timeIntervalSince(at) < maxAge else { return nil }
            return Entry(event: event, pid: record["pid"] as? String, tty: record["tty"] as? String,
                         ghostty: record["ghostty"] as? String, at: at)
        }
    }

    /// What's worth replaying: every event but tool calls, the tool calls HQ reads something from (a question, a
    /// plan, a published artifact, a new PR), and each session's last tool call, which says it was working.
    public static func replayable(_ entries: [Entry]) -> [Entry] {
        let parsed = entries.map { ($0, try? JSONSerialization.jsonObject(with: Data($0.event.utf8)) as? [String: Any]) }
        var lastTool: [String: Int] = [:]
        for (index, (_, object)) in parsed.enumerated() {
            guard let object, isToolCall(object), let session = object["session_id"] as? String else { continue }
            lastTool[session] = index
        }
        let kept = Set(lastTool.values)
        return parsed.enumerated().compactMap { index, pair in
            guard let object = pair.1 else { return nil }
            return !isToolCall(object) || kept.contains(index) || readsSomething(object) ? pair.0 : nil
        }
    }

    // MARK: Parts

    private static func isToolCall(_ object: [String: Any]) -> Bool {
        ["PreToolUse", "PostToolUse", "PostToolUseFailure"].contains(object["hook_event_name"] as? String ?? "")
    }

    private static func readsSomething(_ object: [String: Any]) -> Bool {
        let tool = object["tool_name"] as? String ?? ""
        let command = (object["tool_input"] as? [String: Any])?["command"] as? String ?? ""
        return ["AskUserQuestion", "ExitPlanMode", "Artifact"].contains(tool) || (tool == "Bash" && command.contains("gh pr create"))
    }

    /// Keeps the tool's response only where HQ reads it (a published artifact, `gh pr create`), and caps long text.
    static func compacted(_ object: [String: Any]) -> [String: Any] {
        var object = object
        if !readsSomething(object) { object["tool_response"] = nil }
        if var input = object["tool_input"] as? [String: Any] {
            for (key, value) in input {
                if let text = value as? String, text.count > 2_000 { input[key] = String(text.prefix(2_000)) }
            }
            object["tool_input"] = input
        }
        for key in ["last_assistant_message", "prompt", "message"] {
            if let text = object[key] as? String, text.count > 2_000 { object[key] = String(text.prefix(2_000)) }
        }
        return object
    }
}
