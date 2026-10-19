import XCTest

/// Spec §7: launch, app not running, to the restored note on screen and accepting keystrokes, at most 200 ms. The
/// measured number is `launch_ms` (scripts/perf-extract.py).
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
        app.launchArguments =
            ["-ScratchDataDir", dataDirectory.path, "-ScratchAppearance", "light"]
            + PerfSupport.textKitArguments
        defer { app.terminate() }

        let options = XCTMeasureOptions()
        options.iterationCount = 8
        // Like Xcode's own launch test: `launch()` ends the instance that runs from the last iteration, and an explicit
        // `terminate()` in the block made XCTest lose the launch of some iterations ("Received unexpected number of
        // metrics: 0").
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            app.launch()
        }
    }
}
