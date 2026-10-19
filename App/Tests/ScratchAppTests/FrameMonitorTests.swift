import XCTest

@testable import Scratch

/// Hosted in the app. The numbers the frame monitor writes for the performance tests (plan 1 task 10): the keys are the
/// ones `scripts/perf-extract.py` reads.
@MainActor
final class FrameMonitorTests: XCTestCase {
    private func frames(wall: [Double], cpu: [Double]) -> [FrameMonitor.Frame] {
        zip(wall, cpu).map { FrameMonitor.Frame(wall: $0, cpu: $1) }
    }

    func testReportSummarisesFramesByTheClockAndByCPUTime() {
        let wall = (1...100).map(Double.init)
        let report = FrameMonitor.report(frames: frames(wall: wall, cpu: wall.map { $0 / 2 }))

        XCTAssertEqual(report["frames"] as? Int, 100)
        XCTAssertEqual(report["median_frame_ms"] as? Double, 50)
        XCTAssertEqual(report["p95_frame_ms"] as? Double, 95)
        XCTAssertEqual(report["max_frame_ms"] as? Double, 100)
        XCTAssertEqual(report["mean_frame_ms"] as? Double, 50.5)
        XCTAssertEqual(report["median_cpu_ms"] as? Double, 25)
        XCTAssertEqual(report["p95_cpu_ms"] as? Double, 47.5)
        XCTAssertEqual(report["max_cpu_ms"] as? Double, 50)
        XCTAssertEqual(report["mean_cpu_ms"] as? Double, 25.25)
    }

    func testReportKeepsEveryFrameInOrder() {
        let report = FrameMonitor.report(frames: frames(wall: [3, 1, 2], cpu: [0.5, 0.25, 0.75]))

        XCTAssertEqual(report["frame_ms"] as? [Double], [3, 1, 2])
        XCTAssertEqual(report["frame_cpu_ms"] as? [Double], [0.5, 0.25, 0.75])
        XCTAssertEqual(report["median_frame_ms"] as? Double, 2)
        XCTAssertEqual(report["median_cpu_ms"] as? Double, 0.5)
    }

    func testReportWithoutFramesIsZero() {
        let report = FrameMonitor.report(frames: [])

        XCTAssertEqual(report["frames"] as? Int, 0)
        XCTAssertEqual(report["median_frame_ms"] as? Double, 0)
        XCTAssertEqual(report["max_cpu_ms"] as? Double, 0)
        XCTAssertEqual((report["frame_ms"] as? [Double])?.count, 0)
    }

    func testReportIsRoundedToMicroseconds() {
        let report = FrameMonitor.report(frames: frames(wall: [1.23456789], cpu: [0.00049]))

        XCTAssertEqual(report["max_frame_ms"] as? Double, 1.235)
        XCTAssertEqual(report["max_cpu_ms"] as? Double, 0)
    }

    func testReportDataIsJSONWithTheKeysPerfExtractReads() throws {
        let data = FrameMonitor.reportData(frames: frames(wall: [2.5, 7.25], cpu: [1, 2]))

        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["max_frame_ms"] as? Double, 7.25)
        XCTAssertEqual(object["median_frame_ms"] as? Double, 2.5)
        XCTAssertEqual(object["median_cpu_ms"] as? Double, 1)
        XCTAssertEqual(object["frames"] as? Int, 2)
        XCTAssertEqual(object["frame_ms"] as? [Double], [2.5, 7.25])
    }
}
