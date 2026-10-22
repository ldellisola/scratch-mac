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

    /// 50,000 lines of pretty-printed JSON: `[`, objects of three lines that are 45 bytes or so each, and `]`. It is a valid
    /// document of less than a megabyte, so the detector validates all of it (`DetectionFeatures.isJSONDocument`).
    private func makeJSON() -> String {
        let objects = (Self.lineCount - 2) / 3
        var lines = ["["]
        lines.reserveCapacity(Self.lineCount)
        for index in 1...objects {
            lines.append("  {")
            lines.append("    \"id\": \(index), \"name\": \"item \(index)\"")
            lines.append(index == objects ? "  }" : "  },")
        }
        lines.append("]")
        return lines.joined(separator: "\n")
    }

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

    /// Plan 5 task 7, the 0.4.0 follow-up "large code paste": a paste of 50,000 lines of JSON goes in at once, and the wrap
    /// that puts it in a fence (`PasteClassifier`, the next turn of the main run loop) is as quick. Each step is held to the
    /// budget of a plain paste, and the rest of the styling goes on in chunks that never hold up the run loop.
    func testFiftyThousandLineJSONPasteIsWrappedQuickly() {
        let json = makeJSON()
        XCTAssertEqual(json.split(separator: "\n", omittingEmptySubsequences: false).count, Self.lineCount)
        XCTAssertLessThan(
            json.utf8.count, 1_000_000, "a document that is validated whole, the slowest way to detect it")
        let clock = ContinuousClock()
        let editor = makeEditor()
        defer { withExtendedLifetime(editor.window) {} }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString(json, forType: .string)

        // Step 1: the paste, as it always was.
        var didPaste = false
        let pasted = clock.measure {
            didPaste = editor.view.readSelection(from: pasteboard)
            editor.scrollView.layoutSubtreeIfNeeded()
        }
        XCTAssertTrue(didPaste, "paste")
        XCTAssertLessThan(pasted, Self.limit, "the paste")
        XCTAssertEqual(editor.view.string.utf16.count, json.utf16.count, "the paste is all there")
        XCTAssertEqual(editor.view.pendingPasteClassifications, 1, "the wrap waits for its turn")

        // Step 2: the turn of the run loop that reads the paste, finds the language and wraps it.
        let wrapped = clock.measure {
            let deadline = Date().addingTimeInterval(10)
            while editor.view.pendingPasteClassifications > 0, Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.001))
            }
            editor.scrollView.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(editor.view.pendingPasteClassifications, 0, "the paste was classified")
        XCTAssertLessThan(wrapped, Self.limit, "the wrap")
        let text = editor.view.string
        XCTAssertTrue(text.hasPrefix("```json\n"), "it is JSON: \(text.prefix(12))")
        XCTAssertTrue(text.hasSuffix("\n```"), "the closing fence follows the last line")
        XCTAssertEqual(
            text.utf16.count, json.utf16.count + "```json\n".utf16.count + "\n```".utf16.count,
            "nothing was added but the two fence lines")

        // The rest: the 50,000 lines are styled in chunks, one at a time, until the block is all styled.
        let styler: MarkupStyler = editor.view.styler
        let deadline = Date().addingTimeInterval(60)
        while !styler.isFullyStyled, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(styler.isFullyStyled, "the block is styled in chunks within a minute")
        XCTAssertEqual(editor.view.string, text, "styling never changes a character")
    }
}
