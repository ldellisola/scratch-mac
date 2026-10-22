import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/launch-times.md ("The record"): the two moments that the launch log measures from.
@MainActor
final class LaunchClockTests: XCTestCase {
    func testTheProcessStartedBeforeNowAndAfterTheMacStarted() throws {
        let start = try XCTUnwrap(LaunchClock.processStart(), "the kernel did not say when this process started")
        let boot = try XCTUnwrap(LaunchClock.bootTime(), "the kernel did not say when the Mac started")

        XCTAssertLessThan(start, Date())
        XCTAssertLessThan(boot, start)
        // A test run is minutes old, not days.
        XCTAssertLessThan(Date().timeIntervalSince(start), 24 * 3_600)
    }

    func testTheBootTimeDoesNotChangeBetweenReads() throws {
        let first = try XCTUnwrap(LaunchClock.bootTime())
        let second = try XCTUnwrap(LaunchClock.bootTime())
        XCTAssertEqual(first.timeIntervalSince1970, second.timeIntervalSince1970, accuracy: 30)
    }

    func testTheProcessStartDoesNotChangeBetweenReads() throws {
        XCTAssertEqual(LaunchClock.processStart(), LaunchClock.processStart())
    }
}
