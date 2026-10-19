import Foundation
import Testing

@testable import ScratchCore

// Schema v1 is the one in the plan: `notes` (with the derived title columns) and `session`.

private func columnNames(of table: String, in db: Database) throws -> [String] {
    try db.query("PRAGMA table_info(\(table))").compactMap { $0.string("name") }
}

@Test func migrationCreatesSchemaV1() throws {
    let db = try Database(path: ":memory:")
    #expect(try db.userVersion() == 0)
    try Schema.migrate(db)

    let tables = try db.query("SELECT name FROM sqlite_master WHERE type = 'table'").compactMap { $0.string("name") }
    #expect(tables.contains("notes") && tables.contains("session"))
    #expect(try db.userVersion() == 1)
    #expect(Schema.currentVersion == 1)

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
    #expect(try db.userVersion() == 1)
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
    #expect(try reopened.userVersion() == 1)
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
