import XCTest

@testable import Scratch

/// Hosted in the app. The numbers the frame monitor writes for the performance tests (plan 1 task 10): the keys are the
/// ones `scripts/perf-extract.py` reads.
@MainActor
final class FrameMonitorTests: XCTestCase {
    func testReportSummarisesFrames() {
        let report = FrameMonitor.report(frameMilliseconds: (1...100).map(Double.init))

        XCTAssertEqual(report["frames"], 100)
        XCTAssertEqual(report["max_frame_ms"], 100)
        XCTAssertEqual(report["p95_frame_ms"], 95)
        XCTAssertEqual(report["mean_frame_ms"], 50.5)
    }

    func testReportWithoutFramesIsZero() {
        let report = FrameMonitor.report(frameMilliseconds: [])

        XCTAssertEqual(report, ["frames": 0, "max_frame_ms": 0, "p95_frame_ms": 0, "mean_frame_ms": 0])
    }

    func testReportIsRoundedToMicroseconds() {
        let report = FrameMonitor.report(frameMilliseconds: [1.23456789])

        XCTAssertEqual(report["max_frame_ms"], 1.235)
    }

    func testReportDataIsJSONWithTheKeysPerfExtractReads() throws {
        let data = FrameMonitor.reportData(frameMilliseconds: [2.5, 7.25])

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Double]
        XCTAssertEqual(object?["max_frame_ms"], 7.25)
        XCTAssertEqual(object?["frames"], 2)
    }
}
