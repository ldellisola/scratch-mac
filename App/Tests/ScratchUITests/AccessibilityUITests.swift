import XCTest

/// Covers docs/features/accessibility.md and spec §6.1 (plan 6 task 8): what VoiceOver and the keyboard find in the window.
/// The toolbar's buttons, the editor and the title have labels, a sidebar row is one element that reads its title, time and
/// preview (its three texts are still there, with their identifiers), the close button of a tab names the tab, the header of
/// Recently Deleted is a button that says how many notes it holds and whether they are shown, and Tab moves the keyboard
/// from the search field to the note list, the title and the editor.
///
/// The `typical` fixture lists six notes, and opens "Deploy checklist" and the curl note in two tabs. `recently-deleted`
/// lists "Groceries" and, once the purge has run, holds one deleted note.
@MainActor
final class AccessibilityUITests: XCTestCase {
    private static let curlTitle = #"curl -X POST https://api.local/v1/notes \"#

    /// Launches `typical` and waits until its two tabs and six sidebar rows are shown.
    private func launchTypical() -> XCUIApplication {
        let app = UITestSupport.launch(fixture: "typical")
        XCTAssertTrue(
            UITestSupport.wait(timeout: 20) { UITestSupport.tabs(in: app).count == 2 },
            "the tabs at launch: \(UITestSupport.tabTitles(in: app))")
        XCTAssertTrue(
            UITestSupport.wait { UITestSupport.sidebarTitleTexts(in: app).count == 6 },
            "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: app))\n\(UITestSupport.hierarchy(of: app))")
        return app
    }

    /// Waits until `debug.state` says that `expected` has the keyboard, and fails with what has it when nothing does.
    private func waitForFirstResponder(
        _ expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let reached = UITestSupport.wait { UITestSupport.firstResponder(in: app) == expected }
        XCTAssertTrue(
            reached, "expected \(expected) to have the keyboard, and \(UITestSupport.firstResponder(in: app)) has it",
            file: file, line: line)
    }

    // MARK: Labels

    func testToolbarButtonsHaveLabels() throws {
        continueAfterFailure = false
        let app = launchTypical()
        // A toolbar item without a view reports its label as the label or the title.
        let buttons: [(XCUIElement, String)] = [
            (UITestSupport.pinButton(in: app), "Pin"), (UITestSupport.attachButton(in: app), "Attach File"),
            (UITestSupport.newNoteButton(in: app), "New Note"),
        ]
        for (button, name) in buttons {
            XCTAssertTrue(button.waitForExistence(timeout: 10), "the toolbar has no \(name) button")
            XCTAssertTrue(
                [button.label, button.title].contains(name),
                "the \(name) button is labelled \(button.label) / \(button.title)")
        }
    }

    func testEditorAndTitleHaveLabels() throws {
        continueAfterFailure = false
        let app = launchTypical()
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor did not appear")
        XCTAssertEqual(editor.label, "Note")
        let title = UITestSupport.titleField(in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the title field did not appear")
        XCTAssertEqual(title.label, "Title")
        XCTAssertEqual(UITestSupport.searchField(in: app).label, "Search")
    }

    func testCloseButtonNamesItsTab() throws {
        continueAfterFailure = false
        let app = launchTypical()
        let titles = UITestSupport.tabTitles(in: app)
        XCTAssertEqual(titles, ["Deploy checklist", Self.curlTitle])
        XCTAssertTrue(UITestSupport.wait { UITestSupport.closeButtons(in: app).count == 2 })

        let labels = UITestSupport.closeButtons(in: app).map { $0.label }
        XCTAssertEqual(labels, titles.map { "Close \($0)" })
    }

    // MARK: The sidebar

    /// A row reads as one element, "<title>, <time>, <preview>", with ", pinned" for a pinned note, and its texts are still
    /// there with their identifiers (the other UI tests read them).
    func testSidebarRowReadsAsOneElement() throws {
        continueAfterFailure = false
        let app = launchTypical()
        let title = UITestSupport.sidebarRow(titled: "Groceries", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the sidebar has no row titled Groceries")
        let time = try XCTUnwrap(UITestSupport.sidebarRowTime(besides: title, in: app), "the row has no time")
        XCTAssertTrue(
            UITestSupport.sidebarPreviewTexts(in: app).contains("milk, eggs, coffee beans"),
            "the previews: \(UITestSupport.sidebarPreviewTexts(in: app))")

        let expected = "Groceries, \(time), milk, eggs, coffee beans"
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", expected)).firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 5),
            "no element reads \"\(expected)\"\n\(UITestSupport.hierarchy(of: app))")

        let pinned = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "Snippets I keep reusing, ", ", pinned")
        ).firstMatch
        XCTAssertTrue(pinned.waitForExistence(timeout: 5), "the pinned row does not say that it is pinned")
        XCTAssertFalse(row.label.hasSuffix(", pinned"), "the row of Groceries is not pinned")
    }

    func testRecentlyDeletedHeaderIsAButton() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "recently-deleted")
        XCTAssertTrue(
            UITestSupport.sidebarRow(titled: "Groceries", in: app).waitForExistence(timeout: 20),
            "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: app))")
        let header = UITestSupport.recentlyDeletedHeader(in: app)
        XCTAssertTrue(
            UITestSupport.wait(timeout: 20) {
                header.exists && UITestSupport.text(of: header) == "Recently Deleted (1)"
            },
            "the header reads: \(header.exists ? UITestSupport.text(of: header) : "nothing")\n"
                + UITestSupport.hierarchy(of: app))

        XCTAssertEqual(header.label, "Recently Deleted, 1 note")
        XCTAssertEqual(header.elementType, .button, UITestSupport.hierarchy(of: app))
        XCTAssertEqual(UITestSupport.text(of: header), "Recently Deleted (1)", "its text is still its value")

        // A click on it shows the deleted notes under it, as before.
        header.click()
        XCTAssertTrue(
            UITestSupport.wait { UITestSupport.sidebarTitleTexts(in: app) == ["Groceries", "Old meeting notes"] },
            "the sidebar rows after the click: \(UITestSupport.sidebarTitleTexts(in: app))")
    }

    // MARK: The key view loop

    func testTabFromSearchReachesTheNoteList() throws {
        continueAfterFailure = false
        let app = launchTypical()
        waitForFirstResponder("editor", in: app)

        // ⌥⌘F puts the keyboard in the search field, and Tab goes on: the note list, the title, the editor.
        app.typeKey("f", modifierFlags: [.command, .option])
        waitForFirstResponder("search", in: app)
        app.typeKey("\t", modifierFlags: [])
        waitForFirstResponder("sidebar", in: app)
        app.typeKey("\t", modifierFlags: [])
        waitForFirstResponder("title", in: app)
        app.typeKey("\t", modifierFlags: [])
        waitForFirstResponder("editor", in: app)
    }
}
