import XCTest

/// Covers docs/features/autosave-and-restore.md and spec §6.2, §6.3: the sidebar lists the notes (pinned first, then
/// the most recently edited), a click shows a note, and the toolbar's new note button starts a note that is listed
/// once it has text and is discarded when left untouched.
@MainActor
final class SidebarUITests: XCTestCase {
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
}
