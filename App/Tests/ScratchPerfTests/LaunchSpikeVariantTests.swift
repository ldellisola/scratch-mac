import XCTest

/// THROWAWAY, branch spike/textkit only (plan 1 task 10). The first spike run lost the launch metric of some
/// iterations of `LaunchPerfTests.testLaunch`. Two other ways to ask for it, to see which one XCTest keeps.
@MainActor
final class LaunchSpikeVariantTests: XCTestCase {
    private func seededDataDirectory() -> URL {
        let dataDirectory = UITestSupport.makeDataDirectory()
        let seeding = PerfSupport.launch(fixture: "typical", dataDirectory: dataDirectory)
        XCTAssertTrue(UITestSupport.editor(in: seeding).waitForExistence(timeout: 30), "the seeding launch failed")
        seeding.terminate()
        return dataDirectory
    }

    func testAlternateLaunchTerminatingAfter() {
        let app = XCUIApplication()
        app.launchArguments =
            ["-ScratchDataDir", seededDataDirectory().path, "-ScratchAppearance", "light"]
            + PerfSupport.textKitArguments
        let options = XCTMeasureOptions()
        options.iterationCount = 8
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            app.launch()
            app.terminate()
        }
    }

    func testAlternateLaunchNotWaiting() {
        let app = XCUIApplication()
        app.launchArguments =
            ["-ScratchDataDir", seededDataDirectory().path, "-ScratchAppearance", "light"]
            + PerfSupport.textKitArguments
        defer { app.terminate() }
        let options = XCTMeasureOptions()
        options.iterationCount = 8
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            app.launch()
        }
    }
}
