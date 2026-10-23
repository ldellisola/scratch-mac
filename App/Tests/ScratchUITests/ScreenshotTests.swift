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
/// `recently-deleted-light`, `formatting-light`, `formatting-dark`, `code-light`, `code-dark`, `attachments-light`,
/// `attachments-dark`, the two with Increase Contrast on, `typical-contrast-light` and `code-contrast-dark` (plan 6
/// task 8), and `about-light`, the About panel with the app icon (plan 6 task 9). The Makefile's `SCREENSHOT_NAMES` lists
/// them and must stay in step with this class.
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

    /// The attachments fixture (plan 5, task 8): the note "Screenshots" holds a line of text, an image, a line of text and
    /// the file "rollback-plan.txt". The test waits until both attachments are in place and every preview is decoded, and
    /// a person (or an agent that opens the PNG) checks: the image drawn with rounded corners and a hairline, scaled as
    /// the rules say (as wide as the text up to its own width, at most 240 pt high), a chip with the text file's Finder
    /// icon, "rollback-plan.txt" and its size, no token text anywhere, and in the sidebar the title "Screenshots" with
    /// a preview line that has no token in it. The caret is at the top of the note, so no attachment is selected.
    func testAttachmentsLight() {
        capture("attachments-light", fixture: "attachments", appearance: "light", sidebarRows: 1) { app in
            waitForAttachments(in: app)
        }
    }

    /// The same note in dark mode: the chip's tint, the preview's hairline and the icon on a dark background.
    func testAttachmentsDark() {
        capture("attachments-dark", fixture: "attachments", appearance: "dark", sidebarRows: 1) { app in
            waitForAttachments(in: app)
        }
    }

    /// The typical fixture with Increase Contrast on (`-ScratchAppearance light-contrast`: the accessibility appearance that the
    /// high contrast variants of the colours answer to, plan 6 task 8). A person (or an agent that opens the PNG) checks: the
    /// inline code's pill and the block's tint and border stronger than in `typical-light`, the code in darker colours, and
    /// the glass of the toolbar and the sidebar still the system's.
    func testTypicalContrastLight() {
        capture("typical-contrast-light", fixture: "typical", appearance: "light-contrast", sidebarRows: 6)
    }

    /// The code fixture with Increase Contrast on, in dark mode: the lighter code colours on the stronger tint, a visible
    /// border, and labels that read.
    func testCodeContrastDark() {
        capture("code-contrast-dark", fixture: "code", appearance: "dark-contrast", sidebarRows: 1) { app in
            waitForColours(in: app)
        }
    }

    /// The About panel (plan 6 task 9): Scratch > About Scratch, with the app's icon, its name and version and the licences
    /// of tree-sitter and its grammars as credits. The picture is of the panel, not of the main window. A person (or an agent
    /// that opens the PNG) checks: the new icon (a yellow notepad with a ticked checkbox) and not the generic one, the
    /// version 1.0.0 and the credits' first lines. XCTest sees the panel as a dialog of the app (`aboutPanel(in:)`).
    func testAboutLight() {
        capture(
            "about-light", fixture: "typical", appearance: "light", sidebarRows: 6, parkPointer: false,
            prepare: { app in
                app.menuBars.menuBarItems["Scratch"].click()
                app.menuBars.menuItems["About Scratch"].click()
                XCTAssertTrue(
                    UITestSupport.wait { aboutPanel(in: app) != nil },
                    "the About panel did not appear: \(UITestSupport.hierarchy(of: app))")
            },
            subject: { app in aboutPanel(in: app) ?? app.windows.firstMatch },
            // Looked at once the picture is taken, so that a surprise here never costs the picture. It reads the texts of the
            // panel and asks for no predicate: a predicate on `value` meets the scroll bar's number.
            afterwards: { app in
                let texts =
                    aboutPanel(in: app)?.staticTexts.allElementsBoundByIndex.map { UITestSupport.text(of: $0) } ?? []
                XCTAssertTrue(
                    texts.contains { $0.hasPrefix("Version") }, "the About panel shows no version, its texts: \(texts)")
            })
    }

    /// The About panel, or nil while it is not on screen. XCTest reports it as a Dialog (its subrole is `AXDialog`) and not as
    /// a window, with no title and an identifier of AppKit's own (`_NS:154` on CI), so it is the app's only dialog: the
    /// Launch Times alert is a sheet.
    private func aboutPanel(in app: XCUIApplication) -> XCUIElement? {
        let panel = app.dialogs.firstMatch
        return panel.exists ? panel : nil
    }

    /// Waits until the app has both attachments of the note in place (`debug.state`: each one `copied`, with its file on
    /// disk) and no preview is waiting to be decoded, then checks what the sidebar says about the note: the title
    /// "Screenshots" and a preview line without a token (titles and previews skip attachment lines).
    private func waitForAttachments(in app: XCUIApplication) {
        func attachments() -> [[String: Any]] {
            UITestSupport.debugState(in: app)["attachments"] as? [[String: Any]] ?? []
        }
        XCTAssertTrue(
            UITestSupport.wait(timeout: 20) {
                let rows = attachments()
                return rows.count == 2
                    && rows.allSatisfy { ($0["copied"] as? Bool) == true && ($0["fileExists"] as? Bool) == true }
                    && UITestSupport.debugState(in: app)["pendingPreviews"] as? Int == 0
            },
            "the attachments were not in place and decoded: \(UITestSupport.debugState(in: app))")
        XCTAssertEqual(UITestSupport.sidebarTitleTexts(in: app), ["Screenshots"])
        let previews = UITestSupport.sidebarPreviewTexts(in: app)
        XCTAssertEqual(previews.count, 1, "the sidebar previews: \(previews)")
        XCTAssertTrue(
            previews.allSatisfy { $0.contains("The dashboard after the deploy.") && !$0.contains("[[attachment:") },
            "the sidebar preview shows a token or lacks the text: \(previews)")
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
    /// screenshot of `subject` (the main window unless a test says otherwise) as `name`, kept even though the test
    /// passes. `parkPointer` is false for a picture of something that is not the main window (the pointer is then left where
    /// the preparation put it). `afterwards` runs once the screenshot is attached. `prepare` comes first among the closures, so that a trailing
    /// closure is the preparation (Swift gives an unlabeled trailing closure to the first closure parameter).
    private func capture(
        _ name: String, fixture: String, appearance: String, sidebarRows: Int, parkPointer: Bool = true,
        prepare: @MainActor (XCUIApplication) -> Void = { _ in },
        subject: @MainActor (XCUIApplication) -> XCUIElement = { $0.windows.firstMatch },
        afterwards: @MainActor (XCUIApplication) -> Void = { _ in }
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
        if parkPointer { window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).hover() }

        // Let the first layout, the glass material and the selection highlight settle before the picture is taken.
        Thread.sleep(forTimeInterval: 1.0)

        let screenshot = XCTAttachment(screenshot: subject(app).screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        afterwards(app)
    }
}
