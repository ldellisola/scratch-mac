import Foundation

/// A named, reproducible database for UI tests, screenshots and benchmarks (spec §9.4).
///
/// `LaunchOptions` selects one with `-ScratchFixture <raw value>`, and ``ScratchStorage/open(_:now:)`` seeds it into
/// an empty, isolated directory. Their contents are in `FixtureContent.swift`.
public enum Fixture: String, CaseIterable, Sendable {
    /// No notes and no saved session.
    case empty
    /// Six notes that mirror the design mockup, with "Deploy checklist" and a curl note open in two tabs.
    case typical
    /// A note of exactly 10,000 lines of alternating prose and code, and a small one. For scrolling and switching.
    case hugeNote = "huge-note"
    /// 2,000 notes, for the sidebar and for search.
    case manyNotes = "many-notes"
    /// "Groceries" and two deleted notes: "Old meeting notes" (deleted 2 days ago) and "Ancient" (31 days ago, past the
    /// 30-day retention, so the purge removes it).
    case recentlyDeleted = "recently-deleted"
    /// "Formatting": one note with a bullet, a nested bullet, two checkboxes, bold, inline code, a link, unclosed
    /// markers and a fenced block whose markers must stay literal (spec §6.4).
    case formatting
    /// "Code": one note with a `swift`, `python`, `sql`, `json` and `bash` block, a block whose fence has no name (it
    /// holds JavaScript, so the editor detects the language), and prose between them (spec §6.4).
    case code

    /// Writes this fixture's notes and session through the stores. All dates are relative to `now`.
    ///
    /// The notes go in as one transaction, so a failure leaves none of them behind. Seed into an empty database: this
    /// adds to what is there and does not remove it.
    public func seed(notes: NoteStore, session: SessionStore, now: Date) throws {
        let content = FixtureContent.make(self, now: now)
        try notes.saveAll(content.notes)
        if let state = content.session {
            try session.save(state)
        }
    }
}
