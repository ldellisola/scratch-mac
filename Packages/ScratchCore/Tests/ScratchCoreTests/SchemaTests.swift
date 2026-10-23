import Foundation
import Testing

@testable import ScratchCore

// Schema v1 is `notes` (with the derived title columns) and `session`. Schema v2 adds the full-text index `notes_fts`
// (Plan 2, Task 2). Schema v3 adds `attachments` and works the derived title columns out again with the rule that a
// title skips fence and attachment lines (Plan 5, Task 1). Schema v4 works them out again with the rule that a title and
// a preview are the text without its markers (Plan 6, Task 4). A database written by a newer Scratch is refused and left
// as it was.

private func columnNames(of table: String, in db: Database) throws -> [String] {
    try db.query("PRAGMA table_info(\(table))").compactMap { $0.string("name") }
}

@Test func migrationCreatesNotesAndSession() throws {
    let db = try Database(path: ":memory:")
    #expect(try db.userVersion() == 0)
    try Schema.migrate(db)

    let tables = try db.query("SELECT name FROM sqlite_master WHERE type = 'table'").compactMap { $0.string("name") }
    #expect(tables.contains("notes") && tables.contains("session"))

    #expect(
        try columnNames(of: "notes", in: db) == [
            "id", "title", "body", "display_title", "has_title", "preview",
            "created_at", "modified_at", "pinned_at", "deleted_at",
        ])
    #expect(try columnNames(of: "session", in: db) == ["key", "value"])
    let indexes = try db.query("PRAGMA index_list(notes)").compactMap { $0.string("name") }
    #expect(indexes.contains("notes_list"))
}

@Test func migrationIsIdempotent() throws {
    let db = try Database(path: ":memory:")
    try Schema.migrate(db)
    try db.execute("INSERT INTO session (key, value) VALUES ('k', ?)", [.blob([1])])
    try Schema.migrate(db)
    #expect(try db.userVersion() == Schema.currentVersion)
    #expect(try db.query("SELECT key FROM session").count == 1)
}

@Test func failedMigrationLeavesNoPartialSchema() throws {
    let db = try Database(path: ":memory:")
    try db.execute("CREATE TABLE session (already_there)")  // makes the last step of the migration fail
    #expect(throws: DatabaseError.self) { try Schema.migrate(db) }
    #expect(try db.userVersion() == 0)
    let tables = try db.query("SELECT name FROM sqlite_master WHERE type = 'table'").compactMap { $0.string("name") }
    #expect(tables == ["session"])
}

@Test func migrationSurvivesReopeningAFileDatabase() throws {
    let file = "scratch-schema-\(UUID().uuidString).sqlite"
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(file).path
    defer {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
    }
    try Schema.migrate(Database(path: path))
    let reopened = try Database(path: path)
    try Schema.migrate(reopened)
    #expect(try reopened.userVersion() == Schema.currentVersion)
}

@Test func notesTableEnforcesRequiredColumns() throws {
    let db = try Database(path: ":memory:")
    try Schema.migrate(db)
    // pinned_at and deleted_at are optional. Everything else is NOT NULL.
    #expect(throws: DatabaseError.self) {
        try db.execute("INSERT INTO notes (id) VALUES ('a')")
    }
    try db.execute(
        """
        INSERT INTO notes (id, title, body, display_title, has_title, preview, created_at, modified_at)
        VALUES ('a', '', '', '', 0, '', 1.0, 2.0)
        """)
    #expect(try db.query("SELECT pinned_at, deleted_at FROM notes").first?["pinned_at"] == .null)
}

// MARK: Schema v2

/// The version 1 schema exactly as 0.1.0 created it, so that a test can build the database the owner already has.
/// A migration step is never edited, so neither is this.
private func createSchemaV1(in db: Database) throws {
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

private func insertV1Note(
    _ db: Database, id: String, title: String, body: String, modifiedAt: Double,
    pinnedAt: Double? = nil, deletedAt: Double? = nil
) throws {
    try db.execute(
        """
        INSERT INTO notes (id, title, body, display_title, has_title, preview, created_at, modified_at,
                           pinned_at, deleted_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
            .text(id), .text(title), .text(body), .text(title.isEmpty ? body : title), .integer(title.isEmpty ? 0 : 1),
            .text(body), .real(1.0), .real(modifiedAt), pinnedAt.map { .real($0) } ?? .null,
            deletedAt.map { .real($0) } ?? .null,
        ])
}

private func temporaryDatabasePath() -> String {
    let file = "scratch-schema-\(UUID().uuidString).sqlite"
    return FileManager.default.temporaryDirectory.appendingPathComponent(file).path
}

private func removeDatabaseFiles(at path: String) {
    for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
}

private func matches(_ word: String, in db: Database) throws -> [String] {
    try db.query(
        "SELECT id FROM notes WHERE rowid IN (SELECT rowid FROM notes_fts WHERE notes_fts MATCH ?) ORDER BY id",
        [.text(word)]
    ).compactMap { $0.string("id") }
}

@Test func freshDatabaseIsVersion4() throws {
    let db = try Database(path: ":memory:")
    try Schema.migrate(db)
    #expect(Schema.currentVersion == 4)
    #expect(try db.userVersion() == 4)

    let tables = try db.query("SELECT name FROM sqlite_master WHERE type = 'table'").compactMap { $0.string("name") }
    #expect(tables.contains("notes_fts"))
    let triggerRows = try db.query("SELECT name FROM sqlite_master WHERE type = 'trigger'")
    let triggers = triggerRows.compactMap { $0.string("name") }
    #expect(Set(triggers) == ["notes_fts_ai", "notes_fts_ad", "notes_fts_au"])
    // The index sees inserts, updates and deletes made with plain SQL, which is what the triggers are for.
    try insertV1Note(db, id: "a", title: "Hello", body: "world", modifiedAt: 2)
    #expect(try matches("world", in: db) == ["a"])
    try db.execute("UPDATE notes SET body = 'moon' WHERE id = 'a'")
    #expect(try matches("world", in: db) == [] && matches("moon", in: db) == ["a"])
    try db.execute("DELETE FROM notes WHERE id = 'a'")
    #expect(try matches("moon", in: db) == [])
}

@Test func migratingV1DatabaseIndexesExistingNotes() throws {
    let path = temporaryDatabasePath()
    defer { removeDatabaseFiles(at: path) }
    do {
        let v1 = try Database(path: path)
        try createSchemaV1(in: v1)
        try insertV1Note(v1, id: "old", title: "Deploy checklist", body: "restart the kubectl proxy", modifiedAt: 10)
        try insertV1Note(v1, id: "pinned", title: "", body: "pinned café notes", modifiedAt: 20, pinnedAt: 30)
        try insertV1Note(v1, id: "gone", title: "Old", body: "trashed words", modifiedAt: 5, deletedAt: 40)
        #expect(try v1.userVersion() == 1)
    }

    let store = try NoteStore(database: Database(path: path))
    let db = try Database(path: path)
    #expect(try db.userVersion() == 4)
    // Every note is still there, unchanged.
    #expect(try db.query("SELECT COUNT(*) AS n FROM notes").first?.int("n") == 3)
    let old = try #require(try store.note(NoteID(rawValue: "old")))
    #expect(old.title == "Deploy checklist" && old.body == "restart the kubectl proxy")
    #expect(old.modifiedAt == Date(timeIntervalSinceReferenceDate: 10))
    #expect(try store.note(NoteID(rawValue: "pinned"))?.pinnedAt == Date(timeIntervalSinceReferenceDate: 30))
    #expect(try store.note(NoteID(rawValue: "gone"))?.deletedAt == Date(timeIntervalSinceReferenceDate: 40))
    // Search finds them, deleted ones excluded from the results but kept in the index for a later restore.
    #expect(try store.search("kube").map(\.id.rawValue) == ["old"])
    #expect(try store.search("cafe").map(\.id.rawValue) == ["pinned"])
    #expect(try store.search("checklist").map(\.id.rawValue) == ["old"])
    #expect(try store.search("trashed").isEmpty)
    #expect(try matches("trashed", in: db) == ["gone"])
    // And the index follows edits to notes that came from version 1.
    var edited = old
    edited.body = "something else"
    try store.save(edited)
    #expect(try store.search("kube").isEmpty)
    #expect(try store.search("something").map(\.id.rawValue) == ["old"])
    try db.execute("INSERT INTO notes_fts(notes_fts, rank) VALUES ('integrity-check', 1)")
}

@Test func migratingV1DatabaseKeepsItsSessionAndIndexes() throws {
    let db = try Database(path: ":memory:")
    try createSchemaV1(in: db)
    try db.execute("INSERT INTO session (key, value) VALUES ('state', ?)", [.blob([1, 2, 3])])
    try Schema.migrate(db)
    #expect(try db.query("SELECT value FROM session WHERE key = 'state'").first?["value"] == .blob([1, 2, 3]))
    let indexes = try db.query("PRAGMA index_list(notes)").compactMap { $0.string("name") }
    #expect(indexes.contains("notes_list"))
}

@Test func migratingAnEmptyV1DatabaseWorks() throws {
    let db = try Database(path: ":memory:")
    try createSchemaV1(in: db)
    try Schema.migrate(db)
    #expect(try db.userVersion() == 4)
    #expect(try matches("anything", in: db) == [])
}

@Test func failedV2MigrationLeavesVersion1Intact() throws {
    let db = try Database(path: ":memory:")
    try createSchemaV1(in: db)
    try insertV1Note(db, id: "a", title: "T", body: "kept", modifiedAt: 1)
    try db.execute("CREATE TABLE notes_fts (already_there)")  // makes the first step of version 2 fail
    #expect(throws: DatabaseError.self) { try Schema.migrate(db) }
    #expect(try db.userVersion() == 1)
    #expect(try db.query("SELECT body FROM notes").compactMap { $0.string("body") } == ["kept"])
    let triggers = try db.query("SELECT name FROM sqlite_master WHERE type = 'trigger'")
    #expect(triggers.isEmpty)
}

@Test func newerDatabaseIsRefused() throws {
    let db = try Database(path: ":memory:")
    try Schema.migrate(db)
    try insertV1Note(db, id: "a", title: "T", body: "kept", modifiedAt: 1)
    try db.execute("PRAGMA user_version = 5")

    #expect(throws: SchemaError.newerThanSupported(found: 5, supported: 4)) { try Schema.migrate(db) }
    #expect(try db.userVersion() == 5)
    #expect(try db.query("SELECT COUNT(*) AS n FROM notes").first?.int("n") == 1)
}

@Test func newerDatabaseIsRefusedWithoutBeingChanged() throws {
    let path = temporaryDatabasePath()
    defer { removeDatabaseFiles(at: path) }
    do {
        // What a future version might have written: a version beyond ours, a table we know nothing about, and no
        // `notes_fts` (a newer version may have replaced it), which migrating would try to create.
        let newer = try Database(path: path)
        try createSchemaV1(in: newer)
        try insertV1Note(newer, id: "a", title: "T", body: "kept", modifiedAt: 1)
        try newer.execute("CREATE TABLE from_the_future (x)")
        try newer.execute("PRAGMA user_version = 9")
    }

    #expect(throws: SchemaError.newerThanSupported(found: 9, supported: 4)) {
        try NoteStore(database: Database(path: path))
    }
    #expect(throws: SchemaError.newerThanSupported(found: 9, supported: 4)) {
        try SessionStore(database: Database(path: path))
    }

    let db = try Database(path: path)
    #expect(try db.userVersion() == 9)
    let names = try db.query("SELECT name FROM sqlite_master").compactMap { $0.string("name") }
    #expect(!names.contains("notes_fts") && names.contains("from_the_future"))
    #expect(try db.query("SELECT body FROM notes").compactMap { $0.string("body") } == ["kept"])
}

@Test func theNewerDatabaseErrorSaysWhatToDo() {
    let error = SchemaError.newerThanSupported(found: 5, supported: 4)
    let message =
        "This data was saved by a newer version of Scratch. Install the latest version from the Releases page."
    #expect(error.errorDescription == message)
    #expect(error.localizedDescription == message)
}

// MARK: Schema v3

/// The version 2 schema exactly as 0.2.0 to 0.4.0 created it (version 1 and the full-text index), so that a test can
/// build the database the owner already has. A migration step is never edited, so neither is this.
private func createSchemaV2(in db: Database) throws {
    try createSchemaV1(in: db)
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
    try db.execute("PRAGMA user_version = 2")
}

/// A row as 0.4.0 stored it: the derived columns are whatever the old rule made of the note, given by the test.
private func insertV2Note(
    _ db: Database, id: String, title: String = "", body: String, displayTitle: String, hasTitle: Bool = false,
    preview: String, createdAt: Double = 1.0, modifiedAt: Double, pinnedAt: Double? = nil, deletedAt: Double? = nil
) throws {
    try db.execute(
        """
        INSERT INTO notes (id, title, body, display_title, has_title, preview, created_at, modified_at,
                           pinned_at, deleted_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
            .text(id), .text(title), .text(body), .text(displayTitle), .integer(hasTitle ? 1 : 0), .text(preview),
            .real(createdAt), .real(modifiedAt), pinnedAt.map { .real($0) } ?? .null,
            deletedAt.map { .real($0) } ?? .null,
        ])
}

private func derivedColumns(of id: String, in db: Database) throws -> (title: String, hasTitle: Int64, preview: String)
{
    let row = try #require(
        try db.query("SELECT display_title, has_title, preview FROM notes WHERE id = ?", [.text(id)]).first)
    return (
        try #require(row.string("display_title")), try #require(row.int("has_title")),
        try #require(row.string("preview"))
    )
}

private let v3Token = "[[attachment:6f9619ff-8b86-4d11-b42d-00c04fc964ff]]"

@Test func migrationCreatesTheAttachmentsTable() throws {
    let db = try Database(path: ":memory:")
    try Schema.migrate(db)
    #expect(
        try columnNames(of: "attachments", in: db) == [
            "id", "note_id", "file_name", "type_identifier", "byte_size", "pixel_width", "pixel_height",
            "created_at", "copied",
        ])
    let info = try db.query("PRAGMA table_info(attachments)")
    func column(_ name: String) throws -> Row { try #require(info.first { $0.string("name") == name }) }
    #expect(try column("id").int("pk") == 1)
    // Only the pixel size is optional.
    for name in ["note_id", "file_name", "type_identifier", "byte_size", "created_at", "copied"] {
        #expect(try column(name).int("notnull") == 1, "\(name) is NOT NULL")
    }
    #expect(try column("pixel_width").int("notnull") == 0 && column("pixel_height").int("notnull") == 0)
    #expect(try column("byte_size").string("type") == "INTEGER" && column("created_at").string("type") == "REAL")

    let indexColumns = try db.query("PRAGMA index_list(attachments)").compactMap { $0.string("name") }
        .flatMap { try db.query("PRAGMA index_info(\($0))").compactMap { $0.string("name") } }
    #expect(indexColumns.contains("note_id"))
    // A row can be written and read back.
    try db.execute(
        """
        INSERT INTO attachments (id, note_id, file_name, type_identifier, byte_size, created_at, copied)
        VALUES ('a', 'n', 'plan.txt', 'public.plain-text', 12, 5.0, 0)
        """)
    #expect(try db.query("SELECT pixel_width FROM attachments").first?["pixel_width"] == .null)
    #expect(throws: DatabaseError.self) {
        try db.execute(
            """
            INSERT INTO attachments (id, note_id, file_name, type_identifier, byte_size, created_at, copied)
            VALUES ('a', 'n', 'again.txt', 'public.plain-text', 1, 5.0, 0)
            """)
    }
}

@Test func migratingV2RecomputesTitles() throws {
    let path = temporaryDatabasePath()
    defer { removeDatabaseFiles(at: path) }
    do {
        let v2 = try Database(path: path)
        try createSchemaV2(in: v2)
        // What 0.4.0 stored for a note that starts with a fence: the fence line as the title.
        try insertV2Note(
            v2, id: "fenced", body: "```swift\nlet a = 1\nlet b = 2\n```", displayTitle: "```swift",
            preview: "let a = 1 let b = 2 ```", modifiedAt: 12_345.5)
        #expect(try v2.userVersion() == 2)
    }

    let store = try NoteStore(database: Database(path: path))
    let db = try Database(path: path)
    #expect(try db.userVersion() == 4)
    let derived = try derivedColumns(of: "fenced", in: db)
    #expect(derived.title == "let a = 1" && derived.hasTitle == 0 && derived.preview == "let b = 2")
    // The edit time is the owner's, not the migration's.
    #expect(try db.query("SELECT modified_at FROM notes WHERE id = 'fenced'").first?.double("modified_at") == 12_345.5)
    #expect(try store.note(NoteID(rawValue: "fenced"))?.modifiedAt == Date(timeIntervalSinceReferenceDate: 12_345.5))
    #expect(try store.summaries().map(\.displayTitle) == ["let a = 1"])
}

@Test func migratingV2KeepsEveryNoteAndEveryOtherColumn() throws {
    let path = temporaryDatabasePath()
    defer { removeDatabaseFiles(at: path) }
    do {
        let v2 = try Database(path: path)
        try createSchemaV2(in: v2)
        try insertV2Note(
            v2, id: "plain", title: "Deploy checklist", body: "restart the kubectl proxy",
            displayTitle: "Deploy checklist",
            hasTitle: true, preview: "restart the kubectl proxy", createdAt: 3, modifiedAt: 10)
        try insertV2Note(
            v2, id: "pinned", body: "pinned café notes\nsecond line", displayTitle: "pinned café notes",
            preview: "second line", createdAt: 4, modifiedAt: 20, pinnedAt: 30)
        try insertV2Note(
            v2, id: "gone", body: "```\ntrashed words\n```", displayTitle: "```", preview: "trashed words ```",
            createdAt: 5, modifiedAt: 6, deletedAt: 40)
        try insertV2Note(
            v2, id: "image", body: "\(v3Token)\nA caption", displayTitle: "\(v3Token)", preview: "A caption",
            createdAt: 7, modifiedAt: 8)
        try insertV2Note(v2, id: "empty", body: "", displayTitle: "", preview: "", createdAt: 9, modifiedAt: 9)
        try v2.execute("INSERT INTO session (key, value) VALUES ('state', ?)", [.blob([1, 2, 3])])
    }

    let store = try NoteStore(database: Database(path: path))
    let db = try Database(path: path)
    #expect(try db.query("SELECT COUNT(*) AS n FROM notes").first?.int("n") == 5)

    // A note that is not affected by the new rule is left exactly as it was.
    let plain = try #require(try store.note(NoteID(rawValue: "plain")))
    #expect(plain.title == "Deploy checklist" && plain.body == "restart the kubectl proxy")
    #expect(plain.createdAt == Date(timeIntervalSinceReferenceDate: 3))
    #expect(plain.modifiedAt == Date(timeIntervalSinceReferenceDate: 10))
    let plainDerived = try derivedColumns(of: "plain", in: db)
    #expect(plainDerived.title == "Deploy checklist" && plainDerived.hasTitle == 1)
    #expect(plainDerived.preview == "restart the kubectl proxy")

    // Pins, deletion and creation times survive, and so do the text and the modification time of the notes it changed.
    #expect(try store.note(NoteID(rawValue: "pinned"))?.pinnedAt == Date(timeIntervalSinceReferenceDate: 30))
    let gone = try #require(try store.note(NoteID(rawValue: "gone")))
    #expect(gone.deletedAt == Date(timeIntervalSinceReferenceDate: 40))
    #expect(gone.body == "```\ntrashed words\n```" && gone.modifiedAt == Date(timeIntervalSinceReferenceDate: 6))
    #expect(try store.deletedSummaries().map(\.displayTitle) == ["trashed words"])
    #expect(try store.deletedSummaries().map(\.preview) == [""])
    let image = try #require(try store.note(NoteID(rawValue: "image")))
    #expect(image.body == "\(v3Token)\nA caption" && image.modifiedAt == Date(timeIntervalSinceReferenceDate: 8))
    #expect(try derivedColumns(of: "image", in: db).title == "A caption")
    #expect(try derivedColumns(of: "image", in: db).preview == "")
    #expect(try derivedColumns(of: "empty", in: db).title == "")
    for id in ["plain", "pinned", "gone", "image", "empty"] {
        let note = try #require(try store.note(NoteID(rawValue: id)))
        let derived = try derivedColumns(of: id, in: db)
        #expect(derived.title == note.displayTitle && derived.preview == note.preview, "\(id) matches the rule")
        #expect(derived.hasTitle == (note.hasTitle ? 1 : 0))
    }

    // The session and the search index come through untouched. The migration changed no title or body.
    #expect(try db.query("SELECT value FROM session WHERE key = 'state'").first?["value"] == .blob([1, 2, 3]))
    #expect(try store.search("kube").map(\.id.rawValue) == ["plain"])
    #expect(try store.search("cafe").map(\.id.rawValue) == ["pinned"])
    #expect(try store.search("caption").map(\.id.rawValue) == ["image"])
    try db.execute("INSERT INTO notes_fts(notes_fts, rank) VALUES ('integrity-check', 1)")
}

@Test func migratingV1DatabaseAlsoGetsTheNewTitleRule() throws {
    let db = try Database(path: ":memory:")
    try createSchemaV1(in: db)
    try insertV1Note(db, id: "a", title: "", body: "```sql\nSELECT 1\n```", modifiedAt: 77)
    try Schema.migrate(db)
    #expect(try db.userVersion() == 4)
    #expect(try derivedColumns(of: "a", in: db).title == "SELECT 1")
    #expect(try db.query("SELECT modified_at FROM notes").first?.double("modified_at") == 77)
}

@Test func migratingV2ToV3IsRunOnceAndLeavesLaterEditsAlone() throws {
    let db = try Database(path: ":memory:")
    try createSchemaV2(in: db)
    try insertV2Note(db, id: "a", body: "```\ncode\n```", displayTitle: "```", preview: "code ```", modifiedAt: 5)
    try Schema.migrate(db)
    // A row written by a later version of the same rule is not rewritten when the schema is checked again.
    try db.execute("UPDATE notes SET display_title = 'kept as written' WHERE id = 'a'")
    try Schema.migrate(db)
    #expect(try derivedColumns(of: "a", in: db).title == "kept as written")
}

@Test func migratingAnEmptyV2DatabaseWorks() throws {
    let db = try Database(path: ":memory:")
    try createSchemaV2(in: db)
    try Schema.migrate(db)
    #expect(try db.userVersion() == 4)
    #expect(try db.query("SELECT COUNT(*) AS n FROM attachments").first?.int("n") == 0)
}

@Test func failedV3MigrationLeavesVersion2Intact() throws {
    let db = try Database(path: ":memory:")
    try createSchemaV2(in: db)
    try insertV2Note(db, id: "a", body: "```\ncode\n```", displayTitle: "```", preview: "code ```", modifiedAt: 5)
    // The table is made first, then the index fails: a table named like the index of version 3.
    try db.execute("CREATE TABLE attachments_note (already_there)")
    #expect(throws: DatabaseError.self) { try Schema.migrate(db) }
    #expect(try db.userVersion() == 2)
    let tables = try db.query("SELECT name FROM sqlite_master WHERE type = 'table'").compactMap { $0.string("name") }
    #expect(!tables.contains("attachments"))
    #expect(try derivedColumns(of: "a", in: db).title == "```")
}

// MARK: Schema v4

/// The version 3 schema exactly as 0.5.0 created it (version 2 and the `attachments` table), so that a test can build the
/// database the owner has now. A migration step is never edited, so neither is this.
private func createSchemaV3(in db: Database) throws {
    try createSchemaV2(in: db)
    try db.execute(
        """
        CREATE TABLE attachments (
          id TEXT PRIMARY KEY, note_id TEXT NOT NULL, file_name TEXT NOT NULL,
          type_identifier TEXT NOT NULL, byte_size INTEGER NOT NULL, pixel_width INTEGER, pixel_height INTEGER,
          created_at REAL NOT NULL, copied INTEGER NOT NULL)
        """)
    try db.execute("CREATE INDEX attachments_note ON attachments(note_id)")
    try db.execute("PRAGMA user_version = 3")
}

/// The live notes in the order of the sidebar: pinned first, then the newest edit first (`NoteStore.summaries`).
private func listOrder(in db: Database) throws -> [String] {
    try db.query(
        "SELECT id FROM notes WHERE deleted_at IS NULL ORDER BY pinned_at IS NULL, modified_at DESC, created_at DESC, id"
    ).compactMap { $0.string("id") }
}

private func modifiedTimes(in db: Database) throws -> [String: Double] {
    var times: [String: Double] = [:]
    for row in try db.query("SELECT id, modified_at FROM notes") {
        if let id = row.string("id"), let time = row.double("modified_at") { times[id] = time }
    }
    return times
}

/// Fills a version 3 database with what 0.5.0 stored for notes that begin with markers: the first line as typed, markers
/// and all, in `display_title` and in `preview`.
private func fillV3WithMarkedNotes(_ db: Database) throws {
    try insertV2Note(
        db, id: "task", body: "[ ] bump version to `2.4.1`\n[x] run migrations",
        displayTitle: "[ ] bump version to `2.4.1`", preview: "[x] run migrations", createdAt: 1, modifiedAt: 100)
    try insertV2Note(
        db, id: "bullet", body: "- **don't** deploy\n- later", displayTitle: "- **don't** deploy", preview: "- later",
        createdAt: 2, modifiedAt: 300)
    try insertV2Note(
        db, id: "titled", title: "Deploy checklist", body: "[ ] a\n- b", displayTitle: "Deploy checklist",
        hasTitle: true, preview: "[ ] a - b", createdAt: 3, modifiedAt: 200)
    try insertV2Note(
        db, id: "pinned", body: "**Pinned** plan\n`code`", displayTitle: "**Pinned** plan", preview: "`code`",
        createdAt: 4, modifiedAt: 50, pinnedAt: 400)
    try insertV2Note(
        db, id: "gone", body: "- thrown away", displayTitle: "- thrown away", preview: "", createdAt: 5, modifiedAt: 60,
        deletedAt: 500)
    // Notes the new rule leaves as they are.
    try insertV2Note(
        db, id: "plain", body: "restart the proxy\nthen wait", displayTitle: "restart the proxy", preview: "then wait",
        createdAt: 6, modifiedAt: 70)
    try insertV2Note(
        db, id: "code", body: "```\n- x\n```", displayTitle: "- x", preview: "", createdAt: 7, modifiedAt: 80)
    try insertV2Note(db, id: "empty", body: "", displayTitle: "", preview: "", createdAt: 8, modifiedAt: 8)
}

@Test func migratingV3StripsMarkersFromTitles() throws {
    let path = temporaryDatabasePath()
    defer { removeDatabaseFiles(at: path) }
    let orderBefore: [String]
    let timesBefore: [String: Double]
    do {
        let v3 = try Database(path: path)
        try createSchemaV3(in: v3)
        try fillV3WithMarkedNotes(v3)
        try v3.execute("INSERT INTO session (key, value) VALUES ('state', ?)", [.blob([1, 2, 3])])
        #expect(try v3.userVersion() == 3)
        orderBefore = try listOrder(in: v3)
        timesBefore = try modifiedTimes(in: v3)
        #expect(orderBefore == ["pinned", "bullet", "titled", "task", "code", "plain", "empty"])
    }

    let store = try NoteStore(database: Database(path: path))
    let db = try Database(path: path)
    #expect(try db.userVersion() == 4)

    // The rows show text without markers.
    #expect(try derivedColumns(of: "task", in: db) == ("bump version to 2.4.1", 0, "run migrations"))
    #expect(try derivedColumns(of: "bullet", in: db) == ("don't deploy", 0, "later"))
    #expect(try derivedColumns(of: "titled", in: db) == ("Deploy checklist", 1, "a b"))
    #expect(try derivedColumns(of: "pinned", in: db) == ("Pinned plan", 0, "code"))
    #expect(try derivedColumns(of: "gone", in: db) == ("thrown away", 0, ""))
    #expect(
        try store.summaries().map(\.displayTitle) == [
            "Pinned plan", "don't deploy", "Deploy checklist", "bump version to 2.4.1", "- x", "restart the proxy", "",
        ])
    #expect(try store.summaries().map(\.preview) == ["code", "later", "a b", "run migrations", "", "then wait", ""])
    #expect(try store.deletedSummaries().map(\.displayTitle) == ["thrown away"])

    // The edit times and the order of the list are as they were: the migration is not an edit.
    #expect(try modifiedTimes(in: db) == timesBefore)
    #expect(try listOrder(in: db) == orderBefore)
    #expect(try store.summaries().map(\.id.rawValue) == orderBefore)
    #expect(try store.summaries().first?.pinnedAt == Date(timeIntervalSinceReferenceDate: 400))

    // Nothing is lost: every title, body, creation time and pin is as it was, and so is the session.
    #expect(try db.query("SELECT COUNT(*) AS n FROM notes").first?.int("n") == 8)
    let task = try #require(try store.note(NoteID(rawValue: "task")))
    #expect(task.title == "" && task.body == "[ ] bump version to `2.4.1`\n[x] run migrations")
    #expect(task.createdAt == Date(timeIntervalSinceReferenceDate: 1))
    let titled = try #require(try store.note(NoteID(rawValue: "titled")))
    #expect(titled.title == "Deploy checklist" && titled.body == "[ ] a\n- b")
    let gone = try #require(try store.note(NoteID(rawValue: "gone")))
    #expect(gone.deletedAt == Date(timeIntervalSinceReferenceDate: 500) && gone.body == "- thrown away")
    #expect(try db.query("SELECT value FROM session WHERE key = 'state'").first?["value"] == .blob([1, 2, 3]))
    for id in ["task", "bullet", "titled", "pinned", "gone", "plain", "code", "empty"] {
        let note = try #require(try store.note(NoteID(rawValue: id)))
        let derived = try derivedColumns(of: id, in: db)
        #expect(derived.title == note.displayTitle && derived.preview == note.preview, "\(id) matches the rule")
        #expect(derived.hasTitle == (note.hasTitle ? 1 : 0))
    }

    // Search follows the text, which did not change: it finds the same notes by the same words, markers excluded.
    #expect(try store.search("migrations").map(\.id.rawValue) == ["task"])
    #expect(try store.search("deploy").map(\.id.rawValue) == ["bullet", "titled"])
    #expect(try store.search("pinned").map(\.id.rawValue) == ["pinned"])
    #expect(try store.search("proxy").map(\.id.rawValue) == ["plain"])
    #expect(try store.search("thrown").isEmpty)
    #expect(try matches("thrown", in: db) == ["gone"])
    try db.execute("INSERT INTO notes_fts(notes_fts, rank) VALUES ('integrity-check', 1)")
}

@Test func migratingV3WritesOnlyTheRowsThatChange() throws {
    let db = try Database(path: ":memory:")
    try createSchemaV3(in: db)
    try fillV3WithMarkedNotes(db)
    // Every UPDATE of a row leaves its id in `writes`.
    try db.execute("CREATE TABLE writes (id TEXT)")
    try db.execute("CREATE TRIGGER log_writes AFTER UPDATE ON notes BEGIN INSERT INTO writes VALUES (new.id); END")
    try Schema.migrate(db)
    let written = try db.query("SELECT id FROM writes ORDER BY id").compactMap { $0.string("id") }
    #expect(written == ["bullet", "gone", "pinned", "task", "titled"])
    #expect(try db.userVersion() == 4)
}

@Test func migratingV3ToV4IsRunOnceAndLeavesLaterEditsAlone() throws {
    let db = try Database(path: ":memory:")
    try createSchemaV3(in: db)
    try fillV3WithMarkedNotes(db)
    try Schema.migrate(db)
    try db.execute("UPDATE notes SET display_title = 'kept as written' WHERE id = 'task'")
    try Schema.migrate(db)
    #expect(try derivedColumns(of: "task", in: db).title == "kept as written")
}

@Test func migratingV2ReachesTheMarkerFreeTitlesToo() throws {
    let db = try Database(path: ":memory:")
    try createSchemaV2(in: db)
    try insertV2Note(
        db, id: "a", body: "[ ] ```\n- x", displayTitle: "[ ] ```", preview: "- x", modifiedAt: 9)
    try insertV2Note(
        db, id: "b", body: "```sh\nls\n```\n- **done**", displayTitle: "```sh", preview: "ls ``` - **done**",
        modifiedAt: 10)
    try Schema.migrate(db)
    #expect(try db.userVersion() == 4)
    #expect(try derivedColumns(of: "a", in: db) == ("```", 0, "x"))
    #expect(try derivedColumns(of: "b", in: db) == ("ls", 0, "done"))
    #expect(try modifiedTimes(in: db) == ["a": 9, "b": 10])
}

@Test func migratingAnEmptyV3DatabaseWorks() throws {
    let db = try Database(path: ":memory:")
    try createSchemaV3(in: db)
    try Schema.migrate(db)
    #expect(try db.userVersion() == 4)
    #expect(try db.query("SELECT COUNT(*) AS n FROM notes").first?.int("n") == 0)
}

@Test func failedV4MigrationLeavesVersion3Intact() throws {
    let db = try Database(path: ":memory:")
    try createSchemaV3(in: db)
    try fillV3WithMarkedNotes(db)
    // The first row that changes makes the migration fail, which must undo the rows it had written before.
    try db.execute(
        "CREATE TRIGGER refuse_writes BEFORE UPDATE ON notes WHEN new.id = 'pinned' BEGIN SELECT RAISE(ABORT, 'no'); END"
    )
    #expect(throws: DatabaseError.self) { try Schema.migrate(db) }
    #expect(try db.userVersion() == 3)
    #expect(try derivedColumns(of: "task", in: db).title == "[ ] bump version to `2.4.1`")
    #expect(try derivedColumns(of: "bullet", in: db).title == "- **don't** deploy")
    #expect(try db.query("SELECT COUNT(*) AS n FROM notes").first?.int("n") == 8)
}
