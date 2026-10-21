import XCTest

/// Renders the key screens to PNG files (spec §9.4, plan 1 task 9, plan 2 task 10). Agents cannot see the screen, so
/// this is how they check a visual change: `make screenshots` runs only this class, exports each attachment from the
/// result bundle and names it `<name>.png`, and CI publishes the files to `ci-results/<sha>/macos/screenshots/`.
///
/// There is one test per name. A test launches a fixture in an isolated data directory in one appearance, waits until
/// the window has what it should show, and attaches a screenshot of the window under the name. It asserts nothing about
/// how the window looks: a person (or an agent that opens the PNG) judges that. `make app-test` skips this class, so
/// that the screenshots are taken once per CI job.
///
/// The names are `typical-light`, `typical-dark`, `empty-light`, `huge-note-light`, `search-light`,
/// `recently-deleted-light`, `formatting-light`, `formatting-dark`, `code-light` and `code-dark`. The Makefile's
/// `SCREENSHOT_NAMES` lists them and must stay in step with this class.
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

    /// The typical fixture with "kube" typed in the sidebar's search field: the list narrows to "Deploy checklist",
    /// whose body has `kubectl` in it (every word matches as a prefix, spec §6.2). The field shows its text and has
    /// the keyboard.
    func testSearchLight() {
        capture("search-light", fixture: "typical", appearance: "light", sidebarRows: 6) { app in
            let field = UITestSupport.searchField(in: app)
            XCTAssertTrue(field.waitForExistence(timeout: 10), "the sidebar has no search field")
            field.click()
            field.typeText("kube")
            XCTAssertTrue(
                UITestSupport.wait { UITestSupport.sidebarTitleTexts(in: app) == ["Deploy checklist"] },
                "the sidebar rows after the search: \(UITestSupport.sidebarTitleTexts(in: app))")
        }
    }

    /// The recently-deleted fixture with the Recently Deleted section expanded. The purge has removed "Ancient"
    /// (deleted 31 days ago), so the header reads "Recently Deleted (1)", and "Old meeting notes" is listed under it.
    func testRecentlyDeletedLight() {
        capture("recently-deleted-light", fixture: "recently-deleted", appearance: "light", sidebarRows: 1) { app in
            let header = UITestSupport.recentlyDeletedHeader(in: app)
            XCTAssertTrue(
                UITestSupport.wait(timeout: 20) {
                    header.exists && UITestSupport.text(of: header) == "Recently Deleted (1)"
                },
                "the Recently Deleted header: \(header.exists ? UITestSupport.text(of: header) : "none")")
            header.click()
            XCTAssertTrue(
                UITestSupport.wait {
                    UITestSupport.sidebarTitleTexts(in: app) == ["Groceries", "Old meeting notes"]
                },
                "the sidebar rows with Recently Deleted expanded: \(UITestSupport.sidebarTitleTexts(in: app))")
        }
    }

    /// The formatting fixture: one note with a bullet and a nested bullet, an open and a ticked box, bold, inline code
    /// and a link, a line of unclosed markers, and a fenced block whose markers must show as typed (plan 3, task 8).
    /// The caret is at the top of the note, so every bold and inline code marker is hidden. A person (or an agent that
    /// opens the PNG) checks: hanging indents, the boxes, the struck-through ticked item, no stars next to the bold
    /// text, the tinted inline code, the coloured link and the block's lines exactly as typed.
    func testFormattingLight() {
        capture("formatting-light", fixture: "formatting", appearance: "light", sidebarRows: 1)
    }

    /// The same note in dark mode: the colours of the boxes, the code and the link must all read on a dark background.
    func testFormattingDark() {
        capture("formatting-dark", fixture: "formatting", appearance: "dark", sidebarRows: 1)
    }

    /// The code fixture (plan 4, task 8): one note with a block for each of Swift, Python, SQL, JSON and Shell, and a last
    /// one whose fence has no name, so that its language is detected. The test waits until the colours are written
    /// (they come from a background queue, after the window is up), and a person (or an agent that opens the PNG)
    /// checks: rounded tinted blocks with no fence lines in sight, a label at the top right of each block, the
    /// detected one (JavaScript) in italics and the others upright, and keywords, strings, comments, numbers and types
    /// in the colours of Xcode's default theme. The caret is in the first line of the note, so no fence is shown.
    func testCodeLight() {
        capture("code-light", fixture: "code", appearance: "light", sidebarRows: 1) { app in
            waitForColours(in: app)
        }
    }

    /// The same note in dark mode: the dark variants of the code colours on the dark tint.
    func testCodeDark() {
        capture("code-dark", fixture: "code", appearance: "dark", sidebarRows: 1) { app in
            waitForColours(in: app)
        }
    }

    /// Waits until the app has written the colours and the labels of every block (`debug.state`: `pendingHighlights` is
    /// zero). The request is made when the note is shown, before the window is visible, so zero means done.
    private func waitForColours(in app: XCUIApplication) {
        XCTAssertTrue(
            UITestSupport.wait(timeout: 20) { UITestSupport.debugState(in: app)["pendingHighlights"] as? Int == 0 },
            "the code colours were not written: \(UITestSupport.debugState(in: app))")
    }

    /// Launches `fixture`, waits for the editor and for `sidebarRows` sidebar rows (the fixture's notes that the
    /// sidebar lists), runs `prepare` to bring the window into the state the screenshot is about, and attaches a
    /// screenshot of the window as `name`, kept even though the test passes.
    private func capture(
        _ name: String, fixture: String, appearance: String, sidebarRows: Int,
        prepare: @MainActor (XCUIApplication) -> Void = { _ in }
    ) {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: fixture, appearance: appearance)

        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 20), "the editor text view did not appear")
        XCTAssertTrue(
            UITestSupport.wait { UITestSupport.sidebarTitleTexts(in: app).count == sidebarRows },
            "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: app))")
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "the app has no window")
        prepare(app)
        // Park the pointer over the empty part of the editor. Where the last click left it, it can rest on the sidebar
        // or the toolbar, and its tooltip ("Hide Sidebar") then shows in the picture.
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).hover()

        // Let the first layout, the glass material and the selection highlight settle before the picture is taken.
        Thread.sleep(forTimeInterval: 1.0)

        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
