import AppKit
import XCTest

/// Covers docs/features/formatting.md ("Return, Tab, ⇧Tab and ⌘B"): a list typed with the keyboard (Return continues
/// it and ends it, Tab and ⇧Tab indent and outdent), ⇧⌘L followed by Return, and ⌘B and ⌘C. Real key events go through
/// the responder chain and the menu bar, which the hosted `ListKeyTests` do not (spec §6.4, plan 3 task 5).
@MainActor
final class FormattingUITests: XCTestCase {
    private func launchEditor(file: StaticString = #filePath, line: UInt = #line) -> (XCUIApplication, XCUIElement) {
        let app = UITestSupport.launch(fixture: "empty")
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(
            editor.waitForExistence(timeout: 10), "the editor text view did not appear", file: file, line: line)
        return (app, editor)
    }

    func testTypingAListByKeyboard() throws {
        continueAfterFailure = false
        let (app, editor) = launchEditor()

        editor.typeText("- milk")
        app.typeKey(.return, modifierFlags: [])
        UITestSupport.expectText("- milk\n- ", in: editor, "Return continues the list")
        editor.typeText("eggs")
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        UITestSupport.expectText("- milk\n- eggs\n", in: editor, "Return on the empty item takes its marker away")
        editor.typeText("done")

        UITestSupport.expectText("- milk\n- eggs\ndone", in: editor, "the list has ended")
    }

    func testChecklistShortcutThenReturn() throws {
        continueAfterFailure = false
        let (app, editor) = launchEditor()

        editor.typeText("buy")
        app.typeKey("l", modifierFlags: [.command, .shift])
        UITestSupport.expectText("[ ] buy", in: editor, "⇧⌘L puts a box in front of the line")
        app.typeKey(.rightArrow, modifierFlags: .command)
        app.typeKey(.return, modifierFlags: [])
        editor.typeText("sell")

        UITestSupport.expectText("[ ] buy\n[ ] sell", in: editor, "Return continues the checklist with an open box")
    }

    func testCommandBThenCopyKeepsMarkers() throws {
        continueAfterFailure = false
        let (app, editor) = launchEditor()

        editor.typeText("word")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("b", modifierFlags: .command)
        UITestSupport.expectText("**word**", in: editor, "⌘B puts the stars around the selection")
        // The selection is the word now, without the stars: select everything again to copy them as well.
        app.typeKey("a", modifierFlags: .command)
        NSPasteboard.general.clearContents()
        app.typeKey("c", modifierFlags: .command)

        XCTAssertTrue(
            UITestSupport.wait(timeout: 5) { NSPasteboard.general.string(forType: .string) == "**word**" },
            "copy keeps the markers: \(String(describing: NSPasteboard.general.string(forType: .string)))")
    }

    func testTabIndentsNestedBullet() throws {
        continueAfterFailure = false
        let (app, editor) = launchEditor()

        editor.typeText("- a")
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.tab, modifierFlags: [])
        UITestSupport.expectText("- a\n  - ", in: editor, "Tab indents the new item")
        editor.typeText("b")
        UITestSupport.expectText("- a\n  - b", in: editor, "the item is nested")

        app.typeKey(.tab, modifierFlags: .shift)

        UITestSupport.expectText("- a\n- b", in: editor, "⇧Tab takes the indent back")
    }
}
