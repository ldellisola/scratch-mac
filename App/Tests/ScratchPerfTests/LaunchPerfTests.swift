import XCTest

/// Spec §7: launch, app not running, to the restored note on screen and accepting keystrokes, at most 200 ms (on the
/// owner's M4). The measured number is `launch_ms` (scripts/perf-extract.py): XCTest's application launch metric, from
/// the process start to the first frame.
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
    }
}
