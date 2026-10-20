import XCTest

/// Covers docs/features/formatting.md ("Checkboxes and the checklist command"): ⇧⌘L from the keyboard, through the Format
/// menu's key equivalent, and what ⌘Z takes back (spec §6.4, plan 3 task 4). The hosted `CheckboxTests` cover the rest.
@MainActor
final class ChecklistUITests: XCTestCase {
    func testChecklistShortcutTurnsTheLineIntoACheckbox() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "empty")
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor text view did not appear")

        editor.typeText("buy")
        app.typeKey("l", modifierFlags: [.command, .shift])
        UITestSupport.expectText("[ ] buy", in: editor, "⇧⌘L puts a box in front of the line")

        app.typeKey("l", modifierFlags: [.command, .shift])
        UITestSupport.expectText("buy", in: editor, "⇧⌘L again takes it away")
    }

    func testCommandZAfterTheChecklistShortcutTakesBackOnlyTheChecklist() throws {
        continueAfterFailure = false
        let app = UITestSupport.launch(fixture: "empty")
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor text view did not appear")

        editor.typeText("buy")
        app.typeKey("l", modifierFlags: [.command, .shift])
        UITestSupport.expectText("[ ] buy", in: editor, "⇧⌘L puts a box in front of the line")
        app.typeKey("z", modifierFlags: .command)

        UITestSupport.expectText("buy", in: editor, "⌘Z takes back the box and leaves what was typed")
    }
}
