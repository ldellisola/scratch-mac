import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// TEMPORARY: finds out how NSTextView's typing coalescing and the undo manager's groups interact with `apply(_:)`.
/// Every test fails on purpose with what it saw. Removed before the task is committed.
@MainActor
final class UndoDiagnosticsTests: XCTestCase {
    private func makeHostedEditor() -> (editor: EditorViewController, window: NSWindow) {
        let editor = EditorViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = editor
        window.setContentSize(NSSize(width: 800, height: 600))
        return (editor, window)
    }

    private func start(_ undo: UndoManager) -> (editor: EditorViewController, window: NSWindow) {
        let host = makeHostedEditor()
        let note = Note(id: NoteID.make(), title: "", body: "[ ] a", createdAt: Date(), modifiedAt: Date())
        let tab = TabState(noteID: note.id, selection: 5, scrollY: 0, scrollAnchor: nil)
        host.editor.show(note, tab: tab, undoManager: undo, isReadOnly: false)
        host.editor.view.layoutSubtreeIfNeeded()
        return host
    }

    private func state(_ label: String, _ undo: UndoManager, _ host: (editor: EditorViewController, window: NSWindow))
        -> String
    {
        "[\(label): level \(undo.groupingLevel) coalescing \(host.editor.textView.isCoalescingUndo) canUndo \(undo.canUndo) text \(host.editor.currentText.debugDescription)]"
    }

    private func toggle(_ host: (editor: EditorViewController, window: NSWindow)) {
        let textView = host.editor.textView
        textView.apply(
            TextEdit(range: NSRange(location: 1, length: 1), replacement: "x", selection: textView.selectedRange()))
    }

    func testDiagnoseUndoA_plain() {
        let undo = UndoManager()
        let host = start(undo)
        defer { withExtendedLifetime(host.window) {} }
        var log = ""
        host.editor.textView.insertText("b", replacementRange: NSRange(location: NSNotFound, length: 0))
        log += state("typed", undo, host)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        log += state("afterSpin", undo, host)
        toggle(host)
        log += state("toggled", undo, host)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        log += state("afterSpin2", undo, host)
        undo.undo()
        log += state("undone1", undo, host)
        XCTFail("A: \(log)")
    }

    func testDiagnoseUndoB_explicitBreak() {
        let undo = UndoManager()
        let host = start(undo)
        defer { withExtendedLifetime(host.window) {} }
        var log = ""
        host.editor.textView.insertText("b", replacementRange: NSRange(location: NSNotFound, length: 0))
        log += state("typed", undo, host)
        host.editor.textView.breakUndoCoalescing()
        log += state("broken", undo, host)
        toggle(host)
        log += state("toggled", undo, host)
        undo.undo()
        log += state("undone1", undo, host)
        XCTFail("B: \(log)")
    }

    func testDiagnoseUndoC_toggleOnly() {
        let undo = UndoManager()
        let host = start(undo)
        defer { withExtendedLifetime(host.window) {} }
        var log = ""
        log += state("start", undo, host)
        toggle(host)
        log += state("toggled", undo, host)
        toggle(host)
        log += state("toggledAgain", undo, host)
        undo.undo()
        log += state("undone1", undo, host)
        XCTFail("C: \(log)")
    }

    func testDiagnoseUndoD_typedTwiceThenToggle() {
        let undo = UndoManager()
        let host = start(undo)
        defer { withExtendedLifetime(host.window) {} }
        var log = ""
        host.editor.textView.insertText("b", replacementRange: NSRange(location: NSNotFound, length: 0))
        host.editor.textView.insertText("c", replacementRange: NSRange(location: NSNotFound, length: 0))
        log += state("typed2", undo, host)
        // End the event group by hand, as the end of the run loop turn would.
        if undo.groupingLevel > 0 { undo.endUndoGrouping() }
        log += state("groupEnded", undo, host)
        toggle(host)
        log += state("toggled", undo, host)
        undo.undo()
        log += state("undone1", undo, host)
        undo.undo()
        log += state("undone2", undo, host)
        XCTFail("D: \(log)")
    }
}
