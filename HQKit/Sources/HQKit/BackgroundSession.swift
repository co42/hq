import Foundation

/// Claude Code's background sessions (`claude --bg`): their terminal is the claude daemon's, not Ghostty's.
/// `claude attach <handle>` shows one in a terminal, `claude stop <handle>` ends it, its conversation kept.
public enum BackgroundSession {
    private struct Entry: Decodable {
        var id: String?
        var sessionId: String?
        var kind: String?
    }

    /// The handle of `session` in `claude agents --json`, when it runs in the background.
    public static func handle(of session: String, agents json: Data) -> String? {
        guard let entries = try? JSONDecoder().decode([Entry].self, from: json) else { return nil }
        return entries.first { $0.kind == "background" && $0.sessionId == session }?.id
    }

    public struct Terminal: Sendable, Equatable {
        public var tty: String
        public var title: String

        public init(tty: String, title: String) {
            self.tty = tty
            self.title = title
        }
    }

    /// The terminal that shows a background session: the only one titled with its name that runs Claude (Claude's agent
    /// view titles a tab after the session it shows). Nil when none, or several titled alike.
    public static func terminal(showing name: String, among terminals: [Terminal], runsClaude: (String) -> Bool) -> String? {
        let titled = terminals.filter { title($0.title) == title(name) && runsClaude($0.tty) }
        return titled.count == 1 ? titled[0].tty : nil
    }

    /// A terminal title without the status glyph Claude puts before it ("✳ HQ - Slack").
    public static func title(_ raw: String) -> String {
        String(raw.drop { !$0.isLetter && !$0.isNumber }).trimmingCharacters(in: .whitespaces)
    }
}
