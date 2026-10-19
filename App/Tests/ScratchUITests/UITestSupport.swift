import XCTest

/// Launches Scratch for a UI test, always in a data directory of its own, so no UI test ever touches real data
/// (spec §9.4, AGENTS.md section 3).
enum UITestSupport {
    /// The app's bundle identifier, to find its running process.
    static let bundleIdentifier = "io.github.ldellisola.Scratch"

    /// Launches the app with a new, empty data directory seeded with `fixture` (a `Fixture` raw value such as
    /// `typical`), in the given appearance (`light` or `dark`, the `-ScratchAppearance` values). Returns the running
    /// app.
    @MainActor
    static func launch(fixture: String, appearance: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ScratchDataDir", makeDataDirectory().path,
            "-ScratchFixture", fixture,
            "-ScratchAppearance", appearance,
        ]
        app.launch()
        return app
    }

    /// Launches the app again on the data directory that `app` was launched with, and without a fixture, so what the
    /// first run saved is restored. `app` must have quit or been killed. Returns the new running app.
    @MainActor
    static func relaunch(sameDataAs app: XCUIApplication) -> XCUIApplication {
        let arguments = app.launchArguments
        guard let flag = arguments.firstIndex(of: "-ScratchDataDir"), flag + 1 < arguments.count else {
            preconditionFailure("relaunch(sameDataAs:) needs an app that was launched with -ScratchDataDir")
        }
        let relaunched = XCUIApplication()
        relaunched.launchArguments = [
            "-ScratchDataDir", arguments[flag + 1],
            "-ScratchAppearance", "light",
        ]
        relaunched.launch()
        return relaunched
    }

    /// The editor's text view. Its `value` is the note's text.
    @MainActor
    static func editor(in app: XCUIApplication) -> XCUIElement {
        app.textViews.matching(identifier: AccessibilityID.editorTextView).firstMatch
    }

    /// The toolbar's "new note" button. A toolbar item without a view has no accessibility identifier of its own: AppKit
    /// reports its item identifier (`AccessibilityID.newNoteButton`) as the identifier, and its label as the title or
    /// label, so any of the three finds it.
    @MainActor
    static func newNoteButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ OR label == %@ OR title == %@", AccessibilityID.newNoteButton, "New Note",
                "New Note")
        ).firstMatch
    }

    /// The title texts of the sidebar rows, in the order the accessibility tree lists them.
    @MainActor
    static func sidebarTitles(in app: XCUIApplication) -> XCUIElementQuery {
        app.staticTexts.matching(identifier: AccessibilityID.sidebarRowTitle)
    }

    /// The sidebar rows' titles from top to bottom.
    @MainActor
    static func sidebarTitleTexts(in app: XCUIApplication) -> [String] {
        sidebarTitles(in: app).allElementsBoundByIndex
            .sorted { $0.frame.minY < $1.frame.minY }
            .map { text(of: $0) }
    }

    /// The sidebar row whose title is exactly `title`.
    @MainActor
    static func sidebarRow(titled title: String, in app: XCUIApplication) -> XCUIElement {
        sidebarTitles(in: app).matching(NSPredicate(format: "value == %@ OR label == %@", title, title)).firstMatch
    }

    /// The sidebar row whose title contains `fragment`.
    @MainActor
    static func sidebarRow(titleContaining fragment: String, in app: XCUIApplication) -> XCUIElement {
        sidebarTitles(in: app)
            .matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", fragment, fragment)).firstMatch
    }

    /// What an element shows as text: its value, or else its label.
    @MainActor
    static func text(of element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }

    /// Polls `condition` every 0.1 s until it is true or `timeout` seconds have passed. Returns whether it became
    /// true.
    @MainActor
    static func wait(timeout: TimeInterval = 10, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return condition()
    }

    /// A new directory under the temporary directory. A sandboxed test runner's own temporary directory lives inside
    /// its container, which the app is not allowed to write to, so that case uses /tmp instead.
    private static func makeDataDirectory() -> URL {
        let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        let base = sandboxed ? URL(fileURLWithPath: "/tmp", isDirectory: true) : FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ScratchUITests-\(UUID().uuidString)", isDirectory: true)
    }
}
