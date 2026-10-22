import Foundation
import Testing

@testable import ScratchCore

// Schema v1 is `notes` (with the derived title columns) and `session`. Schema v2 adds the full-text index `notes_fts`
// (Plan 2, Task 2). Schema v3 adds `attachments` and works the derived title columns out again with the rule that a
// title skips fence and attachment lines (Plan 5, Task 1). A database written by a newer Scratch is refused and left
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

@Test func freshDatabaseIsVersion3() throws {
    let db = try Database(path: ":memory:")
    try Schema.migrate(db)
    #expect(Schema.currentVersion == 3)
    #expect(try db.userVersion() == 3)

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
    #expect(try db.userVersion() == 3)
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
    #expect(try db.userVersion() == 3)
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
    try db.execute("PRAGMA user_version = 4")

    #expect(throws: SchemaError.newerThanSupported(found: 4, supported: 3)) { try Schema.migrate(db) }
    #expect(try db.userVersion() == 4)
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

    #expect(throws: SchemaError.newerThanSupported(found: 9, supported: 3)) {
        try NoteStore(database: Database(path: path))
    }
    #expect(throws: SchemaError.newerThanSupported(found: 9, supported: 3)) {
        try SessionStore(database: Database(path: path))
    }

    let db = try Database(path: path)
    #expect(try db.userVersion() == 9)
    let names = try db.query("SELECT name FROM sqlite_master").compactMap { $0.string("name") }
    #expect(!names.contains("notes_fts") && names.contains("from_the_future"))
    #expect(try db.query("SELECT body FROM notes").compactMap { $0.string("body") } == ["kept"])
}

@Test func theNewerDatabaseErrorSaysWhatToDo() {
    let error = SchemaError.newerThanSupported(found: 4, supported: 3)
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
    #expect(try db.userVersion() == 3)
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
    #expect(try db.userVersion() == 3)
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
    #expect(try db.userVersion() == 3)
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
