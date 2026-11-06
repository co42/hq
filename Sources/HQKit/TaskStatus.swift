import Foundation

/// A task's status. A task in Review waits for the user.
public enum TaskStatus: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {
    case todo, doing, review, done

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .todo: "Todo"
        case .doing: "Doing"
        case .review: "Review"
        case .done: "Done"
        }
    }

    /// Reads a stored or typed status; the old `backlog` reads as todo.
    public init?(parsing text: String) {
        let word = text.trimmingCharacters(in: .whitespaces).lowercased()
        if word == "backlog" {
            self = .todo
        } else if let status = TaskStatus(rawValue: word) {
            self = status
        } else {
            return nil
        }
    }
}

/// What kind of work a task is, when it has one. A story is a larger piece of work, still to shape.
public enum TaskType: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {
    case story, bug, feature, chore, research, docs

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .story: "Story"
        case .bug: "Bug"
        case .feature: "Feature"
        case .chore: "Chore"
        case .research: "Research"
        case .docs: "Docs"
        }
    }

    public init?(parsing text: String) {
        self.init(rawValue: text.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

/// Where a top-level task lives: on the overview's Tasks, or in the Backlog.
public enum TaskList: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {
    case overview, backlog

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: "Tasks"
        case .backlog: "Backlog"
        }
    }

    public var other: TaskList { self == .overview ? .backlog : .overview }
}

/// `#word` in a typed title becomes a tag. A tag needs a letter, as in Obsidian: `#418` stays text.
public enum TitleTags {
    public static func split(_ text: String) -> (title: String, tags: [String]) {
        var tags: [String] = []
        let title = text.replacing(pattern) { match -> String in
            let tag = String(match.2)
            guard tag.contains(where: \.isLetter) else { return String(match.0) }
            if !tags.contains(tag) { tags.append(tag) }
            return String(match.1)
        }
        let collapsed = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (collapsed, tags)
    }

    nonisolated(unsafe) private static let pattern = /(^|\s)#([\p{L}\p{N}_\/-]+)/
}

/// Dates in task notes: `2026-11-04` or `2026-11-04T16:20`, local time.
public enum NoteDate {
    public static func parse(_ text: String) -> Date? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == "T" || $0 == " " })
        guard let day = parts.first else { return nil }
        let ymd = day.split(separator: "-").compactMap { Int($0) }
        guard ymd.count == 3 else { return nil }
        var components = DateComponents(year: ymd[0], month: ymd[1], day: ymd[2])
        if parts.count > 1 {
            let hm = parts[1].split(separator: ":").compactMap { Int($0.prefix(2)) }
            if hm.count >= 2 { components.hour = hm[0]; components.minute = hm[1] }
        }
        return Calendar.current.date(from: components)
    }

    public static func day(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func minute(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// A done top-level task on the overview moves to the Backlog the next morning.
public enum DoneRule {
    public static let hour = 5

    /// The first 05:00 local after the task was done.
    public static func moves(after done: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: done, matching: DateComponents(hour: hour, minute: 0, second: 0),
                          matchingPolicy: .nextTime, direction: .forward) ?? done.addingTimeInterval(86_400)
    }

    public static func shouldMove(done: Date, now: Date, calendar: Calendar = .current) -> Bool {
        now >= moves(after: done, calendar: calendar)
    }
}
