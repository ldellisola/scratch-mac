import Foundation
import Testing

@testable import ScratchCore

// docs/features/launch-times.md ("The log" and "The report"): the launch log keeps the newest 50 launches in
// `launch-times.json`, says which one was the first after the Mac started, never fails a launch, and writes the report
// that the owner reads and copies from Help > Launch Times….

private let utc = TimeZone(identifier: "UTC")!

/// 2026-10-23 09:00:00 UTC plus `minutes`.
private func moment(minutes: Double) -> Date {
    Date(timeIntervalSince1970: 1_792_746_000 + minutes * 60)
}

private func record(
    minutes: Double = 0, boot: Double = 0, total: Double = 100, version: String = "1.0.0"
) -> LaunchRecord {
    LaunchRecord(
        date: moment(minutes: minutes), version: version, bootTime: moment(minutes: boot - 600),
        phases: ["main": 10, "storage": 30, "restore": 50, "window": 70, "firstFrame": total],
        isFirstAfterStartUp: false)
}

private func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ScratchLaunchLogTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func file(in directory: URL) -> URL {
    directory.appendingPathComponent(LaunchLog.fileName)
}

// MARK: First after start-up

@Test func appendMarksFirstAfterStartUp() {
    var log = LaunchLog()
    log.append(record(minutes: 0, boot: 0))
    log.append(record(minutes: 5, boot: 0))
    #expect(log.records.map(\.isFirstAfterStartUp) == [true, false])

    // A later boot: the first launch of it is the first after start-up, the next is not.
    log.append(record(minutes: 600, boot: 590))
    log.append(record(minutes: 610, boot: 590))
    #expect(log.records.map(\.isFirstAfterStartUp) == [true, false, true, false])
}

@Test func appendIgnoresWhatTheCallerSaidAboutFirstAfterStartUp() {
    var log = LaunchLog()
    var wrong = record(boot: 0)
    wrong.isFirstAfterStartUp = false
    log.append(wrong)
    var alsoWrong = record(minutes: 1, boot: 0)
    alsoWrong.isFirstAfterStartUp = true
    log.append(alsoWrong)
    #expect(log.records.map(\.isFirstAfterStartUp) == [true, false])
}

@Test func aBootTimeThatMovedAFewSecondsIsTheSameBoot() {
    // The kernel adjusts kern.boottime when the clock is set (a network time sync): a launch must not turn into a
    // "first after start-up" because of it.
    var log = LaunchLog()
    log.append(record(minutes: 0, boot: 0))
    var later = record(minutes: 3, boot: 0)
    later.bootTime = later.bootTime.addingTimeInterval(4)
    log.append(later)
    #expect(log.records.map(\.isFirstAfterStartUp) == [true, false])
}

@Test func recordsAreKeptOldestFirst() {
    var log = LaunchLog()
    log.append(record(minutes: 0, total: 300))
    log.append(record(minutes: 1, total: 200))
    #expect(log.records.map(\.totalMilliseconds) == [300, 200])
}

// MARK: The limit

@Test func logKeepsNewestFifty() {
    var log = LaunchLog()
    for index in 0..<60 { log.append(record(minutes: Double(index), total: Double(index))) }
    #expect(LaunchLog.limit == 50)
    #expect(log.records.count == 50)
    #expect(log.records.first?.totalMilliseconds == 10)
    #expect(log.records.last?.totalMilliseconds == 59)
}

@Test func theFlagOfTheKeptRecordsSurvivesTheLimit() {
    var log = LaunchLog()
    log.append(record(minutes: 0, boot: 0))
    for index in 1..<60 { log.append(record(minutes: Double(index), boot: 0)) }
    // The first launch of the boot has been dropped, and the next ones are not first after start-up either.
    #expect(log.records.count == 50)
    #expect(log.records.allSatisfy { !$0.isFirstAfterStartUp })
}

// MARK: The file

@Test func saveAndLoadRoundTrip() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    var log = LaunchLog()
    log.append(record(minutes: 0, boot: 0, total: 412.3))
    log.append(record(minutes: 6, boot: 0, total: 118.9))
    log.append(record(minutes: 700, boot: 690, total: 90))

    try log.save(to: directory)
    let loaded = LaunchLog.load(from: directory)

    #expect(loaded == log)
    #expect(loaded.records.map(\.isFirstAfterStartUp) == [true, false, true])
}

@Test func loadOfAMissingFileIsEmpty() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(LaunchLog.load(from: directory).records.isEmpty)
    #expect(LaunchLog.load(from: directory.appendingPathComponent("no-such-directory")).records.isEmpty)
}

@Test func launchLogIgnoresACorruptFile() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    for garbage in [
        Data([0xFF, 0xFE, 0x00, 0x13, 0x37]), Data("not json at all".utf8), Data("{\"records\": [1, 2".utf8),
        Data("[]".utf8), Data("{}".utf8), Data("{\"records\": 7}".utf8), Data(),
    ] {
        try garbage.write(to: file(in: directory))
        #expect(LaunchLog.load(from: directory).records.isEmpty)
    }
}

@Test func launchLogIgnoresAHugeFile() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    // A valid log would be about 15 KB. Anything over a megabyte is not one, and is not read.
    var log = LaunchLog()
    log.append(record())
    try log.save(to: directory)
    var bytes = try Data(contentsOf: file(in: directory))
    bytes.append(Data(repeating: 0x20, count: 2_000_000))
    try bytes.write(to: file(in: directory))
    #expect(LaunchLog.load(from: directory).records.isEmpty)
}

@Test func launchLogIgnoresADirectoryWhereTheFileShouldBe() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: file(in: directory), withIntermediateDirectories: false)
    #expect(LaunchLog.load(from: directory).records.isEmpty)

    // Saving there fails, and says so, and leaves the directory as it was.
    var log = LaunchLog()
    log.append(record())
    #expect(throws: (any Error).self) { try log.save(to: directory) }
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: file(in: directory).path, isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
}

@Test func loadKeepsTheGoodRecordsOfAFileWithABadOne() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    var log = LaunchLog()
    log.append(record(minutes: 0, total: 111))
    log.append(record(minutes: 1, total: 222))
    try log.save(to: directory)

    var object = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: file(in: directory))) as? [String: Any])
    var records = try #require(object["records"] as? [Any])
    records.insert(["version": "1.0.0"], at: 1)
    records.append("a string")
    object["records"] = records
    try JSONSerialization.data(withJSONObject: object).write(to: file(in: directory))

    #expect(LaunchLog.load(from: directory).records.map(\.totalMilliseconds) == [111, 222])
}

@Test func loadKeepsOnlyTheNewestFifty() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let many = (0..<80).map { record(minutes: Double($0), total: Double($0)) }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    // The same shape `save` writes, with more records than it ever keeps.
    struct Shape: Encodable { var records: [LaunchRecord] }
    try encoder.encode(Shape(records: many)).write(to: file(in: directory))

    let loaded = LaunchLog.load(from: directory)
    #expect(loaded.records.count == 50)
    #expect(loaded.records.first?.totalMilliseconds == 30)
}

@Test func saveCreatesTheDirectoryWhenItIsMissing() throws {
    let parent = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: parent) }
    let directory = parent.appendingPathComponent("Scratch", isDirectory: true)
    var log = LaunchLog()
    log.append(record())
    try log.save(to: directory)
    #expect(LaunchLog.load(from: directory) == log)
}

@Test func saveReplacesTheFileWhole() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    var log = LaunchLog()
    for index in 0..<5 { log.append(record(minutes: Double(index))) }
    try log.save(to: directory)
    var shorter = LaunchLog()
    shorter.append(record(minutes: 9, total: 77))
    try shorter.save(to: directory)

    #expect(LaunchLog.load(from: directory) == shorter)
    // No temporary file is left beside it.
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [LaunchLog.fileName])
}

// MARK: The report

@Test func reportFormat() {
    var log = LaunchLog()
    log.append(record(minutes: 14, boot: 14, total: 412.4))
    log.append(record(minutes: 20, boot: 14, total: 117.6))

    #expect(
        log.report(version: "1.0.0", timeZone: utc)
            == """
            Scratch 1.0.0, launch times on this Mac, newest first:
            2026-10-23 09:20   118 ms
            2026-10-23 09:14   412 ms   first after start-up
            Other launches, median of the last 1: 118 ms (budget 200 ms). First after start-up, median of 1: 412 ms (budget 500 ms).
            """)
}

@Test func reportWithNoRecords() {
    #expect(LaunchLog().report(version: "1.0.0", timeZone: utc) == "No launches recorded yet.")
}

@Test func reportSaysNoneYetForAnEmptySummary() {
    var onlyFirst = LaunchLog()
    onlyFirst.append(record(minutes: 0, boot: 0, total: 412))
    #expect(
        onlyFirst.report(version: "1.0.0", timeZone: utc).split(separator: "\n").last
            == "Other launches, median of the last 0: none yet (budget 200 ms). First after start-up, median of 1: 412 ms (budget 500 ms)."
    )

    // A log whose records all belong to a boot that an older, dropped record started has no first launch in it.
    var onlyOthers = LaunchLog()
    for index in 0..<60 { onlyOthers.append(record(minutes: Double(index), boot: 0, total: 150)) }
    #expect(
        onlyOthers.report(version: "1.0.0", timeZone: utc).split(separator: "\n").last
            == "Other launches, median of the last 10: 150 ms (budget 200 ms). First after start-up, median of 0: none yet (budget 500 ms)."
    )
}

@Test func reportSummariesUseTheNewestTenOfEachKind() {
    var log = LaunchLog()
    // Twelve boots, one first launch each, then 12 other launches on the last boot.
    for boot in 0..<12 {
        log.append(record(minutes: Double(boot * 100), boot: Double(boot * 100), total: Double(1_000 + boot)))
    }
    for index in 0..<12 {
        log.append(record(minutes: 1_200 + Double(index), boot: 1_100, total: Double(100 + index)))
    }
    let summary = log.report(version: "1.0.0", timeZone: utc).split(separator: "\n").last.map(String.init)
    // First after start-up: the newest ten are 1002...1011, median 1006.5. Others: 102...111, median 106.5.
    #expect(
        summary
            == "Other launches, median of the last 10: 107 ms (budget 200 ms). First after start-up, median of 10: 1007 ms (budget 500 ms)."
    )
}

@Test func reportListsEveryRecordNewestFirstInTheGivenTimeZone() {
    var log = LaunchLog()
    for index in 0..<3 { log.append(record(minutes: Double(index) * 90, boot: 0, total: Double(100 * (index + 1)))) }
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    let lines = log.report(version: "1.0.0", timeZone: tokyo).split(separator: "\n").map(String.init)
    #expect(lines.count == 1 + 3 + 1)
    #expect(lines[1] == "2026-10-23 21:00   300 ms")
    #expect(lines[2] == "2026-10-23 19:30   200 ms")
    #expect(lines[3] == "2026-10-23 18:00   100 ms   first after start-up")
}

@Test func reportAlignsMillisecondsAndNamesTheVersion() {
    var log = LaunchLog()
    log.append(record(minutes: 0, boot: 0, total: 5))
    log.append(record(minutes: 1, boot: 0, total: 1_234))
    let lines = log.report(version: "1.2.3", timeZone: utc).split(separator: "\n").map(String.init)
    #expect(lines[0] == "Scratch 1.2.3, launch times on this Mac, newest first:")
    #expect(lines[1] == "2026-10-23 09:01  1234 ms")
    #expect(lines[2] == "2026-10-23 09:00     5 ms   first after start-up")
}
