import Foundation

/// SQLite's `SQLITE_CORRUPT`, for a row that does not hold what the schema promises.
private let sqliteCorrupt: Int32 = 11

/// Reads and writes notes in the `notes` table (spec §8.1).
///
/// The sidebar columns `display_title`, `has_title` and `preview` are derived from the note on every save, so the
/// list never has to load a body. Any thread may call a `NoteStore`. The ``Database`` serialises the calls.
public final class NoteStore: Sendable {
    private let database: Database

    /// Brings the schema up to date with `Schema.migrate`, then uses `database`.
    public init(database: Database) throws {
        self.database = database
        try Schema.migrate(database)
    }

    /// Inserts an empty note whose creation and modification time are both `now`, and returns it.
    public func create(now: Date) throws -> Note {
        let note = Note(id: NoteID.make(), title: "", body: "", createdAt: now, modifiedAt: now)
        try save(note)
        return note
    }

    /// The note with this id, including a note that is marked deleted, or nil when there is none.
    public func note(_ id: NoteID) throws -> Note? {
        let rows = try database.query(
            """
            SELECT id, title, body, created_at, modified_at, pinned_at, deleted_at FROM notes WHERE id = ?
            """,
            [.text(id.rawValue)])
        return try rows.first.map(Self.note(from:))
    }

    /// Inserts the note, or updates the stored one with the same id, and refreshes its derived columns.
    ///
    /// A new row gets every column of `note`. An existing row gets only the title, the body and the edit time (and the
    /// derived columns that follow from them). The pin, the deletion and the creation time of a stored note are left
    /// alone, because `note` may be a copy from before the owner pinned or deleted it: an autosave of typing must
    /// never undo that. Change them with ``setPinned(_:_:now:)``, ``delete(_:now:)`` and ``restore(_:)``.
    public func save(_ note: Note) throws {
        try database.execute(Self.upsertSQL, Self.arguments(for: note))
    }

    /// Saves every note in one transaction: either all of them are stored or none is.
    public func saveAll(_ notes: [Note]) throws {
        try database.transaction {
            for note in notes { try save(note) }
        }
    }

    /// The sidebar rows: every note that is not deleted, pinned notes first, and within each group the most
    /// recently edited first (spec §6.2).
    public func summaries() throws -> [NoteSummary] {
        try summaries(
            """
            SELECT \(Self.summaryColumns) FROM notes
            WHERE deleted_at IS NULL
            \(Self.summaryOrder)
            """, [])
    }

    /// The sidebar rows of the notes that match what the owner typed in the search field, in the order of
    /// ``summaries()``. A note matches when its title and text together hold every word of `text`, each as the start
    /// of a word, ignoring case and accents. A deleted note never matches. `text` is only ever words (see
    /// ``SearchQuery``), so any input is safe. When it holds no word, nothing is filtered and this is ``summaries()``.
    public func search(_ text: String) throws -> [NoteSummary] {
        guard let expression = SearchQuery.ftsExpression(text) else { return try summaries() }
        return try summaries(
            """
            SELECT \(Self.summaryColumns) FROM notes
            WHERE deleted_at IS NULL
              AND rowid IN (SELECT rowid FROM notes_fts WHERE notes_fts MATCH ?)
            \(Self.summaryOrder)
            """, [.text(expression)])
    }

    /// Removes the row for good. Only for a note that was never used: its tab closed while still empty (spec §6.3).
    /// A note the owner deletes goes to Recently Deleted instead (``delete(_:now:)``).
    public func discard(_ id: NoteID) throws {
        try database.execute("DELETE FROM notes WHERE id = ?", [.text(id.rawValue)])
    }

    // MARK: Pin and delete

    /// How long a note stays in Recently Deleted before ``purge(deletedBefore:)`` may remove it: 30 days (spec §6.2).
    public static let recentlyDeletedRetention: TimeInterval = 30 * 24 * 60 * 60

    /// Pins the note (`pinned_at` becomes `now`) or unpins it (`pinned_at` becomes NULL). The text and the edit time
    /// stay as they are, so pinning does not move the note in the "newest edit first" order. An unknown id is ignored.
    public func setPinned(_ id: NoteID, _ pinned: Bool, now: Date) throws {
        try database.execute(
            "UPDATE notes SET pinned_at = ? WHERE id = ?",
            [pinned ? .date(now) : .null, .text(id.rawValue)])
    }

    /// Moves the note to Recently Deleted (`deleted_at` becomes `now`). Its text, edit time and pin stay as they are.
    /// A note that is already deleted keeps its first deletion date, so a second delete cannot postpone the purge.
    /// An unknown id is ignored.
    public func delete(_ id: NoteID, now: Date) throws {
        try database.execute(
            "UPDATE notes SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL",
            [.date(now), .text(id.rawValue)])
    }

    /// Takes the note out of Recently Deleted (`deleted_at` becomes NULL). Its text, edit time and pin stay as they
    /// are. A note that is not deleted, and an unknown id, are left alone.
    public func restore(_ id: NoteID) throws {
        try database.execute("UPDATE notes SET deleted_at = NULL WHERE id = ?", [.text(id.rawValue)])
    }

    /// Removes a note from Recently Deleted for good (spec §6.2). A note that is not deleted is never removed:
    /// only the owner's Delete puts a note in Recently Deleted, and nothing else removes one (spec §6.7).
    public func deletePermanently(_ id: NoteID) throws {
        try database.execute("DELETE FROM notes WHERE id = ? AND deleted_at IS NOT NULL", [.text(id.rawValue)])
    }

    /// The Recently Deleted rows, the most recently deleted first. Each has its ``NoteSummary/deletedAt``.
    public func deletedSummaries() throws -> [NoteSummary] {
        try summaries(
            """
            SELECT \(Self.summaryColumns) FROM notes
            WHERE deleted_at IS NOT NULL
            ORDER BY deleted_at DESC, id
            """, [])
    }

    /// Removes every deleted note whose deletion is older than `cutoff`, and returns how many rows went. The
    /// owner's own notes are never touched: a note that is not deleted stays however old it is (spec §6.7). Call it
    /// with `now - recentlyDeletedRetention`.
    public func purge(deletedBefore cutoff: Date) throws -> Int {
        let removed = try database.query(
            "DELETE FROM notes WHERE deleted_at IS NOT NULL AND deleted_at < ? RETURNING id", [.date(cutoff)])
        return removed.count
    }

    // MARK: Attachments

    /// The ids of every attachment whose token is in the text of any stored note, live or in Recently Deleted
    /// (``AttachmentToken/referencedIDs(in:)``: the token anywhere in the body counts). This is what keeps an attachment's
    /// file: ``AttachmentStore`` removes a file only when its id is not in this set.
    ///
    /// It reads the bodies that hold the opening of a token and no others, one at a time, so a database of large notes
    /// is not read into memory whole.
    public func referencedAttachmentIDs() throws -> Set<AttachmentID> {
        try database.transaction {
            try attachmentIDs(selecting: "1 = 1", [])
        }
    }

    /// The ids named in the body of the note `id`, when that note is in Recently Deleted. Empty for a note that is not
    /// deleted and for an unknown id: ``deletePermanently(_:)`` leaves those alone.
    func attachmentIDsOfDeletedNote(_ id: NoteID) throws -> Set<AttachmentID> {
        try attachmentIDs(selecting: "id = ? AND deleted_at IS NOT NULL", [.text(id.rawValue)])
    }

    /// The ids named in the bodies of the notes that ``purge(deletedBefore:)`` removes with this `cutoff`.
    func attachmentIDsOfNotesDeleted(before cutoff: Date) throws -> Set<AttachmentID> {
        try attachmentIDs(selecting: "deleted_at IS NOT NULL AND deleted_at < ?", [.date(cutoff)])
    }

    /// The token ids in the bodies of the notes that match `condition` (SQL written here, never typed text) and hold
    /// the text `[[attachment:` at all.
    private func attachmentIDs(selecting condition: String, _ arguments: [SQLValue]) throws -> Set<AttachmentID> {
        let noteIDs = try database.query(
            "SELECT id FROM notes WHERE (\(condition)) AND instr(body, '[[attachment:') > 0", arguments
        ).compactMap { $0.string("id") }
        var found: Set<AttachmentID> = []
        for id in noteIDs {
            guard
                let body = try database.query("SELECT body FROM notes WHERE id = ?", [.text(id)]).first?.string("body")
            else { continue }
            found.formUnion(AttachmentToken.referencedIDs(in: body))
        }
        return found
    }

    // MARK: Rows

    private static let summaryColumns = "id, display_title, has_title, preview, modified_at, pinned_at, deleted_at"
    private static let summaryOrder = "ORDER BY pinned_at IS NULL, modified_at DESC, created_at DESC, id"

    private func summaries(_ sql: String, _ arguments: [SQLValue]) throws -> [NoteSummary] {
        let rows = try database.query(sql, arguments)
        return try rows.map { row in
            guard let id = row.string("id"), let displayTitle = row.string("display_title"),
                let hasTitle = row.int("has_title"), let preview = row.string("preview"),
                let modifiedAt = row.date("modified_at")
            else { throw Self.malformedRow("notes") }
            return NoteSummary(
                id: NoteID(rawValue: id), displayTitle: displayTitle, hasTitle: hasTitle != 0, preview: preview,
                modifiedAt: modifiedAt, pinnedAt: row.date("pinned_at"), deletedAt: row.date("deleted_at"))
        }
    }

    private static let upsertSQL = """
        INSERT INTO notes (id, title, body, display_title, has_title, preview,
                           created_at, modified_at, pinned_at, deleted_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title, body = excluded.body,
          display_title = excluded.display_title, has_title = excluded.has_title, preview = excluded.preview,
          modified_at = excluded.modified_at
        """

    private static func arguments(for note: Note) -> [SQLValue] {
        [
            .text(note.id.rawValue), .text(note.title), .text(note.body),
            .text(note.displayTitle), .integer(note.hasTitle ? 1 : 0), .text(note.preview),
            .date(note.createdAt), .date(note.modifiedAt),
            .optionalDate(note.pinnedAt), .optionalDate(note.deletedAt),
        ]
    }

    private static func note(from row: Row) throws -> Note {
        guard let id = row.string("id"), let title = row.string("title"), let body = row.string("body"),
            let createdAt = row.date("created_at"), let modifiedAt = row.date("modified_at")
        else { throw malformedRow("notes") }
        return Note(
            id: NoteID(rawValue: id), title: title, body: body, createdAt: createdAt, modifiedAt: modifiedAt,
            pinnedAt: row.date("pinned_at"), deletedAt: row.date("deleted_at"))
    }

    private static func malformedRow(_ table: String) -> DatabaseError {
        DatabaseError(code: sqliteCorrupt, message: "a row of table \(table) has a missing or mistyped column")
    }
}
