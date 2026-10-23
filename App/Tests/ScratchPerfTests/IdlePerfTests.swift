import XCTest

/// Spec §7, idle: a scratchpad that sits open all day must use no CPU and cause no wake-ups while nothing happens. The
/// measured numbers are `idle_cpu_pct` and `idle_wakeups` (scripts/perf-extract.py), which the app measures itself:
/// `-ScratchIdleMonitor <path>` has `IdleMonitor` read its own CPU time 3.5 seconds after launch and again 5 seconds later,
/// count the wake-ups of the main run loop in between, and write the report to the file (docs/decisions/0009).
@MainActor
final class IdlePerfTests: XCTestCase {
    /// `idle_cpu_pct`: the app's CPU over 5 seconds of idle, as a percentage of one core, on the `typical` fixture with
    /// the window open and the caret in the note. The test asks the app nothing while it measures (a question through the
    /// accessibility API costs the app CPU time too): it only looks for the file, and attaches what the app wrote as
    /// `idle_cpu`. It fails when the file never comes.
    func testIdle() throws {
        continueAfterFailure = false
        let dataDirectory = UITestSupport.makeDataDirectory()
        let report = dataDirectory.appendingPathComponent("idle-monitor.json")
        let app = PerfSupport.launch(
            fixture: "typical", dataDirectory: dataDirectory, extraArguments: ["-ScratchIdleMonitor", report.path])
        defer { app.terminate() }

        // The monitor starts 3.5 seconds after launch and writes its report 5 seconds later.
        let written = UITestSupport.wait(timeout: 60) { FileManager.default.fileExists(atPath: report.path) }
        XCTAssertTrue(written, "the idle monitor wrote nothing to \(report.path)")
        let data = try Data(contentsOf: report)
        let numbers = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(numbers["cpu_pct"] as? Double, "the idle report: \(numbers)")

        let attachment = XCTAttachment(string: String(decoding: data, as: UTF8.self))
        attachment.name = "idle_cpu"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
