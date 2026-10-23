import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/formatting.md ("Return, Tab, ⇧Tab and ⌘B"): Return continues a list or ends it,
/// Tab and ⇧Tab indent and outdent list lines, ⌘B wraps the selection in `**`, nothing of it runs in a fenced block or a
/// read-only note, and each of them is one undo step (spec §6.4, plan 3 task 5). The rules themselves are tested in
/// ScratchCore (`ListEditingTests`, `InlineEditingTests`): these tests check that the editor asks them, applies the
/// answer and leaves a key alone when it is not a list action.
///
/// The key methods (`insertNewline(_:)` and the others) are what AppKit calls for the key, so the tests call them
/// directly. A test that has two edits in it would have one undo group for both (AGENTS.md, "Undo steps cannot be tested
/// in a hosted test across two edits"), so the undo test makes an editor and an undo manager for each edit.
@MainActor
final class ListKeyTests: XCTestCase {
    private typealias Host = (editor: EditorViewController, window: NSWindow)

    /// An editor in an 800 x 600 window that is never shown. Keep `window` alive for as long as the editor is used.
    private func makeHostedEditor() -> Host {
        let editor = EditorViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = editor
        window.setContentSize(NSSize(width: 800, height: 600))
        return (editor, window)
    }

    /// Shows `marked` as a note. `|` marks the caret, and `⟦` and `⟧` the ends of a selection: they are not part of the
    /// text. The editor has the keyboard, as it has in the app.
    private func show(
        _ marked: String, readOnly: Bool = false, undoManager: UndoManager = UndoManager(), in host: Host
    ) {
        let (text, selection) = Self.unmark(marked)
        let note = Note(id: NoteID.make(), title: "", body: text, createdAt: Date(), modifiedAt: Date())
        let tab = TabState(noteID: note.id, selection: selection.location, scrollY: 0, scrollAnchor: nil)
        host.editor.show(note, tab: tab, undoManager: undoManager, isReadOnly: readOnly)
        host.editor.view.layoutSubtreeIfNeeded()
        host.window.makeFirstResponder(host.editor.textView)
        host.editor.textView.setSelectedRange(selection)
    }

    /// The text of `marked` without its marks, and the selection they stand for.
    private static func unmark(_ marked: String) -> (String, NSRange) {
        if let open = marked.range(of: "⟦"), let close = marked.range(of: "⟧") {
            let before = String(marked[..<open.lowerBound])
            let inside = String(marked[open.upperBound..<close.lowerBound])
            let after = String(marked[close.upperBound...])
            return (before + inside + after, NSRange(location: before.utf16.count, length: inside.utf16.count))
        }
        guard let caret = marked.firstIndex(of: "|") else { return (marked, NSRange(location: 0, length: 0)) }
        let before = String(marked[..<caret])
        let after = String(marked[marked.index(after: caret)...])
        return (before + after, NSRange(location: before.utf16.count, length: 0))
    }

    /// The text of the editor with the selection marked the way `show` reads it.
    private func marked(_ host: Host) -> String {
        let text = host.editor.currentText as NSString
        let selection = host.editor.textView.selectedRange()
        if selection.length == 0 {
            return text.replacingCharacters(in: selection, with: "|")
        }
        return
            (text.replacingCharacters(in: NSRange(location: NSMaxRange(selection), length: 0), with: "⟧") as NSString)
            .replacingCharacters(in: NSRange(location: selection.location, length: 0), with: "⟦")
    }

    private func role(at index: Int, in host: Host) -> String? {
        host.editor.textView.textStorage?.attribute(.scratchMarker, at: index, effectiveRange: nil) as? String
    }

    private func isBold(_ font: NSFont?) -> Bool {
        font?.fontName == NoteTextView.boldNoteFont(size: FontSize.standard).fontName
    }

    // MARK: Return

    func testReturnContinuesBullet() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("- a|", in: host)

        host.editor.textView.insertNewline(nil)

        XCTAssertEqual(marked(host), "- a\n- |")
        XCTAssertEqual(role(at: 4, in: host), "bullet", "the new item is styled as a bullet")
    }

    func testReturnSplitsTheItemAtTheCaret() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("- ab|cd", in: host)

        host.editor.textView.insertNewline(nil)

        XCTAssertEqual(marked(host), "- ab\n- |cd")
    }

    func testReturnOnATickedItemAddsAnOpenBox() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("[x] a|", in: host)

        host.editor.textView.insertNewline(nil)

        XCTAssertEqual(marked(host), "[x] a\n[ ] |")
        XCTAssertEqual(role(at: 6, in: host), "checkboxOpen")
    }

    func testReturnKeepsTheIndentation() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("- a\n  - b|", in: host)

        host.editor.textView.insertNewline(nil)

        XCTAssertEqual(marked(host), "- a\n  - b\n  - |")
    }

    func testReturnOnEmptyItemEndsList() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("- a\n- |", in: host)

        host.editor.textView.insertNewline(nil)

        XCTAssertEqual(marked(host), "- a\n|", "the marker goes and the line is empty")
        XCTAssertEqual(role(at: 0, in: host), "bullet", "the first item is still a bullet")
    }

    func testReturnOnEmptyNestedItemOutdentsIt() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("- a\n  - |", in: host)

        host.editor.textView.insertNewline(nil)

        XCTAssertEqual(marked(host), "- a\n- |")
    }

    func testReturnBeforeTheMarkerInsertsAPlainLine() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("|- a", in: host)

        host.editor.textView.insertNewline(nil)

        XCTAssertEqual(marked(host), "\n|- a", "no marker is added above the item")
    }

    func testReturnOnAPlainLineIsPlain() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("abc|", in: host)

        host.editor.textView.insertNewline(nil)

        XCTAssertEqual(marked(host), "abc\n|")
    }

    func testReturnWithASelectionReplacesIt() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("- ⟦ab⟧c", in: host)

        host.editor.textView.insertNewline(nil)

        XCTAssertEqual(marked(host), "- \n|c", "no new item: Return is the text view's own")
    }

    func testReturnInsideCodeBlockIsPlain() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("```\n- a|\n```", in: host)

        host.editor.textView.insertNewline(nil)

        XCTAssertEqual(marked(host), "```\n- a\n|\n```", "no marker inside a block")
    }

    func testReturnOnAListLineBesideABlockStillContinuesTheList() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("- a|\n```\nx\n```\n- b", in: host)

        host.editor.textView.insertNewline(nil)

        XCTAssertEqual(marked(host), "- a\n- |\n```\nx\n```\n- b", "the block is the next line, not this one")
    }

    func testReturnInAReadOnlyNoteChangesNothing() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("- a|", readOnly: true, in: host)

        host.editor.textView.insertNewline(nil)

        XCTAssertEqual(host.editor.currentText, "- a")
    }

    // MARK: Tab and ⇧Tab

    func testTabIndentsListLine() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("- a|", in: host)

        host.editor.textView.insertTab(nil)

        XCTAssertEqual(marked(host), "  - a|")
    }

    func testTabIndentsEveryListLineOfTheSelection() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("⟦- a\nplain\n[ ] b⟧", in: host)

        host.editor.textView.insertTab(nil)

        XCTAssertEqual(
            marked(host), "  ⟦- a\nplain\n  [ ] b⟧", "the plain line stays, and the selection moves with the text")
    }

    func testShiftTabOutdents() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("    - a|", in: host)

        host.editor.textView.insertBacktab(nil)

        XCTAssertEqual(marked(host), "  - a|")
        host.editor.textView.insertBacktab(nil)
        XCTAssertEqual(marked(host), "- a|")
    }

    func testShiftTabOnATopLevelListLineChangesNothing() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("- a|", in: host)

        host.editor.textView.insertBacktab(nil)

        XCTAssertEqual(marked(host), "- a|", "there is nothing to give back, and the key does not go anywhere else")
        XCTAssertTrue(host.window.firstResponder === host.editor.textView)
    }

    func testTabOnAPlainLineInsertsATab() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("abc|", in: host)

        host.editor.textView.insertTab(nil)

        XCTAssertEqual(marked(host), "abc\t|")
    }

    func testTabInsideCodeBlockInsertsATab() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("```\n- a|\n```", in: host)

        host.editor.textView.insertTab(nil)

        XCTAssertEqual(marked(host), "```\n- a\t|\n```", "a list line inside a block is code")
    }

    func testTabInAReadOnlyNoteChangesNothing() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("- a|", readOnly: true, in: host)

        host.editor.textView.insertTab(nil)

        XCTAssertEqual(host.editor.currentText, "- a")
    }

    func testShiftTabOnAPlainLineChangesNoText() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("  abc|", in: host)

        host.editor.textView.insertBacktab(nil)

        XCTAssertEqual(host.editor.currentText, "  abc", "what ⇧Tab does there is AppKit's, and it is not an outdent")
    }

    // MARK: ⌘B

    func testCommandBWrapsSelection() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("⟦word⟧", in: host)

        host.editor.textView.toggleBoldMarkers(nil)

        XCTAssertEqual(marked(host), "**⟦word⟧**", "the selection covers the content")
        XCTAssertTrue(isBold(host.editor.textView.textStorage?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont))
    }

    func testCommandBWithoutSelectionPutsTheCaretBetweenTheStars() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("a |", in: host)

        host.editor.textView.toggleBoldMarkers(nil)

        XCTAssertEqual(marked(host), "a **|**")
    }

    /// Plan 6 task 5: ⌘B with a caret in a word bolds the word and keeps the caret in it, and ⌘B again takes it off.
    func testBoldOnCaretInWord() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("say he|llo now", in: host)

        host.editor.textView.toggleBoldMarkers(nil)

        XCTAssertEqual(marked(host), "say **he|llo** now", "the caret stays at its place in the word")
        for index in 6...10 {
            XCTAssertTrue(
                isBold(host.editor.textView.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont),
                "the character at \(index) is bold")
        }
        XCTAssertFalse(
            isBold(host.editor.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont))

        host.editor.textView.toggleBoldMarkers(nil)

        XCTAssertEqual(marked(host), "say he|llo now", "twice puts the text back")
    }

    func testBoldOnCaretBetweenEmptyPairRemovesIt() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("a **|** b", in: host)

        host.editor.textView.toggleBoldMarkers(nil)

        XCTAssertEqual(marked(host), "a | b")
    }

    func testCommandBOnSeveralLinesWrapsEachLine() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("⟦- one\n- two⟧", in: host)

        host.editor.textView.toggleBoldMarkers(nil)

        XCTAssertEqual(marked(host), "- **⟦one**\n- **two⟧**")
        XCTAssertTrue(
            isBold(host.editor.textView.textStorage?.attribute(.font, at: 4, effectiveRange: nil) as? NSFont))
        XCTAssertTrue(
            isBold(host.editor.textView.textStorage?.attribute(.font, at: 14, effectiveRange: nil) as? NSFont))

        host.editor.textView.toggleBoldMarkers(nil)

        XCTAssertEqual(marked(host), "- ⟦one\n- two⟧", "the same selection takes the stars off again")
    }

    func testCommandBOnWhiteSpaceOnlyDoesNothing() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let undo = UndoManager()
        show("a⟦  ⟧b", undoManager: undo, in: host)

        host.editor.textView.toggleBoldMarkers(nil)

        XCTAssertEqual(marked(host), "a⟦  ⟧b", "the rule has nothing to wrap, so the key beeps")
        XCTAssertFalse(undo.canUndo)
    }

    func testCommandBOnABoldRunTakesTheStarsAway() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("**⟦word⟧**", in: host)

        host.editor.textView.toggleBoldMarkers(nil)

        XCTAssertEqual(marked(host), "⟦word⟧")
    }

    func testCommandBInsideCodeBlockDoesNothing() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let undo = UndoManager()
        show("```\n⟦word⟧\n```", undoManager: undo, in: host)

        host.editor.textView.toggleBoldMarkers(nil)
        XCTAssertEqual(marked(host), "```\n⟦word⟧\n```", "the selection is in the block")

        host.editor.textView.setSelectedRange(
            NSRange(location: 0, length: (host.editor.currentText as NSString).length))
        host.editor.textView.toggleBoldMarkers(nil)
        XCTAssertEqual(host.editor.currentText, "```\nword\n```", "a selection that holds the block too")
        XCTAssertFalse(undo.canUndo)
    }

    func testCommandBInAReadOnlyNoteDoesNothing() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let undo = UndoManager()
        show("⟦word⟧", readOnly: true, undoManager: undo, in: host)

        host.editor.textView.toggleBoldMarkers(nil)

        XCTAssertEqual(host.editor.currentText, "word")
        XCTAssertFalse(undo.canUndo)
    }

    func testFormatMenuHasBoldOnCommandB() {
        let menu = NSApp.mainMenu?.items.first { $0.submenu?.title == "Format" }?.submenu
        let item = menu?.items.first { $0.action == #selector(NoteTextView.toggleBoldMarkers(_:)) }
        XCTAssertEqual(item?.title, "Bold")
        XCTAssertEqual(item?.keyEquivalent, "b")
        XCTAssertEqual(item?.keyEquivalentModifierMask, NSEvent.ModifierFlags([.command]))
        XCTAssertNil(item?.target, "the first responder gets it: the editor, when it has the keyboard")
        XCTAssertEqual(item?.isEnabled, true)
    }

    // MARK: Undo

    /// Each edit is one undo step: ⌘Z brings back the text and the caret the edit started from, and nothing of what was
    /// typed before it goes with it. An editor and an undo manager for each case, because a second edit in the same
    /// undo manager would be one group with the first.
    func testEachEditIsOneUndoStep() {
        let cases: [(name: String, marked: String, edited: String, action: @MainActor (NoteTextView) -> Void)] = [
            ("Return continues a bullet", "- a|", "- a\n- |", { $0.insertNewline(nil) }),
            ("Return splits an item", "- ab|cd", "- ab\n- |cd", { $0.insertNewline(nil) }),
            ("Return ends the list", "- a\n- |", "- a\n|", { $0.insertNewline(nil) }),
            ("Return outdents an empty item", "- a\n  - |", "- a\n- |", { $0.insertNewline(nil) }),
            ("Tab on a line", "- a|", "  - a|", { $0.insertTab(nil) }),
            ("Tab on three lines", "⟦- a\n- b\n- c⟧", "  ⟦- a\n  - b\n  - c⟧", { $0.insertTab(nil) }),
            ("⇧Tab on a line", "  - a|", "- a|", { $0.insertBacktab(nil) }),
            ("⌘B on a selection", "⟦word⟧", "**⟦word⟧**", { $0.toggleBoldMarkers(nil) }),
            ("⌘B on a bold run", "**⟦word⟧**", "⟦word⟧", { $0.toggleBoldMarkers(nil) }),
            ("⌘B on nothing", "a |", "a **|**", { $0.toggleBoldMarkers(nil) }),
            ("⌘B on a word", "say he|llo now", "say **he|llo** now", { $0.toggleBoldMarkers(nil) }),
            ("⌘B on an empty pair", "a **|** b", "a | b", { $0.toggleBoldMarkers(nil) }),
            ("⌘B on two lines", "⟦- a\n- b⟧", "- **⟦a**\n- **b⟧**", { $0.toggleBoldMarkers(nil) }),
            ("⇧⌘U on a line", "[ ] a|", "[x] a|", { $0.toggleCheckmarks(nil) }),
            ("⇧⌘U on two lines", "⟦[ ] a\n[x] b⟧", "⟦[x] a\n[x] b⟧", { $0.toggleCheckmarks(nil) }),
            ("⇧⌘U on ticked lines", "⟦[x] a\n[x] b⟧", "⟦[ ] a\n[ ] b⟧", { $0.toggleCheckmarks(nil) }),
        ]
        for testCase in cases {
            let host = makeHostedEditor()
            defer { withExtendedLifetime(host.window) {} }
            let undo = UndoManager()
            show(testCase.marked, undoManager: undo, in: host)
            XCTAssertFalse(undo.canUndo, "\(testCase.name): showing a note is no undo step")

            testCase.action(host.editor.textView)
            XCTAssertEqual(marked(host), testCase.edited, testCase.name)
            XCTAssertTrue(undo.canUndo, "\(testCase.name): the edit can be undone")

            undo.undo()

            XCTAssertEqual(
                host.editor.currentText, Self.unmark(testCase.marked).0, "\(testCase.name): one undo takes it back")
            XCTAssertFalse(undo.canUndo, "\(testCase.name): it was one step")
            XCTAssertTrue(undo.canRedo, "\(testCase.name): and it can be redone")
        }
    }
}
