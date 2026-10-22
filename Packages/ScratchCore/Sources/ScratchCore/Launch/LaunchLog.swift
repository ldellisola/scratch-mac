import Foundation

/// The record of Scratch's own launches, `launch-times.json` in the data directory, newest 50 (docs/features/launch-times.md).
///
/// The app appends a record after each launch's first frame, on a background queue, and Help > Launch Times… shows
/// ``report(version:timeZone:)``, which the owner can copy: that is how the cold-boot budget of the spec (§7), which no
/// CI runner can measure, is checked on a real Mac.
///
/// A log never gets in the way of a launch: a file that is missing, damaged, too big or not a file is an empty log
/// (``load(from:)``), and a failed write is an error that the caller may ignore (``save(to:)``).
public struct LaunchLog: Equatable, Sendable {
    /// The name of the file in the data directory.
    public static let fileName = "launch-times.json"
    /// The number of records the log keeps: the newest.
    public static let limit = 50
    /// The spec's budget (§7) of a launch with the files in the disk cache, in milliseconds.
    public static let otherLaunchBudget = 200
    /// The spec's budget (§7) of the first launch after the Mac started, in milliseconds.
    public static let firstLaunchBudget = 500

    /// The records, oldest first.
    public private(set) var records: [LaunchRecord]

    /// How many records of each kind the report's medians are over.
    private static let medianCount = 10
    /// A file larger than this is not a launch log (50 records are about 15 KB), and is not read.
    private static let largestFile = 1_000_000
    /// Two boot times closer than this are the same boot: the kernel moves `kern.boottime` by the amount that the clock
    /// is set by (a time sync), and no Mac starts again within half a minute.
    private static let sameBootTolerance: TimeInterval = 30

    public init(records: [LaunchRecord] = []) {
        self.records = Array(records.suffix(Self.limit))
    }

    // MARK: Appending

    /// Adds a launch as the newest record, marks it ``LaunchRecord/isFirstAfterStartUp`` when no record of the log has
    /// the same boot time (whatever the record said), and drops the oldest records over the ``limit``.
    public mutating func append(_ record: LaunchRecord) {
        var record = record
        record.isFirstAfterStartUp = !records.contains {
            abs($0.bootTime.timeIntervalSince(record.bootTime)) < Self.sameBootTolerance
        }
        records.append(record)
        if records.count > Self.limit { records.removeFirst(records.count - Self.limit) }
    }

    // MARK: The file

    /// The log in `directory`. A file that is missing, cannot be read, is larger than a log can be or is not JSON of the
    /// shape ``save(to:)`` writes is an empty log, and a record of it that cannot be read is left out. Never throws:
    /// whatever is wrong with the file, a launch goes on.
    public static func load(from directory: URL) -> LaunchLog {
        let url = directory.appendingPathComponent(fileName)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            (attributes[.type] as? FileAttributeType) == .typeRegular,
            let size = attributes[.size] as? NSNumber, size.intValue <= largestFile,
            let data = try? Data(contentsOf: url),
            let stored = try? decoder().decode(Stored.self, from: data)
        else { return LaunchLog() }
        return LaunchLog(records: stored.records.compactMap(\.record))
    }

    /// Writes the log to `directory`, creating it when it is missing, as one atomic replacement of the file: a launch that
    /// is killed halfway leaves the old file, never half of a new one. Throws when the file cannot be written.
    public func save(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Stored(records: records.map(Stored.Entry.init)))
        try data.write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }

    /// `{"records": [...]}`, so that the file can grow other keys. A record that cannot be decoded is `nil` and is skipped.
    private struct Stored: Codable {
        var records: [Entry]

        struct Entry: Codable {
            var record: LaunchRecord?

            init(_ record: LaunchRecord) {
                self.record = record
            }

            init(from decoder: any Decoder) throws {
                record = try? LaunchRecord(from: decoder)
            }

            func encode(to encoder: any Encoder) throws {
                try record?.encode(to: encoder)
            }
        }
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    // MARK: The report

    /// The text of Help > Launch Times…, newest launch first, in `timeZone`: a line for each record, then the medians of
    /// the newest ten launches that are not the first after start-up and of the newest ten that are, each with its
    /// budget. A log with no record says so.
    public func report(version: String, timeZone: TimeZone) -> String {
        guard !records.isEmpty else { return "No launches recorded yet." }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        var lines = ["Scratch \(version), launch times on this Mac, newest first:"]
        for record in records.reversed() {
            let milliseconds = String(Int(record.totalMilliseconds.rounded()))
            let padding = String(repeating: " ", count: max(0, 5 - milliseconds.count))
            var line = "\(formatter.string(from: record.date)) \(padding)\(milliseconds) ms"
            if record.isFirstAfterStartUp { line += "   first after start-up" }
            lines.append(line)
        }

        let others = records.filter { !$0.isFirstAfterStartUp }.suffix(Self.medianCount)
        let firsts = records.filter { $0.isFirstAfterStartUp }.suffix(Self.medianCount)
        lines.append(
            "Other launches, median of the last \(others.count): \(Self.median(of: others)) "
                + "(budget \(Self.otherLaunchBudget) ms). "
                + "First after start-up, median of \(firsts.count): \(Self.median(of: firsts)) "
                + "(budget \(Self.firstLaunchBudget) ms).")
        return lines.joined(separator: "\n")
    }

    /// The median of the records' totals, to the millisecond, as "118 ms", or "none yet" for no record.
    private static func median(of records: ArraySlice<LaunchRecord>) -> String {
        let totals = records.map(\.totalMilliseconds).sorted()
        guard !totals.isEmpty else { return "none yet" }
        let middle = totals.count / 2
        let median = totals.count.isMultiple(of: 2) ? (totals[middle - 1] + totals[middle]) / 2 : totals[middle]
        return "\(Int(median.rounded())) ms"
    }
}
