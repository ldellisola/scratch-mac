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
