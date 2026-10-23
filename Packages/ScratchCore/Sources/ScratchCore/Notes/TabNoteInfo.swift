import Foundation

/// What a tab needs to know about its note without the note's text: the title the strip shows, whether the note is
/// deleted, and whether it was ever used. ``NoteStore/tabInfo(_:)`` answers it from the derived columns of the `notes`
/// table, so a launch that restores several tabs reads the body of the active note only (spec §7).
public struct TabNoteInfo: Equatable, Sendable {
    public let id: NoteID
    /// The note's ``Note/displayTitle``: its title, or else its first line with words in it, or "".
    public let displayTitle: String
    /// ``Note/hasTitle``: the owner typed a title.
    public let hasTitle: Bool
    /// When the note went to Recently Deleted, or nil for a live note.
    public let deletedAt: Date?
    /// True for a note that nobody ever typed in: it has no title and no line with words in it, and its edit time is still
    /// its creation time (``NoteStore/create(now:)`` sets both to one date, and every save of typed text changes the
    /// edit time). A note that the owner emptied is not this: its edit time moved (docs/decisions/0004).
    public let isNeverUsed: Bool

    public init(id: NoteID, displayTitle: String, hasTitle: Bool, deletedAt: Date?, isNeverUsed: Bool) {
        self.id = id
        self.displayTitle = displayTitle
        self.hasTitle = hasTitle
        self.deletedAt = deletedAt
        self.isNeverUsed = isNeverUsed
    }
}
