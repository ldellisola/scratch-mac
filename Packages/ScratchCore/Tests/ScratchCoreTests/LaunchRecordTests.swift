import Foundation
import Testing

@testable import ScratchCore

// docs/features/launch-times.md ("The record"): what a launch writes down.

@Test func totalIsTheFirstFramePhase() {
    let record = LaunchRecord(
        date: Date(timeIntervalSince1970: 1_000), version: "1.0.0", bootTime: Date(timeIntervalSince1970: 0),
        phases: ["main": 20, "firstFrame": 123.4], isFirstAfterStartUp: false)
    #expect(record.totalMilliseconds == 123.4)
}

@Test func totalWithoutAFirstFrameIsZero() {
    let record = LaunchRecord(
        date: Date(timeIntervalSince1970: 1_000), version: "1.0.0", bootTime: Date(timeIntervalSince1970: 0),
        phases: ["main": 20], isFirstAfterStartUp: false)
    #expect(record.totalMilliseconds == 0)
}

@Test func recordRoundTripsThroughJSON() throws {
    let record = LaunchRecord(
        date: Date(timeIntervalSince1970: 1_761_210_840.25), version: "1.0.0",
        bootTime: Date(timeIntervalSince1970: 1_761_100_000),
        phases: ["main": 31.5, "storage": 60.1, "restore": 80.2, "window": 120, "firstFrame": 150.7],
        isFirstAfterStartUp: true)
    let data = try JSONEncoder().encode(record)
    #expect(try JSONDecoder().decode(LaunchRecord.self, from: data) == record)
}

@Test func theTotalIsNotStored() throws {
    let record = LaunchRecord(
        date: Date(timeIntervalSince1970: 1_000), version: "1.0.0", bootTime: Date(timeIntervalSince1970: 0),
        phases: ["firstFrame": 99], isFirstAfterStartUp: false)
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any]
    #expect(object?["totalMilliseconds"] == nil)
    #expect(Set(object?.keys.map { $0 } ?? []) == ["date", "version", "bootTime", "phases", "isFirstAfterStartUp"])
}
