import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/title-and-font-size.md (the title field, the font size) and the scroll and
/// undo parts of docs/features/autosave-and-restore.md (the scroll anchor, one undo history per note).
@MainActor
final class EditorViewControllerTests: XCTestCase {
    /// An editor in an 800 x 600 window that is never shown. Keep `window` alive for as long as the editor is used.
    private func makeHostedEditor() -> (editor: EditorViewController, window: NSWindow) {
        let editor = EditorViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = editor
        // Assigning the content view controller resizes the window to the controller's view, so size it afterwards.
        window.setContentSize(NSSize(width: 800, height: 600))
        return (editor, window)
    }

    private func makeNote(_ body: String, title: String = "") -> Note {
        Note(id: NoteID.make(), title: title, body: body, createdAt: Date(), modifiedAt: Date())
    }

    /// A tab that shows `note` from the top.
    private func makeTab(for note: Note, scrollAnchor: Int? = nil) -> TabState {
        TabState(noteID: note.id, selection: 0, scrollY: 0, scrollAnchor: scrollAnchor)
    }

    /// The 1-based number of the line that holds the UTF-16 offset `offset` of `text`.
    private func lineNumber(ofOffset offset: Int, in text: String) -> Int {
        text.utf16.prefix(offset).filter { $0 == 0x0A }.count + 1
    }

    /// "line 1" to "line 10000", and the UTF-16 offset at which line 5,000 starts.
    private func makeTenThousandLines() -> (text: String, startOfLine5000: Int) {
        let lines = (1...10_000).map { "line \($0)" }
        let start = lines.prefix(4_999).reduce(0) { $0 + $1.utf16.count + 1 }
        return (lines.joined(separator: "\n"), start)
    }

    /// Checks that `value` is the note font at `size` points: SF Mono, regular weight. The font is compared by name and
    /// size, which does not depend on whether AppKit hands out the same `NSFont` object twice.
    private func assertNoteFont(
        _ value: Any?, size: Double, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let font = value as? NSFont else {
            return XCTFail("the font is \(String(describing: value))", file: file, line: line)
        }
        let expected = NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
        XCTAssertEqual(font.pointSize, CGFloat(size), file: file, line: line)
        XCTAssertEqual(font.fontName, expected.fontName, file: file, line: line)
    }

    // MARK: Scroll anchor

    /// A note shown before the window has laid out (as at launch) is scrolled to its anchor by the first layout.
    func testScrollAnchorRoundTrips() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let (text, anchor) = makeTenThousandLines()
        let note = makeNote(text)

        host.editor.show(
            note, tab: makeTab(for: note, scrollAnchor: anchor), undoManager: UndoManager(), isReadOnly: false)
        host.editor.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(lineNumber(ofOffset: host.editor.currentScrollAnchor, in: text), 5_000)
    }

    /// A note shown in a window that has laid out (a switch between notes) is scrolled at once.
    func testScrollAnchorAppliesWhenAlreadyLaidOut() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        host.editor.view.layoutSubtreeIfNeeded()
        let (text, anchor) = makeTenThousandLines()
        let note = makeNote(text)

        host.editor.show(
            note, tab: makeTab(for: note, scrollAnchor: anchor), undoManager: UndoManager(), isReadOnly: false)

        XCTAssertEqual(lineNumber(ofOffset: host.editor.currentScrollAnchor, in: text), 5_000)
    }

    /// The anchor that was given is the one to save, whether or not the editor has laid out yet: a save right after
    /// launch must not move a note back to its top.
    func testScrollAnchorIsSavedAsGiven() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let (text, anchor) = makeTenThousandLines()
        let note = makeNote(text)

        host.editor.show(
            note, tab: makeTab(for: note, scrollAnchor: anchor), undoManager: UndoManager(), isReadOnly: false)

        XCTAssertEqual(host.editor.currentScrollAnchor, anchor)
    }

    /// Without an anchor (a session saved by Scratch 0.1.0) the note is at its top, and its anchor is 0.
    func testNoteWithoutAnchorShowsItsTop() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let (text, _) = makeTenThousandLines()
        let note = makeNote(text)

        host.editor.show(note, tab: makeTab(for: note), undoManager: UndoManager(), isReadOnly: false)
        host.editor.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(host.editor.currentScrollAnchor, 0)
    }

    /// Plan 3 task 7 (the huge-note screenshot of Plan 2's final review): the top of a note is the text view's top
    /// inset, which stays visible: a note shown without an anchor, or with anchor 0, is scrolled to `-contentInsets.top`
    /// and not to the first line itself. It holds after a note that was scrolled far down, and after the layout.
    func testNoteWithoutAnchorShowsItsTopInset() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let (text, startOfLine5000) = makeTenThousandLines()
        let scrolled = makeNote(text)
        host.editor.show(
            scrolled, tab: makeTab(for: scrolled, scrollAnchor: startOfLine5000), undoManager: UndoManager(),
            isReadOnly: false)
        host.editor.view.layoutSubtreeIfNeeded()

        for anchor in [nil, 0] as [Int?] {
            let note = makeNote(text)
            host.editor.show(
                note, tab: makeTab(for: note, scrollAnchor: anchor), undoManager: UndoManager(), isReadOnly: false)
            host.editor.view.layoutSubtreeIfNeeded()

            let clipView = host.editor.clipView
            let insetTop = clipView.enclosingScrollView?.contentInsets.top ?? 0
            let state =
                "anchor \(String(describing: anchor)): clip origin \(clipView.bounds.origin), insets \(insetTop), "
                + "visible rect \(host.editor.textView.visibleRect)"
            XCTAssertEqual(clipView.bounds.origin.y, -insetTop, state)
            XCTAssertLessThanOrEqual(host.editor.textView.visibleRect.minY, 0, state)
        }
    }

    /// Plan 3 task 7: AppKit scrolls a text view to its selection when its frame changes, and for a caret on the first
    /// line of a long note that put the line at the top of the window, 12 pt up, in the huge-note screenshot (the stack
    /// was `-[NSTextView setFrameSize:]` to `-scrollRectToVisible:`). `NoteTextView.scrollToVisible` scrolls the rest
    /// of the way to the top when a scroll to a rect that starts in the top inset leaves less than the inset above.
    func testScrollToTheFirstLineKeepsTheTopInsetOnScreen() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let (text, _) = makeTenThousandLines()
        let note = makeNote(text)
        host.editor.show(note, tab: makeTab(for: note), undoManager: UndoManager(), isReadOnly: false)
        host.editor.view.layoutSubtreeIfNeeded()
        let textView = host.editor.textView
        let clipView = host.editor.clipView
        let insetTop = clipView.enclosingScrollView?.contentInsets.top ?? 0
        let top = -insetTop
        let firstLine = NSRect(x: 0, y: textView.textContainerInset.height, width: 100, height: 16)

        // From further down, the minimum scroll that shows the first line puts it at the top of the window.
        textView.scroll(NSPoint(x: 0, y: 400))
        XCTAssertEqual(clipView.bounds.origin.y, 400, "the scroll away from the top")
        _ = textView.scrollToVisible(firstLine)
        XCTAssertEqual(clipView.bounds.origin.y, top, "the first line was shown without its top inset")
        XCTAssertLessThanOrEqual(textView.visibleRect.minY, 0)

        // A rect that is visible already scrolls nothing: not even the few points that the top inset needs.
        textView.scroll(NSPoint(x: 0, y: 6))
        _ = textView.scrollToVisible(firstLine)
        XCTAssertEqual(clipView.bounds.origin.y, 6, "a visible rect must not scroll the view")

        // A rect further down scrolls as AppKit decides.
        textView.scroll(NSPoint(x: 0, y: 0))
        _ = textView.scrollToVisible(NSRect(x: 0, y: 5_000, width: 100, height: 16))
        XCTAssertGreaterThan(clipView.bounds.origin.y, 1_000, "a rect far down must scroll normally")
    }

    // MARK: Font size

    func testFontSizeAppliesToTextTypingAndTitle() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let note = makeNote("one\ntwo", title: "Heading")
        host.editor.show(note, tab: makeTab(for: note), undoManager: UndoManager(), isReadOnly: false)

        host.editor.setFontSize(16)

        let storage = host.editor.textView.textStorage!
        var runs = 0
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            runs += 1
            assertNoteFont(value, size: 16)
        }
        XCTAssertGreaterThan(runs, 0)
        assertNoteFont(host.editor.textView.typingAttributes[.font], size: 16)
        // The title is bold, three points larger than the text.
        let title = host.editor.titleField.font
        XCTAssertEqual(title?.pointSize, 19)
        XCTAssertEqual(title?.fontName, NSFont.monospacedSystemFont(ofSize: 19, weight: .bold).fontName)
        XCTAssertNotEqual(title?.fontName, NSFont.monospacedSystemFont(ofSize: 19, weight: .regular).fontName)
        XCTAssertEqual(host.editor.fontSize, 16)
    }

    /// The size is the same for every note: the next note shown takes it too.
    func testFontSizeAppliesToTheNextNote() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let first = makeNote("first")
        let second = makeNote("second")
        host.editor.show(first, tab: makeTab(for: first), undoManager: UndoManager(), isReadOnly: false)
        host.editor.setFontSize(20)

        host.editor.show(second, tab: makeTab(for: second), undoManager: UndoManager(), isReadOnly: false)

        let storage = host.editor.textView.textStorage!
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            assertNoteFont(value, size: 20)
        }
    }

    func testPasteAfterFontSizeChangeUsesNewSize() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let note = makeNote("")
        host.editor.show(note, tab: makeTab(for: note), undoManager: UndoManager(), isReadOnly: false)
        host.editor.setFontSize(16)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let rich = NSAttributedString(
            string: "Pasted",
            attributes: [
                .font: NSFont(name: "Times New Roman", size: 24) ?? NSFont.systemFont(ofSize: 24),
                .foregroundColor: NSColor.red,
            ])
        pasteboard.writeObjects([rich])

        XCTAssertTrue(host.editor.textView.readSelection(from: pasteboard))

        XCTAssertEqual(host.editor.currentText, "Pasted")
        let storage = host.editor.textView.textStorage!
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            assertNoteFont(value, size: 16)
        }
    }

    // MARK: Undo

    private func insertText(_ text: String, into editor: EditorViewController) {
        editor.textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    /// Each note has its own history: leaving a note and coming back finds its typing still undoable, and the other
    /// note's history is not mixed in.
    func testUndoHistoryIsPerNote() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let noteA = makeNote("alpha")
        let noteB = makeNote("beta")
        let undoA = UndoManager()
        let undoB = UndoManager()
        host.editor.show(noteA, tab: makeTab(for: noteA), undoManager: undoA, isReadOnly: false)
        insertText("x", into: host.editor)
        XCTAssertEqual(host.editor.currentText, "xalpha")
        // The coordinator shows a note as it was saved, which is the text the editor held when it was left.
        var editedA = noteA
        editedA.body = host.editor.currentText

        host.editor.show(noteB, tab: makeTab(for: noteB), undoManager: undoB, isReadOnly: false)
        XCTAssertEqual(host.editor.currentText, "beta")
        XCTAssertFalse(undoB.canUndo, "loading a note must not register undo")

        host.editor.show(editedA, tab: makeTab(for: editedA), undoManager: undoA, isReadOnly: false)
        XCTAssertTrue(undoA.canUndo)
        undoA.undo()

        XCTAssertEqual(host.editor.currentText, "alpha")
        XCTAssertFalse(undoB.canUndo)
    }

    func testShowDoesNotClearUndo() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let note = makeNote("alpha")
        let undo = UndoManager()
        host.editor.show(note, tab: makeTab(for: note), undoManager: undo, isReadOnly: false)
        insertText("x", into: host.editor)
        var edited = note
        edited.body = host.editor.currentText
        XCTAssertTrue(undo.canUndo)

        host.editor.show(edited, tab: makeTab(for: edited), undoManager: undo, isReadOnly: false)

        XCTAssertTrue(undo.canUndo)
    }

    // MARK: Read-only

    func testReadOnlyRejectsTyping() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let note = makeNote("abc", title: "Kept")
        host.editor.show(note, tab: makeTab(for: note), undoManager: UndoManager(), isReadOnly: true)

        insertText("x", into: host.editor)

        XCTAssertEqual(host.editor.currentText, "abc")
        XCTAssertFalse(host.editor.textView.isEditable)
        XCTAssertFalse(host.editor.titleField.isEditable)
        XCTAssertTrue(host.editor.isReadOnly)

        // The next note, shown editable, can be typed in again.
        let other = makeNote("def")
        host.editor.show(other, tab: makeTab(for: other), undoManager: UndoManager(), isReadOnly: false)
        insertText("x", into: host.editor)
        XCTAssertEqual(host.editor.currentText, "xdef")
        XCTAssertTrue(host.editor.titleField.isEditable)
    }

    /// A note in Recently Deleted can have an undo history from before it was deleted. Undoing would change its text, so
    /// a read-only note offers none, and gets its history back when it is restored (docs/features/recently-deleted.md).
    func testReadOnlyNoteOffersNoUndo() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let note = makeNote("alpha")
        let undo = UndoManager()
        host.editor.show(note, tab: makeTab(for: note), undoManager: undo, isReadOnly: false)
        insertText("x", into: host.editor)
        var edited = note
        edited.body = host.editor.currentText
        XCTAssertTrue(undo.canUndo)
        XCTAssertTrue(host.editor.activeUndoManager === undo)

        host.editor.show(edited, tab: makeTab(for: edited), undoManager: undo, isReadOnly: true)

        XCTAssertNil(host.editor.activeUndoManager)
        XCTAssertNil(host.editor.textView.undoManager)
        XCTAssertEqual(host.editor.currentText, "xalpha")

        host.editor.setReadOnly(false)

        XCTAssertTrue(host.editor.activeUndoManager === undo)
        XCTAssertTrue(host.editor.textView.undoManager === undo)
        XCTAssertTrue(undo.canUndo, "the history is kept for when the note is restored")
    }

    /// Restoring the note that is open makes it editable in place: the text, the title and the cursor stay.
    func testSetReadOnlyFalseMakesTheShownNoteEditable() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let note = makeNote("abc", title: "Kept")
        host.editor.show(note, tab: makeTab(for: note), undoManager: UndoManager(), isReadOnly: true)
        insertText("x", into: host.editor)
        XCTAssertEqual(host.editor.currentText, "abc")

        host.editor.setReadOnly(false)
        insertText("x", into: host.editor)

        XCTAssertEqual(host.editor.currentText, "xabc")
        XCTAssertFalse(host.editor.isReadOnly)
        XCTAssertTrue(host.editor.textView.isEditable)
        XCTAssertTrue(host.editor.titleField.isEditable)
        XCTAssertEqual(host.editor.titleField.stringValue, "Kept")
    }

    // MARK: Title field

    func testShowFillsTheTitleField() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let note = makeNote("body", title: "Groceries")

        host.editor.show(note, tab: makeTab(for: note), undoManager: UndoManager(), isReadOnly: false)

        XCTAssertEqual(host.editor.titleField.stringValue, "Groceries")
        XCTAssertEqual(host.editor.currentText, "body")
    }

    /// Return and Tab in the title field move the cursor to the text. ⇧Tab is left to AppKit.
    func testReturnInTitleFocusesBody() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let note = makeNote("body")
        host.editor.show(note, tab: makeTab(for: note), undoManager: UndoManager(), isReadOnly: false)
        host.editor.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(host.editor.titleField.delegate === host.editor)
        let fieldEditor = TextViewFactory.makeEditor().1
        host.editor.focusTitle()
        XCTAssertFalse(host.window.firstResponder === host.editor.textView)

        let handled = host.editor.control(
            host.editor.titleField, textView: fieldEditor, doCommandBy: #selector(NSResponder.insertNewline(_:)))

        XCTAssertTrue(handled)
        XCTAssertTrue(host.window.firstResponder === host.editor.textView)

        host.editor.focusTitle()
        XCTAssertTrue(
            host.editor.control(
                host.editor.titleField, textView: fieldEditor, doCommandBy: #selector(NSResponder.insertTab(_:))))
        XCTAssertTrue(host.window.firstResponder === host.editor.textView)

        XCTAssertFalse(
            host.editor.control(
                host.editor.titleField, textView: fieldEditor, doCommandBy: #selector(NSResponder.insertBacktab(_:))))
    }

    /// An edit of the title is reported, and loading a note's title is not.
    func testTitleEditsAreReported() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        var reported: [String] = []
        host.editor.onTitleChange = { reported.append($0) }
        let note = makeNote("body", title: "Old")

        host.editor.show(note, tab: makeTab(for: note), undoManager: UndoManager(), isReadOnly: false)
        XCTAssertEqual(reported, [])

        host.editor.titleField.stringValue = "New"
        host.editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        XCTAssertEqual(reported, ["New"])
    }
}
