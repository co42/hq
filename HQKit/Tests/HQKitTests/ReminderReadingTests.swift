import Foundation
import Testing
@testable import HQKit

private let paris: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

/// Friday 6 November 2026, 18:15 in Paris.
private let friday = paris.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 18, minute: 15))!

private func when(_ text: String, now: Date = friday) -> String {
    guard let date = ReminderTime.parse(text, now: now, calendar: paris) else { return "nil" }
    let c = paris.dateComponents([.month, .day, .hour, .minute], from: date)
    return String(format: "%02d-%02d %02d:%02d", c.month!, c.day!, c.hour!, c.minute!)
}

@Test(arguments: [
    ("tomorrow at 15:00", "11-07 15:00"),
    ("tomorrow at 3pm", "11-07 15:00"),
    ("tomorrow 9am", "11-07 09:00"),
    ("tomorrow, 9:30", "11-07 09:30"),
    ("15:00 tomorrow", "11-07 15:00"),
    ("friday at 3pm", "11-13 15:00"),
    ("monday at 14:00", "11-09 14:00"),
    ("on monday at 2 pm", "11-09 14:00"),
    ("today at 19:00", "11-06 19:00"),
    ("today", "11-06 19:00"),
    ("tonight at 22:00", "11-06 22:00"),
    ("tomorrow evening", "11-07 18:00"),
    ("tomorrow morning", "11-07 09:00"),
    ("monday afternoon", "11-09 14:00"),
    ("tomorrow noon", "11-07 12:00"),
    ("at 19:30", "11-06 19:30"),
    ("noon", "11-07 12:00"),
    ("3 pm", "11-07 15:00"),
    ("next week at 10", "11-09 10:00"),
    ("2026-11-09 9am", "11-09 09:00"),
    ("2026-11-09 at 15:00", "11-09 15:00"),
    ("2026-11-09T09:30:00", "11-09 09:30"),
    ("2026-11-07T17:00:00Z", "11-07 18:00"),
    ("in 1h30", "11-06 19:45"),
    ("in 1h 30m", "11-06 19:45"),
    ("in 1 hour and 30 minutes", "11-06 19:45"),
    ("in 90 min", "11-06 19:45"),
    ("in an hour", "11-06 19:15"),
    ("in half an hour", "11-06 18:45"),
    ("in 1.5h", "11-06 19:45"),
    ("in 2 weeks", "11-20 18:15"),
    ("in 2h.", "11-06 20:15"),
])
func remindReadsEveryWord(_ text: String, _ expected: String) {
    #expect(when(text) == expected)
}

@Test(arguments: [
    ("tomorrow at 15:00 maybe", "maybe"),
    ("tomorrow blah", "blah"),
    ("someday", "someday"),
    ("in 2 parsecs", "parsecs"),
    ("in two hours", "two"),
    ("in 2", "2"),
    ("foo friday", "foo"),
    ("tomorrow monday", "monday"),
])
func remindRefusesWhatItDoesntRead(_ text: String, _ word: String) {
    #expect(ReminderTime.read(text, now: friday, calendar: paris) == .unread(word))
}

@Test func remindRefusesEmptyAndAloneFillers() {
    #expect(ReminderTime.parse("", now: friday, calendar: paris) == nil)
    #expect(ReminderTime.parse("at", now: friday, calendar: paris) == nil)
    #expect(ReminderTime.parse("this", now: friday, calendar: paris) == nil)
}

@Test func remindThisEveningIsToday() {
    let noon = paris.date(bySettingHour: 12, minute: 15, second: 0, of: friday)!
    #expect(when("this evening", now: noon) == "11-06 18:00")
    #expect(when("evening", now: noon) == "11-06 18:00")
    // Past 18:00 a bare part of the day is the next one; "this" stays today.
    #expect(when("evening") == "11-07 18:00")
    #expect(when("this evening") == "11-06 18:00")
}

@Test func remindDaysAreCalendarDaysAcrossAClockChange() {
    // Paris leaves summer time on 25 October 2026.
    let before = paris.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12))!
    #expect(when("in 1d", now: before) == "10-25 12:00")
    #expect(when("in 1w", now: before) == "10-31 12:00")
}

@Test func remindTodayLateIsTheNextHour() {
    let late = paris.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 23, minute: 20))!
    #expect(when("today", now: late) == "11-07 00:00")
}

@Test func remindWordierEnglishOnlyWhenAllOfItIsRead() {
    let after = ReminderTime.parse("the day after tomorrow")
    let expected = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: .now))
        .flatMap { Calendar.current.date(bySettingHour: ReminderTime.morning, minute: 0, second: 0, of: $0) }
    #expect(after == expected)
    #expect(ReminderTime.parse("the day after tomorrow, or so") == nil)
}
