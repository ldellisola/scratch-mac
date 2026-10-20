import XCTest

/// Covers docs/features/autosave-and-restore.md and docs/features/sidebar.md, and spec §6.2, §6.3: the sidebar lists
/// the notes (pinned first, then the most recently edited) under group headers with the edit time on each row, a click
/// shows a note, the toolbar's new note button starts a note that is listed once it has text and is discarded when left
/// untouched, and notes can be pinned and searched. Plan 2 "Review Focus" 1: a pin that is clicked while the note has
/// unsaved typing sticks, and so does the typing.
///
/// The `typical` fixture lists six notes: "Snippets I keep reusing" (pinned), "Deploy checklist" and the curl note (1
/// and 2 hours old), "Standup" and the SQL note (a day old), and "Groceries" (5 days old). The group headers, the
/// titles of the rows and the time labels are different elements with identifiers of their own, so a count of the
/// titles counts rows only.
@MainActor
final class SidebarUITests: XCTestCase {
    /// Launches `typical` and waits until the sidebar lists its six notes.
    private func launchTypical() -> XCUIApplication {
        let app = UITestSupport.launch(fixture: "typical")
        XCTAssertTrue(
            UITestSupport.wait(timeout: 20) { UITestSupport.sidebarTitleTexts(in: app).count == 6 },
            "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: app))")
        return app
    }

    /// Waits until the sidebar's rows, from top to bottom, are exactly `titles`.
    private func waitForRows(
        _ titles: [String], in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let shown = UITestSupport.wait { UITestSupport.sidebarTitleTexts(in: app) == titles }
        XCTAssertTrue(
            shown, "expected the rows \(titles) and found: \(UITestSupport.sidebarTitleTexts(in: app))", file: file,
            line: line)
    }

    /// Waits until the first rows of the sidebar, from the top, are `titles`, and the rows after them do not matter.
    private func waitForFirstRows(
        _ titles: [String], in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let shown = UITestSupport.wait {
            Array(UITestSupport.sidebarTitleTexts(in: app).prefix(titles.count)) == titles
        }
        XCTAssertTrue(
            shown, "expected the rows to start with \(titles) and found: \(UITestSupport.sidebarTitleTexts(in: app))",
            file: file, line: line)
    }

    /// Quits with ⌘Q, which writes everything that is unsaved, and waits until the app is gone.
    private func quit(_ app: XCUIApplication) {
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "the app did not quit")
    }

    /// Clicks the row of "Groceries" and waits until the editor shows it, so that it is the note of the active tab.
    private func openGroceries(in app: XCUIApplication) {
        let row = UITestSupport.sidebarRow(titled: "Groceries", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the sidebar has no row titled Groceries")
        row.click()
        let editor = UITestSupport.editor(in: app)
        let shown = UITestSupport.wait { (editor.value as? String ?? "").contains("milk, eggs") }
        XCTAssertTrue(shown, "the editor shows: \(editor.value as? String ?? "")")
    }

    func testSidebarListsFixtureNotesPinnedFirst() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "typical")
        XCTAssertTrue(
            UITestSupport.wait { UITestSupport.sidebarTitleTexts(in: app).count == 6 },
            "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: app))")

        let titles = UITestSupport.sidebarTitleTexts(in: app)
        XCTAssertEqual(titles.first, "Snippets I keep reusing", "the sidebar rows: \(titles)")
        XCTAssertEqual(titles.dropFirst().first, "Deploy checklist", "the sidebar rows: \(titles)")
    }

    func testClickingRowShowsNote() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "typical")
        let row = UITestSupport.sidebarRow(titled: "Groceries", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the sidebar has no row titled Groceries")

        row.click()

        let editor = UITestSupport.editor(in: app)
        let shown = UITestSupport.wait { (editor.value as? String ?? "").contains("milk, eggs") }
        XCTAssertTrue(shown, "the editor shows: \(editor.value as? String ?? "")")
    }

    func testNewNoteButtonCreatesListedNote() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "typical")
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor text view did not appear")
        let button = UITestSupport.newNoteButton(in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 10), "the toolbar has no new note button")

        button.click()
        editor.typeText("fresh idea")

        let row = UITestSupport.sidebarRow(titleContaining: "fresh idea", in: app)
        XCTAssertTrue(
            row.waitForExistence(timeout: 3), "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: app))")
    }

    func testUntouchedNewNoteIsDiscarded() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "typical")
        let button = UITestSupport.newNoteButton(in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 10), "the toolbar has no new note button")
        XCTAssertTrue(
            UITestSupport.wait { UITestSupport.sidebarTitleTexts(in: app).count == 6 },
            "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: app))")

        button.click()
        let groceries = UITestSupport.sidebarRow(titled: "Groceries", in: app)
        XCTAssertTrue(groceries.waitForExistence(timeout: 10), "the sidebar has no row titled Groceries")
        groceries.click()

        // Leaving the untouched note discards it. Give the sidebar time to reload before looking at it.
        let editor = UITestSupport.editor(in: app)
        let shown = UITestSupport.wait { (editor.value as? String ?? "").contains("milk, eggs") }
        XCTAssertTrue(shown, "the editor shows: \(editor.value as? String ?? "")")
        Thread.sleep(forTimeInterval: 1.0)
        let titles = UITestSupport.sidebarTitleTexts(in: app)
        XCTAssertEqual(titles.count, 6, "the sidebar rows: \(titles)")
        XCTAssertFalse(titles.contains { $0.isEmpty || $0 == "Untitled" }, "the sidebar rows: \(titles)")
    }

    // MARK: Groups

    func testGroupHeadersInOrder() throws {
        continueAfterFailure = false
        let app = launchTypical()

        let groups = UITestSupport.sidebarGroupTitles(in: app)
        // The fixture's two newest notes are 1 and 2 hours old, so in the first hour after midnight they are
        // yesterday's, and there is no Today group (the test also gives the app a minute to seed its notes).
        let sinceMidnight = Date().timeIntervalSince(Calendar.current.startOfDay(for: Date()))
        let all = ["Pinned", "Today", "Yesterday", "Earlier"]
        if sinceMidnight > 3600 + 120 {
            XCTAssertEqual(groups, all)
        } else {
            XCTAssertTrue(groups == all || groups == ["Pinned", "Yesterday", "Earlier"], "the groups: \(groups)")
        }
    }

    func testRowShowsTimeLabel() throws {
        continueAfterFailure = false
        let app = launchTypical()
        let title = UITestSupport.sidebarRow(titled: "Groceries", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the sidebar has no row titled Groceries")

        let time = UITestSupport.sidebarRowTime(besides: title, in: app)
        XCTAssertFalse((time ?? "").isEmpty, "the time label of the Groceries row: \(String(describing: time))")
    }

    // MARK: Pinning

    func testPinButtonMovesNoteToPinned() throws {
        continueAfterFailure = false
        let app = launchTypical()
        openGroceries(in: app)
        let pin = UITestSupport.pinButton(in: app)
        XCTAssertTrue(pin.waitForExistence(timeout: 10), "the toolbar has no pin button")

        pin.click()

        // Pinned notes come first, the most recently edited of them at the top.
        waitForFirstRows(["Groceries", "Snippets I keep reusing"], in: app)
        XCTAssertEqual(UITestSupport.sidebarGroupTitles(in: app).first, "Pinned")
    }

    func testShiftCommandPTogglesPin() throws {
        continueAfterFailure = false
        let app = launchTypical()
        openGroceries(in: app)

        app.typeKey("p", modifierFlags: [.command, .shift])
        waitForFirstRows(["Groceries", "Snippets I keep reusing"], in: app)

        app.typeKey("p", modifierFlags: [.command, .shift])
        waitForFirstRows(["Snippets I keep reusing", "Deploy checklist"], in: app)
    }

    func testContextMenuUnpins() throws {
        continueAfterFailure = false
        let app = launchTypical()
        let row = UITestSupport.sidebarRow(titleContaining: "Snippets", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the sidebar has no Snippets row")
        XCTAssertEqual(UITestSupport.sidebarGroupTitles(in: app).first, "Pinned")

        row.rightClick()
        let unpin = app.menuItems["Unpin"]
        XCTAssertTrue(unpin.waitForExistence(timeout: 5), "the row's context menu has no Unpin item")
        unpin.click()

        let gone = UITestSupport.wait { !UITestSupport.sidebarGroupTitles(in: app).contains("Pinned") }
        XCTAssertTrue(gone, "the groups: \(UITestSupport.sidebarGroupTitles(in: app))")
        XCTAssertEqual(UITestSupport.sidebarTitleTexts(in: app).count, 6)
    }

    /// Plan 2 "Review Focus" 1: the typing is still unsaved when the pin is clicked, and neither undoes the other.
    func testPinWhileTypingSticks() throws {
        continueAfterFailure = false
        let app = launchTypical()
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor text view did not appear")
        let before = editor.value as? String ?? ""
        let pin = UITestSupport.pinButton(in: app)
        XCTAssertTrue(pin.waitForExistence(timeout: 10), "the toolbar has no pin button")

        editor.typeText("x")
        pin.click()
        Thread.sleep(forTimeInterval: 2)
        quit(app)

        let relaunched = UITestSupport.relaunch(sameDataAs: app)
        XCTAssertTrue(
            UITestSupport.wait(timeout: 20) { UITestSupport.sidebarTitleTexts(in: relaunched).count == 6 },
            "the sidebar rows after relaunch: \(UITestSupport.sidebarTitleTexts(in: relaunched))")
        // Both are pinned now, and "Deploy checklist" was edited last.
        let titles = UITestSupport.sidebarTitleTexts(in: relaunched)
        XCTAssertEqual(Array(titles.prefix(2)), ["Deploy checklist", "Snippets I keep reusing"], "the rows: \(titles)")
        XCTAssertEqual(UITestSupport.sidebarGroupTitles(in: relaunched).first, "Pinned")
        let restored = UITestSupport.editor(in: relaunched)
        let kept = UITestSupport.wait { (restored.value as? String ?? "").contains("bump version") }
        XCTAssertTrue(kept, "the editor after relaunch shows: \(restored.value as? String ?? "")")
        let letters: (String) -> Int = { $0.filter { $0 == "x" }.count }
        XCTAssertEqual(letters(restored.value as? String ?? ""), letters(before) + 1, "the typed x is missing")
    }

    // MARK: Search

    /// Types `text` into the sidebar's search field.
    private func search(_ text: String, in app: XCUIApplication) -> XCUIElement {
        let field = UITestSupport.searchField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the sidebar has no search field")
        field.click()
        field.typeText(text)
        return field
    }

    func testSearchFiltersByBodyText() throws {
        continueAfterFailure = false
        let app = launchTypical()

        _ = search("kubectl", in: app)

        waitForRows(["Deploy checklist"], in: app)
    }

    func testSearchMatchesTitlesCaseInsensitively() throws {
        continueAfterFailure = false
        let app = launchTypical()

        _ = search("GROCER", in: app)

        waitForRows(["Groceries"], in: app)
    }

    func testClearingSearchRestoresList() throws {
        continueAfterFailure = false
        let app = launchTypical()
        let field = search("kubectl", in: app)
        waitForRows(["Deploy checklist"], in: app)

        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])

        let restored = UITestSupport.wait { UITestSupport.sidebarTitleTexts(in: app).count == 6 }
        XCTAssertTrue(restored, "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: app))")
        XCTAssertTrue(UITestSupport.sidebarGroupTitles(in: app).contains("Earlier"))
    }

    func testEscapeClearsSearch() throws {
        continueAfterFailure = false
        let app = launchTypical()
        let field = search("kubectl", in: app)
        waitForRows(["Deploy checklist"], in: app)

        field.typeKey(.escape, modifierFlags: [])

        let restored = UITestSupport.wait { UITestSupport.sidebarTitleTexts(in: app).count == 6 }
        XCTAssertTrue(restored, "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: app))")
        XCTAssertEqual(field.value as? String ?? "", "")
    }
}
