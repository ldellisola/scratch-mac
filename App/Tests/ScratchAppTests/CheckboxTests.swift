import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/formatting.md ("Checkboxes and the checklist command"): a click on the box of
/// a checklist item ticks or unticks it without moving the caret and is one undo step, ⇧⌘L turns lines into a checklist
/// and back, and the box is drawn over the transparent `[?]` (spec §6.4, plan 3 task 4).
///
/// A click that reaches `NoteTextView.mouseDown` and is not a toggle goes to `super.mouseDown`, which runs AppKit's
/// tracking loop until the mouse button is released: a test that sent it would wait for an event that never comes. So
/// every test that sends a click first checks that the point is on a box (`clickBox`), and the cases that are not a
/// toggle (a read-only note, the space after the box) ask `checkboxMarker(atViewPoint:)` and `toggleCheckbox(atViewPoint:)`
/// instead of sending a click.
@MainActor
final class CheckboxTests: XCTestCase {
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

    /// Shows `text` as a note, with the caret at `caret`, and lays the editor out so that positions can be measured.
    private func show(
        _ text: String, caret: Int = 0, readOnly: Bool = false, undoManager: UndoManager = UndoManager(),
        in host: Host
    ) {
        let note = Note(id: NoteID.make(), title: "", body: text, createdAt: Date(), modifiedAt: Date())
        let tab = TabState(noteID: note.id, selection: caret, scrollY: 0, scrollAnchor: nil)
        host.editor.show(note, tab: tab, undoManager: undoManager, isReadOnly: readOnly)
        host.editor.view.layoutSubtreeIfNeeded()
    }

    private func role(at index: Int, in host: Host) -> String? {
        host.editor.textView.textStorage?.attribute(.scratchMarker, at: index, effectiveRange: nil) as? String
    }

    /// The rectangle the glyphs of `range` take, in the coordinates of the text view.
    private func viewRect(ofCharacters range: NSRange, in host: Host) -> NSRect {
        let textView = host.editor.textView
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return .zero }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        return rect
    }

    private func center(of rect: NSRect) -> NSPoint {
        NSPoint(x: rect.midX, y: rect.midY)
    }

    /// Sends a left mouse click at the centre of the glyphs of `marker` to the text view, when that is a click on a box.
    /// Anything else would end in `super.mouseDown`, which does not return without a mouse up.
    private func clickBox(
        at marker: NSRange, clickCount: Int = 1, in host: Host, file: StaticString = #filePath, line: UInt = #line
    ) {
        let textView = host.editor.textView
        XCTAssertGreaterThan(textView.frame.width, 100, "the editor is laid out", file: file, line: line)
        let point = center(of: viewRect(ofCharacters: marker, in: host))
        guard textView.checkboxMarker(atViewPoint: point) == marker else {
            XCTFail(
                "\(point) is not on the box at \(marker): a click there would run AppKit's tracking loop", file: file,
                line: line)
            return
        }
        guard
            let event = NSEvent.mouseEvent(
                with: .leftMouseDown, location: textView.convert(point, to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: host.window.windowNumber, context: nil,
                eventNumber: 1, clickCount: clickCount, pressure: 1)
        else {
            XCTFail("no mouse event", file: file, line: line)
            return
        }
        textView.mouseDown(with: event)
    }

    // MARK: Clicks

    func testClickingCheckboxTogglesWithoutMovingCaret() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("[ ] a", caret: 5, in: host)

        clickBox(at: NSRange(location: 0, length: 3), in: host)

        XCTAssertEqual(host.editor.currentText, "[x] a")
        XCTAssertEqual(host.editor.textView.selectedRange(), NSRange(location: 5, length: 0), "the caret stays")
        XCTAssertEqual(role(at: 0, in: host), "checkboxChecked", "the item is restyled as ticked")
        XCTAssertEqual(
            host.editor.textView.textStorage?.attribute(.strikethroughStyle, at: 4, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue)

        clickBox(at: NSRange(location: 0, length: 3), in: host)

        XCTAssertEqual(host.editor.currentText, "[ ] a", "a second click unticks it")
        XCTAssertEqual(host.editor.textView.selectedRange(), NSRange(location: 5, length: 0))
        XCTAssertEqual(role(at: 0, in: host), "checkboxOpen")
    }

    /// Plan 6 task 5: the second click of a double-click is part of the first one's gesture. Before, it unticked the box
    /// again (two clicks, no change) or ended in AppKit's selection of a word.
    func testDoubleClickOnABoxTicksItOnce() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let undo = UndoManager()
        show("[ ] a", caret: 5, undoManager: undo, in: host)
        let box = NSRange(location: 0, length: 3)

        clickBox(at: box, clickCount: 1, in: host)
        XCTAssertEqual(host.editor.currentText, "[x] a", "the first click ticks it")

        clickBox(at: box, clickCount: 2, in: host)
        XCTAssertEqual(host.editor.currentText, "[x] a", "the second click is taken and does nothing")
        XCTAssertEqual(
            host.editor.textView.selectedRange(), NSRange(location: 5, length: 0), "it selects no word either")

        clickBox(at: box, clickCount: 3, in: host)
        XCTAssertEqual(host.editor.currentText, "[x] a", "nor does a third click of the series")

        undo.undo()
        XCTAssertEqual(host.editor.currentText, "[ ] a", "the double-click was one undo step")
        XCTAssertFalse(undo.canUndo)
    }

    func testASingleClickAfterADoubleClickTicksAgain() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("[ ] a", caret: 5, in: host)
        let box = NSRange(location: 0, length: 3)

        clickBox(at: box, clickCount: 1, in: host)
        clickBox(at: box, clickCount: 2, in: host)
        // A later click starts a new series: its count is 1 again.
        clickBox(at: box, clickCount: 1, in: host)

        XCTAssertEqual(host.editor.currentText, "[ ] a")
    }

    func testClickingATickedUppercaseBoxUnticksIt() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("[X] a", caret: 0, in: host)

        clickBox(at: NSRange(location: 0, length: 3), in: host)

        XCTAssertEqual(host.editor.currentText, "[ ] a")
    }

    func testClickingOneBoxChangesOnlyThatBox() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("[ ] a\n[x] b\n  [ ] c", caret: 3, in: host)

        clickBox(at: NSRange(location: 6, length: 3), in: host)
        XCTAssertEqual(host.editor.currentText, "[ ] a\n[ ] b\n  [ ] c")
        clickBox(at: NSRange(location: 14, length: 3), in: host)

        XCTAssertEqual(host.editor.currentText, "[ ] a\n[ ] b\n  [x] c", "an indented box is a box too")
        XCTAssertEqual(host.editor.textView.selectedRange(), NSRange(location: 3, length: 0), "inside the first marker")
    }

    func testClickingABoxMovesTheKeyboardToTheEditor() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("[ ] a", caret: 5, in: host)
        host.window.makeFirstResponder(nil)
        XCTAssertFalse(host.window.firstResponder === host.editor.textView, "the editor has not the keyboard yet")

        clickBox(at: NSRange(location: 0, length: 3), in: host)

        XCTAssertEqual(host.editor.currentText, "[x] a")
        XCTAssertTrue(host.window.firstResponder === host.editor.textView, "the click puts the caret in the note")
    }

    func testUndoAfterCheckboxClick() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let undo = UndoManager()
        show("[ ] a", caret: 5, undoManager: undo, in: host)
        XCTAssertFalse(undo.canUndo, "showing a note is no undo step")

        clickBox(at: NSRange(location: 0, length: 3), in: host)
        XCTAssertEqual(host.editor.currentText, "[x] a")
        XCTAssertTrue(undo.canUndo)

        undo.undo()

        XCTAssertEqual(host.editor.currentText, "[ ] a")
        XCTAssertFalse(undo.canUndo, "the click was one undo step")
        XCTAssertTrue(undo.canRedo)
        XCTAssertEqual(role(at: 0, in: host), "checkboxOpen", "the undo is styled as well")
    }

    func testClickRightOfBoxIsNotAToggle() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("[ ] a", caret: 5, in: host)
        let textView = host.editor.textView

        let box = viewRect(ofCharacters: NSRange(location: 0, length: 3), in: host)
        XCTAssertEqual(textView.checkboxMarker(atViewPoint: center(of: box)), NSRange(location: 0, length: 3))
        XCTAssertEqual(
            textView.checkboxMarker(atViewPoint: NSPoint(x: box.maxX - 0.5, y: box.midY)),
            NSRange(location: 0, length: 3), "the right edge of the box is still the box")
        XCTAssertNil(textView.styler.checkboxMarker(at: 3), "the space after the box")
        let space = viewRect(ofCharacters: NSRange(location: 3, length: 1), in: host)
        XCTAssertNil(textView.checkboxMarker(atViewPoint: center(of: space)), "the space after the box")
        XCTAssertFalse(textView.toggleCheckbox(atViewPoint: center(of: space)))
        let text = viewRect(ofCharacters: NSRange(location: 4, length: 1), in: host)
        XCTAssertNil(textView.checkboxMarker(atViewPoint: center(of: text)), "the text of the item")
        XCTAssertNil(
            textView.checkboxMarker(atViewPoint: NSPoint(x: box.maxX + 1, y: box.midY)), "just right of the box")
        XCTAssertNil(
            textView.checkboxMarker(atViewPoint: NSPoint(x: box.minX - 1, y: box.midY)), "just left of the box")
        XCTAssertNil(
            textView.checkboxMarker(atViewPoint: NSPoint(x: box.midX, y: box.maxY + 40)), "below the last line")
        XCTAssertEqual(host.editor.currentText, "[ ] a")
    }

    func testReadOnlyCheckboxIgnoresClick() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let undo = UndoManager()
        show("[ ] a", caret: 5, readOnly: true, undoManager: undo, in: host)
        let point = center(of: viewRect(ofCharacters: NSRange(location: 0, length: 3), in: host))

        // `mouseDown` itself would hand this click to AppKit, which places the caret and tracks the mouse.
        XCTAssertFalse(host.editor.textView.toggleCheckbox(atViewPoint: point))

        XCTAssertEqual(host.editor.currentText, "[ ] a")
        XCTAssertFalse(undo.canUndo)
        XCTAssertEqual(host.editor.textView.selectedRange(), NSRange(location: 5, length: 0))
    }

    func testNothingInACodeBlockIsACheckbox() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "```\n[ ] a\n```"
        show(text, caret: 0, in: host)

        XCTAssertNil(role(at: 4, in: host))
        XCTAssertNil(host.editor.textView.styler.checkboxMarker(at: 4))
        let point = center(of: viewRect(ofCharacters: NSRange(location: 4, length: 3), in: host))
        XCTAssertNil(host.editor.textView.checkboxMarker(atViewPoint: point))
        XCTAssertFalse(host.editor.textView.toggleCheckbox(atViewPoint: point))
        XCTAssertEqual(host.editor.currentText, text)
    }

    // MARK: ⇧⌘L

    func testToggleChecklistOnSelection() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("one\ntwo", in: host)
        host.editor.textView.setSelectedRange(NSRange(location: 0, length: 7))

        host.editor.textView.toggleChecklist(nil)

        XCTAssertEqual(host.editor.currentText, "[ ] one\n[ ] two")
        XCTAssertEqual(role(at: 0, in: host), "checkboxOpen")
        XCTAssertEqual(role(at: 8, in: host), "checkboxOpen")

        host.editor.textView.toggleChecklist(nil)

        XCTAssertEqual(host.editor.currentText, "one\ntwo", "doing it again restores the lines")
        XCTAssertNil(role(at: 0, in: host))
        XCTAssertNil(role(at: 4, in: host))
    }

    func testToggleChecklistWithoutSelectionUsesTheCaretsLine() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("a\nbuy\nc", caret: 5, in: host)

        host.editor.textView.toggleChecklist(nil)

        XCTAssertEqual(host.editor.currentText, "a\n[ ] buy\nc")
        XCTAssertEqual(
            host.editor.textView.selectedRange(), NSRange(location: 9, length: 0), "the caret moves with its text")
    }

    func testToggleChecklistTurnsABulletIntoABox() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("- milk\n- eggs", caret: 3, in: host)
        host.editor.textView.setSelectedRange(NSRange(location: 0, length: 13))

        host.editor.textView.toggleChecklist(nil)

        XCTAssertEqual(host.editor.currentText, "[ ] milk\n[ ] eggs")
    }

    func testChecklistCommandIsOneUndoStep() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let undo = UndoManager()
        show("one\ntwo", undoManager: undo, in: host)
        host.editor.textView.setSelectedRange(NSRange(location: 0, length: 7))

        host.editor.textView.toggleChecklist(nil)
        XCTAssertEqual(host.editor.currentText, "[ ] one\n[ ] two")
        undo.undo()

        XCTAssertEqual(host.editor.currentText, "one\ntwo", "both lines come back with one undo")
        XCTAssertFalse(undo.canUndo)
    }

    func testToggleChecklistInACodeBlockDoesNothing() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "a\n```\nb\n```\nc"
        let undo = UndoManager()
        show(text, caret: 6, undoManager: undo, in: host)

        host.editor.textView.toggleChecklist(nil)
        XCTAssertEqual(host.editor.currentText, text, "the caret is in the block")

        host.editor.textView.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        host.editor.textView.toggleChecklist(nil)
        XCTAssertEqual(host.editor.currentText, text, "a selection that holds the block")

        host.editor.textView.setSelectedRange(NSRange(location: 0, length: 1))
        host.editor.textView.toggleChecklist(nil)
        XCTAssertEqual(host.editor.currentText, "[ ] a\n```\nb\n```\nc", "a line next to the block is fine")
    }

    // MARK: ⇧⌘U (Mark as Checked)

    func testMarkAsCheckedTicksTheSelectedLines() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let undo = UndoManager()
        show("[ ] one\n[x] two\nplain\n[ ] three", undoManager: undo, in: host)
        host.editor.textView.setSelectedRange(NSRange(location: 0, length: 27))

        host.editor.textView.toggleCheckmarks(nil)

        XCTAssertEqual(host.editor.currentText, "[x] one\n[x] two\nplain\n[x] three")
        XCTAssertEqual(role(at: 0, in: host), "checkboxChecked", "the box is restyled as ticked")
        XCTAssertEqual(host.editor.textView.selectedRange(), NSRange(location: 0, length: 27), "the selection stays")
        XCTAssertTrue(undo.canUndo)

        undo.undo()

        XCTAssertEqual(host.editor.currentText, "[ ] one\n[x] two\nplain\n[ ] three", "one undo takes all back")
        XCTAssertFalse(undo.canUndo, "the command was one undo step")
    }

    func testMarkAsCheckedUntickWhenEveryBoxIsTicked() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("[x] one\n[X] two", in: host)
        host.editor.textView.setSelectedRange(NSRange(location: 0, length: 15))

        host.editor.textView.toggleCheckmarks(nil)

        XCTAssertEqual(host.editor.currentText, "[ ] one\n[ ] two")
        XCTAssertEqual(role(at: 0, in: host), "checkboxOpen")
    }

    func testMarkAsCheckedUsesTheCaretsLine() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("[ ] a\n[ ] b", caret: 9, in: host)

        host.editor.textView.toggleCheckmarks(nil)

        XCTAssertEqual(host.editor.currentText, "[ ] a\n[x] b")
        XCTAssertEqual(host.editor.textView.selectedRange(), NSRange(location: 9, length: 0))
    }

    func testMarkAsCheckedBeepsInCodeBlock() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "[ ] a\n```\n[ ] b\n```\n[ ] c"
        let undo = UndoManager()
        show(text, caret: 11, undoManager: undo, in: host)

        host.editor.textView.toggleCheckmarks(nil)
        XCTAssertEqual(host.editor.currentText, text, "the caret is in the block")

        host.editor.textView.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        host.editor.textView.toggleCheckmarks(nil)
        XCTAssertEqual(host.editor.currentText, text, "a selection that holds the block")
        XCTAssertFalse(undo.canUndo)

        host.editor.textView.setSelectedRange(NSRange(location: 1, length: 0))
        host.editor.textView.toggleCheckmarks(nil)
        XCTAssertEqual(host.editor.currentText, "[x] a\n```\n[ ] b\n```\n[ ] c", "a line next to the block is fine")
    }

    func testMarkAsCheckedWithoutACheckboxDoesNothing() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let undo = UndoManager()
        show("- a\nplain", undoManager: undo, in: host)
        host.editor.textView.setSelectedRange(NSRange(location: 0, length: 9))

        host.editor.textView.toggleCheckmarks(nil)

        XCTAssertEqual(host.editor.currentText, "- a\nplain", "no checklist line: the key beeps")
        XCTAssertFalse(undo.canUndo)
    }

    func testMarkAsCheckedInAReadOnlyNoteDoesNothing() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let undo = UndoManager()
        show("[ ] a", readOnly: true, undoManager: undo, in: host)

        host.editor.textView.toggleCheckmarks(nil)

        XCTAssertEqual(host.editor.currentText, "[ ] a")
        XCTAssertFalse(undo.canUndo)
    }

    func testToggleChecklistInAReadOnlyNoteDoesNothing() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let undo = UndoManager()
        show("one", readOnly: true, undoManager: undo, in: host)

        host.editor.textView.toggleChecklist(nil)

        XCTAssertEqual(host.editor.currentText, "one")
        XCTAssertFalse(undo.canUndo)
    }

    // MARK: Drawing

    /// The number of pixels in the rectangle of `marker` that are not the colour of the background around the box.
    private func inkedPixels(over marker: NSRange, in host: Host) -> Int {
        let textView = host.editor.textView
        let rect = viewRect(ofCharacters: marker, in: host).integral
        guard rect.width > 0, rect.height > 0, let rep = textView.bitmapImageRepForCachingDisplay(in: rect) else {
            return -1
        }
        textView.cacheDisplay(in: rect, to: rep)
        guard let background = rep.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else { return -1 }
        var count = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let distance =
                    abs(color.redComponent - background.redComponent)
                    + abs(color.greenComponent - background.greenComponent)
                    + abs(color.blueComponent - background.blueComponent)
                if distance > 0.15 { count += 1 }
            }
        }
        return count
    }

    func testCheckboxSymbolIsDrawn() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        // The caret is at the end, so it is not in either rectangle.
        show("[ ] a\n[x] b", caret: 11, in: host)

        let open = inkedPixels(over: NSRange(location: 0, length: 3), in: host)
        let ticked = inkedPixels(over: NSRange(location: 6, length: 3), in: host)

        XCTAssertGreaterThan(open, 10, "the `[ ]` is transparent: what is in its rectangle is the box")
        XCTAssertGreaterThan(ticked, open, "a ticked box is filled, an open one is an outline")
    }

    // MARK: The menu

    func testMarkAsCheckedMenuItem() {
        let menu = NSApp.mainMenu?.items.first { $0.submenu?.title == "Format" }?.submenu
        let item = menu?.items.first { $0.action == #selector(NoteTextView.toggleCheckmarks(_:)) }
        XCTAssertEqual(item?.title, "Mark as Checked")
        XCTAssertEqual(item?.keyEquivalent, "u")
        XCTAssertEqual(item?.keyEquivalentModifierMask, NSEvent.ModifierFlags([.command, .shift]))
        XCTAssertNil(item?.target, "the first responder gets it: the editor, when it has the keyboard")
        XCTAssertEqual(item?.isEnabled, true)
        let titles = menu?.items.map(\.title)
        XCTAssertEqual(titles, ["Bold", "Checklist", "Mark as Checked"], "it follows Checklist")
    }

    func testFormatMenuHasTheChecklistShortcut() {
        let menu = NSApp.mainMenu?.items.first { $0.submenu?.title == "Format" }?.submenu
        XCTAssertNotNil(menu, "the menu bar has a Format menu")
        let item = menu?.items.first { $0.action == #selector(NoteTextView.toggleChecklist(_:)) }
        XCTAssertEqual(item?.title, "Checklist")
        XCTAssertEqual(item?.keyEquivalent, "l")
        XCTAssertEqual(item?.keyEquivalentModifierMask, NSEvent.ModifierFlags([.command, .shift]))
        XCTAssertNil(item?.target, "the first responder gets it: the editor, when it has the keyboard")
        let titles = NSApp.mainMenu?.items.map { $0.submenu?.title ?? "" }
        let edit = titles?.firstIndex(of: "Edit")
        let format = titles?.firstIndex(of: "Format")
        XCTAssertNotNil(edit)
        XCTAssertEqual(format, edit.map { $0 + 1 }, "Format comes after Edit")
        XCTAssertEqual(
            menu?.autoenablesItems, false, "AppKit does not switch the item off by asking the first responder")
        XCTAssertEqual(item?.isEnabled, true)
    }
}
