import Foundation
import Testing

@testable import ScratchCore

// Spec §9.4 (fixtures) and the data rules: tests never touch real data, and a fixture only ever replaces the
// contents of an isolated directory.

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ScratchStorageTests-\(UUID().uuidString)")
}

private func options(
    directory: URL, isolated: Bool = true, fixture: Fixture? = nil
) -> LaunchOptions {
    LaunchOptions(dataDirectory: directory, isIsolated: isolated, fixture: fixture)
}

private func fileNames(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
}

@Test func openCreatesDirectoryAndDatabase() throws {
    let directory = temporaryDirectory().appendingPathComponent("nested/deeper")
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent().deletingLastPathComponent()) }
    let storage = try ScratchStorage.open(options(directory: directory))
    #expect(storage.directory == directory)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("scratch.sqlite").path))
    #expect(ScratchStorage.databaseFileName == "scratch.sqlite")
    #expect(try storage.notes.summaries().isEmpty)
    #expect(try storage.session.load() == nil)
}

@Test func notesAndSessionPersistAcrossOpens() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let created: Note
    do {
        let storage = try ScratchStorage.open(options(directory: directory))
        created = try storage.notes.create(now: Date(timeIntervalSinceReferenceDate: 1000))
        try storage.session.save(
            SessionState(tabs: [TabState(noteID: created.id, selection: 0, scrollY: 0)], activeTabIndex: 0))
    }
    let reopened = try ScratchStorage.open(options(directory: directory))
    #expect(try reopened.notes.note(created.id) == created)
    #expect(try reopened.session.load()?.tabs.first?.noteID == created.id)
}

@Test func openWithoutFixtureKeepsExistingData() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
        let storage = try ScratchStorage.open(options(directory: directory, fixture: .typical))
        #expect(try storage.notes.summaries().count == 6)
    }
    let storage = try ScratchStorage.open(options(directory: directory))
    #expect(try storage.notes.summaries().count == 6)
    #expect(try storage.session.load()?.tabs.count == 2)
}

@Test func openSeedsTheFixture() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let storage = try ScratchStorage.open(options(directory: directory, fixture: .typical), now: now)
    let summaries = try storage.notes.summaries()
    #expect(summaries.count == 6)
    #expect(summaries[1].modifiedAt == now.addingTimeInterval(-3600))
    #expect(try storage.session.load()?.tabs.count == 2)
}

@Test func fixtureReplacesExistingData() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
        let typical = try ScratchStorage.open(options(directory: directory, fixture: .typical))
        #expect(try typical.notes.summaries().count == 6)
    }
    let empty = try ScratchStorage.open(options(directory: directory, fixture: .empty))
    #expect(try empty.notes.summaries().count == 0)
    #expect(try empty.session.load() == nil)
}

@Test func fixtureLeavesOnlyTheNewDatabaseFilesBehind() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    do { _ = try ScratchStorage.open(options(directory: directory, fixture: .typical)) }
    let stale = directory.appendingPathComponent("scratch.sqlite-journal")
    try Data("stale".utf8).write(to: stale)
    let unrelated = directory.appendingPathComponent("notes-export.txt")
    try Data("keep".utf8).write(to: unrelated)

    _ = try ScratchStorage.open(options(directory: directory, fixture: .empty))
    #expect(!FileManager.default.fileExists(atPath: stale.path))
    #expect(FileManager.default.fileExists(atPath: unrelated.path))
    #expect(try fileNames(in: directory).filter { $0.hasPrefix("scratch.sqlite") }.contains("scratch.sqlite"))
}

@Test func fixtureOnRealDirectoryIsRefused() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let real = options(directory: directory, isolated: false, fixture: .typical)
    #expect(throws: StorageError.fixtureRequiresIsolatedDirectory) { try ScratchStorage.open(real) }
    // Refused before anything happened to the directory.
    #expect(!FileManager.default.fileExists(atPath: directory.path))
}

@Test func realDirectoryWithoutFixtureOpens() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = try ScratchStorage.open(options(directory: directory, isolated: false))
    #expect(try storage.notes.summaries().isEmpty)
}

@Test func fixtureRunsInTheSystemTemporaryDirectory() throws {
    // Launch arguments as the UI tests pass them, resolved against the real home and the real temporary directory.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ScratchStorageTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let parsed = try LaunchOptions.parse(
        ["-ScratchDataDir", directory.path, "-ScratchFixture", "typical"],
        home: FileManager.default.homeDirectoryForCurrentUser,
        temporaryDirectory: FileManager.default.temporaryDirectory)
    #expect(parsed.isIsolated)
    let storage = try ScratchStorage.open(parsed)
    #expect(try storage.notes.summaries().count == 6)
}

@Test func openRefusesDataFromANewerVersion() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
        let storage = try ScratchStorage.open(options(directory: directory))
        _ = try storage.notes.create(now: Date(timeIntervalSinceReferenceDate: 1000))
    }
    let path = directory.appendingPathComponent(ScratchStorage.databaseFileName).path
    try Database(path: path).execute("PRAGMA user_version = 4")

    #expect(throws: SchemaError.newerThanSupported(found: 4, supported: 3)) {
        try ScratchStorage.open(options(directory: directory))
    }
    #expect(try Database(path: path).userVersion() == 4)
    #expect(try Database(path: path).query("SELECT COUNT(*) AS n FROM notes").first?.int("n") == 1)
}

/// `database` is the one the stores use, so a test can change how it behaves (`PRAGMA query_only` makes every write
/// fail, which is how the app's tests simulate a failing disk: a read-only file does not work, SQLite keeps it open).
@Test func databaseIsTheOneTheStoresUse() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = try ScratchStorage.open(options(directory: directory))
    let note = try storage.notes.create(now: Date(timeIntervalSinceReferenceDate: 1000))

    try storage.database.execute("PRAGMA query_only = 1")
    var edited = note
    edited.body = "typed while the disk is failing"
    #expect(throws: DatabaseError.self) { try storage.notes.save(edited) }
    #expect(try storage.notes.note(note.id)?.body == "")

    try storage.database.execute("PRAGMA query_only = 0")
    try storage.notes.save(edited)
    #expect(try storage.notes.note(note.id)?.body == "typed while the disk is failing")
}

// MARK: Attachments (Plan 5, Task 2; spec §6.4, §6.2)

private let hour: TimeInterval = 3600
private let day: TimeInterval = 24 * hour

/// A note with `body`, saved, and in Recently Deleted from `deletedAt` when that is given.
@discardableResult
private func addNote(
    _ storage: ScratchStorage, _ body: String, edited: Date = Date(timeIntervalSinceReferenceDate: 800_000_000),
    deletedAt: Date? = nil
) throws -> Note {
    var note = try storage.notes.create(now: edited)
    note.body = body
    try storage.notes.save(note)
    if let deletedAt { try storage.notes.delete(note.id, now: deletedAt) }
    return note
}

/// A copied attachment of `note`, as the store has it after the copy.
private func attach(_ storage: ScratchStorage, to note: Note, name: String = "file.txt") throws -> Attachment {
    let id = AttachmentID.make()
    _ = try storage.attachments.register(
        id: id, noteID: note.id, fileName: name, typeIdentifier: "public.plain-text", byteSize: 4, pixelSize: nil,
        now: Date())
    try storage.attachments.writeIn(id, data: Data("data".utf8))
    return try #require(try storage.attachments.attachment(id))
}

/// The attachments that the first note of the list holds.
private func attachmentsOfFirstNote(in storage: ScratchStorage) throws -> [Attachment] {
    let summary = try #require(try storage.notes.summaries().first)
    let note = try #require(try storage.notes.note(summary.id))
    return Array(try storage.attachments.attachments(AttachmentToken.ids(in: note.body)).values)
}

private func fileExists(_ attachment: Attachment, in storage: ScratchStorage) -> Bool {
    FileManager.default.fileExists(atPath: storage.attachments.fileURL(for: attachment).path)
}

private func folderExists(_ attachment: Attachment, in directory: URL) -> Bool {
    FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("attachments").appendingPathComponent(attachment.id.rawValue).path)
}

@Test func openGivesTheAttachmentStoreItsFolderInTheDataDirectory() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = try ScratchStorage.open(options(directory: directory))
    let note = try addNote(storage, "")
    let row = try attach(storage, to: note, name: "plan.txt")
    #expect(
        storage.attachments.fileURL(for: row)
            == directory.appendingPathComponent("attachments").appendingPathComponent(row.id.rawValue)
            .appendingPathComponent("plan.txt"))
    #expect(fileExists(row, in: storage))
    // The rows are in the database the notes are in, so they come back with the next open.
    let reopened = try ScratchStorage.open(options(directory: directory))
    #expect(try reopened.attachments.attachment(row.id) == row)
    #expect(fileExists(row, in: reopened))
}

@Test func openSeedsTheAttachmentsFixtureWithItsFiles() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let storage = try ScratchStorage.open(options(directory: directory, fixture: .attachments), now: now)
    let summary = try #require(try storage.notes.summaries().first)
    #expect(summary.displayTitle == "Screenshots")
    let rows = try attachmentsOfFirstNote(in: storage)
    #expect(rows.count == 2)
    for row in rows {
        #expect(row.isCopied)
        #expect(fileExists(row, in: storage), "\(row.fileName)")
    }
}

@Test func aFixtureAlsoReplacesTheAttachmentFiles() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let old: Attachment
    do {
        let storage = try ScratchStorage.open(options(directory: directory, fixture: .attachments))
        old = try #require(try attachmentsOfFirstNote(in: storage).first)
        #expect(folderExists(old, in: directory))
    }
    let unrelated = directory.appendingPathComponent("notes-export.txt")
    try Data("keep".utf8).write(to: unrelated)

    _ = try ScratchStorage.open(options(directory: directory, fixture: .empty))
    // The rows went with the old database, so the files they named would be unreachable.
    #expect(!folderExists(old, in: directory))
    #expect(FileManager.default.fileExists(atPath: unrelated.path))
}

@Test func openWithoutAFixtureKeepsTheAttachmentFiles() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let row: Attachment
    do {
        let storage = try ScratchStorage.open(options(directory: directory))
        row = try attach(storage, to: try addNote(storage, ""))
    }
    let storage = try ScratchStorage.open(options(directory: directory))
    #expect(fileExists(row, in: storage))
}

@Test func deletePermanentlyRemovesUnsharedFiles() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = try ScratchStorage.open(options(directory: directory))
    let note = try addNote(storage, "")
    let image = try attach(storage, to: note, name: "one.txt")
    let other = try attach(storage, to: note, name: "two.txt")
    var edited = note
    edited.body = "text\n\(AttachmentToken.line(for: image.id))\n\(AttachmentToken.line(for: other.id))"
    try storage.notes.save(edited)
    let bystander = try attach(storage, to: try addNote(storage, "unrelated"), name: "bystander.txt")
    try storage.notes.delete(note.id, now: Date())

    try storage.deletePermanently(note.id)

    #expect(try storage.notes.note(note.id) == nil)
    for row in [image, other] {
        #expect(!fileExists(row, in: storage), "\(row.fileName)")
        #expect(!folderExists(row, in: directory), "\(row.fileName)")
        #expect(try storage.attachments.attachment(row.id) == nil, "\(row.fileName)")
    }
    // An attachment that the note did not hold is not touched, referenced or not.
    #expect(fileExists(bystander, in: storage))
    #expect(try storage.attachments.attachment(bystander.id) != nil)
}

@Test func sharedTokenKeepsFile() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = try ScratchStorage.open(options(directory: directory))
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let first = try addNote(storage, "")
    let shared = try attach(storage, to: first, name: "shared.txt")
    let line = AttachmentToken.line(for: shared.id)
    var holder = first
    holder.body = "one\n\(line)"
    try storage.notes.save(holder)
    // A second note names the same id. The first is purged, 40 days after it was deleted.
    let second = try addNote(storage, "two\n\(line)")
    try storage.notes.delete(first.id, now: now.addingTimeInterval(-40 * day))

    #expect(try storage.purge(deletedBefore: now.addingTimeInterval(-30 * day)) == 1)
    #expect(try storage.notes.note(first.id) == nil)
    #expect(try storage.notes.note(second.id) != nil)
    #expect(fileExists(shared, in: storage))
    #expect(try storage.attachments.attachment(shared.id) == shared)

    // When the second note goes too, nothing names the file any more, and it goes.
    try storage.notes.delete(second.id, now: now.addingTimeInterval(-35 * day))
    #expect(try storage.purge(deletedBefore: now.addingTimeInterval(-30 * day)) == 1)
    #expect(!fileExists(shared, in: storage))
    #expect(try storage.attachments.attachment(shared.id) == nil)
}

@Test func deletePermanentlyKeepsAFileThatAnotherNoteNames() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = try ScratchStorage.open(options(directory: directory))
    let deleted = try addNote(storage, "")
    let shared = try attach(storage, to: deleted, name: "shared.txt")
    let line = AttachmentToken.line(for: shared.id)
    var edited = deleted
    edited.body = line
    try storage.notes.save(edited)
    try addNote(storage, "also here\n\(line)", deletedAt: Date())
    try storage.notes.delete(deleted.id, now: Date())

    try storage.deletePermanently(deleted.id)
    #expect(try storage.notes.note(deleted.id) == nil)
    #expect(fileExists(shared, in: storage))
    #expect(try storage.attachments.attachment(shared.id) != nil)
}

@Test func deletePermanentlyOfANoteThatIsNotDeletedChangesNothing() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = try ScratchStorage.open(options(directory: directory))
    let live = try addNote(storage, "")
    let row = try attach(storage, to: live)
    var edited = live
    edited.body = AttachmentToken.line(for: row.id)
    try storage.notes.save(edited)

    try storage.deletePermanently(live.id)
    #expect(try storage.notes.note(live.id) == edited)
    #expect(fileExists(row, in: storage))
    #expect(try storage.attachments.attachment(row.id) != nil)
    // An unknown note is ignored, too.
    try storage.deletePermanently(NoteID.make())
    #expect(fileExists(row, in: storage))
}

@Test func purgeRemovesTheFilesOfPurgedNotesOnly() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = try ScratchStorage.open(options(directory: directory))
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func noteHolding(_ name: String, deletedAt: Date?) throws -> (Note, Attachment) {
        let note = try addNote(storage, "")
        let row = try attach(storage, to: note, name: name)
        var edited = note
        edited.body = "text\n\(AttachmentToken.line(for: row.id))"
        try storage.notes.save(edited)
        if let deletedAt { try storage.notes.delete(note.id, now: deletedAt) }
        return (edited, row)
    }
    let (expired, expiredFile) = try noteHolding("expired.txt", deletedAt: now.addingTimeInterval(-31 * day))
    let (recent, recentFile) = try noteHolding("recent.txt", deletedAt: now.addingTimeInterval(-2 * day))
    let (live, liveFile) = try noteHolding("live.txt", deletedAt: nil)
    // Unreferenced, created now, and not the purge's to remove: only the sweep looks at a file no purged note named.
    let stray = try attach(storage, to: live, name: "stray.txt")

    #expect(try storage.purge(deletedBefore: now.addingTimeInterval(-NoteStore.recentlyDeletedRetention)) == 1)
    #expect(try storage.notes.note(expired.id) == nil)
    #expect(try storage.notes.note(recent.id) != nil)
    #expect(try storage.notes.note(live.id) != nil)
    #expect(!fileExists(expiredFile, in: storage))
    #expect(!folderExists(expiredFile, in: directory))
    #expect(try storage.attachments.attachment(expiredFile.id) == nil)
    for kept in [recentFile, liveFile, stray] {
        #expect(fileExists(kept, in: storage), "\(kept.fileName)")
        #expect(try storage.attachments.attachment(kept.id) != nil, "\(kept.fileName)")
    }
}

@Test func purgeOfNothingReturnsZeroAndTouchesNoFile() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = try ScratchStorage.open(options(directory: directory))
    let row = try attach(storage, to: try addNote(storage, ""))
    #expect(try storage.purge(deletedBefore: Date()) == 0)
    #expect(fileExists(row, in: storage))
}

@Test func aNoteWithNoAttachmentsIsPurgedAndDeletedAsBefore() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = try ScratchStorage.open(options(directory: directory))
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let old = try addNote(storage, "old", deletedAt: now.addingTimeInterval(-40 * day))
    let gone = try addNote(storage, "gone", deletedAt: now)
    #expect(try storage.purge(deletedBefore: now.addingTimeInterval(-30 * day)) == 1)
    #expect(try storage.notes.note(old.id) == nil)
    try storage.deletePermanently(gone.id)
    #expect(try storage.notes.note(gone.id) == nil)
    // No attachment was ever made, so no folder was either.
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("attachments").path))
}
