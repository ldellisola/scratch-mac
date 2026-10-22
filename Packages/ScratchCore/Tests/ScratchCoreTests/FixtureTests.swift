import Foundation
import Testing

@testable import ScratchCore

// Spec §9.4 (fixtures): a named fixture gives UI tests, screenshots and benchmarks the same data every time.

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func stores() throws -> (NoteStore, SessionStore) {
    let db = try Database(path: ":memory:")
    return (try NoteStore(database: db), try SessionStore(database: db))
}

private func lines(of text: String) -> [Substring] {
    text.split(separator: "\n", omittingEmptySubsequences: false)
}

/// The text of every note, the live ones and then the deleted ones, in sidebar order.
private func bodies(of notes: NoteStore) throws -> [String] {
    try (notes.summaries() + notes.deletedSummaries()).map { try #require(try notes.note($0.id)).body }
}

private func note(titled title: String, in notes: NoteStore) throws -> Note {
    let summary = try #require(try notes.summaries().first { $0.displayTitle == title })
    return try #require(try notes.note(summary.id))
}

@Test func typicalMatchesMockup() throws {
    let (notes, session) = try stores()
    try Fixture.typical.seed(notes: notes, session: session, now: now)
    let summaries = try notes.summaries()
    #expect(summaries.count == 6)
    #expect(summaries[0].displayTitle == "Snippets I keep reusing")
    #expect(summaries[0].pinnedAt != nil)
    #expect(summaries[1].displayTitle == "Deploy checklist")
    #expect(summaries.dropFirst().allSatisfy { $0.pinnedAt == nil })
    let state = try #require(try session.load())
    #expect(state.tabs.count == 2)
    #expect(state.activeTabIndex == 0)
}

@Test func typicalListsTheMockupRowsInOrder() throws {
    let (notes, session) = try stores()
    try Fixture.typical.seed(notes: notes, session: session, now: now)
    let summaries = try notes.summaries()
    #expect(
        summaries.map(\.displayTitle) == [
            "Snippets I keep reusing", "Deploy checklist", "curl -X POST https://api.local/v1/notes \\", "Standup",
            "SELECT region, sum(volume)", "Groceries",
        ])
    #expect(summaries.map(\.hasTitle) == [true, true, false, true, false, true])
    #expect(summaries[0].preview.hasPrefix("git log --oneline --graph --all"))
    #expect(summaries[5].preview == "milk, eggs, coffee beans")
}

@Test func typicalDatesAreRelativeToNow() throws {
    let (notes, session) = try stores()
    try Fixture.typical.seed(notes: notes, session: session, now: now)
    let hour = 3600.0
    let day = 24 * hour
    let expected: [String: Double] = [
        "Snippets I keep reusing": -7 * day,
        "Deploy checklist": -hour,
        "curl -X POST https://api.local/v1/notes \\": -2 * hour,
        "Standup": -day,
        "SELECT region, sum(volume)": -day - 3 * hour,
        "Groceries": -5 * day,
    ]
    for summary in try notes.summaries() {
        let offset = try #require(expected[summary.displayTitle])
        #expect(summary.modifiedAt == now.addingTimeInterval(offset), "\(summary.displayTitle)")
    }
}

@Test func typicalSessionOpensDeployChecklistThenTheCurlNote() throws {
    let (notes, session) = try stores()
    try Fixture.typical.seed(notes: notes, session: session, now: now)
    let state = try #require(try session.load())
    let first = try #require(try notes.note(state.tabs[0].noteID))
    let second = try #require(try notes.note(state.tabs[1].noteID))
    #expect(first.displayTitle == "Deploy checklist")
    #expect(second.hasTitle == false)
    #expect(second.body.hasPrefix("curl -X POST https://api.local/v1/notes \\\n"))
    #expect(lines(of: second.body).count == 3)
    #expect(state.tabs.allSatisfy { $0.selection == 0 && $0.scrollY == 0 })
}

@Test func typicalDeployChecklistUsesEveryFormattingFeature() throws {
    let (notes, session) = try stores()
    try Fixture.typical.seed(notes: notes, session: session, now: now)
    let deploy = try note(titled: "Deploy checklist", in: notes)
    #expect(deploy.title == "Deploy checklist")
    for marker in ["[ ] ", "[x] ", "- ", "**", "`2.4.1`", "```bash\n", "\n```"] {
        #expect(deploy.body.contains(marker), "\(marker)")
    }
}

@Test func typicalUntitledNotesStartWithTheMockupText() throws {
    let (notes, session) = try stores()
    try Fixture.typical.seed(notes: notes, session: session, now: now)
    let query = try note(titled: "SELECT region, sum(volume)", in: notes)
    #expect(query.title == "")
    #expect(query.body == "SELECT region, sum(volume)\nFROM production GROUP BY region")
    let groceries = try note(titled: "Groceries", in: notes)
    #expect(groceries.body == "milk, eggs, coffee beans")
}

@Test func hugeNoteHasTenThousandLines() throws {
    let (notes, session) = try stores()
    try Fixture.hugeNote.seed(notes: notes, session: session, now: now)
    let huge = try note(titled: "Huge", in: notes)
    #expect(lines(of: huge.body).count == 10_000)
    #expect(huge.body.contains("```swift"))
}

@Test func hugeNoteAlternatesProseAndCodeBlocksOfFiftyLines() throws {
    let (notes, session) = try stores()
    try Fixture.hugeNote.seed(notes: notes, session: session, now: now)
    let all = lines(of: try note(titled: "Huge", in: notes).body)
    for block in 0..<200 {
        let slice = all[block * 50..<(block + 1) * 50]
        if block.isMultiple(of: 2) {
            #expect(!slice.contains { $0.hasPrefix("```") }, "block \(block) is prose")
        } else {
            #expect(slice.first == "```swift" && slice.last == "```", "block \(block) is code")
            #expect(!slice.dropFirst().dropLast().contains { $0.hasPrefix("```") }, "block \(block) has no inner fence")
        }
    }
}

@Test func hugeNoteSessionHasOneTabOnHuge() throws {
    let (notes, session) = try stores()
    try Fixture.hugeNote.seed(notes: notes, session: session, now: now)
    let summaries = try notes.summaries()
    #expect(summaries.count == 2)
    let small = try note(titled: "Small", in: notes)
    #expect(lines(of: small.body).count == 10)
    let huge = try note(titled: "Huge", in: notes)
    let state = try #require(try session.load())
    #expect(state.tabs.map(\.noteID) == [huge.id])
    #expect(state.activeTabIndex == 0)
}

@Test func fixtureContentIsTheSameEveryTime() throws {
    for fixture in Fixture.allCases {
        let (notesA, sessionA) = try stores()
        let (notesB, sessionB) = try stores()
        try fixture.seed(notes: notesA, session: sessionA, now: now)
        try fixture.seed(notes: notesB, session: sessionB, now: now)
        #expect(try bodies(of: notesA) == bodies(of: notesB), "\(fixture)")
    }
}

@Test func manyNotesHasTwoThousandNotes() throws {
    let (notes, session) = try stores()
    let started = ContinuousClock.now
    try Fixture.manyNotes.seed(notes: notes, session: session, now: now)
    #expect(ContinuousClock.now - started < .seconds(2))
    let summaries = try notes.summaries()
    #expect(summaries.count == 2000)
    #expect(Set(summaries.map(\.displayTitle)) == Set((1...2000).map { "Note \($0)" }))
}

@Test func manyNotesAreOneMinuteApartAndTheSessionIsOnTheNewest() throws {
    let (notes, session) = try stores()
    try Fixture.manyNotes.seed(notes: notes, session: session, now: now)
    let summaries = try notes.summaries()
    #expect(summaries.first?.displayTitle == "Note 2000")
    #expect(summaries.last?.displayTitle == "Note 1")
    for (newer, older) in zip(summaries, summaries.dropFirst()) {
        #expect(newer.modifiedAt.timeIntervalSince(older.modifiedAt) == 60)
    }
    #expect(summaries.allSatisfy { $0.modifiedAt <= now })
    let state = try #require(try session.load())
    #expect(state.tabs.map(\.noteID) == [summaries[0].id])
    #expect(state.activeTabIndex == 0)
}

@Test func emptyHasNoNotesAndNoSession() throws {
    let (notes, session) = try stores()
    try Fixture.empty.seed(notes: notes, session: session, now: now)
    #expect(try notes.summaries().isEmpty)
    #expect(try session.load() == nil)
}

@Test func recentlyDeletedFixture() throws {
    let (notes, session) = try stores()
    try Fixture.recentlyDeleted.seed(notes: notes, session: session, now: now)
    let summaries = try notes.summaries()
    #expect(summaries.count == 1)
    #expect(summaries.map(\.displayTitle) == ["Groceries"])
    let deleted = try notes.deletedSummaries()
    #expect(deleted.count == 2)
    #expect(deleted.map(\.displayTitle) == ["Old meeting notes", "Ancient"])
}

@Test func recentlyDeletedFixtureDatesAreRelativeToNow() throws {
    let (notes, session) = try stores()
    try Fixture.recentlyDeleted.seed(notes: notes, session: session, now: now)
    let hour = 3600.0
    let day = 24 * hour
    let groceries = try #require(try notes.summaries().first)
    #expect(groceries.modifiedAt == now.addingTimeInterval(-hour))
    #expect(groceries.deletedAt == nil && groceries.pinnedAt == nil)
    let deleted = try notes.deletedSummaries()
    let (meeting, ancient) = (deleted[0], deleted[1])
    #expect(meeting.deletedAt == now.addingTimeInterval(-2 * day))
    #expect(meeting.modifiedAt == now.addingTimeInterval(-3 * day))
    #expect(ancient.deletedAt == now.addingTimeInterval(-31 * day))
    #expect(ancient.modifiedAt == now.addingTimeInterval(-40 * day))
    // "Ancient" is past the retention and waits for the purge. "Old meeting notes" is not.
    let cutoff = now.addingTimeInterval(-NoteStore.recentlyDeletedRetention)
    #expect(deleted.filter { ($0.deletedAt ?? now) < cutoff }.map(\.displayTitle) == ["Ancient"])
}

@Test func recentlyDeletedFixtureSessionHasOneTabOnGroceries() throws {
    let (notes, session) = try stores()
    try Fixture.recentlyDeleted.seed(notes: notes, session: session, now: now)
    let groceries = try note(titled: "Groceries", in: notes)
    #expect(groceries.body == "milk, eggs, coffee beans")
    let state = try #require(try session.load())
    #expect(state.tabs.map(\.noteID) == [groceries.id])
    #expect(state.activeTabIndex == 0)
}

@Test func recentlyDeletedFixtureNotesAreReadableAndKeepTheirText() throws {
    let (notes, session) = try stores()
    try Fixture.recentlyDeleted.seed(notes: notes, session: session, now: now)
    for summary in try notes.deletedSummaries() {
        let stored = try #require(try notes.note(summary.id))
        #expect(stored.deletedAt == summary.deletedAt)
        #expect(!stored.body.isEmpty, "\(summary.displayTitle)")
        #expect(stored.title == summary.displayTitle)
    }
}

// Spec §6.4 (the marker table): the `formatting` fixture holds one of every marker, and a fenced block that must stay
// literal. Plan 3 shows it in the formatting UI tests and the screenshots.

@Test func formattingFixtureHasOneNote() throws {
    let (notes, session) = try stores()
    try Fixture.formatting.seed(notes: notes, session: session, now: now)
    let summaries = try notes.summaries()
    #expect(summaries.map(\.displayTitle) == ["Formatting"])
    #expect(try notes.deletedSummaries().isEmpty)
    let formatting = try note(titled: "Formatting", in: notes)
    #expect(formatting.title == "Formatting")
    #expect(formatting.pinnedAt == nil && formatting.deletedAt == nil)
    #expect(formatting.modifiedAt == now)
    let state = try #require(try session.load())
    #expect(state.tabs.map(\.noteID) == [formatting.id])
    #expect(state.activeTabIndex == 0)
    #expect(state.tabs.allSatisfy { $0.selection == 0 && $0.scrollY == 0 })
}

@Test func formattingFixtureBodyIsTheOneInThePlan() throws {
    let (notes, session) = try stores()
    try Fixture.formatting.seed(notes: notes, session: session, now: now)
    let body = try note(titled: "Formatting", in: notes).body
    #expect(
        lines(of: body) == [
            "- first bullet",
            "  - nested bullet",
            "[ ] open task",
            "[x] done task",
            "Some **bold** text, `inline **code**` and https://example.com/a_(b)?q=1.",
            "Unclosed **star and a lone ` tick stay plain.",
            "```sh",
            "- not a bullet",
            "**not bold**",
            "```",
        ])
}

// Spec §6.4 (code block, code highlighting): the `code` fixture holds a fenced block for five languages, a block whose
// fence has no name, and prose between them. Plan 4 shows it in the screenshots and the code UI tests.

@Test func codeFixtureHasOneNote() throws {
    let (notes, session) = try stores()
    try Fixture.code.seed(notes: notes, session: session, now: now)
    let summaries = try notes.summaries()
    #expect(summaries.map(\.displayTitle) == ["Code"])
    #expect(try notes.deletedSummaries().isEmpty)
    let code = try note(titled: "Code", in: notes)
    #expect(code.pinnedAt == nil && code.deletedAt == nil)
    #expect(code.modifiedAt == now)
    let state = try #require(try session.load())
    #expect(state.tabs.map(\.noteID) == [code.id])
    #expect(state.activeTabIndex == 0)
    #expect(state.tabs.allSatisfy { $0.selection == 0 && $0.scrollY == 0 })
}

@Test func codeFixtureHasABlockForEachLanguageAndOneWithoutAName() throws {
    let (notes, session) = try stores()
    try Fixture.code.seed(notes: notes, session: session, now: now)
    let body = try note(titled: "Code", in: notes).body
    let text = body as NSString

    let blocks = FenceScanner.codeBlocks(in: body)
    let names = blocks.map { block -> String in
        let opening = text.substring(with: NSRange(location: block.location, length: min(12, block.length)))
        return String(opening.prefix { $0 != "\n" }.dropFirst(3))
    }
    #expect(names == ["swift", "python", "sql", "json", "bash", ""])

    // Every fence pairs up: the note has twelve fence lines and no stray one.
    #expect(lines(of: body).filter { FenceScanner.isFenceLine(String($0)) }.count == 12)
    // Prose before the first block and between the blocks, and the first line is not a fence.
    #expect(lines(of: body).first == "Snippets, one block for each language.")
    #expect(blocks.first?.location ?? 0 > 0)
    // The block without a name is the last one, and holds JavaScript.
    let unnamed = text.substring(with: try #require(blocks.last))
    #expect(unnamed.contains("const notes = await fetch"))
}

// Plan 5, Task 2 (spec §6.4, Attachments): the `attachments` fixture holds the note "Screenshots": a line of text, a
// PNG of 64 x 40 pixels, a line of text and a text file "rollback-plan.txt". Its two files are written under the
// attachments directory, which is why seeding it needs an `AttachmentStore`.

private func attachmentsStores() throws -> (NoteStore, SessionStore, AttachmentStore, URL) {
    let db = try Database(path: ":memory:")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "FixtureTests-\(UUID().uuidString)")
    return (
        try NoteStore(database: db), try SessionStore(database: db),
        AttachmentStore(database: db, directory: directory.appendingPathComponent("attachments")), directory
    )
}

@Test func attachmentsFixtureWritesFiles() throws {
    let (notes, session, attachments, directory) = try attachmentsStores()
    defer { try? FileManager.default.removeItem(at: directory) }
    try Fixture.attachments.seed(notes: notes, session: session, attachments: attachments, now: now)

    let screenshots = try note(titled: "Screenshots", in: notes)
    let ids = AttachmentToken.ids(in: screenshots.body)
    #expect(ids.count == 2)
    let rows = try attachments.attachments(ids)
    #expect(rows.count == 2)
    let png = try #require(rows[ids[0]])
    let text = try #require(rows[ids[1]])
    #expect(png.isCopied && text.isCopied)
    #expect(png.noteID == screenshots.id && text.noteID == screenshots.id)
    #expect(png.createdAt == now && text.createdAt == now)

    // The image: 64 x 40, public.png, and the file holds exactly the embedded bytes.
    #expect(png.typeIdentifier == "public.png" && png.isImage)
    #expect(png.pixelWidth == 64 && png.pixelHeight == 40)
    let pngBytes = try Data(contentsOf: attachments.fileURL(for: png))
    #expect(pngBytes.count == Int(png.byteSize))
    #expect(Array(pngBytes.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    // IHDR: the width and the height as 32-bit big-endian numbers at offsets 16 and 20.
    let size = pngBytes.dropFirst(16).prefix(8).map(Int.init)
    #expect(size == [0, 0, 0, 64, 0, 0, 0, 40])
    #expect(pngBytes == FixtureContent.make(.attachments, now: now).attachments[0].data)

    // The text file.
    #expect(text.fileName == "rollback-plan.txt" && !text.isImage)
    #expect(text.pixelWidth == nil && text.pixelHeight == nil)
    let textBytes = try Data(contentsOf: attachments.fileURL(for: text))
    #expect(textBytes.count == Int(text.byteSize))
    #expect(String(decoding: textBytes, as: UTF8.self).hasPrefix("Rollback plan"))
    #expect(attachments.fileURL(for: text).lastPathComponent == "rollback-plan.txt")
}

@Test func attachmentsFixtureNoteIsTextThenImageThenTextThenFile() throws {
    let (notes, session, attachments, directory) = try attachmentsStores()
    defer { try? FileManager.default.removeItem(at: directory) }
    try Fixture.attachments.seed(notes: notes, session: session, attachments: attachments, now: now)

    #expect(try notes.summaries().map(\.displayTitle) == ["Screenshots"])
    #expect(try notes.deletedSummaries().isEmpty)
    let screenshots = try note(titled: "Screenshots", in: notes)
    #expect(screenshots.title == "Screenshots")
    #expect(screenshots.modifiedAt == now && screenshots.pinnedAt == nil && screenshots.deletedAt == nil)
    let body = lines(of: screenshots.body)
    #expect(body.count == 4)
    #expect(AttachmentToken.id(inLine: body[0]) == nil && !body[0].isEmpty)
    #expect(AttachmentToken.id(inLine: body[1]) != nil)
    #expect(AttachmentToken.id(inLine: body[2]) == nil && !body[2].isEmpty)
    #expect(AttachmentToken.id(inLine: body[3]) != nil)
    let state = try #require(try session.load())
    #expect(state.tabs.map(\.noteID) == [screenshots.id])
    #expect(state.activeTabIndex == 0)
    // The note holds the files, so a sweep that finds them old enough keeps them.
    #expect(try attachments.sweep(createdBefore: now.addingTimeInterval(1), notes: notes) == 0)
}

/// The notes alone are seeded when there is no store to write the files with, as in every test that predates it.
@Test func attachmentsFixtureWithoutAStoreSeedsTheNote() throws {
    let (notes, session) = try stores()
    try Fixture.attachments.seed(notes: notes, session: session, now: now)
    #expect(try notes.summaries().map(\.displayTitle) == ["Screenshots"])
}
