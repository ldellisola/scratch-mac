import XCTest

/// Renders the key screens to PNG files (spec §9.4, plan 1 task 9). Agents cannot see the screen, so this is how they
/// check a visual change: `make screenshots` runs only this class, exports each attachment from the result bundle and
/// names it `<name>.png`, and CI publishes the files to `ci-results/<sha>/macos/screenshots/`.
///
/// There is one test per name. A test launches a fixture in an isolated data directory in one appearance, waits until
/// the window has what it should show, and attaches a screenshot of the window under the name. It asserts nothing about
/// how the window looks: a person (or an agent that opens the PNG) judges that. `make app-test` skips this class, so
/// that the screenshots are taken once per CI job.
@MainActor
final class ScreenshotTests: XCTestCase {
    func testTypicalLight() {
        capture("typical-light", fixture: "typical", appearance: "light", sidebarRows: 6)
    }

    func testTypicalDark() {
        capture("typical-dark", fixture: "typical", appearance: "dark", sidebarRows: 6)
    }

    func testEmptyLight() {
        capture("empty-light", fixture: "empty", appearance: "light", sidebarRows: 0)
    }

    func testHugeNoteLight() {
        capture("huge-note-light", fixture: "huge-note", appearance: "light", sidebarRows: 2)
    }

    /// Launches `fixture`, waits for the editor and for `sidebarRows` sidebar rows (the fixture's notes that the
    /// sidebar lists), and attaches a screenshot of the window as `name`, kept even though the test passes.
    private func capture(_ name: String, fixture: String, appearance: String, sidebarRows: Int) {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: fixture, appearance: appearance)

        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 20), "the editor text view did not appear")
        XCTAssertTrue(
            UITestSupport.wait { UITestSupport.sidebarTitleTexts(in: app).count == sidebarRows },
            "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: app))")
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "the app has no window")

        // Let the first layout, the glass material and the selection highlight settle before the picture is taken.
        Thread.sleep(forTimeInterval: 1.0)

        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
