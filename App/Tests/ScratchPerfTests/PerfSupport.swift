import XCTest

/// What the performance tests share. They drive the real app, like the UI tests do, always in a data directory of its
/// own (`UITestSupport.makeDataDirectory`).
@MainActor
enum PerfSupport {
    /// The metric of the app's signpost interval `name`: `keystroke` and `switch-note`. The subsystem and the category
    /// are those of `Signposts.editor` in the app.
    static func signpostMetric(named name: String) -> XCTOSSignpostMetric {
        XCTOSSignpostMetric(subsystem: "io.github.ldellisola.Scratch", category: "editor", name: name)
    }

    /// `-ScratchTextKit <n>` when `make perf TEXTKIT=<n>` asked for one TextKit version (it reaches the tests as the
    /// environment variable SCRATCH_TEXTKIT). An empty or missing value asks for nothing: the flag has no empty form.
    static var textKitArguments: [String] {
        guard let version = ProcessInfo.processInfo.environment["SCRATCH_TEXTKIT"], !version.isEmpty else { return [] }
        return ["-ScratchTextKit", version]
    }

    /// Launches the app on `fixture`, seeded into `dataDirectory`, in light mode. `extraArguments` come last.
    static func launch(fixture: String, dataDirectory: URL, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            [
                "-ScratchDataDir", dataDirectory.path,
                "-ScratchFixture", fixture,
                "-ScratchAppearance", "light",
            ] + textKitArguments + extraArguments
        app.launch()
        return app
    }

    /// Attaches a screenshot of the app's window to the test, kept even when the test passes, so that a person (or an
    /// agent that opens the PNG) can see what the test saw.
    static func attachScreenshot(of app: XCUIApplication, named name: String, to test: XCTestCase) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }
}
