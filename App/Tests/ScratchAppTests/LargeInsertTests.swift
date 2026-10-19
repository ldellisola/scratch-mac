import AppKit
import XCTest

@testable import Scratch

/// Hosted in the app. Covers plan 1 "Review Focus" 5 and spec §7 ("very large pastes, such as a 50,000-line log, must
/// never freeze the UI"): putting 50,000 lines into the editor, by insertion or by paste, returns within half a second.
/// The text is laid out as far as a window needs, which is where a text system pays for a big insert (TextKit lays out
/// lazily, so the cost must not grow with the length of the text).
@MainActor
final class LargeInsertTests: XCTestCase {
    private static let lineCount = 50_000
    private static let limit: Duration = .milliseconds(500)

    private func makeText() -> String {
        (1...Self.lineCount).map { "line \($0): the quick brown fox jumps over the lazy dog" }.joined(separator: "\n")
    }

    /// A configured editor in a window that is never shown, so that the text view has a width to lay out for.
    private func makeEditor() -> (window: NSWindow, scrollView: NSScrollView, view: NoteTextView) {
        let (scrollView, view) = TextViewFactory.makeEditor()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        scrollView.layoutSubtreeIfNeeded()
        return (window, scrollView, view)
    }

    func testInsertingFiftyThousandLinesIsFast() {
        let text = makeText()
        let clock = ContinuousClock()

        // Typed or inserted by a service: `insertText`.
        let inserting = makeEditor()
        let inserted = clock.measure {
            inserting.view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            inserting.scrollView.layoutSubtreeIfNeeded()
        }
        XCTAssertLessThan(inserted, Self.limit, "insertText")
        XCTAssertEqual(inserting.view.string.utf16.count, text.utf16.count, "insertText")
        withExtendedLifetime(inserting.window) {}  // the window must outlive the layout above

        // Pasted: `readSelection(from:)` is what Paste runs.
        let pasting = makeEditor()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        var didPaste = false
        let pasted = clock.measure {
            didPaste = pasting.view.readSelection(from: pasteboard)
            pasting.scrollView.layoutSubtreeIfNeeded()
        }
        XCTAssertTrue(didPaste, "paste")
        XCTAssertLessThan(pasted, Self.limit, "paste")
        XCTAssertEqual(pasting.view.string.utf16.count, text.utf16.count, "paste")
        withExtendedLifetime(pasting.window) {}
    }
}
