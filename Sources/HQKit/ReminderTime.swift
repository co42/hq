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

    /// `16:00`, `9am`, `in 2h`, `in 30 minutes`, `tomorrow`, `tomorrow 9:30`, `monday`, `mon 14:00`,
    /// `2026-11-09`, `2026-11-09T09:00`. A time alone that has passed today means tomorrow.
    public static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> Date? {
        let words = text.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard let first = words.first else { return nil }
        if first == "in" { return relative(words.dropFirst().joined(), now: now) }
        if first.first?.isNumber == true, first.contains("-") {
            return NoteDate.parse(words.prefix(2).joined(separator: "T").uppercased()).map { date in
                // A day alone: its morning.
                first.contains("t") || words.count > 1 ? date : calendar.date(bySettingHour: morning, minute: 0, second: 0, of: date) ?? date
            }
        }
        let time = words.count > 1 ? clock(words[1]) : nil
        if first == "today" || first == "tonight" {
            let (hour, minute) = time ?? (first == "tonight" ? (20, 0) : (now.hour(calendar) + 1, 0))
            return at(hour, minute, dayAfter: now, days: 0, calendar: calendar)
        }
        if first == "tomorrow" {
            let (hour, minute) = time ?? (morning, 0)
            return at(hour, minute, dayAfter: now, days: 1, calendar: calendar)
        }
        if let weekday = weekday(first) {
            let (hour, minute) = time ?? (morning, 0)
            return next(weekday: weekday, after: now, hour: hour, minute: minute, calendar: calendar)
        }
        if let (hour, minute) = clock(first) {
            let today = at(hour, minute, dayAfter: now, days: 0, calendar: calendar)
            return today > now ? today : at(hour, minute, dayAfter: now, days: 1, calendar: calendar)
        }
        let phrase = words.joined(separator: " ")
        if phrase == "evening" || phrase == "this evening" { return date(.evening, now: now, calendar: calendar) }
        if phrase == "next week" { return date(.nextWeek, now: now, calendar: calendar) }
        return detected(text, now: now, calendar: calendar)
    }

    /// Wordier English ("next friday at 3pm") as macOS reads dates in text; a day alone means its morning.
    static func detected(_ text: String, now: Date, calendar: Calendar) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.range.length * 2 >= text.utf16.count, var date = match.date else { return nil }
        if text.rangeOfCharacter(from: .decimalDigits) == nil, !text.lowercased().contains("noon") {
            date = calendar.date(bySettingHour: morning, minute: 0, second: 0, of: date) ?? date
        }
        return date > now ? date : nil
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

    /// `2h`, `30m`, `90min`, `3d`, `2hours`, `1week`.
    static func relative(_ text: String, now: Date) -> Date? {
        guard let split = text.firstIndex(where: { !$0.isNumber }), let amount = Double(text[..<split]) else { return nil }
        let unit = text[split...]
        let seconds: Double
        if unit.hasPrefix("mi") || unit == "m" { seconds = 60 }
        else if unit.hasPrefix("h") { seconds = 3600 }
        else if unit.hasPrefix("d") { seconds = 86_400 }
        else if unit.hasPrefix("w") { seconds = 604_800 }
        else { return nil }
        return now.addingTimeInterval(amount * seconds)
    }

    /// `16:00`, `9`, `9am`, `6pm`, `18h`, `18h30`.
    static func clock(_ text: String) -> (Int, Int)? {
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
