import Foundation

/// The database file was written by a newer Scratch than this one, so this one must not touch it.
public enum SchemaError: Error, Equatable {
    /// `found` is the file's `user_version` and `supported` is ``Schema/currentVersion``.
    case newerThanSupported(found: Int, supported: Int)
}

extension SchemaError: LocalizedError {
    /// The text of the "cannot start" alert (`AppDelegate.quit(after:)`), which shows the error's description.
    public var errorDescription: String? {
        switch self {
        case .newerThanSupported:
            "This data was saved by a newer version of Scratch. Install the latest version from the Releases page."
        }
    }
}

/// The database schema and its migrations.
///
/// The version lives in the database file as `PRAGMA user_version`. To change the schema, add a `migrateToVN` step
/// to ``migrate(_:)``, raise ``currentVersion`` and add a test. Never edit an existing step.
public enum Schema {
    public static let currentVersion = 2

    /// Brings `db` up to ``currentVersion`` in one transaction. It does nothing when `db` is already there.
    ///
    /// Throws ``SchemaError/newerThanSupported(found:supported:)`` without changing anything when `db` was written by
    /// a newer version, because an older version cannot know what a newer one stored or how it indexed it.
    public static func migrate(_ db: Database) throws {
        try db.transaction {
            // Read the version inside the transaction, which holds the write lock. A second process that
            // migrates the same file at the same moment then waits and finds the work already done.
            let version = try db.userVersion()
            if version > currentVersion {
                throw SchemaError.newerThanSupported(found: version, supported: currentVersion)
            }
            if version < 1 { try migrateToV1(db) }
            if version < 2 { try migrateToV2(db) }
        }
    }

    /// Notes, with their derived sidebar columns, and the session key-value table.
    private static func migrateToV1(_ db: Database) throws {
        // `execute` runs one statement per call.
        try db.execute(
            """
            CREATE TABLE notes (
              id TEXT PRIMARY KEY, title TEXT NOT NULL, body TEXT NOT NULL,
              display_title TEXT NOT NULL, has_title INTEGER NOT NULL, preview TEXT NOT NULL,
              created_at REAL NOT NULL, modified_at REAL NOT NULL, pinned_at REAL, deleted_at REAL)
            """)
        try db.execute("CREATE INDEX notes_list ON notes(deleted_at, pinned_at, modified_at)")
        try db.execute("CREATE TABLE session (key TEXT PRIMARY KEY, value BLOB NOT NULL)")
        try db.execute("PRAGMA user_version = 1")
    }

    /// Full-text search over a note's title and body (spec §6.2).
    ///
    /// `notes_fts` stores no text of its own: it indexes the `notes` table (`content='notes'`), keyed on the table's
    /// implicit `rowid`. Three triggers keep the index current, and the last statement indexes every note that
    /// exists already, which is how a version 1 database keeps its notes searchable. Changing `deleted_at` or
    /// `pinned_at` leaves the index alone, so a deleted note stays indexed for when it is restored.
    ///
    /// Never `VACUUM` the database: it may renumber the implicit `rowid`s and so break the index (AGENTS.md).
    private static func migrateToV2(_ db: Database) throws {
        try db.execute(
            """
            CREATE VIRTUAL TABLE notes_fts USING fts5(
              title, body, content='notes', content_rowid='rowid', tokenize='unicode61 remove_diacritics 2')
            """)
        try db.execute(
            """
            CREATE TRIGGER notes_fts_ai AFTER INSERT ON notes BEGIN
              INSERT INTO notes_fts(rowid, title, body) VALUES (new.rowid, new.title, new.body);
            END
            """)
        try db.execute(
            """
            CREATE TRIGGER notes_fts_ad AFTER DELETE ON notes BEGIN
              INSERT INTO notes_fts(notes_fts, rowid, title, body) VALUES ('delete', old.rowid, old.title, old.body);
            END
            """)
        try db.execute(
            """
            CREATE TRIGGER notes_fts_au AFTER UPDATE OF title, body ON notes BEGIN
              INSERT INTO notes_fts(notes_fts, rowid, title, body) VALUES ('delete', old.rowid, old.title, old.body);
              INSERT INTO notes_fts(rowid, title, body) VALUES (new.rowid, new.title, new.body);
            END
            """)
        try db.execute("INSERT INTO notes_fts(notes_fts) VALUES ('rebuild')")
        try db.execute("PRAGMA user_version = 2")
    }
}
