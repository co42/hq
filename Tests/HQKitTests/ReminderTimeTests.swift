import Foundation
import Testing
@testable import HQKit

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

/// Friday 6 November 2026, 18:15 in Paris.
private let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 18, minute: 15))!

private func parts(_ date: Date?) -> String {
    guard let date else { return "nil" }
    let c = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
    return String(format: "%02d-%02d %02d:%02d", c.month!, c.day!, c.hour!, c.minute!)
}

@Test func remindAtTimesOfDay() {
    #expect(parts(ReminderTime.parse("19:30", now: now, calendar: calendar)) == "11-06 19:30")
    #expect(parts(ReminderTime.parse("9:00", now: now, calendar: calendar)) == "11-07 09:00")
    #expect(parts(ReminderTime.parse("6pm", now: now, calendar: calendar)) == "11-07 18:00")
    #expect(parts(ReminderTime.parse("21h", now: now, calendar: calendar)) == "11-06 21:00")
    #expect(parts(ReminderTime.parse("18h30", now: now, calendar: calendar)) == "11-06 18:30")
}

@Test func remindRelativeAndDays() {
    #expect(parts(ReminderTime.parse("in 2h", now: now, calendar: calendar)) == "11-06 20:15")
    #expect(parts(ReminderTime.parse("in 30 minutes", now: now, calendar: calendar)) == "11-06 18:45")
    #expect(parts(ReminderTime.parse("in 1d", now: now, calendar: calendar)) == "11-07 18:15")
    #expect(parts(ReminderTime.parse("tomorrow", now: now, calendar: calendar)) == "11-07 09:00")
    #expect(parts(ReminderTime.parse("tomorrow 14:00", now: now, calendar: calendar)) == "11-07 14:00")
    #expect(parts(ReminderTime.parse("monday", now: now, calendar: calendar)) == "11-09 09:00")
    #expect(parts(ReminderTime.parse("fri 10:00", now: now, calendar: calendar)) == "11-13 10:00")
    #expect(parts(ReminderTime.parse("tonight", now: now, calendar: calendar)) == "11-06 20:00")
    #expect(parts(ReminderTime.parse("2026-11-09T09:30", now: now, calendar: calendar)) == "11-09 09:30")
    #expect(parts(ReminderTime.parse("2026-11-10", now: now, calendar: calendar)) == "11-10 09:00")
    #expect(parts(ReminderTime.parse("next week", now: now, calendar: calendar)) == "11-09 09:00")
    // macOS reads wordier dates against the real clock.
    let friday = ReminderTime.parse("next friday at 3pm")
    #expect(friday.map { Calendar.current.dateComponents([.weekday, .hour], from: $0) } == DateComponents(hour: 15, weekday: 6))
    #expect(ReminderTime.parse("someday", now: now, calendar: calendar) == nil)
    #expect(ReminderTime.parse("25:00", now: now, calendar: calendar) == nil)
}

@Test func laterPresetsAndTheirNames() {
    #expect(parts(ReminderTime.date(.hour, now: now, calendar: calendar)) == "11-06 19:15")
    #expect(parts(ReminderTime.date(.tomorrow, now: now, calendar: calendar)) == "11-07 09:00")
    #expect(parts(ReminderTime.date(.nextWeek, now: now, calendar: calendar)) == "11-09 09:00")
    #expect(parts(ReminderTime.date(.evening, now: now.addingTimeInterval(-6 * 3600), calendar: calendar)) == "11-06 18:00")
    #expect(ReminderTime.Preset.available(now: now, calendar: calendar) == [.hour, .tomorrow, .nextWeek])
    #expect(ReminderTime.Preset.available(now: now.addingTimeInterval(-6 * 3600), calendar: calendar) == [.hour, .evening, .tomorrow, .nextWeek])
    #expect(ReminderTime.describe(ReminderTime.date(.hour, now: now, calendar: calendar), now: now, calendar: calendar) == "19:15")
    #expect(ReminderTime.describe(ReminderTime.date(.tomorrow, now: now, calendar: calendar), now: now, calendar: calendar) == "Tomorrow 9:00")
}
