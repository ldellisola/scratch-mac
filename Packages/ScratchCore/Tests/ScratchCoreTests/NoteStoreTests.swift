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
    note.modifiedAt = date(5)
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
    try store.save(note)
    try store.setPinned(note.id, true, now: date(3))
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
    newest.body = "newest"
    newest.modifiedAt = date(30)
    try store.saveAll([oldest, middle, newest])
    try store.setPinned(middle.id, true, now: date(5))
    #expect(try store.summaries().map(\.displayTitle) == ["middle", "newest", "oldest"])
}

@Test func pinnedNotesAreOrderedAmongThemselvesByLastEdit() throws {
    let (store, _) = try noteStore()
    var older = try store.create(now: date(0))
    var newer = try store.create(now: date(0))
    var unpinned = try store.create(now: date(0))
    older.body = "older pinned"
    older.modifiedAt = date(10)
    newer.body = "newer pinned"
    newer.modifiedAt = date(20)
    unpinned.body = "unpinned"
    unpinned.modifiedAt = date(30)
    try store.saveAll([older, newer, unpinned])
    try store.setPinned(older.id, true, now: date(99))  // pinned most recently, but edited least recently
    try store.setPinned(newer.id, true, now: date(1))
    #expect(try store.summaries().map(\.displayTitle) == ["newer pinned", "older pinned", "unpinned"])
}

@Test func summariesExcludeDeleted() throws {
    let (store, _) = try noteStore()
    var kept = try store.create(now: date(0))
    let gone = try store.create(now: date(0))
    kept.body = "kept"
    try store.save(kept)
    try store.delete(gone.id, now: date(5))
    #expect(try store.summaries().map(\.id) == [kept.id])
    #expect(try store.note(gone.id)?.deletedAt == date(5))
}

// Plan 2, Review Focus 1: an autosave writes the text of a note that the owner may have pinned or deleted since the
// text was loaded. The save must keep the text, and must not undo the pin or the deletion.
@Test func saveDoesNotOverwritePinOrDeletion() throws {
    let (store, _) = try noteStore()
    var stale = try store.create(now: date(0))
    stale.body = "typed while unpinned"
    try store.save(stale)

    try store.setPinned(stale.id, true, now: date(5))
    stale.body = "typed after the pin"
    stale.modifiedAt = date(6)
    try store.save(stale)  // `stale` still says "not pinned"
    var stored = try #require(try store.note(stale.id))
    #expect(stored.pinnedAt == date(5))
    #expect(stored.body == "typed after the pin" && stored.modifiedAt == date(6))

    try store.delete(stale.id, now: date(8))
    stale.body = "typed after the delete"
    stale.modifiedAt = date(9)
    try store.save(stale)  // `stale` still says "not deleted"
    stored = try #require(try store.note(stale.id))
    #expect(stored.deletedAt == date(8))
    #expect(stored.pinnedAt == date(5))
    #expect(stored.body == "typed after the delete" && stored.modifiedAt == date(9))
    #expect(try store.summaries().isEmpty)

    // Unpinning is just as sticky: a stale copy that still says "pinned" does not pin it again.
    try store.restore(stale.id)
    try store.setPinned(stale.id, false, now: date(10))
    var pinnedCopy = stored
    pinnedCopy.body = "typed from a pinned copy"
    try store.save(pinnedCopy)
    #expect(try store.note(stale.id)?.pinnedAt == nil)
    #expect(try store.note(stale.id)?.deletedAt == nil)
}

@Test func saveInsertsEveryColumnOfANewRow() throws {
    let (store, _) = try noteStore()
    let note = Note(
        id: NoteID.make(), title: "T", body: "b", createdAt: date(1), modifiedAt: date(2), pinnedAt: date(3),
        deletedAt: date(4))
    try store.save(note)
    #expect(try store.note(note.id) == note)
}

@Test func pinningDoesNotChangeModifiedAt() throws {
    let (store, _) = try noteStore()
    var note = try store.create(now: date(0))
    note.body = "text"
    note.modifiedAt = date(7)
    try store.save(note)

    try store.setPinned(note.id, true, now: date(50))
    var stored = try #require(try store.note(note.id))
    #expect(stored.pinnedAt == date(50))
    #expect(stored.modifiedAt == date(7))
    #expect(stored.body == "text")
    #expect(try store.summaries().first?.pinnedAt == date(50))
    #expect(try store.summaries().first?.modifiedAt == date(7))

    try store.setPinned(note.id, false, now: date(60))
    stored = try #require(try store.note(note.id))
    #expect(stored.pinnedAt == nil)
    #expect(stored.modifiedAt == date(7))
    #expect(try store.summaries().first?.pinnedAt == nil)
}

@Test func pinnedNotesComeFirstInSummaries() throws {
    let (store, _) = try noteStore()
    var older = try store.create(now: date(0))
    var newer = try store.create(now: date(0))
    older.body = "older"
    older.modifiedAt = date(10)
    newer.body = "newer"
    newer.modifiedAt = date(20)
    try store.saveAll([older, newer])
    #expect(try store.summaries().map(\.displayTitle) == ["newer", "older"])
    try store.setPinned(older.id, true, now: date(30))
    #expect(try store.summaries().map(\.displayTitle) == ["older", "newer"])
    try store.setPinned(older.id, false, now: date(31))
    #expect(try store.summaries().map(\.displayTitle) == ["newer", "older"])
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

// Plan 6 task 3 (docs/features/autosave-and-restore.md, "Launch"): a launch that restores several tabs reads the body of
// the active note only. `tabInfo` is what the other tabs need: the title they show, whether the note is deleted, and
// whether it was ever used, from the derived columns and never from the body.

@Test func tabInfoReadsNoBody() throws {
    let (store, db) = try noteStore()
    // The statement names no body, for one id and for many.
    #expect(!NoteStore.tabInfoSQL(count: 1).lowercased().contains("body"))
    #expect(!NoteStore.tabInfoSQL(count: 40).lowercased().contains("body"))

    // And its answer follows the derived columns: a body that was changed behind the store's back (the columns are
    // written on a save only) is not what the title comes from.
    let note = Note(
        id: NoteID.make(), title: "", body: "first line\nsecond line", createdAt: date(1), modifiedAt: date(2))
    try store.save(note)
    try db.execute(
        "UPDATE notes SET body = ? WHERE id = ?", [.text("something else entirely"), .text(note.id.rawValue)])
    let info = try store.tabInfo([note.id])[note.id]
    #expect(info?.displayTitle == "first line")
    #expect(info?.hasTitle == false)
}

@Test func tabInfoHasTheTitleTheRowHas() throws {
    let (store, _) = try noteStore()
    let titled = Note(id: NoteID.make(), title: "  Plan  ", body: "text", createdAt: date(1), modifiedAt: date(2))
    let untitled = Note(
        id: NoteID.make(), title: "", body: "\n\nfirst words\nmore", createdAt: date(1), modifiedAt: date(2))
    let fenceOnly = Note(id: NoteID.make(), title: "", body: "```swift\n```", createdAt: date(1), modifiedAt: date(2))
    try store.saveAll([titled, untitled, fenceOnly])

    let info = try store.tabInfo([titled.id, untitled.id, fenceOnly.id])
    #expect(
        info[titled.id]
            == TabNoteInfo(id: titled.id, displayTitle: "Plan", hasTitle: true, deletedAt: nil, isNeverUsed: false))
    #expect(
        info[untitled.id]
            == TabNoteInfo(
                id: untitled.id, displayTitle: "first words", hasTitle: false, deletedAt: nil, isNeverUsed: false))
    #expect(info[fenceOnly.id]?.displayTitle == "", "a note of fence lines has no title: its tab says Untitled")
    #expect(info[fenceOnly.id]?.isNeverUsed == false, "its edit time is not its creation time")
}

@Test func tabInfoMarksNeverUsed() throws {
    let (store, _) = try noteStore()
    // A note nobody typed in: empty, and its edit time is its creation time.
    let fresh = try store.create(now: date(5))
    // One the owner emptied again: empty, but its edit time moved (docs/decisions/0004: it is theirs).
    var emptied = try store.create(now: date(5))
    emptied.body = "typed"
    emptied.modifiedAt = date(9)
    try store.save(emptied)
    emptied.body = ""
    emptied.modifiedAt = date(12)
    try store.save(emptied)
    // One with text whose two dates are equal (a fixture's notes are like that): it has words, so it was used.
    let seeded = Note(id: NoteID.make(), title: "", body: "words", createdAt: date(5), modifiedAt: date(5))
    try store.save(seeded)
    // One with a title of its own and nothing else.
    let titled = Note(id: NoteID.make(), title: "Only a title", body: "", createdAt: date(5), modifiedAt: date(5))
    try store.save(titled)

    let info = try store.tabInfo([fresh.id, emptied.id, seeded.id, titled.id])
    #expect(info[fresh.id]?.isNeverUsed == true)
    #expect(info[emptied.id]?.isNeverUsed == false)
    #expect(info[seeded.id]?.isNeverUsed == false)
    #expect(info[titled.id]?.isNeverUsed == false)
    for id in [fresh.id, emptied.id] { #expect(info[id]?.displayTitle == "" && info[id]?.hasTitle == false) }
}

@Test func tabInfoOmitsMissing() throws {
    let (store, _) = try noteStore()
    let live = Note(id: NoteID.make(), title: "", body: "live", createdAt: date(1), modifiedAt: date(2))
    let gone = Note(id: NoteID.make(), title: "", body: "gone", createdAt: date(1), modifiedAt: date(2))
    try store.saveAll([live, gone])
    try store.delete(gone.id, now: date(30))
    let unknown = NoteID.make()

    let info = try store.tabInfo([live.id, unknown, gone.id, live.id])
    #expect(Set(info.keys) == [live.id, gone.id], "an id that names no note is not in the answer")
    #expect(info[live.id]?.deletedAt == nil)
    #expect(info[gone.id]?.deletedAt == date(30), "a deleted note says so: the restore drops its tab")
    #expect(try store.tabInfo([]).isEmpty)
}

@Test func tabInfoAnswersForMoreIDsThanOneStatementTakes() throws {
    let (store, _) = try noteStore()
    let count = NoteStore.tabInfoChunk * 2 + 17
    var ids: [NoteID] = []
    var notes: [Note] = []
    for index in 0..<count {
        let note = Note(
            id: NoteID.make(), title: "", body: "note \(index)", createdAt: date(1), modifiedAt: date(2))
        notes.append(note)
        ids.append(note.id)
    }
    try store.saveAll(notes)
    let info = try store.tabInfo(ids)
    #expect(info.count == count)
    #expect(info[ids[count - 1]]?.displayTitle == "note \(count - 1)")
}
