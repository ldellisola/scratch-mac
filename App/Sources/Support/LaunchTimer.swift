import Foundation
import ScratchCore

/// Writes down how long each launch took (docs/features/launch-times.md).
///
/// The launch marks its phases as it goes (`mark(_:)`, a clock read and a dictionary write: `main`, `storage`, `restore`,
/// `window`), and when the main run loop is next idle after the window is shown it marks `firstFrame` and calls
/// `finish(dataDirectory:version:)`. Everything else happens after that, on a utility queue: the process start and the
/// boot time are read, the log is loaded from `launch-times.json`, the record is appended and the file is written. Nothing
/// of the log runs on the main thread before the first frame, and a log that cannot be read or written changes nothing
/// about the launch: the work is `try?` all the way (`LaunchLog.load` never throws, and a failed `save` is dropped).
///
/// The record of the launch and the log as it is now come back to the main thread (`current`, `log`) once the queue is
/// done, for Help > Launch Times… and for `debug.state`.
@MainActor
enum LaunchTimer {
    /// The phases of a launch, in order.
    static let phases = ["main", "storage", "restore", "window", "firstFrame"]

    /// What the timer knows. Held in one value so that a hosted test can run with a state of its own
    /// (`withIsolatedState`), while the app's own launch keeps its.
    struct State {
        var marks: [String: Date] = [:]
        var isFinished = false
        var log: LaunchLog?
        var current: LaunchRecord?
    }

    private static var state = State()

    /// The queue that reads and writes the log: serial, utility. Hosted tests suspend it to look at the state of the file
    /// before the queue has run.
    static let queue = DispatchQueue(label: "io.github.ldellisola.Scratch.launch-log", qos: .utility)

    /// This launch's record, once it is in the log. Nil until the queue has loaded the log and appended it, a moment after the
    /// first frame, and nil for ever when the kernel did not say when the process started. It is there also when the file
    /// could not be written.
    static var current: LaunchRecord? { state.current }

    /// The log as the queue last loaded and appended it to: every launch the file holds, and this one. Nil until then.
    static var log: LaunchLog? { state.log }

    // MARK: Marks

    /// Records now as the time of `phase`, the first time only: a phase that is marked again keeps its first time.
    static func mark(_ phase: String) {
        mark(phase, at: Date())
    }

    /// Records `date` as the time of `phase`, the first time only (the hosted tests give their own times).
    static func mark(_ phase: String, at date: Date) {
        if state.marks[phase] == nil { state.marks[phase] = date }
    }

    // MARK: Finishing

    /// Ends the measurement, once. Marks `firstFrame` when nobody has, then hands the marks to the utility queue, which
    /// builds the record, appends it to the log in `dataDirectory`, writes the file and reports back to the main thread.
    /// Returns at once and writes nothing itself.
    static func finish(dataDirectory: URL, version: String) {
        guard !state.isFinished else { return }
        state.isFinished = true
        mark("firstFrame")
        let marks = state.marks
        queue.async {
            let record = makeRecord(
                marks: marks, version: version, processStart: LaunchClock.processStart(),
                bootTime: LaunchClock.bootTime())
            let log = append(record, toLogIn: dataDirectory)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    state.log = log
                    state.current = record == nil ? nil : log.records.last
                }
            }
        }
    }

    /// The record of a launch: each mark as milliseconds from `processStart` (to a tenth of a millisecond, never before the
    /// start), dated at the `firstFrame` mark. Nil without a start of the process or a `firstFrame` mark. The dates are
    /// whole milliseconds, which the file keeps exactly. `isFirstAfterStartUp` is the log's to set. Without a boot time
    /// the record has `.distantPast`, so the log counts all such launches as one boot.
    nonisolated static func makeRecord(
        marks: [String: Date], version: String, processStart: Date?, bootTime: Date?
    ) -> LaunchRecord? {
        guard let processStart, let end = marks["firstFrame"] else { return nil }
        var phases: [String: Double] = [:]
        for (name, date) in marks {
            let seconds = max(0, date.timeIntervalSince(processStart))
            phases[name] = (seconds * 10_000).rounded() / 10
        }
        return LaunchRecord(
            date: wholeMilliseconds(end), version: version, bootTime: wholeMilliseconds(bootTime ?? .distantPast),
            phases: phases, isFirstAfterStartUp: false)
    }

    /// Loads the log, appends `record` to it and writes the file, on the queue. A file that cannot be written is left alone:
    /// the log that comes back holds the record all the same.
    nonisolated private static func append(_ record: LaunchRecord?, toLogIn directory: URL) -> LaunchLog {
        var log = LaunchLog.load(from: directory)
        guard let record else { return log }
        log.append(record)
        try? log.save(to: directory)
        return log
    }

    nonisolated private static func wholeMilliseconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }

    // MARK: Debug state and tests

    /// The newest `limit` records of the log as `debug.state` shows them under `launchTimes`, newest first: each with its
    /// `date` (seconds since 1970), `version`, `bootTime`, `isFirstAfterStartUp`, `total` (milliseconds) and `phases`.
    static func debugRecords(limit: Int = 20) -> [[String: Any]] {
        (state.log?.records.suffix(limit) ?? []).reversed().map { record in
            [
                "date": record.date.timeIntervalSince1970, "version": record.version,
                "bootTime": record.bootTime.timeIntervalSince1970, "isFirstAfterStartUp": record.isFirstAfterStartUp,
                "total": record.totalMilliseconds, "phases": record.phases,
            ]
        }
    }

    /// Runs `body` with marks, a record and a log of its own, and gives the launch's own back afterwards. For the hosted
    /// tests, which run inside the app after its launch has finished. The queue's work must be done by the time `body`
    /// returns, or it would report into the state that comes back.
    static func withIsolatedState<Result>(_ body: () throws -> Result) rethrows -> Result {
        let saved = state
        state = State()
        defer { state = saved }
        return try body()
    }
}
