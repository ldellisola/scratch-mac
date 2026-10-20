import XCTest

/// Covers docs/features/title-and-font-size.md and the scroll part of docs/features/autosave-and-restore.md: the
/// title field, the font size and the scroll position (spec §6.4, §6.6). The font size and the scroll anchor are read
/// from the app's `debug.state` element (`UITestSupport.debugState`).
@MainActor
final class TitleUITests: XCTestCase {
    /// Types a title into the open note and presses Return, which moves the cursor to the text.
    private func typeTitle(_ title: String, in app: XCUIApplication) {
        let field = UITestSupport.titleField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the title field did not appear")
        field.click()
        field.typeText(title)
        app.typeKey(.return, modifierFlags: [])
    }

    /// Quits with ⌘Q, which writes everything that is unsaved, and waits until the app is gone.
    private func quit(_ app: XCUIApplication) {
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "the app did not quit")
    }

    func testTitleBecomesSidebarTitle() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "empty")
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor text view did not appear")

        typeTitle("Groceries 2", in: app)
        editor.typeText("milk")

        let row = UITestSupport.sidebarRow(titled: "Groceries 2", in: app)
        XCTAssertTrue(
            row.waitForExistence(timeout: 5), "the sidebar rows: \(UITestSupport.sidebarTitleTexts(in: app))")
        XCTAssertEqual(editor.value as? String, "milk")
    }

    func testTitleSurvivesRelaunch() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "empty")
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor text view did not appear")
        typeTitle("Kept title", in: app)
        editor.typeText("kept text")
        quit(app)

        let relaunched = UITestSupport.relaunch(sameDataAs: app)
        let restored = UITestSupport.editor(in: relaunched)
        XCTAssertTrue(restored.waitForExistence(timeout: 10), "the editor text view did not appear after relaunch")
        let field = UITestSupport.titleField(in: relaunched)
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the title field did not appear after relaunch")
        XCTAssertEqual(UITestSupport.text(of: field), "Kept title")
        XCTAssertEqual(restored.value as? String, "kept text")
    }

    /// ⌘= twice is two steps bigger (13 pt to 15 pt). The size is in the session, so a relaunch keeps it.
    func testFontSizeIsRemembered() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "empty")
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor text view did not appear")
        XCTAssertEqual(UITestSupport.debugState(in: app)["fontSize"] as? Double, 13, "the state at launch")

        app.typeKey("=", modifierFlags: .command)
        app.typeKey("=", modifierFlags: .command)
        XCTAssertTrue(
            UITestSupport.wait { UITestSupport.debugState(in: app)["fontSize"] as? Double == 15 },
            "the state after two steps: \(UITestSupport.debugState(in: app))")
        quit(app)

        let relaunched = UITestSupport.relaunch(sameDataAs: app)
        XCTAssertTrue(
            UITestSupport.editor(in: relaunched).waitForExistence(timeout: 10),
            "the editor text view did not appear after relaunch")
        XCTAssertEqual(UITestSupport.debugState(in: relaunched)["fontSize"] as? Double, 15)
    }

    /// Scrolls the huge note a long way, quits and relaunches: the same text is at the top of the editor.
    func testScrollPositionSurvivesRelaunch() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "huge-note")
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "the editor text view did not appear")
        XCTAssertEqual(UITestSupport.debugState(in: app)["scrollAnchor"] as? Int, 0, "the state at launch")

        editor.scroll(byDeltaX: 0, deltaY: -20_000)
        // The sign of a scroll event is the system's to decide: from the top, the wrong one moves nothing.
        if UITestSupport.debugState(in: app)["scrollAnchor"] as? Int == 0 {
            editor.scroll(byDeltaX: 0, deltaY: 20_000)
        }
        Thread.sleep(forTimeInterval: 1.5)
        let before = UITestSupport.debugState(in: app)["scrollAnchor"] as? Int ?? 0
        XCTAssertGreaterThan(before, 0, "the editor did not scroll: \(UITestSupport.debugState(in: app))")
        quit(app)

        let relaunched = UITestSupport.relaunch(sameDataAs: app)
        XCTAssertTrue(
            UITestSupport.editor(in: relaunched).waitForExistence(timeout: 30),
            "the editor text view did not appear after relaunch")
        XCTAssertTrue(
            UITestSupport.wait(timeout: 15) {
                (UITestSupport.debugState(in: relaunched)["scrollAnchor"] as? Int ?? 0) > 0
            },
            "the state after relaunch: \(UITestSupport.debugState(in: relaunched))")
        let after = UITestSupport.debugState(in: relaunched)["scrollAnchor"] as? Int ?? 0
        // The anchor is the first character of a line on screen. The longest line of the note is about 130 characters.
        XCTAssertLessThanOrEqual(abs(after - before), 150, "the anchor was \(before) and is now \(after)")
    }
}
