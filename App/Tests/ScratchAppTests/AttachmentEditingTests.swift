import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/attachments.md ("Selecting and deleting a token", "The paperclip"): the caret
/// never stops inside a token, a selection that covers part of one covers all of it, Backspace and Delete next to a token
/// select it first and the next press deletes it with its line break, typing over a selected token replaces the whole
/// token, and the paperclip inserts the files that the open panel gives (spec §6.4, plan 5 task 5). The rules themselves are
/// `AttachmentEditing` in ScratchCore (tested on Linux too); these tests run them through the text view, its delegate and
/// AppKit's own key commands.
///
/// Nothing here sends a click. A click on an attachment's preview or chip is the view's own (`AttachmentCopyTests`), and a
/// click on a token line anywhere else ends in `super.mouseDown`, whose tracking loop would wait for a mouse button that never
/// comes up.
@MainActor
final class AttachmentEditingTests: XCTestCase {
    /// How many times a panel was asked for.
    @MainActor private final class Counter {
        var count = 0
    }

    private let id = AttachmentID(rawValue: "6f9619ff-8b86-4d11-b42d-00c04fc964ff")
    private var token: String { AttachmentToken.line(for: id) }
    private let size = AttachmentToken.lineLength

    private func caret(_ location: Int) -> NSRange { NSRange(location: location, length: 0) }

    // MARK: Moving

    /// Review Focus 4: the arrow keys step over a token and never stop inside it.
    func testCaretSkipsOverToken() throws {
        let host = try AttachmentTestHost(text: "abc\n\(token)\ndef", caret: 4)
        defer { host.cleanUp() }
        let view = host.textView
        XCTAssertEqual(view.selectedRange(), caret(4), "the start of the token line is a place for the caret")

        view.moveRight(nil)
        XCTAssertEqual(view.selectedRange(), caret(4 + size), "right from the start steps over the token")
        view.moveRight(nil)
        XCTAssertEqual(view.selectedRange(), caret(4 + size + 1), "and on to the next line")

        view.setSelectedRange(caret(4 + size))
        view.moveLeft(nil)
        XCTAssertEqual(view.selectedRange(), caret(4), "left from the end steps over it the other way")
    }

    /// Review Focus 4: ⇧→ over a token takes it into the selection whole, and ⇧← takes it out whole again. The end that
    /// moves back is not pulled to the far side of the token, which would keep the selection from ever being made smaller.
    func testShiftRightOverATokenAndShiftLeftShrinksBackOutOfIt() throws {
        let host = try AttachmentTestHost(text: "abc\n\(token)\ndef", caret: 3)
        defer { host.cleanUp() }
        let view = host.textView

        view.moveRightAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 3, length: 1), "the line break")
        view.moveRightAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 3, length: 1 + size), "the token comes in whole")
        view.moveRightAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 3, length: 2 + size), "and on to the next line")

        view.moveLeftAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 3, length: 1 + size), "back to the end of the token")
        view.moveLeftAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 3, length: 1), "the token leaves whole")
        view.moveLeftAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), caret(3), "and the selection is empty again")
    }

    /// The mirror: ⇧← over a token from below takes it in whole, and ⇧→ takes it out whole, from the other side.
    func testShiftLeftOverATokenAndShiftRightShrinksBackOutOfIt() throws {
        let anchor = 4 + size + 2  // the "e" of "def"
        let host = try AttachmentTestHost(text: "abc\n\(token)\ndef", caret: anchor)
        defer { host.cleanUp() }
        let view = host.textView

        view.moveLeftAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: anchor - 1, length: 1), "the d")
        view.moveLeftAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: anchor - 2, length: 2), "the line break")
        view.moveLeftAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 4, length: anchor - 4), "the token comes in whole")
        view.moveLeftAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 3, length: anchor - 3), "and on to the line above")

        view.moveRightAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 4, length: anchor - 4), "back to the start of the token")
        view.moveRightAndModifySelection(nil)
        XCTAssertEqual(
            view.selectedRange(), NSRange(location: anchor - 2, length: 2), "the token leaves whole, by its start")
        view.moveRightAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: anchor - 1, length: 1))
        view.moveRightAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), caret(anchor), "and the selection is empty again")
    }

    /// A caret that is put inside a token (by code, or by a move that is not a key) goes to the token's edge.
    func testCaretPutInsideATokenGoesToItsEdge() throws {
        let host = try AttachmentTestHost(text: "abc\n\(token)\ndef", caret: 0)
        defer { host.cleanUp() }
        let view = host.textView

        view.setSelectedRange(caret(20))
        XCTAssertEqual(view.selectedRange(), caret(4 + size), "from before the token: to its end")

        view.setSelectedRange(caret(host.text.utf16.count))
        view.setSelectedRange(caret(30))
        XCTAssertEqual(view.selectedRange(), caret(4), "from after the token: to its start")
    }

    /// Review Focus 4: a selection that covers part of a token covers all of it.
    func testPartialSelectionGrowsToWholeToken() throws {
        let host = try AttachmentTestHost(text: "abc\n\(token)\ndef", caret: 0)
        defer { host.cleanUp() }
        let view = host.textView
        let whole = NSRange(location: 4, length: size)

        view.setSelectedRange(NSRange(location: 10, length: 5))
        XCTAssertEqual(view.selectedRange(), whole, "inside the token")

        view.setSelectedRange(NSRange(location: 1, length: 12))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 1, length: 4 + size - 1), "ending inside it")

        view.setSelectedRange(NSRange(location: 30, length: 27))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 4, length: 53), "starting inside it")
    }

    func testTokenInACodeBlockIsTextAndIsNotSnapped() throws {
        let text = "```\n\(token)\n```"
        let host = try AttachmentTestHost(text: text, caret: 0)
        defer { host.cleanUp() }
        let view = host.textView
        XCTAssertTrue(view.styler.isInCodeBlock(10), "the token is in the block")

        view.setSelectedRange(caret(10))
        XCTAssertEqual(view.selectedRange(), caret(10), "the caret can be anywhere in text")
        view.setSelectedRange(NSRange(location: 10, length: 5))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 10, length: 5))
    }

    // MARK: Backspace and Delete

    /// Review Focus 4: Backspace right after a token selects it, and the next press deletes it and its line break.
    func testBackspaceSelectsThenDeletes() throws {
        let text = "abc\n\(token)\ndef"
        let host = try AttachmentTestHost(text: text, caret: 4 + size + 1)
        defer { host.cleanUp() }
        let view = host.textView
        let whole = NSRange(location: 4, length: size)

        view.deleteBackward(nil)
        XCTAssertEqual(host.text, text, "the first press deletes nothing")
        XCTAssertEqual(view.selectedRange(), whole, "it selects the token")

        view.deleteBackward(nil)
        XCTAssertEqual(host.text, "abc\ndef", "the second deletes the token and its line break")
        XCTAssertEqual(view.selectedRange(), caret(4))

        host.undo.undo()
        XCTAssertEqual(host.text, text, "one undo step brings the token back")
    }

    /// Backspace at the end of the token's own line, where the caret is when a token ends the note.
    func testBackspaceAtTheEndOfTheTokenLineSelectsThenDeletes() throws {
        let text = "abc\n\(token)"
        let host = try AttachmentTestHost(text: text, caret: 4 + size)
        defer { host.cleanUp() }
        let view = host.textView

        view.deleteBackward(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 4, length: size))
        XCTAssertEqual(host.text, text)

        view.deleteBackward(nil)
        XCTAssertEqual(host.text, "abc", "the line break before the last line goes with it")
        XCTAssertEqual(view.selectedRange(), caret(3))
    }

    /// Review Focus 4: Delete right before a token selects it, and the next press deletes it.
    func testDeleteForwardSelectsThenDeletes() throws {
        let text = "abc\n\(token)\ndef"
        let host = try AttachmentTestHost(text: text, caret: 3)
        defer { host.cleanUp() }
        let view = host.textView

        view.deleteForward(nil)
        XCTAssertEqual(host.text, text, "the first press deletes nothing")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 4, length: size), "it selects the token")

        view.deleteForward(nil)
        XCTAssertEqual(host.text, "abc\ndef", "the second deletes the token and its line break")
    }

    /// Backspace where it would join "abc" to the token's line leaves the text alone and moves the caret over the break.
    func testBackspaceBelowTextDoesNotJoinTheTokenToIt() throws {
        let text = "abc\n\(token)"
        let host = try AttachmentTestHost(text: text, caret: 4)
        defer { host.cleanUp() }

        host.textView.deleteBackward(nil)

        XCTAssertEqual(host.text, text, "the token is still a whole line")
        XCTAssertEqual(host.textView.selectedRange(), caret(3))
    }

    /// Backspace and Delete away from tokens are the text view's own.
    func testDeletingOrdinaryTextIsUnchanged() throws {
        let host = try AttachmentTestHost(text: "abc\n\(token)\ndef", caret: 2)
        defer { host.cleanUp() }

        host.textView.deleteBackward(nil)
        XCTAssertEqual(host.text, "ac\n\(token)\ndef")
        host.textView.deleteForward(nil)
        XCTAssertEqual(host.text, "a\n\(token)\ndef")
    }

    /// A token in a code block is text, and Backspace deletes a character of it.
    func testBackspaceInATokenInACodeBlockIsPlain() throws {
        let text = "```\n\(token)\n```"
        let host = try AttachmentTestHost(text: text, caret: 4 + size)
        defer { host.cleanUp() }

        host.textView.deleteBackward(nil)

        XCTAssertEqual(host.text, "```\n" + String(token.dropLast()) + "\n```")
    }

    /// A note in Recently Deleted cannot be changed: the keys select and delete nothing.
    func testReadOnlyNoteKeepsItsTokens() throws {
        let text = "abc\n\(token)\ndef"
        let host = try AttachmentTestHost(text: text, caret: 4 + size + 1, isReadOnly: true)
        defer { host.cleanUp() }

        host.textView.deleteBackward(nil)
        host.textView.deleteBackward(nil)

        XCTAssertEqual(host.text, text)
    }

    // MARK: Typing

    /// A selected token is replaced whole by what is typed.
    func testTypingOverSelectedTokenReplacesWholeToken() throws {
        let host = try AttachmentTestHost(text: "abc\n\(token)\ndef", caret: 0)
        defer { host.cleanUp() }
        let view = host.textView
        view.setSelectedRange(NSRange(location: 10, length: 5))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 4, length: size), "the part grew to the whole")

        view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertEqual(host.text, "abc\nx\ndef", "no half of a token is left")
        XCTAssertEqual(view.selectedRange(), caret(5))
    }

    // MARK: The paperclip

    /// File > Attach File… and the paperclip: the open panel's files go in at the caret, each on a line of its own.
    func testPaperclipInsertsChosenFiles() throws {
        let host = try AttachmentTestHost(text: "before", caret: 6)
        defer { host.cleanUp() }
        let first = try host.makeFile(named: "one.txt", contents: Data("1".utf8))
        let second = try host.makePNGFile(named: "two.png")
        let panels = Counter()
        host.textView.presentOpenPanel = { completion in
            panels.count += 1
            completion([first, second])
        }

        host.textView.attachFiles()

        XCTAssertEqual(panels.count, 1)
        let ids = host.tokenIDs
        XCTAssertEqual(ids.count, 2)
        guard ids.count == 2 else { return }
        XCTAssertEqual(
            host.text, "before\n" + AttachmentToken.line(for: ids[0]) + "\n" + AttachmentToken.line(for: ids[1]) + "\n")
        XCTAssertEqual(try host.row(ids[0]).fileName, "one.txt")
        XCTAssertEqual(try host.row(ids[1]).fileName, "two.png")
        XCTAssertTrue(try host.row(ids[1]).isImage)
        host.waitForCopies()
        XCTAssertTrue(try host.row(ids[0]).isCopied)
        XCTAssertTrue(try host.row(ids[1]).isCopied)
    }

    /// A panel that is cancelled inserts nothing, and so does one that is used in a note that cannot be edited.
    func testPaperclipCancelledOrReadOnlyInsertsNothing() throws {
        let host = try AttachmentTestHost(text: "kept")
        defer { host.cleanUp() }
        host.textView.presentOpenPanel = { completion in completion([]) }
        host.textView.attachFiles()
        XCTAssertEqual(host.text, "kept")

        let readOnly = try AttachmentTestHost(text: "kept", isReadOnly: true)
        defer { readOnly.cleanUp() }
        let file = try readOnly.makeFile(named: "one.txt", contents: Data("1".utf8))
        let panels = Counter()
        readOnly.textView.presentOpenPanel = { completion in
            panels.count += 1
            completion([file])
        }
        readOnly.textView.attachFiles()
        XCTAssertEqual(readOnly.text, "kept")
        XCTAssertEqual(panels.count, 0, "no panel is shown for a note that cannot take a file")
    }
}
