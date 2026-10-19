/// The database schema and its migrations.
///
/// The version lives in the database file as `PRAGMA user_version`. To change the schema, add a `migrateToVN` step
/// to ``migrate(_:)``, raise ``currentVersion`` and add a test. Never edit an existing step.
public enum Schema {
    public static let currentVersion = 1

    /// Brings `db` up to ``currentVersion`` in one transaction. It does nothing when `db` is already there.
    public static func migrate(_ db: Database) throws {
        try db.transaction {
            // Read the version inside the transaction, which holds the write lock. A second process that
            // migrates the same file at the same moment then waits and finds the work already done.
            let version = try db.userVersion()
            if version < 1 { try migrateToV1(db) }
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
}
