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

    /// Inserts the note, or replaces the stored one with the same id, and refreshes its derived columns.
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
    /// A note the owner deletes goes to Recently Deleted instead, which is a later plan.
    public func discard(_ id: NoteID) throws {
        try database.execute("DELETE FROM notes WHERE id = ?", [.text(id.rawValue)])
    }

    // MARK: Rows

    private static let summaryColumns = "id, display_title, has_title, preview, modified_at, pinned_at"
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
                modifiedAt: modifiedAt, pinnedAt: row.date("pinned_at"))
        }
    }

    private static let upsertSQL = """
        INSERT INTO notes (id, title, body, display_title, has_title, preview,
                           created_at, modified_at, pinned_at, deleted_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title, body = excluded.body,
          display_title = excluded.display_title, has_title = excluded.has_title, preview = excluded.preview,
          created_at = excluded.created_at, modified_at = excluded.modified_at,
          pinned_at = excluded.pinned_at, deleted_at = excluded.deleted_at
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
