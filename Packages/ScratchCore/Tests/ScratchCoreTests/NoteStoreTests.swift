import Foundation
import Testing

@testable import ScratchCore

// Spec §6.2 (the note list: pinned first, newest edit first), §6.3 (empty notes are discarded) and §6.6 (every
// change is persisted).

private func noteStore() throws -> (NoteStore, Database) {
    let db = try Database(path: ":memory:")
    return (try NoteStore(database: db), db)
}

private func date(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds) }

@Test func createReturnsEmptyNoteWithTimestamps() throws {
    let (store, _) = try noteStore()
    let now = date(10)
    let note = try store.create(now: now)
    #expect(note.isEmpty)
    #expect(note.title == "" && note.body == "")
    #expect(note.createdAt == now && note.modifiedAt == now)
    #expect(note.pinnedAt == nil && note.deletedAt == nil)
    #expect(try store.note(note.id) == note)
}

@Test func createGivesEachNoteItsOwnID() throws {
    let (store, _) = try noteStore()
    let a = try store.create(now: date(0))
    let b = try store.create(now: date(0))
    #expect(a.id != b.id)
}

@Test func noteReturnsNilForUnknownID() throws {
    let (store, _) = try noteStore()
    #expect(try store.note(NoteID.make()) == nil)
}

@Test func saveThenLoadRoundTrips() throws {
    let (store, _) = try noteStore()
    let note = Note(
        id: NoteID.make(), title: "Deploy checklist", body: "[ ] bump version\nhéllo 😀\n",
        createdAt: date(1.123456), modifiedAt: date(99.654321), pinnedAt: date(50.5), deletedAt: date(77.25))
    try store.save(note)
    #expect(try store.note(note.id) == note)
}

@Test func saveTwiceUpdatesTheSameRow() throws {
    let (store, db) = try noteStore()
    var note = try store.create(now: date(0))
    note.body = "first"
    try store.save(note)
    note.body = "second"
    note.title = "T"
    note.pinnedAt = date(5)
    try store.save(note)
    #expect(try store.note(note.id) == note)
    #expect(try db.query("SELECT COUNT(*) AS n FROM notes").first?.int("n") == 1)
}

@Test func saveUpdatesDerivedColumns() throws {
    let (store, _) = try noteStore()
    var note = try store.create(now: date(0))
    note.body = "SELECT 1\nFROM t\nWHERE x"
    try store.save(note)
    var summary = try #require(try store.summaries().first)
    #expect(summary.displayTitle == note.displayTitle && summary.displayTitle == "SELECT 1")
    #expect(summary.preview == note.preview && summary.preview == "FROM t WHERE x")
    #expect(summary.hasTitle == false)

    note.title = "Query"
    note.body = "SELECT 2"
    try store.save(note)
    summary = try #require(try store.summaries().first)
    #expect(summary.displayTitle == "Query" && summary.displayTitle == note.displayTitle)
    #expect(summary.preview == "SELECT 2" && summary.preview == note.preview)
    #expect(summary.hasTitle == true)
}

@Test func summariesCarryIDAndDates() throws {
    let (store, _) = try noteStore()
    var note = try store.create(now: date(1))
    note.body = "x"
    note.modifiedAt = date(9)
    note.pinnedAt = date(3)
    try store.save(note)
    #expect(
        try store.summaries() == [
            NoteSummary(
                id: note.id, displayTitle: "x", hasTitle: false, preview: "", modifiedAt: date(9), pinnedAt: date(3))
        ])
}

@Test func summariesOrderPinnedFirstThenNewestEdited() throws {
    let (store, _) = try noteStore()
    var oldest = try store.create(now: date(0))
    var middle = try store.create(now: date(0))
    var newest = try store.create(now: date(0))
    oldest.body = "oldest"
    oldest.modifiedAt = date(10)
    middle.body = "middle"
    middle.modifiedAt = date(20)
    middle.pinnedAt = date(5)
    newest.body = "newest"
    newest.modifiedAt = date(30)
    try store.saveAll([oldest, middle, newest])
    #expect(try store.summaries().map(\.displayTitle) == ["middle", "newest", "oldest"])
}

@Test func pinnedNotesAreOrderedAmongThemselvesByLastEdit() throws {
    let (store, _) = try noteStore()
    var older = try store.create(now: date(0))
    var newer = try store.create(now: date(0))
    var unpinned = try store.create(now: date(0))
    older.body = "older pinned"
    older.modifiedAt = date(10)
    older.pinnedAt = date(99)  // pinned most recently, but edited least recently
    newer.body = "newer pinned"
    newer.modifiedAt = date(20)
    newer.pinnedAt = date(1)
    unpinned.body = "unpinned"
    unpinned.modifiedAt = date(30)
    try store.saveAll([older, newer, unpinned])
    #expect(try store.summaries().map(\.displayTitle) == ["newer pinned", "older pinned", "unpinned"])
}

@Test func summariesExcludeDeleted() throws {
    let (store, db) = try noteStore()
    var kept = try store.create(now: date(0))
    let gone = try store.create(now: date(0))
    kept.body = "kept"
    try store.save(kept)
    // Deleting is a later plan, so mark the row by hand.
    try db.execute("UPDATE notes SET deleted_at = ? WHERE id = ?", [.date(date(5)), .text(gone.id.rawValue)])
    #expect(try store.summaries().map(\.id) == [kept.id])
    #expect(try store.note(gone.id)?.deletedAt == date(5))
}

@Test func discardRemovesTheRow() throws {
    let (store, db) = try noteStore()
    let empty = try store.create(now: date(0))
    let other = try store.create(now: date(1))
    try store.discard(empty.id)
    #expect(try store.note(empty.id) == nil)
    #expect(try store.note(other.id) != nil)
    #expect(try db.query("SELECT COUNT(*) AS n FROM notes").first?.int("n") == 1)
    try store.discard(empty.id)  // discarding twice is harmless
}

@Test func saveAllWritesEveryNoteInOneTransaction() throws {
    let (store, _) = try noteStore()
    var a = try store.create(now: date(0))
    var b = try store.create(now: date(0))
    a.body = "a"
    b.body = "b"
    try store.saveAll([a, b])
    #expect(try store.note(a.id) == a && store.note(b.id) == b)
}

@Test func storesShareOneDatabaseAndMigrateTwice() throws {
    let db = try Database(path: ":memory:")
    let first = try NoteStore(database: db)
    let note = try first.create(now: date(0))
    let second = try NoteStore(database: db)
    #expect(try second.note(note.id) == note)
    #expect(try db.userVersion() == Schema.currentVersion)
}

@Test func largeBodyRoundTrips() throws {
    let (store, _) = try noteStore()
    let line = String(repeating: "x", count: 99)  // 99 characters and a newline, 100 bytes
    let body = String(repeating: line + "\n", count: 50_000)
    #expect(body.utf8.count == 5_000_000)
    var note = try store.create(now: date(0))
    note.body = body

    let clock = ContinuousClock()
    let saveTime = try clock.measure { try store.save(note) }
    var loaded: Note?
    let loadTime = try clock.measure { loaded = try store.note(note.id) }

    #expect(loaded?.body == body)
    #expect(saveTime < .milliseconds(500), "save took \(saveTime)")
    #expect(loadTime < .milliseconds(500), "load took \(loadTime)")
}
