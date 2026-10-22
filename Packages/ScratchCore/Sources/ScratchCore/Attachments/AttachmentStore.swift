import Foundation

/// SQLite's `SQLITE_CORRUPT`, for a row that does not hold what the schema promises.
private let sqliteCorrupt: Int32 = 11

/// An attachment could not be found.
public enum AttachmentError: Error, Equatable {
    /// There is no row for this id, so there is nothing to copy a file for.
    case unknownAttachment(AttachmentID)
}

/// The files that notes hold, and the rows that describe them (spec §6.4).
///
/// Scratch keeps its own copy of every file, in `directory/<id>/<file name>`, so the original can be moved or deleted
/// without the note losing it. A file and its row are removed only when no stored note body names its id
/// (``removeUnreferenced(_:notes:)``, ``sweep(createdBefore:notes:)``): a token that the owner deleted and brought back
/// with ⌘Z is on screen again and must find its file. Any thread may call an `AttachmentStore`: the ``Database``
/// serialises the SQL, and the file work (``copyIn(_:from:)``, ``writeIn(_:data:)``) belongs on the storage queue.
public final class AttachmentStore: Sendable {
    private let database: Database
    private let directory: URL

    /// `directory` is `<data directory>/attachments`. It is created with the first file, not here.
    public init(database: Database, directory: URL) {
        self.database = database
        self.directory = directory
    }

    // MARK: Writing

    /// Writes the row, with ``Attachment/isCopied`` false, and returns it. Fast: no file work, so the token can go into
    /// the note at once and draw as "Copying…" until ``copyIn(_:from:)`` or ``writeIn(_:data:)`` is done.
    ///
    /// `fileName` is the name to show, and is kept as it is. Throws when a row with `id` exists already.
    public func register(
        id: AttachmentID, noteID: NoteID, fileName: String, typeIdentifier: String, byteSize: Int64,
        pixelSize: (width: Int, height: Int)?, now: Date
    ) throws -> Attachment {
        try database.execute(
            """
            INSERT INTO attachments (id, note_id, file_name, type_identifier, byte_size, pixel_width, pixel_height,
                                     created_at, copied)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)
            """,
            [
                .text(id.rawValue), .text(noteID.rawValue), .text(fileName), .text(typeIdentifier),
                .integer(byteSize), pixelSize.map { SQLValue.integer(Int64($0.width)) } ?? .null,
                pixelSize.map { SQLValue.integer(Int64($0.height)) } ?? .null, .date(now),
            ])
        return Attachment(
            id: id, noteID: noteID, fileName: fileName, typeIdentifier: typeIdentifier, byteSize: byteSize,
            pixelWidth: pixelSize?.width, pixelHeight: pixelSize?.height, createdAt: now, isCopied: false)
    }

    /// Copies the file at `source` into place, then sets ``Attachment/isCopied``. Call it on the storage queue: the
    /// file can be large.
    ///
    /// The copy is written under a temporary name in the attachment's own folder and renamed into place, so the name
    /// of the file is never given to a half-written copy. A copy that fails leaves what was there before, and no
    /// temporary file. Throws ``AttachmentError/unknownAttachment(_:)`` when `id` has no row.
    public func copyIn(_ id: AttachmentID, from source: URL) throws {
        // A link to a file is followed: the copy is the file, not another link to it.
        let original = source.resolvingSymlinksInPath()
        try place(id) { temporary in try FileManager.default.copyItem(at: original, to: temporary) }
    }

    /// Writes `data` into place, then sets ``Attachment/isCopied``, in the same atomic way as ``copyIn(_:from:)``. For
    /// an image that came from the pasteboard and has no file. Call it on the storage queue.
    public func writeIn(_ id: AttachmentID, data: Data) throws {
        try place(id) { temporary in try data.write(to: temporary) }
    }

    /// Runs `write` to make the file under a temporary name, renames it to the attachment's file name and marks the
    /// row copied. The temporary file is removed when anything fails.
    private func place(_ id: AttachmentID, write: (URL) throws -> Void) throws {
        guard let stored = try attachment(id) else { throw AttachmentError.unknownAttachment(id) }
        let target = fileURL(for: stored)
        let folder = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let temporary = folder.appendingPathComponent(".copying-\(UUID().uuidString)")
        do {
            try write(temporary)
            try Self.moveIntoPlace(temporary, at: target)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        try database.execute("UPDATE attachments SET copied = 1 WHERE id = ?", [.text(id.rawValue)])
    }

    /// `rename(2)`: puts `source` at `destination` in one step, replacing a file that is there. `FileManager` has no
    /// call that does both on every platform.
    private static func moveIntoPlace(_ source: URL, at destination: URL) throws {
        guard rename(source.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    // MARK: Reading

    /// The attachment with this id, or nil when there is no row for it.
    public func attachment(_ id: AttachmentID) throws -> Attachment? {
        try attachments([id])[id]
    }

    /// The attachments that exist among `ids`. An id with no row is missing from the result.
    public func attachments(_ ids: [AttachmentID]) throws -> [AttachmentID: Attachment] {
        var found: [AttachmentID: Attachment] = [:]
        let unique = Array(Set(ids))
        // SQLite limits the number of `?` in a statement (999 in old versions), so a long list goes in pieces.
        for start in stride(from: 0, to: unique.count, by: Self.idsPerQuery) {
            let piece = unique[start..<min(start + Self.idsPerQuery, unique.count)]
            let placeholders = Array(repeating: "?", count: piece.count).joined(separator: ", ")
            let rows = try database.query(
                "SELECT \(Self.columns) FROM attachments WHERE id IN (\(placeholders))",
                piece.map { .text($0.rawValue) })
            for row in rows {
                let attachment = try Self.attachment(from: row)
                found[attachment.id] = attachment
            }
        }
        return found
    }

    /// Where the file of `attachment` is, or will be once it is copied: `directory/<id>/<file name>`, with the name
    /// made safe for the file system (``sanitisedFileName(_:)``).
    public func fileURL(for attachment: Attachment) -> URL {
        folder(of: attachment.id).appendingPathComponent(
            Self.sanitisedFileName(attachment.fileName), isDirectory: false)
    }

    private func folder(of id: AttachmentID) -> URL {
        directory.appendingPathComponent(id.rawValue, isDirectory: true)
    }

    /// `name` as a file name: `/` and `:` become `-`, white space around it goes, and a name that is empty, or is `.`
    /// or `..` (which name a folder, not a file), becomes `file`. The row keeps the original name for display.
    public static func sanitisedFileName(_ name: String) -> String {
        let replaced = String(
            name.unicodeScalars.map { scalar -> Character in
                scalar == "/" || scalar == ":" || scalar == "\0" ? "-" : Character(scalar)
            })
        let trimmed = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "." || trimmed == ".." ? "file" : trimmed
    }

    // MARK: Removal

    /// Removes the rows and the files of those of `candidates` that no stored note body names, and returns how many it
    /// removed. A body counts when it holds the token anywhere, in a live note or in Recently Deleted
    /// (``NoteStore/referencedAttachmentIDs()``). An id that has no row is skipped.
    ///
    /// Looking at the notes and removing happen in one transaction, so a note cannot be saved with the token in
    /// between. The file goes before its row: a row with no file draws as a missing attachment and the sweep removes
    /// it later, but a file with no row would stay for ever. A file that cannot be removed keeps its row, the others
    /// are removed anyway, and the first error is thrown at the end.
    @discardableResult
    public func removeUnreferenced(_ candidates: [AttachmentID], notes: NoteStore) throws -> Int {
        if candidates.isEmpty { return 0 }
        return try removeWhatIsUnreferenced(from: { _ in candidates }, notes: notes)
    }

    /// The launch sweep: removes every attachment created before `cutoff` that no stored note body names, and returns
    /// how many it removed. The cutoff is 24 hours before the launch, so that a file whose token is in text that was
    /// never saved is not taken from a note that the owner can still get back (Plan 5, "Never lose an attachment").
    @discardableResult
    public func sweep(createdBefore cutoff: Date, notes: NoteStore) throws -> Int {
        try removeWhatIsUnreferenced(
            from: { database in
                try database.query("SELECT id FROM attachments WHERE created_at < ?", [.date(cutoff)])
                    .compactMap { $0.string("id").map { AttachmentID(rawValue: $0) } }
            }, notes: notes)
    }

    /// The common part of ``removeUnreferenced(_:notes:)`` and ``sweep(createdBefore:notes:)``: `findCandidates` runs
    /// inside the transaction.
    private func removeWhatIsUnreferenced(
        from findCandidates: (Database) throws -> [AttachmentID], notes: NoteStore
    ) throws -> Int {
        var removed = 0
        var firstError: (any Error)?
        try database.transaction {
            let candidates = try findCandidates(database)
            if candidates.isEmpty { return }
            let referenced = try notes.referencedAttachmentIDs()
            for id in Set(candidates).subtracting(referenced) {
                guard try attachment(id) != nil else { continue }
                do {
                    let folder = folder(of: id)
                    if FileManager.default.fileExists(atPath: folder.path) {
                        try FileManager.default.removeItem(at: folder)
                    }
                    try database.execute("DELETE FROM attachments WHERE id = ?", [.text(id.rawValue)])
                    removed += 1
                } catch {
                    firstError = firstError ?? error
                }
            }
        }
        if let firstError { throw firstError }
        return removed
    }

    // MARK: Rows

    private static let columns = """
        id, note_id, file_name, type_identifier, byte_size, pixel_width, pixel_height, created_at, copied
        """

    /// How many ids one `IN (...)` query takes.
    private static let idsPerQuery = 400

    private static func attachment(from row: Row) throws -> Attachment {
        guard let id = row.string("id"), let noteID = row.string("note_id"), let fileName = row.string("file_name"),
            let type = row.string("type_identifier"), let byteSize = row.int("byte_size"),
            let createdAt = row.date("created_at"), let copied = row.int("copied")
        else {
            throw DatabaseError(
                code: sqliteCorrupt, message: "a row of table attachments has a missing or mistyped column")
        }
        return Attachment(
            id: AttachmentID(rawValue: id), noteID: NoteID(rawValue: noteID), fileName: fileName,
            typeIdentifier: type, byteSize: byteSize, pixelWidth: row.int("pixel_width").map(Int.init),
            pixelHeight: row.int("pixel_height").map(Int.init), createdAt: createdAt, isCopied: copied != 0)
    }
}
