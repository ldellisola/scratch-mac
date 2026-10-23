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
    #expect(n.preview == "bump version run migrations")
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
    // Not a fence, so the line is the title. The editor reads the second backtick as the start of inline code, so the
    // first one is a character of the line and the pair that is left is markers (Plan 6, Task 4).
    #expect(note(title: "", body: "``not a fence``\nx").displayTitle == "`not a fence`")
    #expect(note(title: "", body: "``\nx").displayTitle == "``")
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
    #expect(n.preview == "bump make release tag")
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

// MARK: Text without markers (Plan 6, Task 4)
//
// A row and a tab show a line as the editor shows it outside a fenced block: a list line without its marker, bold and
// inline code without theirs. Inside a fenced block a line is as typed (docs/features/sidebar.md).

@Test func checkboxTitleHasNoMarker() {
    let n = note(title: "", body: "[ ] bump version to `2.4.1`\n[x] run migrations")
    #expect(n.displayTitle == "bump version to 2.4.1")
    #expect(n.preview == "run migrations")
    #expect(n.hasTitle == false)
}

@Test func bulletAndBoldTitle() {
    let n = note(title: "", body: "- **don't** deploy")
    #expect(n.displayTitle == "don't deploy")
    #expect(n.preview == "")
}

@Test func codeBlockLinesKeepMarkers() {
    let n = note(title: "", body: "```\n- x\n```")
    #expect(n.displayTitle == "- x")
    #expect(note(title: "", body: "```sh\n**not bold**\n[ ] not a box\n`not code`\n```").displayTitle == "**not bold**")
    #expect(
        note(title: "T", body: "```sh\n**not bold**\n[ ] not a box\n`not code`\n```").preview
            == "**not bold** [ ] not a box `not code`")
}

@Test func markerOnlyLineIsSkipped() {
    let n = note(title: "", body: "- \n****\n[ ] \n  - \n- real words\n- more")
    #expect(n.displayTitle == "real words")
    #expect(n.preview == "more")
    // A note of markers alone has no words: no title, and it is still not an empty note.
    let only = note(title: "", body: "- \n****")
    #expect(only.displayTitle == "" && only.preview == "" && only.hasTitle == false)
    #expect(only.isEmpty == false)
    #expect(note(title: "Typed", body: "- \n[ ] \n****\nafter").preview == "after")
}

@Test func globIsKept() {
    // ADR 0006: stars between punctuation are not bold.
    #expect(note(title: "", body: "src/**/*.ts").displayTitle == "src/**/*.ts")
    #expect(note(title: "", body: "- x**2 + y**2").displayTitle == "x**2 + y**2")
    #expect(note(title: "T", body: "first\nsrc/**/*.ts").preview == "first src/**/*.ts")
}

@Test func linksAndOtherTextAreKeptAsTyped() {
    #expect(note(title: "", body: "- see https://example.com/a_(b)").displayTitle == "see https://example.com/a_(b)")
    #expect(note(title: "", body: "-5 degrees").displayTitle == "-5 degrees")
    #expect(note(title: "", body: "Unclosed **star").displayTitle == "Unclosed **star")
}

@Test func theTitleTheOwnerTypedIsNeverChanged() {
    let n = note(title: "[ ] **typed** `title`", body: "- body")
    #expect(n.displayTitle == "[ ] **typed** `title`")
    #expect(n.hasTitle)
    #expect(n.preview == "body")
}

@Test func theIndentOfAListLineIsNotPartOfItsText() {
    #expect(note(title: "", body: "   - indented bullet").displayTitle == "indented bullet")
    #expect(note(title: "", body: "    [x] indented task").displayTitle == "indented task")
    #expect(note(title: "", body: "   plain, indented").displayTitle == "plain, indented")
}

@Test func theFenceStateFollowsHowTheFencesPair() {
    // Fences pair from the top (FenceScanner): the first two make a block, and a fence left over is no block.
    let body = "```a\n- x\n```\n- y\n```b\n- w"
    #expect(FenceScanner.codeBlocks(in: body).count == 1)
    let n = note(title: "", body: body)
    #expect(n.displayTitle == "- x")
    #expect(n.preview == "y w")
    // An opening fence with no partner at all: the lines after it are outside a block, so their markers go.
    #expect(note(title: "", body: "```swift\n- x\n[ ] y").displayTitle == "x")
    #expect(note(title: "", body: "```swift\n- x\n[ ] y").preview == "y")
    // And the block that does close keeps its lines as typed, whatever the lines after it are.
    #expect(note(title: "", body: "```\n- x\n```\n- y").preview == "y")
}

@Test func aLongerFenceClosesABlockAndTheLinesAfterItAreOutside() {
    let n = note(title: "", body: "```\n**x**\n`````\n**y**")
    #expect(n.displayTitle == "**x**")
    #expect(n.preview == "y")
}

@Test func markersAreTakenOutWithCRLFAndCR() {
    #expect(note(title: "", body: "[ ] one\r\n- two\r\n```\r\n- three\r\n```").displayTitle == "one")
    #expect(note(title: "", body: "[ ] one\r\n- two\r\n```\r\n- three\r\n```").preview == "two - three")
    #expect(note(title: "", body: "[ ] one\r- two\r```\r- three\r```").preview == "two - three")
}

@Test func attachmentLinesAreStillSkippedAroundListLines() {
    let n = note(title: "", body: "\(attachmentLine)\n- **caption**\n\(otherAttachmentLine)\n[ ] next")
    #expect(n.displayTitle == "caption")
    #expect(n.preview == "next")
}

@Test func previewIsCappedAfterTheMarkersAreTakenOut() {
    let words = String(repeating: "a", count: 200)
    let n = note(title: "t", body: "- **\(words)**")
    #expect(n.preview == String(repeating: "a", count: 120))
    // The markers do not count against the limit: the first line's 60 characters, a space and 59 of the second's.
    let sixty = String(repeating: "b", count: 60)
    let two = note(title: "t", body: "- **\(sixty)**\n[ ] `\(sixty)`\nnever")
    #expect(two.preview == sixty + " " + String(repeating: "b", count: 59))
}

@Test func aHugeLineWithMarkersIsStillTheTitle() {
    let long = String(repeating: "word ", count: 20_000) + "end"
    #expect(note(title: "", body: "- **\(long)**").displayTitle == long)
}

@Test func aDeployChecklistReadsWithoutItsMarkers() {
    let body = [
        "[ ] bump version to `2.4.1`", "[x] run migrations on staging", "[ ] tag the release", "",
        "- check error rate in grafana after rollout", "- **don't deploy after 4pm on fridays**", "", "```bash",
        "# watch the rollout", "kubectl rollout status deploy/api -n prod", "```",
    ].joined(separator: "\n")
    let n = note(title: "Deploy checklist", body: body)
    #expect(n.preview.hasPrefix("bump version to 2.4.1 run migrations on staging tag the release check error rate"))
    #expect(n.preview.count == Note.previewLimit)
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

// MARK: The scan follows FenceScanner (Plan 6, Task 4)

/// What the lines of `body` come to as the editor shows them, worked out the plain way: ``FenceScanner/codeBlocks(in:)``
/// says where the blocks are, and each line outside one goes through ``PlainLine``. `Note` does it lazily, with a look
/// ahead for the partner of each opening fence, and the two must agree on every text.
private func linesAsShown(_ body: String) -> [String] {
    let units = Array(body.utf16)
    let lines = TextLines.lines(in: units)
    let blocks = FenceScanner.codeBlocks(units: units, lines: lines)
    var shown: [String] = []
    for line in lines {
        let typed = String(decoding: units[line.start..<line.end], as: UTF16.self)
        if FenceScanner.isFenceLine(typed) || AttachmentToken.id(inLine: typed[...]) != nil { continue }
        let inBlock = blocks.contains { $0.location <= line.start && line.start < NSMaxRange($0) }
        let text = (inBlock ? typed[...] : PlainLine.text(of: typed[...]))
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { shown.append(trimmed) }
    }
    return shown
}

private func previewAsShown(_ lines: [String], titled: Bool) -> String {
    var text = ""
    for line in lines.dropFirst(titled ? 0 : 1) {
        if !text.isEmpty {
            guard text.count + 1 < Note.previewLimit else { break }
            text.append(" ")
        }
        text.append(contentsOf: line.prefix(Note.previewLimit - text.count))
        if text.count >= Note.previewLimit { break }
    }
    return text
}

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Test func randomNotesAreScannedAsTheFencesPair() {
    let pool = [
        "```", "```swift", "  ```sh", "````", "``", "`x`", "- a", "  - **b**", "[ ] c", "[x] `d`", "**e** f", "****",
        "- ", "[ ] ", "plain words", "   ", "", "src/**/*.ts", "[[attachment:6f9619ff-8b86-4d11-b42d-00c04fc964ff]]",
        "see https://example.com", "\t```", "x ```", "``` trailing", "- ```", "é **ü**",
    ]
    let breaks = ["\n", "\n", "\n", "\r\n", "\r"]
    var generator = SplitMix64(state: 20_261_023)
    for round in 0..<1_500 {
        let count = Int.random(in: 0...9, using: &generator)
        var body = ""
        for index in 0..<count {
            body += pool.randomElement(using: &generator)!
            if index < count - 1 || Bool.random(using: &generator) { body += breaks.randomElement(using: &generator)! }
        }
        let shown = linesAsShown(body)
        let untitled = note(title: "", body: body)
        #expect(untitled.displayTitle == (shown.first ?? ""), "round \(round): \(body.debugDescription)")
        #expect(untitled.preview == previewAsShown(shown, titled: false), "round \(round): \(body.debugDescription)")
        let titled = note(title: "T", body: body)
        #expect(titled.preview == previewAsShown(shown, titled: true), "round \(round): \(body.debugDescription)")
    }
}

@Test func aFenceBytesAwayFromItsPartnerIsStillPaired() {
    // The partner is a long way down, after lines that hold single backticks, inline code and a fence with text before it.
    let filler = (0..<2_000).map { "line \($0) with `inline` code and a ` stray tick" }.joined(separator: "\n")
    let body = "```\n- first\n\(filler)\nnot ``` a fence\n   ```\n- after"
    #expect(FenceScanner.codeBlocks(in: body).count == 1)
    let n = note(title: "", body: body)
    #expect(n.displayTitle == "- first")
    #expect(n.preview.hasPrefix("line 0 with `inline` code and a ` stray tick"))
    let tick = "with `inline` code and a ` stray tick"
    #expect(
        note(title: "T", body: "```\n- a\n" + filler + "\n```\n- b").preview
            == String("- a line 0 \(tick) line 1 \(tick) line 2 \(tick)".prefix(Note.previewLimit)))
    // With no partner anywhere, the lines after the fence are outside a block.
    let unpaired = "```\n- first\n" + filler
    #expect(note(title: "", body: unpaired).displayTitle == "first")
}
