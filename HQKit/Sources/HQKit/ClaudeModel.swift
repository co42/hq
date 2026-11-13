import Foundation

/// A Claude Code session's model and effort, as `claude --model --effort` takes them and its transcript records them
/// (T-446), and the tokens its context holds (T-475).
public enum ClaudeModel {
    /// The aliases `claude --model` takes, each the latest of its family.
    public static let aliases = ["opus", "sonnet", "haiku", "fable"]
    /// The efforts `claude --effort` takes, lowest first.
    public static let efforts = ["low", "medium", "high", "xhigh", "max"]

    /// "Opus" for an alias or a full name ("claude-opus-5-5", "claude-opus-5-5[1m]"); the name itself when unknown.
    public static func family(_ model: String) -> String {
        let name = model.lowercased()
        return aliases.first { name == $0 || name.contains("-\($0)") || name.hasPrefix($0) }.map(\.capitalized) ?? model
    }

    /// "L", "M", "H", "VH", "Max": short enough for a card.
    public static func shortEffort(_ effort: String) -> String {
        switch effort.lowercased() {
        case "low": "L"
        case "medium": "M"
        case "high": "H"
        case "xhigh": "VH"
        case "max": "Max"
        default: effort
        }
    }

    /// "Low", "Medium", "High", "Very High", "Max": in menus and tooltips.
    public static func effortTitle(_ effort: String) -> String {
        effort.lowercased() == "xhigh" ? "Very High" : effort.capitalized
    }

    /// "450k", "12k", "800": a context's size on a card.
    public static func shortTokens(_ tokens: Int) -> String {
        tokens < 1000 ? "\(tokens)" : "\(Int((Double(tokens) / 1000).rounded()))k"
    }

    /// Claude Code's user settings, where its own model and effort are.
    public static var settingsPath: String {
        (ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? NSHomeDirectory() + "/.claude") + "/settings.json"
    }

    /// Claude Code's own model and effort, what a session started without --model or --effort runs on. Best effort.
    public static func defaults(settings path: String) -> (model: String?, effort: String?) {
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (nil, nil) }
        let effort = (object["effortLevel"] as? String).flatMap { efforts.contains($0) ? $0 : nil }
        return ((object["model"] as? String).flatMap { $0.isEmpty ? nil : $0 }, effort)
    }

    /// What the session's last reply ran on, and the tokens its context holds since.
    public struct Usage: Equatable, Sendable {
        public var model: String?
        public var effort: String?
        public var contextTokens: Int?
        /// When the reply was written: a change HQ made after it still holds.
        public var at: Date?

        public init(model: String? = nil, effort: String? = nil, contextTokens: Int? = nil, at: Date? = nil) {
            self.model = model
            self.effort = effort
            self.contextTokens = contextTokens
            self.at = at
        }
    }

    /// The last reply of the main thread in the end of a transcript: its model, its effort, and its input, cache and output
    /// tokens, which the next turn starts from. Nil when the tail has none. Best effort: the format is Claude Code's own.
    public static func usage(_ path: String, tail: Int = 262_144) -> Usage? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(tail) ? size - UInt64(tail) : 0)
        return usage(in: String(decoding: handle.readDataToEndOfFile(), as: UTF8.self))
    }

    static func usage(in text: String) -> Usage? {
        for line in text.split(separator: "\n").reversed() where line.contains("\"type\":\"assistant\"") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["type"] as? String == "assistant", object["isSidechain"] as? Bool != true,
                  let message = object["message"] as? [String: Any] else { continue }
            let tokens = (message["usage"] as? [String: Any]).map { usage in
                ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"]
                    .compactMap { usage[$0] as? Int }.reduce(0, +)
            }
            // A reply Claude Code made up (an error, an interrupt) says "<synthetic>": the last real one says more.
            guard let model = message["model"] as? String, model != "<synthetic>" else { continue }
            let at = (object["timestamp"] as? String).flatMap { try? Date($0, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }
            return Usage(model: model, effort: object["effort"] as? String, contextTokens: tokens, at: at)
        }
        return nil
    }
}
