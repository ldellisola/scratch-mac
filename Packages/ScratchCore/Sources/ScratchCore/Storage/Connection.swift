import CSQLite
import Foundation

/// `SQLITE_TRANSIENT` is a C macro for the function pointer `-1`, which Swift cannot import. It tells SQLite to copy
/// the bound bytes, so the Swift value need not outlive the call.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// One open SQLite connection, and every call into the C API.
///
/// A `Connection` does no locking. ``Database`` serialises access to it, which is why the connection is opened with
/// `SQLITE_OPEN_NOMUTEX`.
final class Connection: @unchecked Sendable {
    private let handle: OpaquePointer

    init(path: String) throws {
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(path, &opened, flags, nil)
        guard result == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
            sqlite3_close_v2(opened)
            throw DatabaseError(code: result, message: message)
        }
        handle = opened
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// Runs one statement and discards any rows it returns.
    func execute(_ sql: String, _ args: [SQLValue]) throws {
        try withStatement(sql, args) { statement in
            while try step(statement) {}
        }
    }

    /// Runs one statement and returns all its rows.
    func query(_ sql: String, _ args: [SQLValue]) throws -> [Row] {
        try withStatement(sql, args) { statement in
            let columnCount = sqlite3_column_count(statement)
            var columns: [String: Int] = [:]
            for index in 0..<columnCount {
                let name = String(cString: sqlite3_column_name(statement, index))
                if columns[name] == nil { columns[name] = Int(index) }
            }
            var rows: [Row] = []
            while try step(statement) {
                rows.append(Row(columns: columns, values: (0..<columnCount).map { value(at: $0, in: statement) }))
            }
            return rows
        }
    }

    /// Puts a file database in WAL mode. Memory databases have no journal file and skip this.
    func configureFileDatabase() throws {
        // Set the timeout first, so that switching to WAL waits for another process's lock instead of failing.
        try execute("PRAGMA busy_timeout=2000", [])
        let mode = try query("PRAGMA journal_mode=WAL", []).first?.string("journal_mode")
        guard mode == "wal" else {
            let message = "could not enable WAL, journal mode is \(mode ?? "unknown")"
            throw DatabaseError(code: SQLITE_ERROR, message: message)
        }
        try execute("PRAGMA synchronous=NORMAL", [])
    }

    // MARK: Statements

    private func withStatement<T>(_ sql: String, _ args: [SQLValue], _ body: (OpaquePointer) throws -> T) throws -> T {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        let parameterCount = Int(sqlite3_bind_parameter_count(statement))
        guard parameterCount == args.count else {
            let message = "SQL has \(parameterCount) parameters but \(args.count) arguments were given"
            throw DatabaseError(code: SQLITE_RANGE, message: message)
        }
        for (offset, arg) in args.enumerated() {
            let result = bind(arg, at: Int32(offset + 1), in: statement)
            guard result == SQLITE_OK else { throw error(result) }
        }
        return try body(statement)
    }

    /// Compiles `sql`, which must hold exactly one statement. A second statement would otherwise be dropped silently.
    private func prepare(_ sql: String) throws -> OpaquePointer {
        try sql.withCString { text in
            var statement: OpaquePointer?
            var tail: UnsafePointer<CChar>?
            let result = sqlite3_prepare_v2(handle, text, -1, &statement, &tail)
            guard result == SQLITE_OK else {
                let failure = error(result)
                sqlite3_finalize(statement)
                throw failure
            }
            guard let statement else {
                throw DatabaseError(code: SQLITE_MISUSE, message: "no SQL statement to run")
            }
            if let tail, hasAnotherStatement(at: tail) {
                sqlite3_finalize(statement)
                throw DatabaseError(code: SQLITE_MISUSE, message: "more than one SQL statement in a single call")
            }
            return statement
        }
    }

    private func hasAnotherStatement(at tail: UnsafePointer<CChar>) -> Bool {
        var next: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, tail, -1, &next, nil)
        sqlite3_finalize(next)
        return result != SQLITE_OK || next != nil
    }

    /// True when the statement produced a row, false when it is done.
    private func step(_ statement: OpaquePointer) throws -> Bool {
        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw error(result)
        }
    }

    private func error(_ code: Int32) -> DatabaseError {
        DatabaseError(code: code, message: String(cString: sqlite3_errmsg(handle)))
    }

    // MARK: Values

    private func bind(_ value: SQLValue, at index: Int32, in statement: OpaquePointer) -> Int32 {
        switch value {
        case .null:
            return sqlite3_bind_null(statement, index)
        case .integer(let integer):
            return sqlite3_bind_int64(statement, index, integer)
        case .real(let real):
            return sqlite3_bind_double(statement, index, real)
        case .text(let text):
            // Pass the byte count, so that a NUL inside the text does not cut it short.
            return text.withCString {
                sqlite3_bind_text64(statement, index, $0, UInt64(text.utf8.count), sqliteTransient, UInt8(SQLITE_UTF8))
            }
        case .blob(let bytes):
            return bytes.withUnsafeBytes { buffer in
                // A nil pointer would bind NULL, so an empty blob needs its own call.
                guard let base = buffer.baseAddress else { return sqlite3_bind_zeroblob(statement, index, 0) }
                return sqlite3_bind_blob64(statement, index, base, UInt64(buffer.count), sqliteTransient)
            }
        }
    }

    private func value(at column: Int32, in statement: OpaquePointer) -> SQLValue {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, column))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, column))
        case SQLITE_TEXT:
            // Ask for the text before its length, as SQLite documents.
            guard let text = sqlite3_column_text(statement, column) else { return .text("") }
            let count = Int(sqlite3_column_bytes(statement, column))
            return .text(String(decoding: UnsafeBufferPointer(start: text, count: count), as: UTF8.self))
        case SQLITE_BLOB:
            guard let blob = sqlite3_column_blob(statement, column) else { return .blob([]) }
            let count = Int(sqlite3_column_bytes(statement, column))
            return .blob(Array(UnsafeRawBufferPointer(start: blob, count: count)))
        default:
            return .null
        }
    }
}
