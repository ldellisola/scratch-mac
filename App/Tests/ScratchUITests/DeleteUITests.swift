import XCTest

/// Covers docs/features/recently-deleted.md and spec §6.2, §6.7: deleting a note from the sidebar, the Recently Deleted
/// section (collapsed, with a count, expanded by a click on its header), restoring, deleting for good after a question,
/// reading a deleted note without being able to change it, and the purge of notes that were deleted more than 30 days
/// ago. Plan 2 "Review Focus" 2: ⌘⌫ typed in the editor deletes text and never the note. Review Focus 5: deleting the
/// note in the only tab leaves one tab with a new empty note that the sidebar does not list. Review Focus 1: deleting a
/// note while its typing is unsaved keeps the typing.
///
/// Two fixtures. `typical` lists six notes and opens two tabs: "Deploy checklist" (active) and the untitled curl note.
/// `recently-deleted` lists "Groceries" (open in its one tab) and holds two deleted notes: "Old meeting notes" (deleted 2
/// days ago) and "Ancient" (deleted 31 days ago), which the purge removes at launch, so the header settles on "Recently
/// Deleted (1)". The header of Recently Deleted has its own accessibility identifier (`UITestSupport.
/// recentlyDeletedHeader(in:)`) and the group headers do not count it.
@MainActor
final class DeleteUITests: XCTestCase {
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

    /// Launches `recently-deleted` and waits until the purge has run: the header says one deleted note, and not two.
    private func launchRecentlyDeleted() -> XCUIApplication {
        let app = UITestSupport.launch(fixture: "recently-deleted")
        XCTAssertTrue(
            UITestSupport.sidebarRow(titled: "Groceries", in: app).waitForExistence(timeout: 20),
            "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: app))")
        waitForHeader("Recently Deleted (1)", in: app)
        return app
    }

    /// Waits until the Recently Deleted header reads `text`, and fails with what it reads when it does not.
    private func waitForHeader(
        _ text: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let header = UITestSupport.recentlyDeletedHeader(in: app)
        let shown = UITestSupport.wait(timeout: 20) { header.exists && UITestSupport.text(of: header) == text }
        XCTAssertTrue(
            shown,
            "expected the header \"\(text)\" and found: \(header.exists ? UITestSupport.text(of: header) : "no header")",
            file: file, line: line)
    }

    /// Waits until the sidebar has no Recently Deleted header, which is when no note is deleted.
    private func waitForNoHeader(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let header = UITestSupport.recentlyDeletedHeader(in: app)
        let gone = UITestSupport.wait { !header.exists }
        XCTAssertTrue(
            gone, "expected no Recently Deleted header and found: \(UITestSupport.text(of: header))", file: file,
            line: line)
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

    /// Waits until the app shows exactly the tabs `titles`, from left to right.
    private func waitForTabs(
        _ titles: [String], in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let shown = UITestSupport.wait { UITestSupport.tabTitles(in: app) == titles }
        XCTAssertTrue(
            shown, "expected the tabs \(titles) and found: \(UITestSupport.tabTitles(in: app))", file: file,
            line: line)
    }

    /// Clicks the header of Recently Deleted, which shows the deleted notes under it, or hides them again.
    private func clickHeader(in app: XCUIApplication) {
        let header = UITestSupport.recentlyDeletedHeader(in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 10), "the sidebar has no Recently Deleted header")
        header.click()
    }

    /// Right-clicks `row` (a title element from `UITestSupport.sidebarRow`) and chooses `item` in its context menu.
    private func chooseFromMenu(
        _ item: String, ofRow row: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the sidebar has no such row", file: file, line: line)
        row.rightClick()
        let menuItem = app.menuItems[item]
        XCTAssertTrue(
            menuItem.waitForExistence(timeout: 5), "the row's context menu has no \(item) item", file: file,
            line: line)
        menuItem.click()
    }

    /// The editor's text, "" for an empty note.
    private func editorText(in app: XCUIApplication) -> String {
        UITestSupport.editor(in: app).value as? String ?? ""
    }

    /// Waits until the editor shows text that contains `fragment`.
    private func waitForEditorText(
        containing fragment: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let shown = UITestSupport.wait { self.editorText(in: app).contains(fragment) }
        XCTAssertTrue(shown, "the editor shows: \(editorText(in: app))", file: file, line: line)
    }

    /// Waits until the editor reports that its note is read-only (`true`) or editable (`false`).
    private func waitForReadOnly(
        _ readOnly: Bool, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let reached = UITestSupport.wait { UITestSupport.debugState(in: app)["readOnly"] as? Bool == readOnly }
        XCTAssertTrue(
            reached, "expected readOnly == \(readOnly) and found: \(UITestSupport.debugState(in: app))", file: file,
            line: line)
    }

    /// Quits with ⌘Q, which writes everything that is unsaved, and waits until the app is gone.
    private func quit(_ app: XCUIApplication) {
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "the app did not quit")
    }

    // MARK: Deleting

    func testContextMenuDeleteMovesNoteToRecentlyDeleted() throws {
        continueAfterFailure = false
        let app = launchTypical()

        chooseFromMenu("Delete", ofRow: UITestSupport.sidebarRow(titled: "Groceries", in: app), in: app)

        let gone = UITestSupport.wait { !UITestSupport.sidebarTitleTexts(in: app).contains("Groceries") }
        XCTAssertTrue(gone, "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: app))")
        XCTAssertEqual(UITestSupport.sidebarTitleTexts(in: app).count, 5)
        waitForHeader("Recently Deleted (1)", in: app)
    }

    func testCommandBackspaceInSidebarDeletes() throws {
        continueAfterFailure = false
        let app = launchTypical()
        let row = UITestSupport.sidebarRow(titled: "Groceries", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the sidebar has no row titled Groceries")
        row.click()
        waitForEditorText(containing: "milk, eggs", in: app)

        // The click gave the keyboard to the sidebar, so ⌘⌫ deletes the highlighted note.
        app.typeKey(.delete, modifierFlags: .command)

        let gone = UITestSupport.wait { !UITestSupport.sidebarTitleTexts(in: app).contains("Groceries") }
        XCTAssertTrue(gone, "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: app))")
        waitForHeader("Recently Deleted (1)", in: app)
        // The click had opened Groceries in the first tab, and deleting it closed that tab.
        waitForTabs([Self.curlTitle], in: app)
    }

    /// Plan 2 "Review Focus" 2: ⌘⌫ in the editor is the text system's "delete to the start of the line". A menu key
    /// equivalent for deleting the note would take it from the editor.
    func testCommandBackspaceInEditorKeepsNote() throws {
        continueAfterFailure = false
        let app = launchTypical()
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor text view did not appear")
        let firstLine: () -> String = {
            self.editorText(in: app).split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init)
                ?? ""
        }

        // The cursor is at the start of the note, so ⌘→ moves it to the end of the first line.
        app.typeKey(.rightArrow, modifierFlags: .command)
        editor.typeText("abc")
        XCTAssertTrue(
            UITestSupport.wait { firstLine().hasSuffix("abc") }, "the first line of the editor: \(firstLine())")

        app.typeKey(.delete, modifierFlags: .command)

        XCTAssertTrue(
            UITestSupport.wait { !firstLine().hasSuffix("abc") }, "the first line of the editor: \(firstLine())")
        // Give a wrong deletion of the note time to show before looking at the list.
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(
            UITestSupport.sidebarTitleTexts(in: app).count, 6, "the rows: \(UITestSupport.sidebarTitleTexts(in: app))")
        XCTAssertFalse(UITestSupport.recentlyDeletedHeader(in: app).exists, "a note was deleted")
        XCTAssertEqual(UITestSupport.tabs(in: app).count, 2, "the tabs: \(UITestSupport.tabTitles(in: app))")
    }

    func testDeletingOpenNoteClosesItsTab() throws {
        continueAfterFailure = false
        let app = launchTypical()

        chooseFromMenu("Delete", ofRow: UITestSupport.sidebarRow(titleContaining: "curl -X POST", in: app), in: app)

        waitForTabs(["Deploy checklist"], in: app)
        waitForHeader("Recently Deleted (1)", in: app)
        XCTAssertEqual(UITestSupport.sidebarTitleTexts(in: app).count, 5)
        XCTAssertFalse(UITestSupport.sidebarTitleTexts(in: app).contains { $0.hasPrefix("curl") })
        // The note in the editor is still the one of the tab that is left.
        waitForEditorText(containing: "bump version to", in: app)
    }

    /// Plan 2 "Review Focus" 5.
    func testDeletingNoteInOnlyTabLeavesEmptyNote() throws {
        continueAfterFailure = false
        let app = launchTypical()
        app.typeKey("w", modifierFlags: .command)
        waitForTabs(["Deploy checklist"], in: app)

        chooseFromMenu("Delete", ofRow: UITestSupport.sidebarRow(titled: "Deploy checklist", in: app), in: app)

        waitForTabs(["Untitled"], in: app)
        XCTAssertEqual(editorText(in: app), "", "the editor of the new note")
        waitForHeader("Recently Deleted (1)", in: app)
        // Give the sidebar time to reload: a leftover empty note would be listed by then.
        Thread.sleep(forTimeInterval: 1.0)
        let rows = UITestSupport.sidebarTitleTexts(in: app)
        XCTAssertEqual(rows.count, 5, "the sidebar rows: \(rows)")
        XCTAssertFalse(rows.contains { $0.isEmpty || $0 == "Untitled" || $0 == "Deploy checklist" }, "rows: \(rows)")
    }

    /// Plan 2 "Review Focus" 1: the typing is still unsaved when the note is deleted, and it is not lost.
    func testDeleteWhileTypingKeepsTheTyping() throws {
        continueAfterFailure = false
        let app = launchTypical()
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor text view did not appear")

        editor.typeText("zq9")
        chooseFromMenu("Delete", ofRow: UITestSupport.sidebarRow(titled: "Deploy checklist", in: app), in: app)
        waitForHeader("Recently Deleted (1)", in: app)

        clickHeader(in: app)
        let row = UITestSupport.sidebarRow(titled: "Deploy checklist", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the deleted note is not listed")
        row.click()

        waitForEditorText(containing: "zq9", in: app)
        waitForReadOnly(true, in: app)
    }

    // MARK: Recently Deleted

    func testRecentlyDeletedStartsCollapsedAndToggles() throws {
        continueAfterFailure = false
        let app = launchRecentlyDeleted()
        waitForRows(["Groceries"], in: app)

        clickHeader(in: app)
        waitForRows(["Groceries", "Old meeting notes"], in: app)
        // The count stays what it was: it counts the deleted notes, shown or not.
        waitForHeader("Recently Deleted (1)", in: app)

        clickHeader(in: app)
        waitForRows(["Groceries"], in: app)
    }

    func testRestoreBringsNoteBack() throws {
        continueAfterFailure = false
        let app = launchRecentlyDeleted()
        clickHeader(in: app)
        waitForRows(["Groceries", "Old meeting notes"], in: app)

        chooseFromMenu("Restore", ofRow: UITestSupport.sidebarRow(titled: "Old meeting notes", in: app), in: app)

        // Nothing is deleted any more, so the header is gone, and the note is a live one in the "Earlier" group.
        waitForNoHeader(in: app)
        waitForRows(["Groceries", "Old meeting notes"], in: app)
        XCTAssertTrue(
            UITestSupport.wait { UITestSupport.sidebarGroupTitles(in: app).contains("Earlier") },
            "the groups: \(UITestSupport.sidebarGroupTitles(in: app))")
    }

    /// "Restoring makes it editable in place": the note stays in its tab, and its tab is no longer dimmed.
    func testRestoringOpenNoteMakesItEditable() throws {
        continueAfterFailure = false
        let app = launchRecentlyDeleted()
        clickHeader(in: app)
        let row = UITestSupport.sidebarRow(titled: "Old meeting notes", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the deleted note is not listed")
        row.click()
        waitForEditorText(containing: "agenda: roadmap review", in: app)
        waitForReadOnly(true, in: app)

        chooseFromMenu("Restore", ofRow: row, in: app)

        waitForReadOnly(false, in: app)
        XCTAssertEqual(UITestSupport.activeTabTitle(in: app), "Old meeting notes")
        let editor = UITestSupport.editor(in: app)
        editor.click()
        editor.typeText("zq9")
        waitForEditorText(containing: "zq9", in: app)
    }

    func testDeletePermanentlyAsksThenRemoves() throws {
        continueAfterFailure = false
        let app = launchRecentlyDeleted()
        clickHeader(in: app)
        let row = UITestSupport.sidebarRow(titled: "Old meeting notes", in: app)

        // Cancel keeps the note.
        chooseFromMenu("Delete Permanently…", ofRow: row, in: app)
        let cancel = sheetButton("Cancel", in: app)
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "no question was asked")
        let question = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "permanently", "permanently")
        ).firstMatch
        XCTAssertTrue(question.exists, "the question does not say what it asks: \(app.staticTexts.debugDescription)")
        XCTAssertTrue(
            UITestSupport.text(of: question).contains("Old meeting notes"),
            "the question: \(UITestSupport.text(of: question))")
        cancel.click()
        XCTAssertTrue(UITestSupport.wait { !app.sheets.firstMatch.exists }, "the question did not go away")
        waitForRows(["Groceries", "Old meeting notes"], in: app)
        waitForHeader("Recently Deleted (1)", in: app)

        // Delete removes it.
        chooseFromMenu("Delete Permanently…", ofRow: row, in: app)
        let delete = sheetButton("Delete", in: app)
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "no question was asked")
        delete.click()

        waitForNoHeader(in: app)
        waitForRows(["Groceries"], in: app)
    }

    /// A button of the question that "Delete Permanently…" asks, which is a sheet on the window.
    private func sheetButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let inSheet = app.sheets.buttons[title]
        return inSheet.waitForExistence(timeout: 5) ? inSheet : app.buttons[title]
    }

    func testDeletedNoteIsReadOnly() throws {
        continueAfterFailure = false
        let app = launchRecentlyDeleted()
        clickHeader(in: app)
        let row = UITestSupport.sidebarRow(titled: "Old meeting notes", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the deleted note is not listed")

        row.click()

        // The deleted note is shown in the tab that was open, which is dimmed, and nothing can change it.
        waitForEditorText(containing: "agenda: roadmap review", in: app)
        waitForReadOnly(true, in: app)
        waitForTabs(["Old meeting notes"], in: app)
        let before = editorText(in: app)
        // A title field that cannot be edited is a static text for accessibility, so it is looked up as any element.
        let titleField = app.descendants(matching: .any).matching(identifier: AccessibilityID.titleField).firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "the title field did not appear")
        let titleBefore = UITestSupport.text(of: titleField)
        XCTAssertEqual(titleBefore, "Old meeting notes")
        UITestSupport.editor(in: app).click()
        app.typeKey("q", modifierFlags: [])
        titleField.click()
        app.typeKey("q", modifierFlags: [])
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(editorText(in: app), before, "the editor after typing")
        XCTAssertEqual(UITestSupport.text(of: titleField), titleBefore, "the title field after typing")
        // The pin does not work on a deleted note.
        XCTAssertFalse(UITestSupport.pinButton(in: app).isEnabled, "the pin button is enabled")
    }

    /// "A tab showing a deleted note is dropped at relaunch" (spec §6.6): a deleted note is not restored in a tab.
    func testDeletedNoteTabIsDroppedAtRelaunch() throws {
        continueAfterFailure = false
        let app = launchRecentlyDeleted()
        clickHeader(in: app)
        let row = UITestSupport.sidebarRow(titled: "Old meeting notes", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the deleted note is not listed")
        row.click()
        waitForEditorText(containing: "agenda: roadmap review", in: app)
        quit(app)

        let relaunched = UITestSupport.relaunch(sameDataAs: app)
        XCTAssertTrue(
            UITestSupport.wait(timeout: 20) { UITestSupport.tabTitles(in: relaunched) == ["Untitled"] },
            "the tabs after relaunch: \(UITestSupport.tabTitles(in: relaunched))")
        XCTAssertEqual(editorText(in: relaunched), "", "the editor after relaunch")
        // Nothing was restored or deleted for good by the relaunch: Groceries is live, and one note is deleted.
        XCTAssertTrue(
            UITestSupport.sidebarRow(titled: "Groceries", in: relaunched).waitForExistence(timeout: 10),
            "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: relaunched))")
        waitForHeader("Recently Deleted (1)", in: relaunched)
    }

    func testExpiredNotesArePurgedAtLaunch() throws {
        continueAfterFailure = false
        // `launchRecentlyDeleted` returns once the header says one note: "Ancient", deleted 31 days ago, is purged.
        let app = launchRecentlyDeleted()

        clickHeader(in: app)

        waitForRows(["Groceries", "Old meeting notes"], in: app)
        XCTAssertFalse(UITestSupport.sidebarRow(titled: "Ancient", in: app).exists, "Ancient is still listed")
    }
}
