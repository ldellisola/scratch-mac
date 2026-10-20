import XCTest

/// Covers docs/features/tabs.md and spec §6.3: the tab strip, opening, closing and switching tabs, and the rules that
/// go with them (a note is open in at most one tab, there is always one tab, an empty note that is left is discarded,
/// the tabs come back after a relaunch). Plan 2 "Review Focus" 5: closing the last tab leaves one tab with a new empty
/// note that the sidebar does not list.
///
/// The `typical` fixture opens two tabs: "Deploy checklist" (active) and the untitled curl note. Its sidebar lists six
/// notes. A test types without clicking the editor first, because the editor is first responder at launch and after
/// every tab change.
@MainActor
final class TabsUITests: XCTestCase {
    /// The first line of the curl note, which is the title of its tab and of its sidebar row (it has no title).
    private static let curlTitle = #"curl -X POST https://api.local/v1/notes \"#

    /// Launches `typical` and waits until its two tabs and six sidebar rows are shown.
    private func launchTypical() -> XCUIApplication {
        let app = UITestSupport.launch(fixture: "typical")
        XCTAssertTrue(
            UITestSupport.wait(timeout: 20) { UITestSupport.tabs(in: app).count == 2 },
            "the tabs at launch: \(UITestSupport.tabTitles(in: app))")
        XCTAssertTrue(
            UITestSupport.wait { UITestSupport.sidebarTitleTexts(in: app).count == 6 },
            "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: app))")
        return app
    }

    /// Waits until the app shows `count` tabs, and fails with the titles it shows when it does not.
    private func waitForTabs(_ count: Int, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line)
    {
        let shown = UITestSupport.wait { UITestSupport.tabs(in: app).count == count }
        XCTAssertTrue(
            shown, "expected \(count) tabs and found: \(UITestSupport.tabTitles(in: app))", file: file, line: line)
    }

    /// Waits until the tab at `index` (0 is the leftmost) is the selected one.
    private func waitForActiveTab(
        _ index: Int, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let shown = UITestSupport.wait { UITestSupport.activeTabIndex(in: app) == index }
        XCTAssertTrue(
            shown,
            "expected tab \(index) to be active: tabs \(UITestSupport.tabTitles(in: app)), active tab "
                + "\(String(describing: UITestSupport.activeTabIndex(in: app)))",
            file: file, line: line)
    }

    /// The editor's text, "" for an empty note.
    private func editorText(in app: XCUIApplication) -> String {
        UITestSupport.editor(in: app).value as? String ?? ""
    }

    /// Quits with ⌘Q, which writes everything that is unsaved, and waits until the app is gone.
    private func quit(_ app: XCUIApplication) {
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "the app did not quit")
    }

    func testRestoresBothTabsWithFirstActive() throws {
        continueAfterFailure = false
        let app = launchTypical()

        XCTAssertEqual(UITestSupport.tabTitles(in: app), ["Deploy checklist", Self.curlTitle])
        XCTAssertEqual(UITestSupport.activeTabTitle(in: app), "Deploy checklist")
        XCTAssertTrue(editorText(in: app).contains("bump version to"), "the editor shows: \(editorText(in: app))")
    }

    func testCommandTOpensNewEmptyTab() throws {
        continueAfterFailure = false
        let app = launchTypical()

        app.typeKey("t", modifierFlags: .command)

        waitForTabs(3, in: app)
        waitForActiveTab(2, in: app)
        XCTAssertEqual(editorText(in: app), "", "the new tab's editor")
        // The new tab holds a note nobody has typed in: it is not in the sidebar.
        XCTAssertEqual(UITestSupport.sidebarTitleTexts(in: app).count, 6)
    }

    func testClosingTabKeepsNote() throws {
        continueAfterFailure = false
        let app = launchTypical()
        UITestSupport.tabs(in: app)[1].click()
        waitForActiveTab(1, in: app)

        app.typeKey("w", modifierFlags: .command)

        waitForTabs(1, in: app)
        XCTAssertEqual(UITestSupport.tabTitles(in: app), ["Deploy checklist"])
        let curlRow = UITestSupport.sidebarRow(titleContaining: "curl -X POST", in: app)
        XCTAssertTrue(
            curlRow.waitForExistence(timeout: 5), "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: app))")
    }

    /// Plan 2 "Review Focus" 5.
    func testClosingLastTabLeavesEmptyNote() throws {
        continueAfterFailure = false
        let app = launchTypical()

        app.typeKey("w", modifierFlags: .command)
        waitForTabs(1, in: app)
        app.typeKey("w", modifierFlags: .command)

        let untitled = UITestSupport.wait { UITestSupport.tabTitles(in: app) == ["Untitled"] }
        XCTAssertTrue(untitled, "the tabs: \(UITestSupport.tabTitles(in: app))")
        XCTAssertEqual(editorText(in: app), "", "the editor of the new note")
        // Give the sidebar time to reload: a leftover empty note would be listed by then.
        Thread.sleep(forTimeInterval: 1.0)
        let rows = UITestSupport.sidebarTitleTexts(in: app)
        XCTAssertEqual(rows.count, 6, "the sidebar rows: \(rows)")
        XCTAssertFalse(rows.contains { $0.isEmpty || $0 == "Untitled" }, "the sidebar rows: \(rows)")
    }

    func testCommandClickOpensNoteInNewTab() throws {
        continueAfterFailure = false
        let app = launchTypical()
        let groceries = UITestSupport.sidebarRow(titled: "Groceries", in: app)
        XCTAssertTrue(groceries.waitForExistence(timeout: 10), "the sidebar has no row titled Groceries")

        XCUIElement.perform(withKeyModifiers: .command) { groceries.click() }

        waitForTabs(3, in: app)
        XCTAssertEqual(UITestSupport.activeTabTitle(in: app), "Groceries")
        // The new tab goes right after the active one.
        XCTAssertEqual(UITestSupport.tabTitles(in: app), ["Deploy checklist", "Groceries", Self.curlTitle])
        let shown = UITestSupport.wait { self.editorText(in: app).contains("milk, eggs") }
        XCTAssertTrue(shown, "the editor shows: \(editorText(in: app))")
    }

    func testClickingNoteOpenInOtherTabFocusesIt() throws {
        continueAfterFailure = false
        let app = launchTypical()
        waitForActiveTab(0, in: app)
        let curlRow = UITestSupport.sidebarRow(titleContaining: "curl -X POST", in: app)
        XCTAssertTrue(curlRow.waitForExistence(timeout: 10), "the sidebar has no curl row")

        curlRow.click()

        waitForActiveTab(1, in: app)
        XCTAssertEqual(UITestSupport.tabs(in: app).count, 2, "the tabs: \(UITestSupport.tabTitles(in: app))")
        let shown = UITestSupport.wait { self.editorText(in: app).contains("curl -X POST") }
        XCTAssertTrue(shown, "the editor shows: \(editorText(in: app))")
    }

    func testControlTabCyclesAndWraps() throws {
        continueAfterFailure = false
        let app = launchTypical()
        waitForActiveTab(0, in: app)

        app.typeKey(.tab, modifierFlags: .control)
        waitForActiveTab(1, in: app)
        app.typeKey(.tab, modifierFlags: .control)
        waitForActiveTab(0, in: app)

        // ⌃⇧Tab goes back, and wraps from the first tab to the last.
        app.typeKey(.tab, modifierFlags: [.control, .shift])
        waitForActiveTab(1, in: app)
        app.typeKey(.tab, modifierFlags: [.control, .shift])
        waitForActiveTab(0, in: app)
    }

    func testCommandNineSelectsLastTab() throws {
        continueAfterFailure = false
        let app = launchTypical()
        app.typeKey("t", modifierFlags: .command)
        waitForTabs(3, in: app)
        app.typeKey("1", modifierFlags: .command)
        waitForActiveTab(0, in: app)

        app.typeKey("9", modifierFlags: .command)
        waitForActiveTab(2, in: app)

        app.typeKey("2", modifierFlags: .command)
        waitForActiveTab(1, in: app)
        // A number past the last tab changes nothing.
        app.typeKey("5", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
        waitForActiveTab(1, in: app)
    }

    func testTabsAndActiveTabSurviveRelaunch() throws {
        continueAfterFailure = false
        let app = launchTypical()
        app.typeKey("t", modifierFlags: .command)
        waitForTabs(3, in: app)
        UITestSupport.editor(in: app).typeText("third")
        quit(app)

        let relaunched = UITestSupport.relaunch(sameDataAs: app)
        XCTAssertTrue(
            UITestSupport.wait(timeout: 20) { UITestSupport.tabs(in: relaunched).count == 3 },
            "the tabs after relaunch: \(UITestSupport.tabTitles(in: relaunched))")
        XCTAssertEqual(UITestSupport.tabTitles(in: relaunched), ["Deploy checklist", Self.curlTitle, "third"])
        waitForActiveTab(2, in: relaunched)
        let shown = UITestSupport.wait { self.editorText(in: relaunched) == "third" }
        XCTAssertTrue(shown, "the editor after relaunch shows: \(editorText(in: relaunched))")
    }

    func testUndoSurvivesTabSwitch() throws {
        continueAfterFailure = false
        let app = launchTypical()
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor text view did not appear")
        let original = editorText(in: app)

        editor.typeText("zzz")
        XCTAssertTrue(editorText(in: app).contains("zzz"), "the editor shows: \(editorText(in: app))")
        app.typeKey(.tab, modifierFlags: .control)
        waitForActiveTab(1, in: app)
        app.typeKey(.tab, modifierFlags: [.control, .shift])
        waitForActiveTab(0, in: app)

        // One ⌘Z undoes the typed run when the text system groups it, and a few when it does not. Either way, the
        // history has to be there after the round trip, and undoing it restores the note as it was.
        for _ in 0..<5 where editorText(in: app).contains("zzz") {
            app.typeKey("z", modifierFlags: .command)
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(editorText(in: app), original, "the editor after undo")
    }

    func testUntypedNewTabIsDiscardedOnClose() throws {
        continueAfterFailure = false
        let app = launchTypical()

        app.typeKey("t", modifierFlags: .command)
        waitForTabs(3, in: app)
        app.typeKey("w", modifierFlags: .command)
        waitForTabs(2, in: app)

        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(UITestSupport.sidebarTitleTexts(in: app).count, 6)
        // The note is gone from the database too, and not only from the list: a relaunch lists no empty note.
        quit(app)
        let relaunched = UITestSupport.relaunch(sameDataAs: app)
        XCTAssertTrue(
            UITestSupport.wait(timeout: 20) { UITestSupport.sidebarTitleTexts(in: relaunched).count >= 6 },
            "the sidebar rows after relaunch: \(UITestSupport.sidebarTitleTexts(in: relaunched))")
        let rows = UITestSupport.sidebarTitleTexts(in: relaunched)
        XCTAssertEqual(rows.count, 6, "the sidebar rows after relaunch: \(rows)")
    }
}
