import XCTest

@testable import Scratch

/// Hosted in the app. The numbers the idle monitor writes for the performance tests (plan 6 task 2, docs/decisions/0009):
/// the keys are the ones `scripts/perf-extract.py` reads (`cpu_pct` and `wakeups` of the attachment `idle_cpu`).
@MainActor
final class IdleMonitorTests: XCTestCase {
    func testReportIsTheCPUTimeOverTheClockTimeAsAPercentage() {
        let report = IdleMonitor.report(cpuMilliseconds: 62.5, wallMilliseconds: 5000, wakeups: 120)

        XCTAssertEqual(report["cpu_ms"] as? Double, 62.5)
        XCTAssertEqual(report["wall_ms"] as? Double, 5000)
        XCTAssertEqual(report["cpu_pct"] as? Double, 1.25)
        XCTAssertEqual(report["wakeups"] as? Int, 120)
    }

    func testAFullCoreIsOneHundredPercent() {
        let report = IdleMonitor.report(cpuMilliseconds: 5000, wallMilliseconds: 5000, wakeups: 0)

        XCTAssertEqual(report["cpu_pct"] as? Double, 100)
    }

    func testNoTimeIsZeroPercent() {
        let report = IdleMonitor.report(cpuMilliseconds: 3, wallMilliseconds: 0, wakeups: 0)

        XCTAssertEqual(report["cpu_pct"] as? Double, 0)
    }

    func testReportIsRounded() {
        let report = IdleMonitor.report(cpuMilliseconds: 1.23456789, wallMilliseconds: 5000.0004, wakeups: 1)

        XCTAssertEqual(report["cpu_ms"] as? Double, 1.235)
        XCTAssertEqual(report["wall_ms"] as? Double, 5000)
        XCTAssertEqual(report["cpu_pct"] as? Double, 0.025)
    }

    func testReportDataIsJSONWithTheKeysPerfExtractReads() throws {
        let data = IdleMonitor.reportData(cpuMilliseconds: 40, wallMilliseconds: 5000, wakeups: 77)

        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["cpu_pct"] as? Double, 0.8)
        XCTAssertEqual(object["wakeups"] as? Int, 77)
        XCTAssertEqual(object["cpu_ms"] as? Double, 40)
    }
}
