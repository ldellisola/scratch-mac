import XCTest

/// Covers docs/features/formatting.md ("Checkboxes and the checklist command"): ⇧⌘L from the keyboard, through the Format
/// menu's key equivalent, and what ⌘Z takes back (spec §6.4, plan 3 task 4). The hosted `CheckboxTests` cover the rest.
@MainActor
final class ChecklistUITests: XCTestCase {
    /// Waits until the editor's text is `expected`, or fails after a few seconds with what it is.
    private func expectText(
        _ expected: String, in editor: XCUIElement, _ message: String, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(5)
        while (editor.value as? String) != expected, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(editor.value as? String, expected, message, file: file, line: line)
    }

    func testChecklistShortcutTurnsTheLineIntoACheckbox() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "empty")
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor text view did not appear")

        editor.typeText("buy")
        app.typeKey("l", modifierFlags: [.command, .shift])
        expectText("[ ] buy", in: editor, "⇧⌘L puts a box in front of the line")

        app.typeKey("l", modifierFlags: [.command, .shift])
        expectText("buy", in: editor, "⇧⌘L again takes it away")
    }

    func testCommandZAfterTheChecklistShortcutTakesBackOnlyTheChecklist() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "empty")
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor text view did not appear")

        editor.typeText("buy")
        app.typeKey("l", modifierFlags: [.command, .shift])
        expectText("[ ] buy", in: editor, "⇧⌘L puts a box in front of the line")
        app.typeKey("z", modifierFlags: .command)

        expectText("buy", in: editor, "⌘Z takes back the box and leaves what was typed")
    }
}
