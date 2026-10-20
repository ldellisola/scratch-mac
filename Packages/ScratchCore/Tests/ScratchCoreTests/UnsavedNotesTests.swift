import Foundation
import Testing

@testable import ScratchCore

// Spec §6.6 and the anti-goal "Lost text" (§4): a note whose write failed is kept, with the text the owner typed, until
// a write of it succeeds (docs/features/autosave-and-restore.md, "Write errors are not silent").

private func note(
    _ body: String, id: NoteID = NoteID(rawValue: "a"), edited seconds: TimeInterval = 100
) -> Note {
    Note(
        id: id, title: "", body: body, createdAt: Date(timeIntervalSinceReferenceDate: 0),
        modifiedAt: Date(timeIntervalSinceReferenceDate: seconds))
}

@Test func startsEmpty() {
    let unsaved = UnsavedNotes()
    #expect(unsaved.all.isEmpty)
    #expect(unsaved.note(NoteID(rawValue: "a")) == nil)
}

@Test func failedWriteIsRemembered() {
    let unsaved = UnsavedNotes()
    let typed = note("typed text")
    unsaved.writeFailed(typed)
    #expect(unsaved.note(typed.id) == typed)
    #expect(unsaved.all == [typed])
}

@Test func successfulWriteForgetsTheNote() {
    let unsaved = UnsavedNotes()
    let typed = note("typed text")
    unsaved.writeFailed(typed)
    unsaved.writeSucceeded(typed)
    #expect(unsaved.note(typed.id) == nil)
    #expect(unsaved.all.isEmpty)
}

@Test func successfulWriteOfANoteThatNeverFailedChangesNothing() {
    let unsaved = UnsavedNotes()
    let other = note("other", id: NoteID(rawValue: "b"))
    unsaved.writeFailed(other)
    unsaved.writeSucceeded(note("typed text"))
    #expect(unsaved.all == [other])
}

@Test func newerFailedCopyReplacesAnOlderOne() {
    let unsaved = UnsavedNotes()
    unsaved.writeFailed(note("one", edited: 100))
    unsaved.writeFailed(note("one two", edited: 200))
    #expect(unsaved.note(NoteID(rawValue: "a"))?.body == "one two")
}

/// The writes of one note run in the order they were made, but a failure is reported when its write ends, so an older
/// copy's failure must never replace a newer copy that is remembered already.
@Test func olderFailedCopyNeverReplacesANewerOne() {
    let unsaved = UnsavedNotes()
    unsaved.writeFailed(note("one two", edited: 200))
    unsaved.writeFailed(note("one", edited: 100))
    #expect(unsaved.note(NoteID(rawValue: "a"))?.body == "one two")
}

@Test func successfulWriteOfANewerCopyForgetsAnOlderFailure() {
    let unsaved = UnsavedNotes()
    unsaved.writeFailed(note("one", edited: 100))
    unsaved.writeSucceeded(note("one two", edited: 200))
    #expect(unsaved.note(NoteID(rawValue: "a")) == nil)
}

/// A retry of an old copy that succeeds while a newer copy has failed must not forget the newer one: its text is still
/// only in memory.
@Test func successfulWriteOfAnOlderCopyKeepsANewerFailure() {
    let unsaved = UnsavedNotes()
    unsaved.writeFailed(note("one two", edited: 200))
    unsaved.writeSucceeded(note("one", edited: 100))
    #expect(unsaved.note(NoteID(rawValue: "a"))?.body == "one two")
}

@Test func forgetDropsOneNote() {
    let unsaved = UnsavedNotes()
    let first = note("first", id: NoteID(rawValue: "a"))
    let second = note("second", id: NoteID(rawValue: "b"))
    unsaved.writeFailed(first)
    unsaved.writeFailed(second)
    unsaved.forget(first.id)
    #expect(unsaved.all == [second])
}

@Test func allListsTheOldestEditFirst() {
    let unsaved = UnsavedNotes()
    let newer = note("newer", id: NoteID(rawValue: "a"), edited: 300)
    let older = note("older", id: NoteID(rawValue: "b"), edited: 100)
    unsaved.writeFailed(newer)
    unsaved.writeFailed(older)
    #expect(unsaved.all == [older, newer])
}

/// The storage queue reports while the main thread reads: no report may be lost or tear.
@Test func concurrentReportsAreAllKept() async {
    let unsaved = UnsavedNotes()
    await withTaskGroup(of: Void.self) { group in
        for index in 0..<50 {
            group.addTask {
                unsaved.writeFailed(note("text \(index)", id: NoteID(rawValue: "note-\(index)")))
                _ = unsaved.all
            }
        }
    }
    #expect(unsaved.all.count == 50)
}
