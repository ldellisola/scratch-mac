import Foundation
import Testing

@testable import ScratchCore

// Spec §6.2 (Sidebar rows): the edit time is the time of day for Today and Yesterday, otherwise the date. The date has
// no year in the current year.

private let oslo = TimeZone(identifier: "Europe/Oslo")!

private func osloCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = oslo
    return calendar
}

/// A moment on the wall clock of Oslo.
private func osloDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    return osloCalendar().date(from: parts)!
}

private func label(_ date: Date, now: Date, locale: String) -> String {
    NoteTimeLabel.text(for: date, now: now, calendar: osloCalendar(), locale: Locale(identifier: locale))
}

/// ICU puts a narrow no-break space (U+202F) before AM or PM and a no-break space (U+00A0) in some formats, and which
/// one depends on the ICU version. They are all a space to the reader, so compare with plain spaces.
private func spaced(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
}

@Test func timeOfDayForToday() {
    let now = osloDate(2026, 10, 19, 12, 0)
    #expect(label(osloDate(2026, 10, 19, 10, 42), now: now, locale: "en_GB") == "10:42")
}

@Test func timeOfDayUsesTheLocalesClock() {
    let now = osloDate(2026, 10, 19, 21, 0)
    #expect(label(osloDate(2026, 10, 19, 16, 5), now: now, locale: "en_GB") == "16:05")
    let us = spaced(label(osloDate(2026, 10, 19, 16, 5), now: now, locale: "en_US"))
    #expect(us.contains("4:05"))
    #expect(us.contains("PM"))
}

@Test func timeOfDayForYesterdayInUSLocale() {
    let now = osloDate(2026, 10, 19, 9, 0)
    let text = spaced(label(osloDate(2026, 10, 18, 10, 42), now: now, locale: "en_US"))
    #expect(text.contains("10:42"))
    #expect(text.contains("AM"))
    #expect(!text.contains("Oct"))
}

@Test func yesterdayIsAPreviousCalendarDayEvenWithinTwentyFourHours() {
    let now = osloDate(2026, 10, 19, 9, 0)
    #expect(label(osloDate(2026, 10, 18, 23, 30), now: now, locale: "en_GB") == "23:30")
}

@Test func timeOfDayForADateInTheFuture() {
    // Clock skew puts a note under Today, so its label is a time as well.
    let now = osloDate(2026, 10, 19, 9, 0)
    #expect(label(osloDate(2026, 10, 19, 23, 15), now: now, locale: "en_GB") == "23:15")
    #expect(label(osloDate(2027, 2, 3, 7, 30), now: now, locale: "en_GB") == "07:30")
}

@Test func monthAndDayThisYear() {
    let now = osloDate(2026, 10, 19, 9, 0)
    #expect(spaced(label(osloDate(2026, 10, 14, 15, 30), now: now, locale: "en_US")) == "Oct 14")
}

@Test func twoDaysAgoIsADate() {
    let now = osloDate(2026, 10, 19, 9, 0)
    #expect(spaced(label(osloDate(2026, 10, 17, 23, 59), now: now, locale: "en_US")) == "Oct 17")
}

@Test func includesYearForOlderDates() {
    let now = osloDate(2026, 10, 19, 9, 0)
    #expect(spaced(label(osloDate(2025, 10, 14, 15, 30), now: now, locale: "en_US")) == "Oct 14, 2025")
}

@Test func theYearChangesOnNewYearNotOnADayCount() {
    let now = osloDate(2027, 1, 3, 9, 0)
    #expect(spaced(label(osloDate(2026, 12, 31, 12, 0), now: now, locale: "en_US")) == "Dec 31, 2026")
    #expect(spaced(label(osloDate(2027, 1, 1, 12, 0), now: now, locale: "en_US")) == "Jan 1")
}

@Test func newYearsDayIsYesterdayJustAfterMidnight() {
    let now = osloDate(2027, 1, 1, 0, 10)
    #expect(label(osloDate(2026, 12, 31, 23, 0), now: now, locale: "en_GB") == "23:00")
}

@Test func usesTheCalendarsTimeZone() {
    // 08:42 UTC is 10:42 in Oslo in October, and the label is read in Oslo.
    let now = osloDate(2026, 10, 19, 12, 0)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let date = osloDate(2026, 10, 19, 10, 42)
    let inOslo = NoteTimeLabel.text(for: date, now: now, calendar: osloCalendar(), locale: Locale(identifier: "en_GB"))
    let inUTC = NoteTimeLabel.text(for: date, now: now, calendar: utc, locale: Locale(identifier: "en_GB"))
    #expect(inOslo == "10:42")
    #expect(inUTC == "08:42")
}

@Test func dateOrderFollowsTheLocale() {
    let now = osloDate(2026, 10, 19, 9, 0)
    #expect(spaced(label(osloDate(2026, 10, 14, 15, 30), now: now, locale: "en_GB")) == "14 Oct")
    #expect(spaced(label(osloDate(2025, 10, 14, 15, 30), now: now, locale: "en_GB")) == "14 Oct 2025")
}
