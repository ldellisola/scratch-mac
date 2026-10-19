import XCTest

/// Launches Scratch for a UI test, always in a data directory of its own, so no UI test ever touches real data
/// (spec §9.4, AGENTS.md section 3).
enum UITestSupport {
    /// Launches the app with a new, empty data directory seeded with `fixture` (a `Fixture` raw value such as
    /// `typical`), in light appearance. Returns the running app.
    @MainActor
    static func launch(fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ScratchDataDir", makeDataDirectory().path,
            "-ScratchFixture", fixture,
            "-ScratchAppearance", "light",
        ]
        app.launch()
        return app
    }

    /// The editor's text view. Its `value` is the note's text.
    @MainActor
    static func editor(in app: XCUIApplication) -> XCUIElement {
        app.textViews.matching(identifier: AccessibilityID.editorTextView).firstMatch
    }

    /// A new directory under the temporary directory. A sandboxed test runner's own temporary directory lives inside
    /// its container, which the app is not allowed to write to, so that case uses /tmp instead.
    private static func makeDataDirectory() -> URL {
        let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        let base = sandboxed ? URL(fileURLWithPath: "/tmp", isDirectory: true) : FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ScratchUITests-\(UUID().uuidString)", isDirectory: true)
    }
}
