import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/launch-times.md ("The phases", "The log" and "A log that cannot be read or
/// written"): the launch marks its phases, and after the first frame a background queue appends them to
/// `launch-times.json`. The app has finished its own launch before a test runs, so these tests wait for its record and then
/// run `finish` with a timer state of their own (`LaunchTimer.withIsolatedState`) and a directory of their own.
@MainActor
final class LaunchTimerTests: XCTestCase {
    private func spin(until condition: () -> Bool, seconds: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    }

    /// The app's own launch has reached its first frame and the queue has delivered its record.
    private func waitForTheAppsOwnLaunch() {
        spin(until: { LaunchTimer.current != nil })
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScratchLaunchTimerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func markEveryPhase(from start: Date = Date()) {
        for (index, phase) in LaunchTimer.phases.enumerated() {
            LaunchTimer.mark(phase, at: start.addingTimeInterval(Double(index) * 0.01))
        }
    }

    private func logFile(in directory: URL) -> URL {
        directory.appendingPathComponent(LaunchLog.fileName)
    }

    // MARK: The app's own launch

    func testPhasesAreInOrder() throws {
        waitForTheAppsOwnLaunch()
        let record = try XCTUnwrap(LaunchTimer.current, "the launch's record never came back from the log's queue")

        XCTAssertEqual(Set(record.phases.keys), Set(LaunchTimer.phases))
        let times = LaunchTimer.phases.compactMap { record.phases[$0] }
        XCTAssertEqual(times.count, 5)
        XCTAssertEqual(times, times.sorted(), "main, storage, restore, window and firstFrame, in that order: \(times)")
        XCTAssertEqual(Set(times).count, 5, "each phase takes some time: \(times)")
        XCTAssertGreaterThan(times[0], 0, "the process had started before main")
        XCTAssertEqual(record.totalMilliseconds, record.phases["firstFrame"])
        XCTAssertFalse(record.version.isEmpty)
        XCTAssertEqual(record.version, LaunchTimesPanel.appVersion)
        XCTAssertLessThan(abs(record.date.timeIntervalSinceNow), 3_600, "dated at the first frame")
    }

    func testTheAppsOwnLaunchIsInTheLogItWrote() throws {
        waitForTheAppsOwnLaunch()
        let record = try XCTUnwrap(LaunchTimer.current)
        let log = try XCTUnwrap(LaunchTimer.log)
        XCTAssertEqual(log.records.last, record)
        // A hosted run has a throwaway data directory, so its log holds this launch and nothing else.
        XCTAssertEqual(log.records.count, 1)
        XCTAssertTrue(record.isFirstAfterStartUp)
        let state = LaunchTimer.debugRecords()
        XCTAssertEqual(state.count, min(log.records.count, 20))
        XCTAssertEqual(state.first?["total"] as? Double, record.totalMilliseconds)
        XCTAssertEqual(state.first?["isFirstAfterStartUp"] as? Bool, record.isFirstAfterStartUp)
        XCTAssertEqual((state.first?["phases"] as? [String: Double])?.count, 5)
        // The element UI tests read has it.
        let element = DebugStateElement(frame: .zero)
        let json = element.accessibilityValue() as? String ?? ""
        XCTAssertTrue(json.contains("\"launchTimes\":[{"), json)
    }

    // MARK: finish

    func testLaunchLogIsWrittenAfterTheFirstFrame() throws {
        waitForTheAppsOwnLaunch()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try LaunchTimer.withIsolatedState {
            markEveryPhase()
            // The queue is held back, so that "nothing is written by finish itself" is not a race.
            LaunchTimer.queue.suspend()
            var isSuspended = true
            defer { if isSuspended { LaunchTimer.queue.resume() } }

            LaunchTimer.finish(dataDirectory: directory, version: "9.9.9")
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: logFile(in: directory).path), "finish writes nothing itself")
            XCTAssertNil(LaunchTimer.current, "the record comes back from the queue")

            LaunchTimer.queue.resume()
            isSuspended = false
            spin(until: { LaunchTimer.current != nil })

            let record = try XCTUnwrap(LaunchTimer.current)
            XCTAssertEqual(record.version, "9.9.9")
            XCTAssertTrue(record.isFirstAfterStartUp, "the first record of a log is the first after start-up")
            XCTAssertEqual(Set(record.phases.keys), Set(LaunchTimer.phases))
            let stored = LaunchLog.load(from: directory)
            XCTAssertEqual(stored.records.count, 1)
            XCTAssertEqual(stored.records.first?.phases, record.phases)
            XCTAssertEqual(stored.records.first?.version, "9.9.9")
            XCTAssertEqual(stored.records.first?.isFirstAfterStartUp, true)
            XCTAssertEqual(
                stored.records.first?.date.timeIntervalSince1970 ?? 0, record.date.timeIntervalSince1970,
                accuracy: 0.001)
            XCTAssertEqual(LaunchTimer.log?.records.count, 1)
        }
    }

    func testFinishEndsTheLaunchOnce() throws {
        waitForTheAppsOwnLaunch()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        LaunchTimer.withIsolatedState {
            markEveryPhase()
            LaunchTimer.finish(dataDirectory: directory, version: "9.9.9")
            LaunchTimer.finish(dataDirectory: directory, version: "9.9.9")
            LaunchTimer.queue.sync {}
            spin(until: { LaunchTimer.current != nil })
            LaunchTimer.queue.sync {}
            XCTAssertEqual(LaunchLog.load(from: directory).records.count, 1)
        }
    }

    func testFinishMarksTheFirstFrameWhenNobodyDid() throws {
        waitForTheAppsOwnLaunch()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        LaunchTimer.withIsolatedState {
            LaunchTimer.mark("main", at: Date().addingTimeInterval(-0.5))
            LaunchTimer.finish(dataDirectory: directory, version: "9.9.9")
            spin(until: { LaunchTimer.current != nil })
            XCTAssertEqual(Set(LaunchTimer.current?.phases.keys ?? []), ["main", "firstFrame"])
        }
    }

    func testAPhaseKeepsItsFirstMark() throws {
        waitForTheAppsOwnLaunch()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = try XCTUnwrap(LaunchClock.processStart())

        LaunchTimer.withIsolatedState {
            let first = Date()
            LaunchTimer.mark("storage", at: first)
            LaunchTimer.mark("storage", at: first.addingTimeInterval(5))
            LaunchTimer.mark("storage")
            LaunchTimer.finish(dataDirectory: directory, version: "9.9.9")
            spin(until: { LaunchTimer.current != nil })
            let storage = LaunchTimer.current?.phases["storage"] ?? -1
            XCTAssertEqual(storage, first.timeIntervalSince(start) * 1000, accuracy: 0.1)
        }
    }

    func testAnotherLaunchOfTheSameBootIsNotTheFirst() throws {
        waitForTheAppsOwnLaunch()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        for expectedFirst in [true, false] {
            LaunchTimer.withIsolatedState {
                markEveryPhase()
                LaunchTimer.finish(dataDirectory: directory, version: "9.9.9")
                spin(until: { LaunchTimer.current != nil })
                XCTAssertEqual(LaunchTimer.current?.isFirstAfterStartUp, expectedFirst)
            }
        }
        XCTAssertEqual(LaunchLog.load(from: directory).records.map(\.isFirstAfterStartUp), [true, false])
    }

    // MARK: A log that cannot be read or written

    func testLaunchSurvivesAnUnwritableLaunchLog() throws {
        waitForTheAppsOwnLaunch()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // The log's file is a directory: it can be neither read nor replaced.
        try FileManager.default.createDirectory(at: logFile(in: directory), withIntermediateDirectories: false)

        LaunchTimer.withIsolatedState {
            markEveryPhase()
            LaunchTimer.finish(dataDirectory: directory, version: "9.9.9")
            spin(until: { LaunchTimer.current != nil })

            XCTAssertNotNil(LaunchTimer.current, "the record is kept for this run when the file cannot be written")
            XCTAssertEqual(LaunchTimer.log?.records.count, 1)
        }
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: logFile(in: directory).path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue, "nothing replaced it")
    }

    func testLaunchReplacesACorruptLaunchLog() throws {
        waitForTheAppsOwnLaunch()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([0xFF, 0x00, 0x7B, 0x22]).write(to: logFile(in: directory))

        LaunchTimer.withIsolatedState {
            markEveryPhase()
            LaunchTimer.finish(dataDirectory: directory, version: "9.9.9")
            spin(until: { LaunchTimer.current != nil })
            XCTAssertEqual(LaunchTimer.current?.isFirstAfterStartUp, true)
        }
        XCTAssertEqual(LaunchLog.load(from: directory).records.count, 1)
    }

    func testLaunchGoesOnWithoutADataDirectory() throws {
        waitForTheAppsOwnLaunch()
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScratchLaunchTimerTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("not", isDirectory: true).appendingPathComponent("there", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: missing.deletingLastPathComponent().deletingLastPathComponent())
        }

        LaunchTimer.withIsolatedState {
            markEveryPhase()
            LaunchTimer.finish(dataDirectory: missing, version: "9.9.9")
            spin(until: { LaunchTimer.current != nil })
            XCTAssertNotNil(LaunchTimer.current)
        }
    }

    // MARK: The record

    func testRecordIsMillisecondsFromTheProcessStart() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000.5)
        let marks = [
            "main": start.addingTimeInterval(0.0312), "storage": start.addingTimeInterval(0.0654),
            "restore": start.addingTimeInterval(0.08), "window": start.addingTimeInterval(0.1204),
            "firstFrame": start.addingTimeInterval(0.1567),
        ]
        let boot = Date(timeIntervalSince1970: 1_799_990_000.25)
        let record = try XCTUnwrap(
            LaunchTimer.makeRecord(marks: marks, version: "1.0.0", processStart: start, bootTime: boot))

        XCTAssertEqual(record.phases["main"] ?? 0, 31.2, accuracy: 0.0001)
        XCTAssertEqual(record.phases["storage"] ?? 0, 65.4, accuracy: 0.0001)
        XCTAssertEqual(record.phases["restore"] ?? 0, 80, accuracy: 0.0001)
        XCTAssertEqual(record.phases["window"] ?? 0, 120.4, accuracy: 0.0001)
        XCTAssertEqual(record.phases["firstFrame"] ?? 0, 156.7, accuracy: 0.0001)
        XCTAssertEqual(record.totalMilliseconds, record.phases["firstFrame"])
        XCTAssertEqual(
            record.date.timeIntervalSince1970, 1_800_000_000.657, accuracy: 0.0001, "the first frame's moment")
        XCTAssertEqual(record.bootTime, boot)
        XCTAssertEqual(record.version, "1.0.0")
        XCTAssertFalse(record.isFirstAfterStartUp, "the log decides")
    }

    func testRecordNeedsTheProcessStartAndTheFirstFrame() {
        let now = Date()
        XCTAssertNil(LaunchTimer.makeRecord(marks: ["firstFrame": now], version: "1", processStart: nil, bootTime: now))
        XCTAssertNil(LaunchTimer.makeRecord(marks: ["main": now], version: "1", processStart: now, bootTime: now))
    }

    func testRecordNeverHasAPhaseBeforeTheProcessStart() throws {
        let start = Date()
        let record = try XCTUnwrap(
            LaunchTimer.makeRecord(
                marks: ["main": start.addingTimeInterval(-0.2), "firstFrame": start.addingTimeInterval(0.1)],
                version: "1",
                processStart: start, bootTime: start))
        XCTAssertEqual(record.phases["main"], 0)
    }

    func testRecordWithoutABootTimeIsStillARecord() throws {
        let start = Date()
        let record = try XCTUnwrap(
            LaunchTimer.makeRecord(
                marks: ["firstFrame": start.addingTimeInterval(0.1)], version: "1", processStart: start, bootTime: nil))
        XCTAssertEqual(record.bootTime, .distantPast)
    }
}
