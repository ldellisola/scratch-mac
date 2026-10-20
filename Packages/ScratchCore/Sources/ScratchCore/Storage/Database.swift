import Foundation
import Synchronization

/// SQLite reported an error. `code` is the result code and `message` is SQLite's own text.
public struct DatabaseError: Error, Equatable {
    public let code: Int32
    public let message: String
}

/// A SQLite database that any thread can use.
///
/// Every call is serialised by a `Mutex`, and a ``transaction(_:)`` holds that mutex from `BEGIN` to `COMMIT`, so no
/// other thread's statement can run inside it. The transaction body calls back into the same `Database`. The thread
/// that runs a transaction is the only one allowed to skip the mutex, because it already holds it.
public final class Database: @unchecked Sendable {
    private let connection: Connection
    /// Guards `connection` and `savepointDepth`. `Mutex` cannot be re-entered, hence `owner`.
    private let lock = Mutex<Void>(())
    /// Identifies the thread that is inside a `transaction` body, or 0 when there is none. Only that thread ever
    /// writes its own identifier, so a thread that reads its own identifier knows that it holds `lock`.
    private let owner = Atomic<UInt>(0)
    /// How many `transaction` calls are nested in the running one. Only the owner thread touches it.
    private var savepointDepth = 0

    /// Opens or creates the database at `path`. `":memory:"` gives a private in-memory database.
    ///
    /// A file database is switched to WAL with `synchronous=NORMAL` and a two-second busy timeout.
    public init(path: String) throws {
        connection = try Connection(path: path)
        if path != ":memory:" && !path.isEmpty {
            try connection.configureFileDatabase()
        }
    }

    /// Runs one SQL statement and discards any rows. `args` bind to the `?` placeholders in order.
    public func execute(_ sql: String, _ args: [SQLValue] = []) throws {
        try withConnection { try $0.execute(sql, args) }
    }

    /// Runs one SQL statement and returns its rows. `args` bind to the `?` placeholders in order.
    public func query(_ sql: String, _ args: [SQLValue] = []) throws -> [Row] {
        try withConnection { try $0.query(sql, args) }
    }

    /// Runs `body` in one transaction. It commits when `body` returns and rolls back when it throws.
    ///
    /// `body` runs the transaction's statements through `execute` and `query` on this same `Database`. Other threads
    /// wait until it ends. A `transaction` nested inside `body` becomes a savepoint, so its failure undoes only its
    /// own work.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        let thread = Self.currentThread
        if owner.load(ordering: .relaxed) == thread { return try nestedTransaction(body) }

        var result: T?
        try lock.withLock { _ in
            owner.store(thread, ordering: .relaxed)
            defer { owner.store(0, ordering: .relaxed) }
            try connection.execute("BEGIN IMMEDIATE", [])
            do {
                result = try body()
                try connection.execute("COMMIT", [])
            } catch {
                try? connection.execute("ROLLBACK", [])
                throw error
            }
        }
        return result!
    }

    /// The schema version stored in the database file (`PRAGMA user_version`), which is 0 for a new database.
    public func userVersion() throws -> Int {
        Int(try query("PRAGMA user_version").first?.int("user_version") ?? 0)
    }

    // MARK: Locking

    private func withConnection<T>(_ body: (Connection) throws -> T) throws -> T {
        if owner.load(ordering: .relaxed) == Self.currentThread { return try body(connection) }
        var result: T?
        try lock.withLock { _ in result = try body(connection) }
        return result!
    }

    private func nestedTransaction<T>(_ body: () throws -> T) throws -> T {
        savepointDepth += 1
        defer { savepointDepth -= 1 }
        let name = "scratch_savepoint_\(savepointDepth)"
        try connection.execute("SAVEPOINT \(name)", [])
        do {
            let result = try body()
            try connection.execute("RELEASE \(name)", [])
            return result
        } catch {
            try? connection.execute("ROLLBACK TO \(name)", [])
            try? connection.execute("RELEASE \(name)", [])
            throw error
        }
    }

    /// A non-zero number that is unique among the live threads.
    private static var currentThread: UInt {
        UInt(bitPattern: ObjectIdentifier(Thread.current))
    }
}
