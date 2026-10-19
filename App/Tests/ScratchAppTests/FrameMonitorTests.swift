import XCTest

@testable import Scratch

/// Hosted in the app. The numbers the frame monitor writes for the performance tests (plan 1 task 10): the keys are the
/// ones `scripts/perf-extract.py` reads.
@MainActor
final class FrameMonitorTests: XCTestCase {
    func testReportSummarisesFrames() {
        let report = FrameMonitor.report(frameMilliseconds: (1...100).map(Double.init))

        XCTAssertEqual(report["frames"] as? Int, 100)
        XCTAssertEqual(report["median_frame_ms"] as? Double, 50)
        XCTAssertEqual(report["p95_frame_ms"] as? Double, 95)
        XCTAssertEqual(report["max_frame_ms"] as? Double, 100)
        XCTAssertEqual(report["mean_frame_ms"] as? Double, 50.5)
    }

    func testReportKeepsEveryFrameInOrder() {
        let report = FrameMonitor.report(frameMilliseconds: [3, 1, 2])

        XCTAssertEqual(report["frame_ms"] as? [Double], [3, 1, 2])
        XCTAssertEqual(report["median_frame_ms"] as? Double, 2)
    }

    func testReportWithoutFramesIsZero() {
        let report = FrameMonitor.report(frameMilliseconds: [])

        XCTAssertEqual(report["frames"] as? Int, 0)
        XCTAssertEqual(report["median_frame_ms"] as? Double, 0)
        XCTAssertEqual(report["max_frame_ms"] as? Double, 0)
        XCTAssertEqual((report["frame_ms"] as? [Double])?.count, 0)
    }

    func testReportIsRoundedToMicroseconds() {
        let report = FrameMonitor.report(frameMilliseconds: [1.23456789])

        XCTAssertEqual(report["max_frame_ms"] as? Double, 1.235)
    }

    func testReportDataIsJSONWithTheKeysPerfExtractReads() throws {
        let data = FrameMonitor.reportData(frameMilliseconds: [2.5, 7.25])

        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["max_frame_ms"] as? Double, 7.25)
        XCTAssertEqual(object["median_frame_ms"] as? Double, 2.5)
        XCTAssertEqual(object["frames"] as? Int, 2)
        XCTAssertEqual(object["frame_ms"] as? [Double], [2.5, 7.25])
    }
}
