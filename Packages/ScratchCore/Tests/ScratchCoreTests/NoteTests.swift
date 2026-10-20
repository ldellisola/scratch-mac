import Foundation
import Testing

@testable import ScratchCore

// Spec §6.2 (sidebar rows) and §6.3 (tab titles): a note shows its title, or else its first non-empty line.

@Test func displayTitleUsesTrimmedTitle() {
    #expect(note(title: "  Deploy checklist ", body: "x").displayTitle == "Deploy checklist")
}

@Test func displayTitleFallsBackToFirstNonEmptyBodyLine() {
    let n = note(title: "", body: "\n   \n  curl -X POST https://api.local/v1\n-H x")
    #expect(n.displayTitle == "curl -X POST https://api.local/v1")
    #expect(n.hasTitle == false)
}

@Test func displayTitleIsEmptyForEmptyNote() { #expect(note(title: "", body: "").displayTitle == "") }

@Test func previewOfTitledNoteStartsAtFirstBodyLine() {
    let n = note(title: "Deploy checklist", body: "[ ] bump version\n\n[x] run migrations")
    #expect(n.preview == "[ ] bump version [x] run migrations")
}

@Test func previewOfUntitledNoteSkipsTheLineUsedAsTitle() {
    #expect(note(title: "", body: "SELECT 1\nFROM t").preview == "FROM t")
}

@Test func previewIsCappedAt120Characters() {
    #expect(note(title: "t", body: String(repeating: "a", count: 500)).preview.count == 120)
}

@Test func whitespaceOnlyNoteIsEmpty() {
    #expect(note(title: " ", body: "\n\t ").isEmpty)
    #expect(!note(title: "", body: "a").isEmpty)
}

@Test func noteIDsAreUniqueLowercaseUUIDs() {
    let a = NoteID.make()
    let b = NoteID.make()
    #expect(a != b && a.rawValue == a.rawValue.lowercased() && UUID(uuidString: a.rawValue) != nil)
}

/// A note with fixed dates, so tests only vary the text.
private func note(title: String, body: String) -> Note {
    Note(
        id: NoteID(rawValue: "00000000-0000-0000-0000-000000000001"),
        title: title,
        body: body,
        createdAt: Date(timeIntervalSinceReferenceDate: 1_000),
        modifiedAt: Date(timeIntervalSinceReferenceDate: 2_000)
    )
}
