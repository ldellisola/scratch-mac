import Dispatch
import Foundation
import Synchronization
import Testing

@testable import ScratchCore

// Spec §8.1: the system SQLite library, no ORM, WAL journal mode, FTS5 for search.

private struct TestFailure: Error {}

/// An empty directory for a file database, removed when `body` returns.
private func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("scratch-db-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
}

private func memoryDatabase() throws -> Database {
    try Database(path: ":memory:")
}

private func rowCount(_ db: Database, in table: String) throws -> Int64? {
    try db.query("SELECT COUNT(*) AS n FROM \(table)").first?.int("n")
}

@Test func opensInMemoryDatabase() throws {
    let db = try memoryDatabase()
    let rows = try db.query("SELECT 1 AS one, 'x' AS letter")
    #expect(rows.count == 1)
    #expect(rows.first?.int("one") == 1)
    #expect(rows.first?.string("letter") == "x")
    #expect(rows.first?["missing"] == nil)
}

@Test func fileDatabaseUsesWAL() throws {
    try withTemporaryDirectory { directory in
        let db = try Database(path: directory.appendingPathComponent("scratch.sqlite").path)
        #expect(try db.query("PRAGMA journal_mode").first?.string("journal_mode") == "wal")
        #expect(try db.query("PRAGMA synchronous").first?.int("synchronous") == 1)  // NORMAL
        #expect(try db.query("PRAGMA busy_timeout").first?.int("timeout") == 2000)
    }
}

@Test func fileDatabaseKeepsDataAcrossReopen() throws {
    try withTemporaryDirectory { directory in
        let path = directory.appendingPathComponent("scratch.sqlite").path
        do {
            let db = try Database(path: path)
            try db.execute("CREATE TABLE t (v TEXT)")
            try db.execute("INSERT INTO t VALUES (?)", [.text("kept")])
        }
        let reopened = try Database(path: path)
        #expect(try reopened.query("SELECT v FROM t").first?.string("v") == "kept")
    }
}

@Test func roundTripsEveryValueType() throws {
    let db = try memoryDatabase()
    try db.execute("CREATE TABLE t (v)")
    let values: [SQLValue] = [.null, .integer(-42), .real(.pi), .text("héllo 😀"), .blob([0, 255])]
    for value in values { try db.execute("INSERT INTO t (v) VALUES (?)", [value]) }
    let rows = try db.query("SELECT v FROM t ORDER BY rowid")
    #expect(rows.map { $0["v"] } == values)
}

@Test func roundTripsEmptyBlobAndEmbeddedNul() throws {
    let db = try memoryDatabase()
    try db.execute("CREATE TABLE t (v)")
    let values: [SQLValue] = [.blob([]), .text(""), .text("a\0b"), .blob([0, 0])]
    for value in values { try db.execute("INSERT INTO t (v) VALUES (?)", [value]) }
    let rows = try db.query("SELECT v FROM t ORDER BY rowid")
    #expect(rows.map { $0["v"] } == values)
}

@Test func datesRoundTripExactly() throws {
    let db = try memoryDatabase()
    try db.execute("CREATE TABLE t (at REAL, maybe REAL)")
    let date = Date(timeIntervalSinceReferenceDate: 812_345_678.123456)
    try db.execute("INSERT INTO t VALUES (?, ?)", [.date(date), .optionalDate(nil)])
    let row = try #require(try db.query("SELECT at, maybe FROM t").first)
    #expect(row.date("at") == date)
    #expect(row.date("maybe") == nil)
    #expect(SQLValue.optionalDate(date) == .real(date.timeIntervalSinceReferenceDate))
}

@Test func rowAccessorsReturnNilForTheWrongType() throws {
    let db = try memoryDatabase()
    let row = try #require(try db.query("SELECT 'text' AS s, 7 AS i, 1.5 AS d, NULL AS n").first)
    #expect(row.string("i") == nil && row.string("n") == nil)
    #expect(row.int("s") == nil && row.int("d") == nil)
    #expect(row.double("d") == 1.5 && row.double("i") == 7 && row.double("s") == nil)
    #expect(row["n"] == .null)
}

@Test func transactionRollsBackOnThrow() throws {
    let db = try memoryDatabase()
    try db.execute("CREATE TABLE t (v INTEGER)")
    #expect(throws: TestFailure.self) {
        try db.transaction {
            try db.execute("INSERT INTO t VALUES (1)")
            throw TestFailure()
        }
    }
    #expect(try rowCount(db, in: "t") == 0)
}

@Test func transactionCommitsAndReturnsTheBodyResult() throws {
    let db = try memoryDatabase()
    try db.execute("CREATE TABLE t (v INTEGER)")
    let result = try db.transaction { () throws -> String in
        try db.execute("INSERT INTO t VALUES (1)")
        try db.execute("INSERT INTO t VALUES (2)")
        return "done"
    }
    #expect(result == "done")
    #expect(try rowCount(db, in: "t") == 2)
}

@Test func nestedTransactionRollsBackOnlyTheInnerWork() throws {
    let db = try memoryDatabase()
    try db.execute("CREATE TABLE t (v INTEGER)")
    try db.transaction {
        try db.execute("INSERT INTO t VALUES (1)")
        _ = try? db.transaction {
            try db.execute("INSERT INTO t VALUES (2)")
            throw TestFailure()
        }
        try db.transaction { try db.execute("INSERT INTO t VALUES (3)") }
    }
    #expect(try db.query("SELECT v FROM t ORDER BY v").compactMap { $0.int("v") } == [1, 3])
}

@Test func transactionsFromDifferentThreadsDoNotInterleave() throws {
    let db = try memoryDatabase()
    try db.execute("CREATE TABLE t (worker INTEGER)")
    let failures = Mutex<[any Error]>([])
    DispatchQueue.concurrentPerform(iterations: 4) { worker in
        do {
            try db.transaction {
                for _ in 0..<50 { try db.execute("INSERT INTO t VALUES (?)", [.integer(Int64(worker))]) }
            }
        } catch {
            failures.withLock { $0.append(error) }
        }
    }
    #expect(failures.withLock { $0.isEmpty })
    let workers = try db.query("SELECT worker FROM t ORDER BY rowid").compactMap { $0.int("worker") }
    #expect(workers.count == 200)
    // Each worker's 50 rows are contiguous, so exactly three changes of worker appear in the whole sequence.
    #expect(zip(workers, workers.dropFirst()).filter { $0 != $1 }.count == 3)
}

@Test func errorsCarrySQLiteMessage() throws {
    let db = try memoryDatabase()
    let error = #expect(throws: DatabaseError.self) { try db.execute("SELEC 1") }
    #expect(error?.message.contains("syntax error") == true)
    #expect(error?.code == 1)  // SQLITE_ERROR
}

@Test func rejectsMultipleStatementsInOneCall() throws {
    let db = try memoryDatabase()
    #expect(throws: DatabaseError.self) { try db.execute("CREATE TABLE a (x); CREATE TABLE b (x)") }
    #expect(try db.query("SELECT name FROM sqlite_master").isEmpty)
    try db.execute("CREATE TABLE a (x);")  // one statement with a trailing semicolon is fine
}

@Test func rejectsTheWrongNumberOfArguments() throws {
    let db = try memoryDatabase()
    try db.execute("CREATE TABLE t (a, b)")
    #expect(throws: DatabaseError.self) { try db.execute("INSERT INTO t VALUES (?, ?)", [.integer(1)]) }
    #expect(throws: DatabaseError.self) { try db.execute("INSERT INTO t VALUES (?, ?)", [.null, .null, .null]) }
    #expect(try rowCount(db, in: "t") == 0)
}

@Test func failedStatementLeavesTheConnectionUsable() throws {
    let db = try memoryDatabase()
    try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY)")
    try db.execute("INSERT INTO t VALUES (1)")
    #expect(throws: DatabaseError.self) { try db.execute("INSERT INTO t VALUES (1)") }  // constraint violation
    #expect(try rowCount(db, in: "t") == 1)
}

@Test func fts5IsAvailable() throws {
    let db = try memoryDatabase()
    try db.execute("CREATE VIRTUAL TABLE t USING fts5(x)")  // Plan 2 builds search on this
}
