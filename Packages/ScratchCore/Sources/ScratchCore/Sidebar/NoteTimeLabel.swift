import Foundation

/// The edit time on a sidebar row (spec §6.2): the time of day for notes in Today and Yesterday, otherwise the date.
public enum NoteTimeLabel {
    /// The label for a note edited at `date`, as read at `now`, in `calendar`'s time zone and `locale`'s language.
    ///
    /// - Today, yesterday and a date in the future (a wrong clock puts those under Today): the time of day, in the
    ///   locale's own clock, for example `10:42` or `10:42 AM`.
    /// - Earlier in the same year: the month and the day, for example `Oct 14`.
    /// - Before this year: the month, the day and the year, for example `Oct 14, 2025`.
    ///
    /// "Yesterday" is the previous calendar day, as in ``SidebarSections``. The text is the locale's: its order of the
    /// parts, its month names and its spaces (some of them no-break spaces, which differ between systems).
    public static func text(for date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let template: String
        switch SidebarSections.group(of: date, now: now, calendar: calendar) {
        case .today, .yesterday:
            template = "jmm"
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            template = sameYear ? "MMMd" : "yMMMd"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
