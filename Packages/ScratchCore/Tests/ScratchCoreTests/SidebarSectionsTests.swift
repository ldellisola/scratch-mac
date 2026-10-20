import Foundation
import Testing

@testable import ScratchCore

// Spec §6.2 (Sidebar: the note list): pinned notes in their own section at the top, unpinned notes under Today /
// Yesterday / Earlier, and Recently Deleted last. "Today" is a calendar day in the owner's time zone, not the last 24
// hours.

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

private func summary(
    _ name: String,
    modified: Date,
    pinnedAt: Date? = nil,
    deletedAt: Date? = nil
) -> NoteSummary {
    NoteSummary(
        id: NoteID(rawValue: name),
        displayTitle: name,
        hasTitle: true,
        preview: "",
        modifiedAt: modified,
        pinnedAt: pinnedAt,
        deletedAt: deletedAt
    )
}

private func make(live: [NoteSummary] = [], deleted: [NoteSummary] = [], now: Date) -> [SidebarSection] {
    SidebarSections.make(live: live, deleted: deleted, now: now, calendar: osloCalendar())
}

private func names(_ section: SidebarSection) -> [String] { section.notes.map(\.id.rawValue) }

/// The group each note landed in, by note name.
private func groups(of sections: [SidebarSection]) -> [String: SidebarGroup] {
    var result: [String: SidebarGroup] = [:]
    for section in sections {
        for note in section.notes { result[note.id.rawValue] = section.group }
    }
    return result
}

@Test func groupsByCalendarDayNotTwentyFourHours() {
    let now = osloDate(2026, 10, 19, 9, 0)
    let sections = make(
        live: [
            summary("justAfterMidnight", modified: osloDate(2026, 10, 19, 0, 30)),
            summary("lateLastNight", modified: osloDate(2026, 10, 18, 23, 30)),
            // Less than 24 hours ago, but on the previous calendar day.
            summary("yesterdayMorning", modified: osloDate(2026, 10, 18, 9, 30)),
            summary("startOfYesterday", modified: osloDate(2026, 10, 18, 0, 0)),
            // 33 hours ago: a 24 to 48 hour rule would call it yesterday, the calendar calls it earlier.
            summary("dayBeforeYesterday", modified: osloDate(2026, 10, 17, 23, 59)),
            summary("lastWeek", modified: osloDate(2026, 10, 12, 12, 0)),
        ],
        now: now
    )
    #expect(
        groups(of: sections) == [
            "justAfterMidnight": .today,
            "lateLastNight": .yesterday,
            "yesterdayMorning": .yesterday,
            "startOfYesterday": .yesterday,
            "dayBeforeYesterday": .earlier,
            "lastWeek": .earlier,
        ])
}

@Test func midnightStartsANewDay() {
    let now = osloDate(2026, 10, 19, 9, 0)
    let sections = make(
        live: [
            summary("exactlyMidnight", modified: osloDate(2026, 10, 19, 0, 0)),
            summary("oneMinuteBefore", modified: osloDate(2026, 10, 18, 23, 59)),
        ],
        now: now
    )
    #expect(groups(of: sections) == ["exactlyMidnight": .today, "oneMinuteBefore": .yesterday])
}

@Test func theTimeZoneOfTheCalendarDecidesTheDay() {
    // 00:30 on the 19th in Oslo is 22:30 on the 18th in UTC, and 09:00 in Oslo is 07:00 in UTC.
    let now = osloDate(2026, 10, 19, 9, 0)
    let note = summary("justAfterMidnightInOslo", modified: osloDate(2026, 10, 19, 0, 30))
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let inOslo = SidebarSections.make(live: [note], deleted: [], now: now, calendar: osloCalendar())
    let inUTC = SidebarSections.make(live: [note], deleted: [], now: now, calendar: utc)
    #expect(groups(of: inOslo) == ["justAfterMidnightInOslo": .today])
    #expect(groups(of: inUTC) == ["justAfterMidnightInOslo": .yesterday])
}

@Test func dstChangeStillUsesCalendarDays() {
    // Oslo left summer time at 03:00 on 2026-10-25, so that day is 25 hours long. 24 hours before the start of
    // 2026-10-26 is 01:00 on the 25th, and a rule that subtracts 24 hours would put the first hour of the 25th in
    // "earlier".
    let now = osloDate(2026, 10, 26, 0, 30)
    let sections = make(
        live: [
            summary("lateOnThe25th", modified: osloDate(2026, 10, 25, 23, 0)),
            summary("onePastOne", modified: osloDate(2026, 10, 25, 1, 0)),
            summary("halfPastMidnight", modified: osloDate(2026, 10, 25, 0, 30)),
            summary("startOfThe25th", modified: osloDate(2026, 10, 25, 0, 0)),
            summary("lateOnThe24th", modified: osloDate(2026, 10, 24, 23, 30)),
        ],
        now: now
    )
    #expect(
        groups(of: sections) == [
            "lateOnThe25th": .yesterday,
            "onePastOne": .yesterday,
            "halfPastMidnight": .yesterday,
            "startOfThe25th": .yesterday,
            "lateOnThe24th": .earlier,
        ])
}

@Test func theDayAfterASpringChangeStillHasAYesterday() {
    // Oslo moved to summer time at 02:00 on 2026-03-29, so that day is 23 hours long.
    let now = osloDate(2026, 3, 30, 8, 0)
    let sections = make(
        live: [
            summary("startOfThe29th", modified: osloDate(2026, 3, 29, 0, 0)),
            summary("lateOnThe28th", modified: osloDate(2026, 3, 28, 23, 59)),
        ],
        now: now
    )
    #expect(groups(of: sections) == ["startOfThe29th": .yesterday, "lateOnThe28th": .earlier])
}

@Test func pinnedSectionFirstInGivenOrder() {
    let now = osloDate(2026, 10, 19, 9, 0)
    let sections = make(
        live: [
            // Given order, which the store sorts: not by pinnedAt and not by modifiedAt.
            summary("pinnedOld", modified: osloDate(2026, 1, 1), pinnedAt: osloDate(2026, 10, 19, 8, 0)),
            summary("pinnedNew", modified: osloDate(2026, 10, 19, 8, 30), pinnedAt: osloDate(2026, 9, 1)),
            summary("todayNote", modified: osloDate(2026, 10, 19, 8, 45)),
            summary("earlierNote", modified: osloDate(2026, 10, 1)),
        ],
        now: now
    )
    #expect(sections.map(\.group) == [.pinned, .today, .earlier])
    #expect(names(sections[0]) == ["pinnedOld", "pinnedNew"])
    #expect(names(sections[1]) == ["todayNote"])
    #expect(names(sections[2]) == ["earlierNote"])
}

@Test func aPinnedNoteIsNotAlsoListedUnderItsDay() {
    let now = osloDate(2026, 10, 19, 9, 0)
    let sections = make(
        live: [summary("pinnedToday", modified: osloDate(2026, 10, 19, 8, 0), pinnedAt: osloDate(2026, 10, 19, 8, 1))],
        now: now
    )
    #expect(sections.map(\.group) == [.pinned])
    #expect(names(sections[0]) == ["pinnedToday"])
}

@Test func notesKeepTheGivenOrderInsideEachGroup() {
    let now = osloDate(2026, 10, 19, 9, 0)
    let sections = make(
        live: [
            summary("c", modified: osloDate(2026, 10, 19, 8, 0)),
            summary("a", modified: osloDate(2026, 10, 19, 8, 30)),
            summary("b", modified: osloDate(2026, 10, 19, 7, 0)),
        ],
        now: now
    )
    #expect(names(sections[0]) == ["c", "a", "b"])
}

@Test func emptyGroupsOmitted() {
    let now = osloDate(2026, 10, 19, 9, 0)
    let onlyEarlier = make(live: [summary("old", modified: osloDate(2026, 9, 1))], now: now)
    #expect(onlyEarlier.map(\.group) == [.earlier])
    let todayAndYesterday = make(
        live: [
            summary("t", modified: osloDate(2026, 10, 19, 8, 0)),
            summary("y", modified: osloDate(2026, 10, 18, 8, 0)),
        ],
        now: now
    )
    #expect(todayAndYesterday.map(\.group) == [.today, .yesterday])
    #expect(make(now: now).isEmpty)
}

@Test func recentlyDeletedLastOnlyWhenNonEmpty() {
    let now = osloDate(2026, 10, 19, 9, 0)
    let live = [
        summary("pinned", modified: osloDate(2026, 10, 19, 8, 0), pinnedAt: osloDate(2026, 10, 19, 8, 1)),
        summary("today", modified: osloDate(2026, 10, 19, 8, 0)),
        summary("yesterday", modified: osloDate(2026, 10, 18, 8, 0)),
        summary("earlier", modified: osloDate(2026, 10, 1)),
    ]
    let deleted = [
        summary("goneB", modified: osloDate(2026, 10, 19, 8, 0), deletedAt: osloDate(2026, 10, 19, 8, 30)),
        summary("goneA", modified: osloDate(2026, 8, 1), deletedAt: osloDate(2026, 10, 1)),
    ]

    let without = make(live: live, now: now)
    #expect(without.map(\.group) == [.pinned, .today, .yesterday, .earlier])

    let with = make(live: live, deleted: deleted, now: now)
    #expect(with.map(\.group) == [.pinned, .today, .yesterday, .earlier, .recentlyDeleted])
    // The deleted notes keep their given order and are not grouped by day.
    #expect(names(with[4]) == ["goneB", "goneA"])
}

@Test func recentlyDeletedAloneWhenThereAreNoLiveNotes() {
    let now = osloDate(2026, 10, 19, 9, 0)
    let sections = make(
        deleted: [summary("gone", modified: osloDate(2026, 10, 1), deletedAt: osloDate(2026, 10, 2))],
        now: now
    )
    #expect(sections.map(\.group) == [.recentlyDeleted])
    #expect(names(sections[0]) == ["gone"])
}

@Test func futureDateCountsAsToday() {
    let now = osloDate(2026, 10, 19, 9, 0)
    let sections = make(
        live: [
            summary("laterToday", modified: osloDate(2026, 10, 19, 23, 59)),
            summary("tomorrow", modified: osloDate(2026, 10, 20, 8, 0)),
            summary("nextYear", modified: osloDate(2027, 3, 1)),
        ],
        now: now
    )
    #expect(sections.map(\.group) == [.today])
    #expect(names(sections[0]) == ["laterToday", "tomorrow", "nextYear"])
}
