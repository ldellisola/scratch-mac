import Foundation

/// A fixture was asked for on the real data directory, which it would wipe.
public enum StorageError: Error, Equatable {
    case fixtureRequiresIsolatedDirectory
}

/// The opened database of one Scratch data directory, with the stores that read and write it.
///
/// Every launch goes through ``open(_:now:)``, which is also where tests, screenshots and benchmarks are kept away from
/// real data: a fixture only ever runs in a directory that is not `~/Library/Application Support/Scratch`.
public struct ScratchStorage: Sendable {
    public let directory: URL
    public let notes: NoteStore
    public let session: SessionStore

    /// The database file inside the data directory. SQLite adds `-wal`, `-shm` and `-journal` files beside it.
    public static let databaseFileName = "scratch.sqlite"

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
        }

        let database = try Database(path: directory.appendingPathComponent(databaseFileName).path)
        let storage = ScratchStorage(
            directory: directory, notes: try NoteStore(database: database),
            session: try SessionStore(database: database))
        if let fixture = options.fixture {
            try fixture.seed(notes: storage.notes, session: storage.session, now: now)
        }
        return storage
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
