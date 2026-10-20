import AppKit
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/paste-and-copy.md: pasted text takes the note's font and colours, copied
/// text is plain text only, and no smart substitution changes what the user types or pastes (spec §6.4, §6.5).
@MainActor
final class NoteTextViewTests: XCTestCase {
    private func makeConfiguredView() -> NoteTextView {
        let view = TextViewFactory.makeEditor().1
        view.applyScratchConfiguration()
        return view
    }

    /// A pasteboard of its own, so a test never touches the real clipboard. Release it with `releaseGlobally()`.
    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        return pasteboard
    }

    func testPastingRichTextUsesNoteFont() {
        let view = makeConfiguredView()
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let rich = NSAttributedString(
            string: "Hello",
            attributes: [
                .font: NSFont(name: "Times New Roman", size: 24) ?? NSFont.systemFont(ofSize: 24),
                .foregroundColor: NSColor.red,
            ])
        pasteboard.writeObjects([rich])

        XCTAssertTrue(view.readSelection(from: pasteboard))

        XCTAssertEqual(view.string, "Hello")
        view.textStorage!.enumerateAttributes(in: NSRange(location: 0, length: 5)) { attributes, _, _ in
            XCTAssertEqual(attributes[.font] as? NSFont, NoteTextView.noteFont)
            let color = attributes[.foregroundColor] as? NSColor  // absent means the view's textColor
            XCTAssertTrue(color == nil || color == NSColor.textColor)
        }
    }

    func testSmartSubstitutionsAreOff() {
        let view = makeConfiguredView()
        XCTAssertFalse(view.isRichText)
        XCTAssertFalse(view.importsGraphics)
        XCTAssertFalse(view.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(view.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(view.isAutomaticTextReplacementEnabled)
        XCTAssertFalse(view.isAutomaticSpellingCorrectionEnabled)
        XCTAssertFalse(view.isContinuousSpellCheckingEnabled)
        XCTAssertFalse(view.isGrammarCheckingEnabled)
        XCTAssertFalse(view.isAutomaticLinkDetectionEnabled)
        XCTAssertFalse(view.isAutomaticDataDetectionEnabled)
        XCTAssertFalse(view.isAutomaticTextCompletionEnabled)
        XCTAssertFalse(view.smartInsertDeleteEnabled)
        XCTAssertEqual(view.font, NoteTextView.noteFont)
    }

    func testTypedStraightQuotesStayStraight() {
        let view = makeConfiguredView()
        let typed = "\"don't\" -- x"
        view.insertText(typed, replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(view.string, typed)
    }

    func testCopyWritesOnlyPlainText() {
        let view = makeConfiguredView()
        let text = "- [ ] copy **me**"
        view.string = text
        view.setSelectedRange(NSRange(location: 0, length: text.utf16.count))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: text.utf16.count))
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        let written = view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes)

        XCTAssertTrue(
            written, "writable types: \(view.writablePasteboardTypes), selection: \(view.selectedRange())")

        let types = pasteboard.types ?? []
        XCTAssertTrue(types.contains(.string), "pasteboard types: \(types)")
        XCTAssertFalse(types.contains(.rtf), "pasteboard types: \(types)")
        XCTAssertFalse(types.contains(.rtfd), "pasteboard types: \(types)")
        XCTAssertFalse(types.contains(.html), "pasteboard types: \(types)")
        XCTAssertEqual(pasteboard.string(forType: .string), text)
    }

    /// The editor is a TextKit 1 view (ADR 0001). Its storage owns the layout manager, and nothing but the view keeps
    /// the storage alive once `makeEditor` has returned. The scroll view is dropped here too: only the text view is
    /// held.
    func testEditorKeepsItsTextKitOneStack() {
        let view = TextViewFactory.makeEditor().1

        view.string = "abc"

        XCTAssertEqual(view.textStorage?.string, "abc")
        XCTAssertNotNil(view.layoutManager)
        XCTAssertNil(view.textLayoutManager)
        XCTAssertNotNil(view.ownedTextStorage)
        XCTAssertTrue(view.ownedTextStorage === view.textStorage)
    }

    /// Loading and typing text leave the view on TextKit 1: it has no text layout manager afterwards, and still has a
    /// layout manager.
    func testEditorStaysOnTextKitOneWhileEditing() {
        let view = makeConfiguredView()

        view.load("one\ntwo")
        view.insertText("x", replacementRange: NSRange(location: 0, length: 0))

        XCTAssertNil(view.textLayoutManager)
        XCTAssertNotNil(view.layoutManager)
    }
}
