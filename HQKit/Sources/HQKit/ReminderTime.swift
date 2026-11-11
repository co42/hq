import Foundation

/// When a reminder or a row put Later comes back: typed (`hq remind --at`) or picked from Later's menu.
public enum ReminderTime {
    /// The hour a day without a time means.
    public static let morning = 9

    /// The hour This Evening means.
    public static let evening = 18

    /// The When picker's choices, in order.
    public enum Preset: String, CaseIterable, Sendable {
        case hour, evening, tomorrow, nextWeek

        public var title: String {
            switch self {
            case .hour: "In 1 Hour"
            case .evening: "This Evening"
            case .tomorrow: "Tomorrow"
            case .nextWeek: "Next Week"
            }
        }

        /// The choices that make sense now: This Evening only until an hour before it.
        public static func available(now: Date = .now, calendar: Calendar = .current) -> [Preset] {
            allCases.filter { $0 != .evening || calendar.component(.hour, from: now) < ReminderTime.evening - 1 }
        }
    }

    public static func date(_ preset: Preset, now: Date = .now, calendar: Calendar = .current) -> Date {
        switch preset {
        case .hour: now.addingTimeInterval(3600)
        case .evening: at(evening, 0, dayAfter: now, days: 0, calendar: calendar)
        case .tomorrow: at(morning, 0, dayAfter: now, days: 1, calendar: calendar)
        case .nextWeek: next(weekday: 2, after: now, hour: morning, minute: 0, calendar: calendar)
        }
    }

    /// A typed time: the date it means, or the first word it doesn't read.
    public enum Reading: Sendable, Equatable {
        case date(Date)
        case unread(String)
    }

    /// `16:00`, `3 pm`, `noon`, `in 1h30`, `in an hour`, `tomorrow at 15:00`, `tomorrow evening`, `fri 3pm`, `next week`,
    /// `2026-11-09 9am`. A time alone that has passed today means tomorrow; nil when a word isn't read.
    public static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> Date? {
        if case .date(let date) = read(text, now: now, calendar: calendar) { date } else { nil }
    }

    /// `parse`, saying which word it doesn't read: a time is never given while a word is left unread.
    public static func read(_ text: String, now: Date = .now, calendar: Calendar = .current) -> Reading {
        let words = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ".")))
            .split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
        guard let first = words.first else { return .unread("") }
        let own = first == "in" ? relative(words.dropFirst(), now: now, calendar: calendar) : named(words, now: now, calendar: calendar)
        if case .date = own { return own }
        return detected(text, now: now, calendar: calendar).map(Reading.date) ?? own
    }

    /// Wordier English ("next friday at 3pm") as macOS reads dates in text, only when it reads all of it; a day alone means
    /// its morning.
    static func detected(_ text: String, now: Date, calendar: Calendar) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ".,")))
        guard !trimmed.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.range == NSRange(trimmed.startIndex..., in: trimmed), var date = match.date else { return nil }
        let words = trimmed.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let timed = words.contains { ["at", "@"].contains($0) || part($0) != nil || $0.contains(":") || $0.hasSuffix("am") || $0.hasSuffix("pm") }
        if !timed { date = calendar.date(bySettingHour: morning, minute: 0, second: 0, of: date) ?? date }
        return date > now ? date : nil
    }

    /// A day, a time of day, or both, in any order, with `at`, `on` or `this` between: every word read, or the first that isn't.
    static func named(_ words: [String], now: Date, calendar: Calendar) -> Reading {
        var day: Day?
        var time: (hour: Int, minute: Int)?
        var this = false
        var index = 0
        while index < words.count {
            let word = words[index]
            let following = index + 1 < words.count ? words[index + 1] : nil
            index += 1
            if ["at", "@", "on"].contains(word) { continue }
            if word == "this" { this = true; continue }
            if day == nil, word == "next", following == "week" { day = .nextWeek; index += 1; continue }
            if day == nil, let named = Day(word) { day = named; continue }
            if day == nil, time == nil, let stamp = iso(word, calendar: calendar) {
                if case .instant(let date) = stamp { return words.count == 1 ? .date(date) : .unread(word) }
                if case .day(let components, let clock) = stamp { day = .date(components); time = clock }
                continue
            }
            if time == nil, let following, following == "am" || following == "pm", let clock = clock(word + following) {
                time = clock
                index += 1
                continue
            }
            if time == nil, let clock = clock(word) ?? part(word) { time = clock; continue }
            return .unread(word)
        }
        if day == nil, this, time != nil { day = .today }
        guard day != nil || time != nil else { return .unread(words.joined(separator: " ")) }
        let hour = time?.hour ?? day?.hour ?? now.hour(calendar) + 1
        let minute = time?.minute ?? 0
        switch day {
        case nil:
            let today = at(hour, minute, dayAfter: now, days: 0, calendar: calendar)
            return .date(today > now ? today : at(hour, minute, dayAfter: now, days: 1, calendar: calendar))
        case .today?, .tonight?:
            guard time != nil || day == .tonight else { return .date(calendar.dateInterval(of: .hour, for: now)?.end ?? now) }
            return .date(at(hour, minute, dayAfter: now, days: 0, calendar: calendar))
        case .tomorrow?: return .date(at(hour, minute, dayAfter: now, days: 1, calendar: calendar))
        case .weekday(let weekday)?: return .date(next(weekday: weekday, after: now, hour: hour, minute: minute, calendar: calendar))
        case .nextWeek?: return .date(next(weekday: 2, after: now, hour: hour, minute: minute, calendar: calendar))
        case .date(let components)?:
            var components = components
            components.hour = hour
            components.minute = minute
            return calendar.date(from: components).map(Reading.date) ?? .unread(words.joined(separator: " "))
        }
    }

    /// The day a typed time names.
    enum Day: Equatable {
        case today, tonight, tomorrow, nextWeek
        case weekday(Int)
        case date(DateComponents)

        init?(_ word: String) {
            switch word {
            case "today": self = .today
            case "tonight": self = .tonight
            case "tomorrow", "tmrw": self = .tomorrow
            default:
                guard let weekday = ReminderTime.weekday(word) else { return nil }
                self = .weekday(weekday)
            }
        }

        /// Its hour when no time is given: nil for today, which means the next full hour.
        var hour: Int? {
            switch self {
            case .today: nil
            case .tonight: 20
            default: ReminderTime.morning
            }
        }
    }

    /// `2026-11-09` (a day, maybe with `T09:30`), or `2026-11-09T09:30:00Z` with its zone (an instant).
    enum Stamp {
        case day(DateComponents, (hour: Int, minute: Int)?)
        case instant(Date)
    }

    static func iso(_ word: String, calendar: Calendar) -> Stamp? {
        let parts = word.split(separator: "t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let ymd = parts[0].split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard parts[0].count == 10, ymd.count == 3, let year = ymd[0], let month = ymd[1], let day = ymd[2] else { return nil }
        let components = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: day)
        guard components.isValidDate else { return nil }
        guard parts.count == 2 else { return .day(components, nil) }
        if parts[1].hasSuffix("z") || parts[1].contains("+") || parts[1].contains("-") {
            return (try? Date(word.uppercased(), strategy: .iso8601)).map(Stamp.instant)
        }
        // Seconds don't matter to a reminder.
        let hm = parts[1].split(separator: ":").prefix(2).joined(separator: ":")
        return clock(hm).map { .day(components, $0) }
    }

    /// "18:00" today, "Tomorrow 9:00", "Monday 9:00" within the week, else "9 Nov 9:00".
    public static func describe(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = String(format: "%d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return time
        case 1: return "Tomorrow \(time)"
        case 2...6: return "\(date.formatted(.dateTime.weekday(.wide))) \(time)"
        default: return "\(date.formatted(.dateTime.day().month(.abbreviated))) \(time)"
        }
    }

    /// "19:15" today, "Sat 9:00" within the week, else "9 Nov 9:00": beside a choice that already names its day.
    public static func brief(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = String(format: "%d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return time
        case 1...6: return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
        default: return "\(date.formatted(.dateTime.day().month(.abbreviated))) \(time)"
        }
    }

    /// "Friday 13 November, 15:00": a typed time, read back in full.
    public static func full(_ date: Date) -> String {
        "\(date.formatted(.dateTime.weekday(.wide).day().month(.wide))), \(date.formatted(.dateTime.hour().minute()))"
    }

    // MARK: Parts

    /// After `in`: `2h`, `30 minutes`, `1h30`, `1h 30m`, `1 hour and 30 minutes`, `an hour`, `half an hour`, `3d`, `2 weeks`.
    /// Days and weeks are calendar days: the same hour across a clock change.
    static func relative(_ words: ArraySlice<String>, now: Date, calendar: Calendar) -> Reading {
        // Numbers and words apart: "1h30" is 1, h, 30.
        var tokens: [String] = []
        for word in words {
            var current = ""
            for character in word {
                let digit = character.isNumber || character == "."
                if let last = current.last, (last.isNumber || last == ".") != digit {
                    tokens.append(current)
                    current = ""
                }
                current.append(character)
            }
            if !current.isEmpty { tokens.append(current) }
        }
        var seconds = 0.0, days = 0.0
        var amount: Double?
        var lastUnit: Double?
        var read = false
        for token in tokens {
            if let number = Double(token) {
                guard amount == nil else { return .unread(token) }
                amount = number
                continue
            }
            switch token {
            case "a", "an":
                if amount == nil { amount = 1 }
                continue
            case "half":
                guard amount == nil else { return .unread(token) }
                amount = 0.5
                continue
            case "and": continue
            default: break
            }
            guard let value = amount, let unit = unit(token) else { return .unread(token) }
            if unit >= 86_400 { days += value * unit / 86_400 } else { seconds += value * unit }
            amount = nil
            lastUnit = unit
            read = true
        }
        // "1h30": minutes after hours.
        if let value = amount {
            guard lastUnit == 3600 else { return .unread(tokens.last ?? "in") }
            seconds += value * 60
        }
        guard read else { return .unread((["in"] + words).joined(separator: " ")) }
        var date = now.addingTimeInterval(seconds)
        if days == days.rounded() {
            date = calendar.date(byAdding: .day, value: Int(days), to: date) ?? date
        } else {
            date = date.addingTimeInterval(days * 86_400)
        }
        return .date(date)
    }

    /// Seconds in a unit `relative` reads.
    static func unit(_ word: String) -> Double? {
        switch word {
        case "m", "min", "mins", "minute", "minutes": 60
        case "h", "hr", "hrs", "hour", "hours": 3600
        case "d", "day", "days": 86_400
        case "w", "wk", "wks", "week", "weeks": 604_800
        default: nil
        }
    }

    /// A time of day said in words: `morning`, `noon`, `afternoon`, `evening`, `tonight`.
    static func part(_ word: String) -> (hour: Int, minute: Int)? {
        switch word {
        case "morning": (morning, 0)
        case "noon", "midday": (12, 0)
        case "afternoon": (14, 0)
        case "evening": (evening, 0)
        case "tonight", "night": (20, 0)
        default: nil
        }
    }

    /// `16:00`, `9`, `9am`, `6pm`, `18h`, `18h30`.
    static func clock(_ text: String) -> (hour: Int, minute: Int)? {
        var text = Substring(text)
        var pm = false, am = false
        if text.hasSuffix("pm") { pm = true; text = text.dropLast(2) } else if text.hasSuffix("am") { am = true; text = text.dropLast(2) }
        let parts = text.split(whereSeparator: { $0 == ":" || $0 == "h" || $0 == "." }).map(String.init)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              var hour = Int(parts[0]), let minute = parts.count > 1 ? Int(parts[1]) : 0 else { return nil }
        if pm && hour < 12 { hour += 12 }
        if am && hour == 12 { hour = 0 }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    /// 1 is Sunday, as Calendar counts.
    static func weekday(_ text: String) -> Int? {
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        guard text.count >= 3 else { return nil }
        return names.firstIndex { $0.hasPrefix(text) }.map { $0 + 1 }
    }

    static func at(_ hour: Int, _ minute: Int, dayAfter now: Date, days: Int, calendar: Calendar) -> Date {
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: min(hour, 23), minute: minute, second: 0, of: day) ?? day
    }

    /// The next such weekday after today, a week on when it's today.
    static func next(weekday: Int, after now: Date, hour: Int, minute: Int, calendar: Calendar) -> Date {
        let today = calendar.component(.weekday, from: now)
        let ahead = (weekday - today + 7) % 7
        return at(hour, minute, dayAfter: now, days: ahead == 0 ? 7 : ahead, calendar: calendar)
    }
}

private extension Date {
    func hour(_ calendar: Calendar) -> Int { calendar.component(.hour, from: self) }
}
