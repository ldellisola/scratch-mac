import XCTest

/// Spec §7: launch, app not running, to the restored note on screen and accepting keystrokes, at most 200 ms (on the
/// owner's M4). The measured number is `launch_ms` (scripts/perf-extract.py): XCTest's application launch metric, from
/// the process start to the first frame.
///
/// CI's Macs cannot say whether Scratch meets that: a launch takes 600 ms there whatever the app is, and varies by a factor
/// of two between runs (docs/decisions/0003, 0009). So `launch_ms` is reported and never fails, and the number that gates
/// is `launch_overhead_ms`, `launch_ms` minus `launch_reference_ms`: the same measurement of `LaunchReference.app`, an
/// empty AppKit app that the same job builds (`testReferenceLaunch`). `testLaunch` also attaches the phases of the launches
/// that Scratch wrote in its own launch log (`launch_phases`), to see where the time goes.
@MainActor
final class LaunchPerfTests: XCTestCase {
    func testLaunch() throws {
        continueAfterFailure = false
        let dataDirectory = UITestSupport.makeDataDirectory()

        // Seed the data directory once with the `typical` fixture. The measured launches pass no fixture: they restore
        // what is saved, like every real launch.
        let seeding = PerfSupport.launch(fixture: "typical", dataDirectory: dataDirectory)
        XCTAssertTrue(UITestSupport.editor(in: seeding).waitForExistence(timeout: 30), "the seeding launch failed")
        seeding.terminate()

        let app = XCUIApplication()
        app.launchArguments = ["-ScratchDataDir", dataDirectory.path, "-ScratchAppearance", "light"]
        defer { app.terminate() }

        // The first launches of an instance are the slowest (0.53 s, then 0.37 s in the first runs): launch a few times
        // before measuring, so that "files in the disk cache" (spec §7) holds.
        for _ in 0..<3 {
            app.launch()
            app.terminate()
        }

        // Like Xcode's own launch test: `launch()` ends the instance that runs from the last iteration. The plan asked
        // for `XCTApplicationLaunchMetric(waitUntilResponsive: true)`, but on macos-26 that one reported a launch for
        // the first iteration only, with or without a `terminate()` in the block ("Received unexpected number of
        // metrics: 0"). The plain metric reported all of them.
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            app.launch()
        }

        // One more launch, outside the measurement, for the launch log (Help > Launch Times…): the app writes how far into the
        // process each phase of a launch was, `debug.state` has the newest records, and perf-extract.py takes the median of
        // each phase over them (`launch_phase_<name>_ms`). The log is written on a queue after the first frame, so the record
        // of this launch is there a moment after the launch returns. What is missing is reported, and fails nothing: the
        // phases are for a person.
        let launchedAt = Date().timeIntervalSince1970
        app.launch()
        var records: [[String: Any]] = []
        let logged = UITestSupport.wait(timeout: 30) {
            records = UITestSupport.debugState(in: app)["launchTimes"] as? [[String: Any]] ?? []
            return (records.first?["date"] as? Double ?? 0) >= launchedAt
        }
        let json =
            (try? JSONSerialization.data(withJSONObject: records, options: [.sortedKeys]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        let attachment = XCTAttachment(string: json)
        attachment.name = logged ? "launch_phases" : "launch_phases_incomplete"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// `launch_reference_ms`: the same measurement of `LaunchReference.app` (App/LaunchReference), an AppKit app that shows
    /// one window with a TextKit 1 text view and does nothing else, launched from the products folder of this build with the
    /// same warm-up and the same ten iterations. What Scratch's launch costs above it (`launch_overhead_ms`) is Scratch's own
    /// work, and does not depend on how fast the runner is that day (docs/decisions/0009).
    func testReferenceLaunch() throws {
        continueAfterFailure = false
        let url = PerfSupport.referenceApplicationURL()
        let located = XCTAttachment(
            string:
                "LaunchReference.app: \(url.path)\nsearched: \(PerfSupport.referenceApplicationCandidates().map(\.path))"
        )
        located.name = "reference-app-location"
        located.lifetime = .keepAlways
        add(located)

        let app = XCUIApplication(url: url)
        defer { app.terminate() }
        for _ in 0..<3 {
            app.launch()
            app.terminate()
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            app.launch()
        }
    }
}
