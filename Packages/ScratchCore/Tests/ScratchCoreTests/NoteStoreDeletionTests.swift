import Foundation
import Testing

@testable import ScratchCore

// Spec §6.2 (Recently Deleted: restore, delete permanently, purge after 30 days) and §6.7 (Deleting: only the owner
// deletes, and the purge only removes notes that are already in Recently Deleted). Plan 2, Global Constraints: pinning,
// deleting and restoring never change a note's text or its `modifiedAt`.

private let day: TimeInterval = 24 * 60 * 60

private func noteStore() throws -> (NoteStore, Database) {
    let db = try Database(path: ":memory:")
    return (try NoteStore(database: db), db)
}

private func date(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds) }

@discardableResult
private func add(_ store: NoteStore, _ body: String, edited: Double = 0) throws -> Note {
    var note = try store.create(now: date(edited))
    note.body = body
    try store.save(note)
    return note
}

private func count(_ db: Database) throws -> Int64? {
    try db.query("SELECT COUNT(*) AS n FROM notes").first?.int("n")
}

@Test func retentionIsThirtyDays() {
    #expect(NoteStore.recentlyDeletedRetention == 30 * 24 * 60 * 60)
}

@Test func deleteMovesNoteOutOfSummaries() throws {
    let (store, _) = try noteStore()
    let kept = try add(store, "kept", edited: 1)
    let gone = try add(store, "gone", edited: 2)
    try store.delete(gone.id, now: date(100))
    #expect(try store.summaries().map(\.id) == [kept.id])
    let deleted = try store.deletedSummaries()
    #expect(deleted.map(\.id) == [gone.id])
    #expect(deleted.first?.deletedAt == date(100))
    #expect(deleted.first?.displayTitle == "gone")
    #expect(try store.note(gone.id)?.deletedAt == date(100))
}

@Test func liveSummariesHaveNoDeletionDate() throws {
    let (store, _) = try noteStore()
    try add(store, "live")
    #expect(try store.summaries().allSatisfy { $0.deletedAt == nil })
}

@Test func deletingKeepsTheTextAndModifiedAt() throws {
    let (store, _) = try noteStore()
    var note = try add(store, "text", edited: 0)
    note.modifiedAt = date(7)
    try store.save(note)
    try store.delete(note.id, now: date(500))
    var stored = try #require(try store.note(note.id))
    #expect(stored.body == "text" && stored.modifiedAt == date(7))
    try store.restore(note.id)
    stored = try #require(try store.note(note.id))
    #expect(stored.body == "text" && stored.modifiedAt == date(7))
}

@Test func deletingAnAlreadyDeletedNoteKeepsTheFirstDeletionDate() throws {
    let (store, _) = try noteStore()
    let note = try add(store, "x")
    try store.delete(note.id, now: date(10))
    try store.delete(note.id, now: date(99))  // must not postpone the purge
    #expect(try store.note(note.id)?.deletedAt == date(10))
}

@Test func deleteAndRestoreIgnoreUnknownIDs() throws {
    let (store, db) = try noteStore()
    try add(store, "x")
    let unknown = NoteID.make()
    try store.delete(unknown, now: date(1))
    try store.restore(unknown)
    try store.setPinned(unknown, true, now: date(1))
    try store.deletePermanently(unknown)
    #expect(try count(db) == 1)
    #expect(try store.note(unknown) == nil)
}

@Test func restoreBringsItBackWithPinKept() throws {
    let (store, _) = try noteStore()
    let note = try add(store, "pinned", edited: 3)
    let other = try add(store, "other", edited: 9)
    try store.setPinned(note.id, true, now: date(20))
    try store.delete(note.id, now: date(30))
    #expect(try store.summaries().map(\.id) == [other.id])

    try store.restore(note.id)
    let summaries = try store.summaries()
    #expect(summaries.map(\.id) == [note.id, other.id])
    #expect(summaries.first?.pinnedAt == date(20))
    #expect(summaries.first?.deletedAt == nil)
    #expect(try store.deletedSummaries().isEmpty)
    #expect(try store.note(note.id)?.modifiedAt == date(3))
}

@Test func restoreOfALiveNoteChangesNothing() throws {
    let (store, _) = try noteStore()
    let note = try add(store, "live")
    try store.setPinned(note.id, true, now: date(4))
    let before = try store.note(note.id)
    try store.restore(note.id)
    #expect(try store.note(note.id) == before)
    #expect(try store.summaries().map(\.id) == [note.id])
}

@Test func deletePermanentlyRemovesADeletedNote() throws {
    let (store, db) = try noteStore()
    let note = try add(store, "doomed words")
    try store.delete(note.id, now: date(1))
    try store.deletePermanently(note.id)
    #expect(try store.note(note.id) == nil)
    #expect(try store.deletedSummaries().isEmpty)
    #expect(try count(db) == 0)
    // The search index forgets it too.
    #expect(try db.query("SELECT rowid FROM notes_fts WHERE notes_fts MATCH 'doomed'").isEmpty)
}

@Test func deletePermanentlyIgnoresLiveNotes() throws {
    let (store, db) = try noteStore()
    let live = try add(store, "live")
    try store.setPinned(live.id, true, now: date(1))
    try store.deletePermanently(live.id)
    #expect(try store.note(live.id) != nil)
    #expect(try count(db) == 1)
}

@Test func purgeRemovesOnlyExpiredDeletedNotes() throws {
    let (store, db) = try noteStore()
    let now = date(0)
    let expired = try add(store, "expired")
    let recent = try add(store, "recent")
    let old = try add(store, "old but live", edited: -400 * 24 * 60 * 60)
    try store.delete(expired.id, now: now.addingTimeInterval(-31 * day))
    try store.delete(recent.id, now: now.addingTimeInterval(-29 * day))

    let removed = try store.purge(deletedBefore: now.addingTimeInterval(-NoteStore.recentlyDeletedRetention))
    #expect(removed == 1)
    #expect(try store.note(expired.id) == nil)
    #expect(try store.note(recent.id) != nil)
    #expect(try store.note(old.id) != nil)
    #expect(try count(db) == 2)
    #expect(try store.purge(deletedBefore: now.addingTimeInterval(-NoteStore.recentlyDeletedRetention)) == 0)
}

@Test func purgeKeepsANoteDeletedExactlyAtTheCutoff() throws {
    let (store, _) = try noteStore()
    let note = try add(store, "edge")
    let cutoff = date(1_000)
    try store.delete(note.id, now: cutoff)
    #expect(try store.purge(deletedBefore: cutoff) == 0)
    #expect(try store.purge(deletedBefore: cutoff.addingTimeInterval(0.001)) == 1)
}

@Test func purgeWithNothingToRemoveReturnsZero() throws {
    let (store, _) = try noteStore()
    #expect(try store.purge(deletedBefore: date(0)) == 0)
    try add(store, "live")
    #expect(try store.purge(deletedBefore: date(1_000_000)) == 0)
}

@Test func purgeRemovesEveryExpiredNote() throws {
    let (store, db) = try noteStore()
    for index in 0..<5 {
        let note = try add(store, "gone \(index)")
        try store.delete(note.id, now: date(Double(index)))
    }
    try add(store, "kept")
    #expect(try store.purge(deletedBefore: date(100)) == 5)
    #expect(try count(db) == 1)
}

@Test func deletedSummariesNewestDeletionFirst() throws {
    let (store, _) = try noteStore()
    let first = try add(store, "first", edited: 1)
    let second = try add(store, "second", edited: 2)
    let third = try add(store, "third", edited: 3)
    // Delete in an order that differs from the order of editing and of creation.
    try store.delete(second.id, now: date(10))
    try store.delete(third.id, now: date(30))
    try store.delete(first.id, now: date(20))
    #expect(try store.deletedSummaries().map(\.id) == [third.id, first.id, second.id])
    #expect(try store.deletedSummaries().map(\.deletedAt) == [date(30), date(20), date(10)])
}

@Test func deletedSummariesBreakTiesByID() throws {
    let (store, _) = try noteStore()
    let a = try add(store, "a")
    let b = try add(store, "b")
    try store.delete(a.id, now: date(5))
    try store.delete(b.id, now: date(5))
    #expect(try store.deletedSummaries().map(\.id.rawValue) == [a.id.rawValue, b.id.rawValue].sorted())
}

@Test func deletedSummariesCarryTheSidebarColumns() throws {
    let (store, _) = try noteStore()
    var note = try store.create(now: date(1))
    note.title = "Old meeting notes"
    note.body = "first line\nsecond line"
    note.modifiedAt = date(4)
    try store.save(note)
    try store.setPinned(note.id, true, now: date(5))
    try store.delete(note.id, now: date(6))
    #expect(
        try store.deletedSummaries() == [
            NoteSummary(
                id: note.id, displayTitle: "Old meeting notes", hasTitle: true, preview: note.preview,
                modifiedAt: date(4), pinnedAt: date(5), deletedAt: date(6))
        ])
}

@Test func deletedNotesStayInTheSearchIndexButOutOfSearchResults() throws {
    let (store, _) = try noteStore()
    let note = try add(store, "kubernetes rollout")
    try store.delete(note.id, now: date(1))
    #expect(try store.search("kube").isEmpty)
    try store.restore(note.id)
    #expect(try store.search("kube").map(\.id) == [note.id])
}

@Test func savingADeletedNoteKeepsItInRecentlyDeleted() throws {
    let (store, _) = try noteStore()
    var note = try add(store, "before")
    try store.delete(note.id, now: date(1))
    note.body = "typed after the delete"
    try store.save(note)
    #expect(try store.summaries().isEmpty)
    #expect(try store.deletedSummaries().map(\.id) == [note.id])
    #expect(try store.note(note.id)?.body == "typed after the delete")
}
