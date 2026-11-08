import Foundation

/// A Slack permalink: a message (`…/archives/C123/p1730971234000100`), a reply in a thread (the same with
/// `?thread_ts=…`), or a channel (`…/archives/C123`).
public struct SlackLink: Hashable, Sendable {
    /// The workspace's host: `example.slack.com`.
    public let host: String
    public let channel: String
    /// The message's timestamp as Slack's API writes it: `1730971234.000100`. Nil for a channel.
    public let ts: String?
    /// The thread a reply is in.
    public let threadTS: String?

    public init?(_ text: String) {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https",
              let host = url.host()?.lowercased(), host.hasSuffix(".slack.com") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[0] == "archives", let first = parts[1].first, "CGD".contains(first) else { return nil }
        self.host = host
        channel = parts[1]
        if parts.count >= 3 {
            guard let ts = Self.ts(fromPath: parts[2]) else { return nil }
            self.ts = ts
        } else {
            ts = nil
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        threadTS = query?.first { $0.name == "thread_ts" }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }

    public static func isLink(_ text: String) -> Bool { SlackLink(text) != nil }

    /// A reply in a thread, not the thread's first message.
    public var isReply: Bool { threadTS != nil && threadTS != ts }

    /// The first Slack permalink in a text, and where it is.
    public static func find(in text: String) -> (url: String, range: Range<String.Index>)? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let url = String(text[range])
            if isLink(url) { return (url, range) }
        }
        return nil
    }

    /// `p1730971234000100` → `1730971234.000100`.
    static func ts(fromPath part: String) -> String? {
        guard part.hasPrefix("p"), part.count > 7 else { return nil }
        let digits = part.dropFirst()
        guard digits.allSatisfy(\.isNumber) else { return nil }
        return "\(digits.dropLast(6)).\(digits.suffix(6))"
    }
}

/// What a Slack message link shows: who wrote it, where, its first line. Read once, when it's linked.
public struct SlackMessage: Codable, Hashable, Sendable {
    /// The channel's name without `#`; nil in a direct message.
    public var channel: String?
    public var author: String?
    public var text: String

    public init(channel: String?, author: String?, text: String) {
        self.channel = channel
        self.author = author
        self.text = text
    }

    /// The message's first line, as plain text: what a task or a reminder made from it is called.
    public var firstLine: String {
        let plain = Self.plain(text)
        return plain.split(whereSeparator: \.isNewline).lazy.map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
    }

    /// "Julien in #infra: can you look at…", "Julien: …" in a direct message, "#infra" for a channel.
    public var title: String {
        let line = firstLine
        let who = switch (author, channel) {
        case let (author?, channel?): "\(author) in #\(channel)"
        case let (author?, nil): author
        case let (nil, channel?): "#\(channel)"
        case (nil, nil): ""
        }
        if who.isEmpty { return line.isEmpty ? "Slack message" : line }
        return line.isEmpty ? who : "\(who): \(line)"
    }

    /// Slack's markup as text: `<https://x|label>` → label, `<#C1|infra>` → #infra, `<!here>` → @here, `<@U1>` → @someone,
    /// entities decoded.
    public static func plain(_ text: String) -> String {
        var out = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "<"), let close = rest[open...].firstIndex(of: ">") {
            out += rest[..<open]
            let inside = rest[rest.index(after: open)..<close]
            let parts = inside.split(separator: "|", maxSplits: 1)
            let target = parts.first.map(String.init) ?? ""
            let label = parts.count > 1 ? String(parts[1]) : nil
            switch target.first {
            case "#": out += "#" + (label ?? String(target.dropFirst()))
            case "@": out += "@" + (label ?? "someone")
            case "!": out += "@" + (label ?? String(target.dropFirst().split(separator: "^").first ?? ""))
            default: out += label ?? target
            }
            rest = rest[rest.index(after: close)...]
        }
        out += rest
        return out.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
