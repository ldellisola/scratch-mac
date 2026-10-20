import Foundation

/// What a sidebar row needs to know about a note: its title and preview, without the body.
///
/// ``NoteStore/summaries()`` reads these from derived columns, so listing thousands of notes never loads their text.
public struct NoteSummary: Equatable, Sendable {
    public let id: NoteID
    public let displayTitle: String
    public let hasTitle: Bool
    public let preview: String
    public let modifiedAt: Date
    public let pinnedAt: Date?

    public init(
        id: NoteID,
        displayTitle: String,
        hasTitle: Bool,
        preview: String,
        modifiedAt: Date,
        pinnedAt: Date? = nil
    ) {
        self.id = id
        self.displayTitle = displayTitle
        self.hasTitle = hasTitle
        self.preview = preview
        self.modifiedAt = modifiedAt
        self.pinnedAt = pinnedAt
    }
}
