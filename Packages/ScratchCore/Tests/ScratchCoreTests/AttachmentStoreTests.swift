import Foundation
import Testing

@testable import ScratchCore

// Plan 5, Task 2 (spec §6.4, Attachments): Scratch keeps its own copy of every file under
// `<data directory>/attachments/<id>/<file name>`, a copy is never half written, and a file goes only when no stored
// note body, live or in Recently Deleted, names its id (Review Focus 1 and 5). The removal that follows a permanent
// delete and a purge is in `ScratchStorageTests`.

private let hour: TimeInterval = 3600
private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

/// The stores of one test, on an in-memory database, and a folder for the copied files and the files to copy.
private struct Harness {
    let database: Database
    let notes: NoteStore
    let attachments: AttachmentStore
    let directory: URL
    let sources: URL

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AttachmentStoreTests-\(UUID().uuidString)")
        directory = root.appendingPathComponent("attachments")
        sources = root.appendingPathComponent("sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        database = try Database(path: ":memory:")
        notes = try NoteStore(database: database)
        attachments = AttachmentStore(database: database, directory: directory)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    /// A file somewhere else, which is what the owner attaches.
    func source(_ text: String, named name: String = "source.txt") throws -> URL {
        let url = sources.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    /// A note with `body`, saved.
    @discardableResult
    func note(_ body: String, deletedAt: Date? = nil) throws -> Note {
        var note = try notes.create(now: now)
        note.body = body
        try notes.save(note)
        if let deletedAt { try notes.delete(note.id, now: deletedAt) }
        return note
    }

    /// A registered attachment of `note`, copied in from a file holding `text` unless `copied` is false. It is returned
    /// as the store has it then.
    @discardableResult
    func attach(
        to note: Note, text: String = "contents", name: String = "file.txt", createdAt: Date = now, copied: Bool = true
    ) throws -> Attachment {
        let id = AttachmentID.make()
        let row = try attachments.register(
            id: id, noteID: note.id, fileName: name, typeIdentifier: "public.plain-text",
            byteSize: Int64(text.utf8.count), pixelSize: nil, now: createdAt)
        guard copied else { return row }
        try attachments.copyIn(id, from: try source(text, named: "source-\(id.rawValue).txt"))
        return try #require(try attachments.attachment(id))
    }

    func exists(_ attachment: Attachment) -> Bool {
        FileManager.default.fileExists(atPath: attachments.fileURL(for: attachment).path)
    }

    /// The folder `<attachments>/<id>`, where the file of an attachment lives.
    func folder(_ attachment: Attachment) -> URL {
        directory.appendingPathComponent(attachment.id.rawValue)
    }

    func rowCount() throws -> Int64? {
        try database.query("SELECT COUNT(*) AS n FROM attachments").first?.int("n")
    }
}

private func token(_ attachment: Attachment) -> String { AttachmentToken.line(for: attachment.id) }

private func contents(of url: URL) throws -> String {
    String(decoding: try Data(contentsOf: url), as: UTF8.self)
}

/// What is in `folder`, which is nothing when the folder is not there.
private func names(in folder: URL) throws -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
}

// MARK: Register and copy

@Test func registerThenCopyIn() throws {
    let h = try Harness()
    defer { h.remove() }
    let note = try h.note("")
    let id = AttachmentID.make()
    let source = try h.source("quarterly numbers", named: "Report Q3.pdf")

    let row = try h.attachments.register(
        id: id, noteID: note.id, fileName: "Report Q3.pdf", typeIdentifier: "com.adobe.pdf", byteSize: 17,
        pixelSize: nil, now: now)
    #expect(row.id == id && row.noteID == note.id)
    #expect(row.fileName == "Report Q3.pdf" && row.typeIdentifier == "com.adobe.pdf")
    #expect(row.byteSize == 17 && row.pixelWidth == nil && row.pixelHeight == nil)
    #expect(row.createdAt == now)
    // Registering does no file work: the row says the file is not in place yet.
    #expect(row.isCopied == false)
    #expect(try h.attachments.attachment(id) == row)
    #expect(!h.exists(row))
    #expect(!FileManager.default.fileExists(atPath: h.directory.path))

    try h.attachments.copyIn(id, from: source)
    let copied = try #require(try h.attachments.attachment(id))
    #expect(copied.isCopied)
    #expect(
        copied
            == Attachment(
                id: id, noteID: note.id, fileName: "Report Q3.pdf", typeIdentifier: "com.adobe.pdf", byteSize: 17,
                pixelWidth: nil, pixelHeight: nil, createdAt: now, isCopied: true))
    let url = h.attachments.fileURL(for: copied)
    #expect(url == h.directory.appendingPathComponent(id.rawValue).appendingPathComponent("Report Q3.pdf"))
    #expect(try contents(of: url) == "quarterly numbers")
    // The original is left alone, and the folder holds the one file.
    #expect(FileManager.default.fileExists(atPath: source.path))
    #expect(try names(in: h.folder(copied)) == ["Report Q3.pdf"])
}

@Test func theCopySurvivesTheOriginalBeingDeleted() throws {
    let h = try Harness()
    defer { h.remove() }
    let note = try h.note("")
    let id = AttachmentID.make()
    let source = try h.source("keep me")
    let row = try h.attachments.register(
        id: id, noteID: note.id, fileName: "source.txt", typeIdentifier: "public.plain-text", byteSize: 7,
        pixelSize: nil, now: now)
    try h.attachments.copyIn(id, from: source)
    try FileManager.default.removeItem(at: source)
    #expect(try contents(of: h.attachments.fileURL(for: row)) == "keep me")
}

@Test func registerKeepsThePixelSizeOfAnImage() throws {
    let h = try Harness()
    defer { h.remove() }
    let note = try h.note("")
    let id = AttachmentID.make()
    let row = try h.attachments.register(
        id: id, noteID: note.id, fileName: "shot.png", typeIdentifier: "public.png", byteSize: 304,
        pixelSize: (width: 64, height: 40), now: now)
    #expect(row.pixelWidth == 64 && row.pixelHeight == 40)
    let stored = try #require(try h.attachments.attachment(id))
    #expect(stored == row)
    #expect(stored.pixelWidth == 64 && stored.pixelHeight == 40)
}

@Test func registeringTheSameIDTwiceFailsAndKeepsTheFirstRow() throws {
    let h = try Harness()
    defer { h.remove() }
    let note = try h.note("")
    let id = AttachmentID.make()
    let first = try h.attachments.register(
        id: id, noteID: note.id, fileName: "a.txt", typeIdentifier: "public.plain-text", byteSize: 1, pixelSize: nil,
        now: now)
    #expect(throws: DatabaseError.self) {
        try h.attachments.register(
            id: id, noteID: note.id, fileName: "b.txt", typeIdentifier: "public.plain-text", byteSize: 2,
            pixelSize: nil, now: now)
    }
    #expect(try h.attachments.attachment(id) == first)
}

@Test func writeInData() throws {
    let h = try Harness()
    defer { h.remove() }
    let note = try h.note("")
    let id = AttachmentID.make()
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0xFF])
    let row = try h.attachments.register(
        id: id, noteID: note.id, fileName: "Pasted Image.png", typeIdentifier: "public.png",
        byteSize: Int64(png.count), pixelSize: (width: 2, height: 3), now: now)
    #expect(!h.exists(row))

    try h.attachments.writeIn(id, data: png)
    #expect(try h.attachments.attachment(id)?.isCopied == true)
    #expect(try Data(contentsOf: h.attachments.fileURL(for: row)) == png)
    #expect(try names(in: h.folder(row)) == ["Pasted Image.png"])

    // Writing again puts the new bytes in place, whole.
    let other = Data("replacement".utf8)
    try h.attachments.writeIn(id, data: other)
    #expect(try Data(contentsOf: h.attachments.fileURL(for: row)) == other)
    #expect(try names(in: h.folder(row)) == ["Pasted Image.png"])
}

@Test func copyingAnUnknownIDFails() throws {
    let h = try Harness()
    defer { h.remove() }
    let source = try h.source("x")
    let unknown = AttachmentID.make()
    #expect(throws: AttachmentError.unknownAttachment(unknown)) { try h.attachments.copyIn(unknown, from: source) }
    #expect(throws: AttachmentError.unknownAttachment(unknown)) {
        try h.attachments.writeIn(unknown, data: Data("x".utf8))
    }
    // Nothing was made for an id that has no row.
    #expect(!FileManager.default.fileExists(atPath: h.directory.path))
}

// MARK: File names

@Test func fileNameIsSanitised() throws {
    #expect(AttachmentStore.sanitisedFileName("report.pdf") == "report.pdf")
    #expect(AttachmentStore.sanitisedFileName("a/b:c.txt") == "a-b-c.txt")
    #expect(AttachmentStore.sanitisedFileName("../../etc/passwd") == "..-..-etc-passwd")
    #expect(AttachmentStore.sanitisedFileName("  padded name.txt \n") == "padded name.txt")
    #expect(AttachmentStore.sanitisedFileName("") == "file")
    #expect(AttachmentStore.sanitisedFileName("   \n\t") == "file")
    #expect(
        AttachmentStore.sanitisedFileName("Screenshot 2026-10-22 at 10.42.07.png")
            == "Screenshot 2026-10-22 at 10.42.07.png")
    #expect(AttachmentStore.sanitisedFileName("日本語 🙂.txt") == "日本語 🙂.txt")
    // A name that would point at the folder itself or at its parent is no name.
    #expect(AttachmentStore.sanitisedFileName(".") == "file")
    #expect(AttachmentStore.sanitisedFileName("..") == "file")
    #expect(AttachmentStore.sanitisedFileName(" .. ") == "file")
    #expect(AttachmentStore.sanitisedFileName("...") == "...")
    // Sanitising twice changes nothing more.
    for name in ["a/b:c", " : ", "///", "a\u{0}b"] {
        let once = AttachmentStore.sanitisedFileName(name)
        #expect(AttachmentStore.sanitisedFileName(once) == once, "\(name)")
        #expect(!once.contains("/") && !once.contains(":") && !once.contains("\u{0}"), "\(name)")
    }
}

@Test func theFileOfAnAwkwardNameIsCopiedUnderItsSanitisedName() throws {
    let h = try Harness()
    defer { h.remove() }
    let note = try h.note("")
    let id = AttachmentID.make()
    let row = try h.attachments.register(
        id: id, noteID: note.id, fileName: "a/b:c.txt", typeIdentifier: "public.plain-text", byteSize: 5,
        pixelSize: nil, now: now)
    try h.attachments.copyIn(id, from: try h.source("hello"))

    // The row keeps the name for display. The file system gets the sanitised one, inside the attachment's folder.
    #expect(try h.attachments.attachment(id)?.fileName == "a/b:c.txt")
    let url = h.attachments.fileURL(for: row)
    #expect(url.lastPathComponent == "a-b-c.txt")
    #expect(url.deletingLastPathComponent() == h.folder(row))
    #expect(try contents(of: url) == "hello")
    #expect(try names(in: h.folder(row)) == ["a-b-c.txt"])
}

@Test func anEmptyNameIsCopiedAsFile() throws {
    let h = try Harness()
    defer { h.remove() }
    let note = try h.note("")
    let id = AttachmentID.make()
    let row = try h.attachments.register(
        id: id, noteID: note.id, fileName: "  ", typeIdentifier: "public.data", byteSize: 2, pixelSize: nil, now: now)
    try h.attachments.writeIn(id, data: Data("ab".utf8))
    #expect(h.attachments.fileURL(for: row).lastPathComponent == "file")
    #expect(try names(in: h.folder(row)) == ["file"])
}

// MARK: Atomic copies

@Test func copyIsAtomic() throws {
    let h = try Harness()
    defer { h.remove() }
    let note = try h.note("")
    let id = AttachmentID.make()
    let row = try h.attachments.register(
        id: id, noteID: note.id, fileName: "report.txt", typeIdentifier: "public.plain-text", byteSize: 6,
        pixelSize: nil, now: now)
    let missing = h.sources.appendingPathComponent("not-there.txt")

    // A source that cannot be read: nothing is named like the target, and nothing stays behind.
    #expect(throws: (any Error).self) { try h.attachments.copyIn(id, from: missing) }
    #expect(!h.exists(row))
    #expect(try names(in: h.folder(row)).isEmpty)
    #expect(try h.attachments.attachment(id)?.isCopied == false)

    // A complete copy, then a copy that fails: the first one is whole and the row still says so.
    try h.attachments.copyIn(id, from: try h.source("whole!"))
    #expect(throws: (any Error).self) { try h.attachments.copyIn(id, from: missing) }
    #expect(try contents(of: h.attachments.fileURL(for: row)) == "whole!")
    #expect(try names(in: h.folder(row)) == ["report.txt"])
    #expect(try h.attachments.attachment(id)?.isCopied == true)
}

@Test func aCopyThatFailsAtTheLastStepLeavesNoTemporaryFile() throws {
    let h = try Harness()
    defer { h.remove() }
    let note = try h.note("")
    let id = AttachmentID.make()
    let row = try h.attachments.register(
        id: id, noteID: note.id, fileName: "report.txt", typeIdentifier: "public.plain-text", byteSize: 4,
        pixelSize: nil, now: now)
    // A folder in the target's place cannot be replaced by a file, so the copy is written and then cannot be named.
    let blocker = h.attachments.fileURL(for: row)
    try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: blocker.appendingPathComponent("inner.txt"))

    #expect(throws: (any Error).self) { try h.attachments.copyIn(id, from: try h.source("data")) }
    #expect(throws: (any Error).self) { try h.attachments.writeIn(id, data: Data("data".utf8)) }
    #expect(try names(in: h.folder(row)) == ["report.txt"])
    #expect(try contents(of: blocker.appendingPathComponent("inner.txt")) == "keep")
    #expect(try h.attachments.attachment(id)?.isCopied == false)
}

// MARK: Lookup

@Test func attachmentsByIDs() throws {
    let h = try Harness()
    defer { h.remove() }
    let note = try h.note("")
    let a = try h.attach(to: note, name: "a.txt")
    let b = try h.attach(to: note, name: "b.txt", copied: false)
    let unknown = AttachmentID.make()

    let found = try h.attachments.attachments([a.id, b.id, unknown, a.id])
    #expect(Set(found.keys) == [a.id, b.id])
    #expect(found[a.id]?.fileName == "a.txt" && found[a.id]?.isCopied == true)
    #expect(found[b.id]?.fileName == "b.txt" && found[b.id]?.isCopied == false)
    #expect(try h.attachments.attachments([]).isEmpty)
    #expect(try h.attachments.attachment(unknown) == nil)
}

@Test func attachmentsByIDsHandlesALongList() throws {
    let h = try Harness()
    defer { h.remove() }
    let note = try h.note("")
    var rows: [Attachment] = []
    for number in 0..<1_200 {
        rows.append(
            try h.attachments.register(
                id: AttachmentID.make(), noteID: note.id, fileName: "f\(number)", typeIdentifier: "public.data",
                byteSize: 1, pixelSize: nil, now: now))
    }
    let found = try h.attachments.attachments(rows.map(\.id) + [AttachmentID.make()])
    #expect(found.count == 1_200)
    #expect(found[rows[1_199].id]?.fileName == "f1199")
}

@Test func isImageNamesTheImageTypes() {
    func attachment(_ type: String) -> Attachment {
        Attachment(
            id: AttachmentID.make(), noteID: NoteID.make(), fileName: "x", typeIdentifier: type, byteSize: 1,
            pixelWidth: nil, pixelHeight: nil, createdAt: now, isCopied: true)
    }
    for type in ["public.png", "public.jpeg", "public.heic", "public.tiff", "com.compuserve.gif", "public.image"] {
        #expect(attachment(type).isImage, "\(type)")
    }
    for type in ["public.plain-text", "com.adobe.pdf", "public.data", "public.svg-image", "public.movie", ""] {
        #expect(!attachment(type).isImage, "\(type)")
    }
}

// MARK: What the notes refer to

@Test func referencedAttachmentIDsScansLiveAndDeletedBodies() throws {
    let h = try Harness()
    defer { h.remove() }
    let live = AttachmentID.make()
    let deleted = AttachmentID.make()
    let both = AttachmentID.make()
    let inLine = AttachmentID.make()
    let unused = AttachmentID.make()
    try h.note("text\n\(AttachmentToken.line(for: live))\n\(AttachmentToken.line(for: both))\nmore")
    try h.note("\(AttachmentToken.line(for: deleted))\n\(AttachmentToken.line(for: both))", deletedAt: now)
    try h.note("a token inside a sentence: \(AttachmentToken.line(for: inLine)) is still a reference")
    try h.note("nothing here\n[[attachment:abc]]")

    let referenced = try h.notes.referencedAttachmentIDs()
    #expect(referenced == [live, deleted, both, inLine])
    #expect(!referenced.contains(unused))
}

@Test func referencedAttachmentIDsOfNoNotes() throws {
    let h = try Harness()
    defer { h.remove() }
    #expect(try h.notes.referencedAttachmentIDs().isEmpty)
    try h.note("plain text")
    #expect(try h.notes.referencedAttachmentIDs().isEmpty)
}

// MARK: Removal by reference

@Test func removeUnreferencedRemovesOnlyUnreferencedCandidates() throws {
    let h = try Harness()
    defer { h.remove() }
    let kept = try h.attach(to: try h.note(""), name: "kept.txt")
    let gone = try h.attach(to: try h.note(""), name: "gone.txt")
    let outsider = try h.attach(to: try h.note(""), name: "outsider.txt")
    try h.note("text\n\(token(kept))")

    let removed = try h.attachments.removeUnreferenced([kept.id, gone.id], notes: h.notes)
    #expect(removed == 1)
    #expect(try h.attachments.attachment(gone.id) == nil)
    #expect(!h.exists(gone))
    #expect(!FileManager.default.fileExists(atPath: h.folder(gone).path))
    // A referenced candidate stays, and so does anything that is not a candidate, referenced or not.
    #expect(try h.attachments.attachment(kept.id) != nil && h.exists(kept))
    #expect(try h.attachments.attachment(outsider.id) != nil && h.exists(outsider))
}

@Test func removeUnreferencedLeavesAFileNamedByADeletedNote() throws {
    let h = try Harness()
    defer { h.remove() }
    let file = try h.attach(to: try h.note(""))
    try h.note(token(file), deletedAt: now)
    #expect(try h.attachments.removeUnreferenced([file.id], notes: h.notes) == 0)
    #expect(h.exists(file))
    #expect(try h.attachments.attachment(file.id) != nil)
}

@Test func removeUnreferencedNeedsNoFileOnDisk() throws {
    let h = try Harness()
    defer { h.remove() }
    let note = try h.note("")
    let never = try h.attach(to: note, name: "never-copied.txt", copied: false)
    let vanished = try h.attach(to: note, name: "vanished.txt")
    try FileManager.default.removeItem(at: h.folder(vanished))

    #expect(try h.attachments.removeUnreferenced([never.id, vanished.id, AttachmentID.make()], notes: h.notes) == 2)
    #expect(try h.rowCount() == 0)
}

@Test func removeUnreferencedWithNoCandidatesDoesNothing() throws {
    let h = try Harness()
    defer { h.remove() }
    let file = try h.attach(to: try h.note(""))
    #expect(try h.attachments.removeUnreferenced([], notes: h.notes) == 0)
    #expect(h.exists(file))
}

/// Review Focus 1: a token deleted from a note and brought back with ⌘Z is on screen again, so the file must be there.
/// Nothing but a permanent delete, a purge or the launch sweep removes one, and each of them asks the notes first.
@Test func aTokenThatIsNotInTheStoredTextYetStillHasItsFile() throws {
    let h = try Harness()
    defer { h.remove() }
    var note = try h.note("")
    let file = try h.attach(to: note)
    note.body = "text\n\(token(file))"
    try h.notes.save(note)

    // The owner deletes the token and the autosave stores that. Nothing removes the file.
    note.body = "text"
    try h.notes.save(note)
    #expect(h.exists(file))
    #expect(try h.attachments.attachment(file.id)?.isCopied == true)

    // ⌘Z brings the token back, and the next autosave stores it.
    note.body = "text\n\(token(file))"
    try h.notes.save(note)
    #expect(try h.attachments.removeUnreferenced([file.id], notes: h.notes) == 0)
    #expect(try contents(of: h.attachments.fileURL(for: file)) == "contents")
}

// MARK: The launch sweep

@Test func sweepNeverRemovesAReferencedFile() throws {
    let h = try Harness()
    defer { h.remove() }
    let longAgo = now.addingTimeInterval(-90 * 24 * hour)
    let inRecentlyDeleted = try h.attach(to: try h.note(""), name: "deleted.txt", createdAt: longAgo)
    let inALiveNote = try h.attach(to: try h.note(""), name: "live.txt", createdAt: longAgo)
    let inASentence = try h.attach(to: try h.note(""), name: "sentence.txt", createdAt: longAgo)
    try h.note("old\n\(token(inRecentlyDeleted))", deletedAt: longAgo)
    try h.note("text\n\(token(inALiveNote))\nmore")
    try h.note("see \(token(inASentence)) above")

    let removed = try h.attachments.sweep(createdBefore: now.addingTimeInterval(-24 * hour), notes: h.notes)
    #expect(removed == 0)
    for file in [inRecentlyDeleted, inALiveNote, inASentence] {
        #expect(h.exists(file), "\(file.fileName)")
        #expect(try h.attachments.attachment(file.id)?.isCopied == true, "\(file.fileName)")
    }
    #expect(try h.rowCount() == 3)
}

@Test func sweepRemovesOldUnreferenced() throws {
    let h = try Harness()
    defer { h.remove() }
    let note = try h.note("nothing")
    let old = try h.attach(to: note, name: "old.txt", createdAt: now.addingTimeInterval(-2 * 24 * hour))
    let neverFinished = try h.attach(
        to: note, name: "half.txt", createdAt: now.addingTimeInterval(-3 * 24 * hour), copied: false)

    let removed = try h.attachments.sweep(createdBefore: now.addingTimeInterval(-24 * hour), notes: h.notes)
    #expect(removed == 2)
    #expect(try h.attachments.attachment(old.id) == nil)
    #expect(try h.attachments.attachment(neverFinished.id) == nil)
    #expect(!h.exists(old))
    #expect(!FileManager.default.fileExists(atPath: h.folder(old).path))
}

@Test func sweepKeepsRecentUnreferenced() throws {
    let h = try Harness()
    defer { h.remove() }
    let note = try h.note("nothing")
    // Created an hour ago: the text that names it may not be saved yet, so it is not the sweep's to remove.
    let recent = try h.attach(to: note, name: "recent.txt", createdAt: now.addingTimeInterval(-hour))
    let removed = try h.attachments.sweep(createdBefore: now.addingTimeInterval(-24 * hour), notes: h.notes)
    #expect(removed == 0)
    #expect(h.exists(recent))
    #expect(try h.attachments.attachment(recent.id) != nil)
}

@Test func sweepRemovesOnlyTheOldUnreferencedOnesAmongMany() throws {
    let h = try Harness()
    defer { h.remove() }
    let note = try h.note("")
    let oldGone = try h.attach(to: note, name: "a.txt", createdAt: now.addingTimeInterval(-5 * 24 * hour))
    let oldKept = try h.attach(to: note, name: "b.txt", createdAt: now.addingTimeInterval(-5 * 24 * hour))
    let recent = try h.attach(to: note, name: "c.txt", createdAt: now.addingTimeInterval(-hour))
    var edited = note
    edited.body = token(oldKept)
    try h.notes.save(edited)

    #expect(try h.attachments.sweep(createdBefore: now.addingTimeInterval(-24 * hour), notes: h.notes) == 1)
    #expect(try h.attachments.attachment(oldGone.id) == nil)
    #expect(try h.attachments.attachment(oldKept.id) != nil && h.exists(oldKept))
    #expect(try h.attachments.attachment(recent.id) != nil && h.exists(recent))
    // A second sweep finds nothing more.
    #expect(try h.attachments.sweep(createdBefore: now.addingTimeInterval(-24 * hour), notes: h.notes) == 0)
}
