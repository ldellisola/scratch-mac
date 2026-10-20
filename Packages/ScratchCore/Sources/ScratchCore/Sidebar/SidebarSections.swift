import Foundation

/// A group of rows in the sidebar (spec §6.2).
public enum SidebarGroup: Equatable, Sendable {
    case pinned
    case today
    case yesterday
    case earlier
    case recentlyDeleted
}

/// One header and the rows under it.
public struct SidebarSection: Equatable, Sendable {
    public let group: SidebarGroup
    public let notes: [NoteSummary]

    public init(group: SidebarGroup, notes: [NoteSummary]) {
        self.group = group
        self.notes = notes
    }
}

/// Splits the note list into the sidebar's sections (spec §6.2): Pinned, then Today, Yesterday and Earlier, then
/// Recently Deleted.
public enum SidebarSections {
    /// The sections for `live` (``NoteStore/summaries()``) and `deleted` (``NoteStore/deletedSummaries()``), in the
    /// order the sidebar shows them.
    ///
    /// Every section keeps the order of the notes it was given, so the caller's order (pinned first, newest edit first)
    /// decides the order of the rows. A note with a `pinnedAt` goes to ``SidebarGroup/pinned``. The others go to the
    /// group of the calendar day of their `modifiedAt` (see ``group(of:now:calendar:)``). A group with no notes has no
    /// section, and ``SidebarGroup/recentlyDeleted``, last, exists only when `deleted` has notes.
    public static func make(
        live: [NoteSummary],
        deleted: [NoteSummary],
        now: Date,
        calendar: Calendar
    ) -> [SidebarSection] {
        var pinned: [NoteSummary] = []
        var today: [NoteSummary] = []
        var yesterday: [NoteSummary] = []
        var earlier: [NoteSummary] = []
        for note in live {
            guard note.pinnedAt == nil else {
                pinned.append(note)
                continue
            }
            switch group(of: note.modifiedAt, now: now, calendar: calendar) {
            case .today: today.append(note)
            case .yesterday: yesterday.append(note)
            default: earlier.append(note)
            }
        }
        let all: [SidebarSection] = [
            SidebarSection(group: .pinned, notes: pinned),
            SidebarSection(group: .today, notes: today),
            SidebarSection(group: .yesterday, notes: yesterday),
            SidebarSection(group: .earlier, notes: earlier),
            SidebarSection(group: .recentlyDeleted, notes: deleted),
        ]
        return all.filter { !$0.notes.isEmpty }
    }

    /// Which day group an unpinned note edited at `date` is in: ``SidebarGroup/today``, ``SidebarGroup/yesterday`` or
    /// ``SidebarGroup/earlier``.
    ///
    /// The groups are calendar days in `calendar`'s time zone, not spans of 24 hours: a note from 23:30 last night is
    /// yesterday's at 09:00 even though it is less than a day old, and a day that is 23 or 25 hours long because the
    /// clocks changed is still one day. A date after the start of today, that is today or later because the clock was
    /// wrong, is today. ``NoteTimeLabel`` asks this too, so a row's label always agrees with its group.
    static func group(of date: Date, now: Date, calendar: Calendar) -> SidebarGroup {
        let startOfToday = calendar.startOfDay(for: now)
        if date >= startOfToday { return .today }
        guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) else {
            return .earlier
        }
        return date >= startOfYesterday ? .yesterday : .earlier
    }
}
