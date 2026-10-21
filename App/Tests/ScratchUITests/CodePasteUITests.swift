import AppKit
import XCTest

/// Covers docs/features/code.md ("Pasting code") and docs/features/paste-and-copy.md ("Paste order"), with real key
/// events and the real pasteboard: ⌘V of code is wrapped in a fence, ⌘Z gives back exactly the pasted text and a second
/// ⌘Z takes it away, and an email stays as it was pasted (spec §6.4, §6.5, plan 4 task 6). The hosted `CodePasteTests`
/// cannot press keys, and an undo group ends with a turn of the run loop, which a hosted test never has.
///
/// The test runner puts text on `NSPasteboard.general`, which the app reads when it pastes: the same pasteboard as every
/// copy and paste on the Mac, so each test sets what it pastes first.
@MainActor
final class CodePasteUITests: XCTestCase {
    private func launchEditor(file: StaticString = #filePath, line: UInt = #line) -> (XCUIApplication, XCUIElement) {
        let app = UITestSupport.launch(fixture: "empty")
        let editor = UITestSupport.editor(in: app)
        XCTAssertTrue(
            editor.waitForExistence(timeout: 10), "the editor text view did not appear", file: file, line: line)
        return (app, editor)
    }

    private func putOnPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// The editor's text, "" for an empty note (its value is nil then).
    private func text(of editor: XCUIElement) -> String {
        editor.value as? String ?? ""
    }

    /// Waits until the app has classified what was pasted (`debug.state`: `pendingPastes` is zero again). Call it after the
    /// pasted text is in the editor: until then the paste has not happened yet, and the count is zero as well.
    private func waitForClassification(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let done = UITestSupport.wait { UITestSupport.debugState(in: app)["pendingPastes"] as? Int == 0 }
        XCTAssertTrue(done, "the paste is classified: \(UITestSupport.debugState(in: app))", file: file, line: line)
    }

    /// Six lines of Go, with a tab for the indent, and no line break at the end.
    private static let go = [
        "package main", "import \"fmt\"", "func main() {", "\tfmt.Println(\"hello\")", "\tfmt.Println(\"world\")", "}",
    ].joined(separator: "\n")

    /// An email: lines with colons, a greeting and a signature. It must stay as it is.
    private static let email = [
        "Subject: Lunch on Thursday", "", "Hi team,", "",
        "I booked a table for 12:30 at the place near the station. Please tell me if you have allergies: otherwise I "
            + "will pick for everyone.",
        "", "Thanks!", "Sam",
    ].joined(separator: "\n")

    /// Review Focus 2: ⌘V of code is fenced with its language, ⌘Z leaves exactly the pasted lines, and ⌘Z again leaves an
    /// empty note.
    func testUndoAfterCodePasteRestoresPlainText() throws {
        continueAfterFailure = false
        let (app, editor) = launchEditor()
        putOnPasteboard(Self.go)

        app.typeKey("v", modifierFlags: .command)

        UITestSupport.expectText("```go\n" + Self.go + "\n```", in: editor, "⌘V of Go code is wrapped in a fence")
        app.typeKey("z", modifierFlags: .command)
        UITestSupport.expectText(Self.go, in: editor, "⌘Z leaves exactly the six pasted lines")
        app.typeKey("z", modifierFlags: .command)
        let isEmpty = UITestSupport.wait { text(of: editor).isEmpty }
        XCTAssertTrue(isEmpty, "⌘Z again takes the paste away: \(text(of: editor).debugDescription)")
    }

    /// Review Focus 1: an email is pasted as it is.
    func testPastingAnEmailStaysPlain() throws {
        continueAfterFailure = false
        let (app, editor) = launchEditor()
        putOnPasteboard(Self.email)

        app.typeKey("v", modifierFlags: .command)

        UITestSupport.expectText(Self.email, in: editor, "⌘V pastes the email")
        waitForClassification(in: app)
        XCTAssertEqual(text(of: editor), Self.email, "the email is not wrapped in a fence")
    }

    /// The paste goes into the middle of a line: the fence lines are lines of their own, and ⌘Z leaves the plain paste.
    func testCodePastedMidLineGetsFenceLinesOfItsOwn() throws {
        continueAfterFailure = false
        let (app, editor) = launchEditor()
        editor.typeText("before after")
        for _ in 0..<5 { app.typeKey(.leftArrow, modifierFlags: []) }
        putOnPasteboard(Self.go)

        app.typeKey("v", modifierFlags: .command)

        UITestSupport.expectText(
            "before \n```go\n" + Self.go + "\n```\nafter", in: editor, "the fence lines are lines of their own")
        app.typeKey("z", modifierFlags: .command)
        UITestSupport.expectText("before " + Self.go + "after", in: editor, "⌘Z leaves the plain paste")
    }
}
