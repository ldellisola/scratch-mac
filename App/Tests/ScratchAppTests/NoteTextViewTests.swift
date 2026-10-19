import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/paste-and-copy.md: pasted text takes the note's font and colours, copied
/// text is plain text only, and no smart substitution changes what the user types or pastes (spec §6.4, §6.5). Each
/// behaviour is checked on both TextKit stacks, because `-ScratchTextKit` can start the app on either.
@MainActor
final class NoteTextViewTests: XCTestCase {
    private var modes: [TextKitMode] { [.one, .two] }

    private func makeConfiguredView(mode: TextKitMode) -> NoteTextView {
        let view = TextViewFactory.makeEditor(mode: mode).1
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
        for mode in modes {
            let view = makeConfiguredView(mode: mode)
            let pasteboard = makePasteboard()
            defer { pasteboard.releaseGlobally() }
            let rich = NSAttributedString(
                string: "Hello",
                attributes: [
                    .font: NSFont(name: "Times New Roman", size: 24) ?? NSFont.systemFont(ofSize: 24),
                    .foregroundColor: NSColor.red,
                ])
            pasteboard.writeObjects([rich])

            XCTAssertTrue(view.readSelection(from: pasteboard), "TextKit \(mode.rawValue)")

            XCTAssertEqual(view.string, "Hello", "TextKit \(mode.rawValue)")
            view.textStorage!.enumerateAttributes(in: NSRange(location: 0, length: 5)) { attributes, _, _ in
                XCTAssertEqual(attributes[.font] as? NSFont, NoteTextView.noteFont, "TextKit \(mode.rawValue)")
                let color = attributes[.foregroundColor] as? NSColor  // absent means the view's textColor
                XCTAssertTrue(color == nil || color == NSColor.textColor, "TextKit \(mode.rawValue)")
            }
        }
    }

    func testSmartSubstitutionsAreOff() {
        for mode in modes {
            let view = makeConfiguredView(mode: mode)
            let label = "TextKit \(mode.rawValue)"
            XCTAssertFalse(view.isRichText, label)
            XCTAssertFalse(view.importsGraphics, label)
            XCTAssertFalse(view.isAutomaticQuoteSubstitutionEnabled, label)
            XCTAssertFalse(view.isAutomaticDashSubstitutionEnabled, label)
            XCTAssertFalse(view.isAutomaticTextReplacementEnabled, label)
            XCTAssertFalse(view.isAutomaticSpellingCorrectionEnabled, label)
            XCTAssertFalse(view.isContinuousSpellCheckingEnabled, label)
            XCTAssertFalse(view.isGrammarCheckingEnabled, label)
            XCTAssertFalse(view.isAutomaticLinkDetectionEnabled, label)
            XCTAssertFalse(view.isAutomaticDataDetectionEnabled, label)
            XCTAssertFalse(view.isAutomaticTextCompletionEnabled, label)
            XCTAssertFalse(view.smartInsertDeleteEnabled, label)
            XCTAssertEqual(view.font, NoteTextView.noteFont, label)
        }
    }

    func testTypedStraightQuotesStayStraight() {
        for mode in modes {
            let view = makeConfiguredView(mode: mode)
            let typed = "\"don't\" -- x"
            view.insertText(typed, replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertEqual(view.string, typed, "TextKit \(mode.rawValue)")
        }
    }

    func testCopyWritesOnlyPlainText() {
        for mode in modes {
            let view = makeConfiguredView(mode: mode)
            let label = "TextKit \(mode.rawValue)"
            let text = "- [ ] copy **me**"
            view.string = text
            view.setSelectedRange(NSRange(location: 0, length: text.utf16.count))
            XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: text.utf16.count), label)
            let pasteboard = makePasteboard()
            defer { pasteboard.releaseGlobally() }

            let written = view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes)

            XCTAssertTrue(
                written, "\(label), writable types: \(view.writablePasteboardTypes), selection: \(view.selectedRange())"
            )

            let types = pasteboard.types ?? []
            XCTAssertTrue(types.contains(.string), "\(label), pasteboard types: \(types)")
            XCTAssertFalse(types.contains(.rtf), "\(label), pasteboard types: \(types)")
            XCTAssertFalse(types.contains(.rtfd), "\(label), pasteboard types: \(types)")
            XCTAssertFalse(types.contains(.html), "\(label), pasteboard types: \(types)")
            XCTAssertEqual(pasteboard.string(forType: .string), text, label)
        }
    }

    /// The TextKit 1 storage owns the layout manager, and nothing but the view keeps the storage alive once
    /// `makeEditor` has returned. The scroll view is dropped here too: only the text view is held.
    func testTextKitOneEditorKeepsItsTextStack() {
        let view = TextViewFactory.makeEditor(mode: .one).1

        view.string = "abc"

        XCTAssertEqual(view.textStorage?.string, "abc")
        XCTAssertNotNil(view.layoutManager)
        XCTAssertNil(view.textLayoutManager)
        XCTAssertNotNil(view.ownedTextStorage)
        XCTAssertTrue(view.ownedTextStorage === view.textStorage)
    }

    func testTextKitTwoEditorUsesTextLayoutManager() {
        let view = TextViewFactory.makeEditor(mode: .two).1

        view.string = "abc"

        XCTAssertEqual(view.textStorage?.string, "abc")
        XCTAssertNotNil(view.textLayoutManager)
        XCTAssertNil(view.ownedTextStorage)
    }
}
