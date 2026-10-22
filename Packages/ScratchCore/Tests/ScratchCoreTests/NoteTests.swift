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

// MARK: Fence and attachment lines (Plan 5, Task 1)
//
// A fence line (three backticks) and an attachment line (`[[attachment:<id>]]`) are structure, not words: a note never
// takes its title or its preview from them. A note with nothing else shows "Untitled" (docs/features/sidebar.md).

private let attachmentLine = "[[attachment:6f9619ff-8b86-4d11-b42d-00c04fc964ff]]"
private let otherAttachmentLine = "[[attachment:0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d]]"

@Test func titleSkipsFenceLines() {
    let n = note(title: "", body: "```swift\nlet a = 1\n```")
    #expect(n.displayTitle == "let a = 1")
    #expect(n.hasTitle == false)
}

@Test func titleSkipsAFenceLineWithSpacesBeforeItAndMoreBackticks() {
    #expect(note(title: "", body: "   ````python\nprint(1)\n````").displayTitle == "print(1)")
    #expect(note(title: "", body: "```\n\n  \nx = 1").displayTitle == "x = 1")
}

@Test func titleSkipsAFenceThatHasNoPartner() {
    #expect(note(title: "", body: "```swift").displayTitle == "")
    #expect(note(title: "", body: "```swift\nlet a = 1").displayTitle == "let a = 1")
}

@Test func twoBackticksAreText() {
    #expect(note(title: "", body: "``not a fence``\nx").displayTitle == "``not a fence``")
}

@Test func titleSkipsAttachmentLines() {
    #expect(note(title: "", body: "\(attachmentLine)\nBug screenshot").displayTitle == "Bug screenshot")
    #expect(
        note(title: "", body: "\(attachmentLine)\n\(otherAttachmentLine)\n\nBug screenshot").displayTitle
            == "Bug screenshot")
}

@Test func titleSkipsAFenceAndAnAttachmentTogether() {
    let n = note(title: "", body: "\(attachmentLine)\n```sh\nls -la\n```")
    #expect(n.displayTitle == "ls -la")
}

@Test func imageOnlyNoteHasEmptyTitle() {
    let n = note(title: "", body: attachmentLine)
    #expect(n.displayTitle == "")
    #expect(n.hasTitle == false)
    #expect(n.preview == "")
    // The note is not empty: it holds an attachment, so it must never be taken for an unused note.
    #expect(n.isEmpty == false)
    #expect(note(title: "", body: "\(attachmentLine)\n\(otherAttachmentLine)\n").displayTitle == "")
    #expect(note(title: "", body: "```\n```").displayTitle == "")
}

@Test func anAttachmentLineThatHoldsMoreIsText() {
    let line = "see \(attachmentLine)"
    #expect(note(title: "", body: line).displayTitle == line)
    #expect(
        note(title: "", body: " \(attachmentLine)").displayTitle
            == "[[attachment:6f9619ff-8b86-4d11-b42d-00c04fc964ff]]")
    #expect(note(title: "", body: "\(attachmentLine) done").displayTitle == "\(attachmentLine) done")
}

@Test func anUppercaseTokenIsText() {
    let line = "[[attachment:6F9619FF-8B86-4D11-B42D-00C04FC964FF]]"
    #expect(note(title: "", body: line).displayTitle == line)
}

@Test func aTypedTitleIsNeverReplaced() {
    let n = note(title: "My title", body: "\(attachmentLine)\n```\ncode\n```")
    #expect(n.displayTitle == "My title")
    #expect(n.hasTitle)
}

@Test func previewSkipsFenceAndAttachmentLines() {
    let n = note(title: "Deploy", body: "[ ] bump\n\(attachmentLine)\n```sh\nmake release\n```\n[x] tag")
    #expect(n.preview == "[ ] bump make release [x] tag")
}

@Test func previewOfUntitledNoteSkipsTheTitleAndTheStructureAround() {
    let body = "\(attachmentLine)\n```swift\nlet a = 1\nlet b = 2\n```\n\(otherAttachmentLine)\nlet c = 3"
    let n = note(title: "", body: body)
    #expect(n.displayTitle == "let a = 1")
    #expect(n.preview == "let b = 2 let c = 3")
}

@Test func previewOfAnImageOnlyNoteIsEmpty() {
    #expect(note(title: "Screenshots", body: "\(attachmentLine)\n\(otherAttachmentLine)").preview == "")
    #expect(note(title: "", body: "\(attachmentLine)\ncaption").preview == "")
}

@Test func structureLinesWorkWithCRLFAndCR() {
    #expect(note(title: "", body: "\(attachmentLine)\r\n```\r\ncode\r\n```\r\nmore").displayTitle == "code")
    #expect(note(title: "", body: "\(attachmentLine)\r```\rcode\r```\rmore").preview == "more")
}

@Test func aHugeLineAfterStructureLinesIsStillTheTitle() {
    let long = String(repeating: "x", count: 100_000)
    #expect(note(title: "", body: "\(attachmentLine)\n```\n\(long)").displayTitle == long)
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
