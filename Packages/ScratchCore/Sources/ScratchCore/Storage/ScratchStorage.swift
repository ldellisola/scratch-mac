import Foundation

/// A fixture was asked for on the real data directory, which it would wipe.
public enum StorageError: Error, Equatable {
    case fixtureRequiresIsolatedDirectory
}

/// The opened database of one Scratch data directory, with the stores that read and write it.
///
/// Every launch goes through ``open(_:now:)``, which is also where tests, screenshots and benchmarks are kept away from
/// real data: a fixture only ever runs in a directory that is not `~/Library/Application Support/Scratch`.
///
/// Removing notes for good goes through ``deletePermanently(_:)`` and ``purge(deletedBefore:)``, which also remove the
/// files that no note names any more.
public struct ScratchStorage: Sendable {
    public let directory: URL
    /// The open database that `notes` and `session` use. Public so that tests can change how it behaves: `PRAGMA
    /// query_only = 1` makes every write fail with `SQLITE_READONLY`, which simulates a failing disk (a read-only file
    /// would not do, because SQLite keeps it open). The app never reads or writes it directly.
    public let database: Database
    public let notes: NoteStore
    public let session: SessionStore
    /// The attachments: their rows in `database` and their files in ``attachmentsDirectoryName`` of the data directory.
    public let attachments: AttachmentStore

    /// The database file inside the data directory. SQLite adds `-wal`, `-shm` and `-journal` files beside it.
    public static let databaseFileName = "scratch.sqlite"

    /// The folder of the data directory that holds Scratch's copies of attached files, one folder for each attachment.
    public static let attachmentsDirectoryName = "attachments"

    /// Creates the data directory when it is missing, opens the database in it and migrates the schema.
    ///
    /// With a fixture it first throws ``StorageError/fixtureRequiresIsolatedDirectory`` when the directory is not
    /// isolated, before anything is touched. Then it deletes the existing database files, so nothing from an earlier
    /// run is left, and seeds the fixture with dates relative to `now`.
    ///
    /// Close the previous storage for a directory (let it go out of scope) before opening a fixture over it.
    public static func open(_ options: LaunchOptions, now: Date = Date()) throws -> ScratchStorage {
        if options.fixture != nil && !options.isIsolated {
            throw StorageError.fixtureRequiresIsolatedDirectory
        }
        let directory = options.dataDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if options.fixture != nil {
            try removeDatabaseFiles(in: directory)
            try removeAttachmentFiles(in: directory)
        }

        let database = try Database(path: directory.appendingPathComponent(databaseFileName).path)
        let storage = ScratchStorage(
            directory: directory, database: database, notes: try NoteStore(database: database),
            session: try SessionStore(database: database),
            attachments: AttachmentStore(
                database: database,
                directory: directory.appendingPathComponent(attachmentsDirectoryName, isDirectory: true)))
        if let fixture = options.fixture {
            try fixture.seed(
                notes: storage.notes, session: storage.session, attachments: storage.attachments, now: now)
        }
        return storage
    }

    // MARK: Removing notes for good

    /// Removes a note from Recently Deleted for good (``NoteStore/deletePermanently(_:)``), and then the files of the
    /// attachments it held that no other note names (``AttachmentStore/removeUnreferenced(_:notes:)``). A note that is
    /// not deleted is left alone, and so are its files. The app calls this and never `NoteStore.deletePermanently`.
    ///
    /// The files are cleaned up after the note is gone, and a failure of that is not this call's failure: the note is
    /// deleted, and what is left (a row that no note names) is found by the launch sweep once it is a day old.
    public func deletePermanently(_ id: NoteID) throws {
        let held = try database.transaction {
            let held = try notes.attachmentIDsOfDeletedNote(id)
            try notes.deletePermanently(id)
            return held
        }
        removeUnreferenced(held)
    }

    /// Removes the notes that were deleted before `cutoff` (``NoteStore/purge(deletedBefore:)``, spec §6.2), and then
    /// the files of the attachments they held that no remaining note names. Returns how many notes went. The app calls
    /// this and never `NoteStore.purge`. A failed clean-up of the files is not this call's failure, as for
    /// ``deletePermanently(_:)``.
    public func purge(deletedBefore cutoff: Date) throws -> Int {
        let (removed, held) = try database.transaction {
            let held = try notes.attachmentIDsOfNotesDeleted(before: cutoff)
            return (try notes.purge(deletedBefore: cutoff), held)
        }
        removeUnreferenced(held)
        return removed
    }

    /// Removes the attachments among `ids` that no note names. The note removal that came first is done and stays so,
    /// so a failure here only leaves the files for the launch sweep.
    private func removeUnreferenced(_ ids: Set<AttachmentID>) {
        guard !ids.isEmpty else { return }
        _ = try? attachments.removeUnreferenced(Array(ids), notes: notes)
    }

    /// Deletes the copies of attached files. A fixture replaces the database, and with it the rows that name them, so
    /// the files would be unreachable. Only ever called for a fixture, which only ever runs in an isolated directory.
    private static func removeAttachmentFiles(in directory: URL) throws {
        let folder = directory.appendingPathComponent(attachmentsDirectoryName, isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    /// Deletes `scratch.sqlite` and the files SQLite keeps beside it. Anything else in the directory stays.
    private static func removeDatabaseFiles(in directory: URL) throws {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let file = directory.appendingPathComponent(databaseFileName + suffix)
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        }
    }
}
