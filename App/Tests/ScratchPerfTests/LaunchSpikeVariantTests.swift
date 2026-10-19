import XCTest

/// THROWAWAY, branch spike/textkit only (plan 1 task 10). How slow is a launch on this runner for an app that is not
/// ours? Calculator, the same measurement as `LaunchPerfTests`, tells whether the 200 ms launch budget (the owner's M4)
/// can be reached on a GitHub virtual Mac at all.
@MainActor
final class LaunchSpikeVariantTests: XCTestCase {
    func testCalibrateLaunchOfCalculator() {
        let app = XCUIApplication(bundleIdentifier: "com.apple.calculator")
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
