import Foundation

/// What a sidebar row needs to know about a note: its title and preview, without the body.
///
/// ``NoteStore/summaries()`` reads these from derived columns, so listing thousands of notes never loads their text.
/// ``NoteStore/deletedSummaries()`` returns the same rows for Recently Deleted, with ``deletedAt`` set.
public struct NoteSummary: Equatable, Sendable {
    public let id: NoteID
    public let displayTitle: String
    public let hasTitle: Bool
    public let preview: String
    public let modifiedAt: Date
    public let pinnedAt: Date?
    /// When the owner deleted the note. Nil for every row of ``NoteStore/summaries()``, and set for every row of
    /// ``NoteStore/deletedSummaries()``.
    public let deletedAt: Date?

    public init(
        id: NoteID,
        displayTitle: String,
        hasTitle: Bool,
        preview: String,
        modifiedAt: Date,
        pinnedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.displayTitle = displayTitle
        self.hasTitle = hasTitle
        self.preview = preview
        self.modifiedAt = modifiedAt
        self.pinnedAt = pinnedAt
        self.deletedAt = deletedAt
    }
}
