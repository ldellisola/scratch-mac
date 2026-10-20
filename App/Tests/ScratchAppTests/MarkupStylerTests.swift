import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/formatting.md (the styling sections): bullets, checkboxes, bold, inline code
/// and links render from the plain-text markers without changing a character; markers inside fenced blocks and unclosed
/// markers stay plain; the markers of a bold run or inline code are hidden unless the caret is at them; a note of 10,000
/// lines is styled in chunks after the first frame (spec §6.4, plan 3 task 3).
@MainActor
final class MarkupStylerTests: XCTestCase {
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

    /// Shows `text` as a note, with the caret at `caret`.
    private func show(
        _ text: String, caret: Int = 0, undoManager: UndoManager = UndoManager(), in host: Host
    ) {
        let note = Note(id: NoteID.make(), title: "", body: text, createdAt: Date(), modifiedAt: Date())
        let tab = TabState(noteID: note.id, selection: caret, scrollY: 0, scrollAnchor: nil)
        host.editor.show(note, tab: tab, undoManager: undoManager, isReadOnly: false)
    }

    private func attribute(_ key: NSAttributedString.Key, at index: Int, in host: Host) -> Any? {
        host.editor.textView.textStorage?.attribute(key, at: index, effectiveRange: nil)
    }

    private func font(at index: Int, in host: Host) -> NSFont? {
        attribute(.font, at: index, in: host) as? NSFont
    }

    private func role(at index: Int, in host: Host) -> String? {
        attribute(.scratchMarker, at: index, in: host) as? String
    }

    private func isBold(_ font: NSFont?, size: Double = FontSize.standard) -> Bool {
        font?.fontName == NoteTextView.boldNoteFont(size: size).fontName && font?.pointSize == CGFloat(size)
    }

    private func isRegular(_ font: NSFont?, size: Double = FontSize.standard) -> Bool {
        font?.fontName == NoteTextView.noteFont(size: size).fontName && font?.pointSize == CGFloat(size)
    }

    /// True when the glyph of the character at `index` is a null glyph: it has no width and nothing is drawn.
    private func isNullGlyph(at index: Int, in host: Host) -> Bool {
        let textView = host.editor.textView
        guard let layoutManager = textView.layoutManager else { return false }
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        return layoutManager.propertyForGlyph(at: glyph).contains(.null)
    }

    private func spin(until condition: () -> Bool, seconds: TimeInterval = 2) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    }

    private func insert(_ text: String, into host: Host) {
        host.editor.textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func utf16Range(of needle: String, in text: String) -> NSRange {
        (text as NSString).range(of: needle)
    }

    /// The body of the `formatting` fixture (ScratchCore's `FixtureContent`), which the sections below refer to.
    private static let formattingBody = [
        "- first bullet",
        "  - nested bullet",
        "[ ] open task",
        "[x] done task",
        "Some **bold** text, `inline **code**` and https://example.com/a_(b)?q=1.",
        "Unclosed **star and a lone ` tick stay plain.",
        "```sh",
        "- not a bullet",
        "**not bold**",
        "```",
    ].joined(separator: "\n")

    // MARK: Bold and hidden markers

    func testBoldContentIsBoldAndMarkersAreNullGlyphs() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }

        show("a **b** c", caret: 0, in: host)

        XCTAssertTrue(isBold(font(at: 4, in: host)), "the b: \(String(describing: font(at: 4, in: host)))")
        XCTAssertTrue(isRegular(font(at: 0, in: host)))
        XCTAssertTrue(isRegular(font(at: 8, in: host)))
        for index in [2, 3, 5, 6] {
            XCTAssertTrue(isNullGlyph(at: index, in: host), "the marker at \(index) is hidden")
            XCTAssertEqual(role(at: index, in: host), "hidden")
        }
        for index in [0, 1, 4, 7, 8] { XCTAssertFalse(isNullGlyph(at: index, in: host), "the text at \(index)") }
        XCTAssertEqual(host.editor.currentText, "a **b** c", "styling never changes a character")
    }

    func testMarkersRevealedWhenCaretTouchesRun() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }

        show("a **b** c", caret: 7, in: host)

        for index in [2, 3, 5, 6] {
            XCTAssertFalse(isNullGlyph(at: index, in: host), "the marker at \(index) is shown")
            XCTAssertEqual(role(at: index, in: host), "revealed")
            XCTAssertEqual(attribute(.foregroundColor, at: index, in: host) as? NSColor, NSColor.tertiaryLabelColor)
        }
        XCTAssertTrue(isBold(font(at: 4, in: host)))
    }

    func testMarkersAreRevealedAtBothEdgesOfTheRun() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("a **b** c", caret: 0, in: host)

        host.editor.textView.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertEqual(role(at: 2, in: host), "revealed", "the caret in front of the run")

        host.editor.textView.setSelectedRange(NSRange(location: 1, length: 0))
        XCTAssertEqual(role(at: 2, in: host), "hidden", "one character away")

        host.editor.textView.setSelectedRange(NSRange(location: 7, length: 0))
        XCTAssertEqual(role(at: 6, in: host), "revealed", "the caret behind the run")

        host.editor.textView.setSelectedRange(NSRange(location: 8, length: 0))
        XCTAssertEqual(role(at: 6, in: host), "hidden", "one character away")
        XCTAssertTrue(isNullGlyph(at: 6, in: host))
    }

    func testASelectionThatTouchesTheRunRevealsItsMarkers() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("a **b** c", caret: 0, in: host)

        host.editor.textView.setSelectedRange(NSRange(location: 0, length: 3))

        XCTAssertEqual(role(at: 2, in: host), "revealed")
        XCTAssertEqual(role(at: 6, in: host), "revealed", "the whole run is one run")
    }

    func testBackspaceAfterBoldDeletesOneVisibleStar() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("a **b** c", caret: 7, in: host)
        XCTAssertFalse(isNullGlyph(at: 6, in: host), "the star that Backspace deletes is visible")

        host.editor.textView.deleteBackward(nil)

        XCTAssertEqual(host.editor.currentText, "a **b* c")
        // The run is no longer closed: plain text, with no hidden character.
        XCTAssertNil(role(at: 2, in: host))
        XCTAssertTrue(isRegular(font(at: 4, in: host)))
        for index in 0..<8 { XCTAssertFalse(isNullGlyph(at: index, in: host), "character \(index)") }
    }

    func testTypingClosesBoldRun() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("", in: host)

        insert("**x", into: host)
        XCTAssertNil(role(at: 0, in: host), "an unclosed run is plain")
        XCTAssertTrue(isRegular(font(at: 2, in: host)))

        insert("**", into: host)
        XCTAssertEqual(host.editor.currentText, "**x**")
        XCTAssertTrue(isBold(font(at: 2, in: host)))
        XCTAssertEqual(role(at: 0, in: host), "revealed", "the caret is at the end of the run")

        insert(" after", into: host)
        XCTAssertEqual(host.editor.currentText, "**x** after")
        for index in [0, 1, 3, 4] {
            XCTAssertEqual(role(at: index, in: host), "hidden", "the caret moved away from \(index)")
            XCTAssertTrue(isNullGlyph(at: index, in: host))
        }
        XCTAssertTrue(isRegular(font(at: 8, in: host)), "the text typed after the run is not bold")
    }

    func testFontSizeChangeKeepsBold() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("a **b** c", caret: 0, in: host)

        host.editor.setFontSize(20)

        XCTAssertTrue(isBold(font(at: 4, in: host), size: 20), "\(String(describing: font(at: 4, in: host)))")
        XCTAssertTrue(isRegular(font(at: 0, in: host), size: 20))
        XCTAssertTrue(isNullGlyph(at: 2, in: host))
        XCTAssertEqual(host.editor.textView.styler.fontSize, 20)
    }

    // MARK: Inline code, links, lists

    func testInlineCodeColours() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }

        show("x `code` y", caret: 0, in: host)

        XCTAssertEqual(attribute(.foregroundColor, at: 4, in: host) as? NSColor, MarkupColors.codeText)
        XCTAssertEqual(attribute(.backgroundColor, at: 4, in: host) as? NSColor, MarkupColors.codeBackground)
        XCTAssertEqual(attribute(.foregroundColor, at: 0, in: host) as? NSColor, NSColor.textColor)
        XCTAssertNil(attribute(.backgroundColor, at: 0, in: host))
        XCTAssertTrue(isNullGlyph(at: 2, in: host), "the opening backtick is hidden")
        XCTAssertTrue(isNullGlyph(at: 7, in: host), "the closing backtick is hidden")
        XCTAssertTrue(isRegular(font(at: 4, in: host)), "inline code keeps the note font")
    }

    func testTheCodeColoursComeFromTheAssets() {
        // `CodeText` is #C41A16 in light mode and #FC6A5D in dark mode, `CodeBackground` is black at 6% and white at 10%.
        func components(of color: NSColor, in name: NSAppearance.Name) -> [CGFloat] {
            var result: [CGFloat] = []
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
                if let rgb = color.usingColorSpace(.sRGB) {
                    result = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
                }
            }
            return result
        }
        let light = components(of: MarkupColors.codeText, in: .aqua)
        let dark = components(of: MarkupColors.codeText, in: .darkAqua)
        XCTAssertEqual(light.count, 4)
        XCTAssertEqual(dark.count, 4)
        guard light.count == 4, dark.count == 4 else { return }
        XCTAssertEqual(light[0], 196.0 / 255, accuracy: 0.01)
        XCTAssertEqual(light[1], 26.0 / 255, accuracy: 0.01)
        XCTAssertEqual(light[2], 22.0 / 255, accuracy: 0.01)
        XCTAssertEqual(dark[0], 252.0 / 255, accuracy: 0.01)
        XCTAssertEqual(dark[1], 106.0 / 255, accuracy: 0.01)
        XCTAssertEqual(dark[2], 93.0 / 255, accuracy: 0.01)
        let lightTint = components(of: MarkupColors.codeBackground, in: .aqua)
        let darkTint = components(of: MarkupColors.codeBackground, in: .darkAqua)
        XCTAssertEqual(lightTint.last ?? 0, 0.06, accuracy: 0.005)
        XCTAssertEqual(darkTint.last ?? 0, 0.10, accuracy: 0.005)
    }

    func testLinkIsColouredAndUnderlined() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let url = URL(string: "https://example.com/a")!

        show("see https://example.com/a. now", caret: 0, in: host)

        XCTAssertEqual(attribute(.foregroundColor, at: 10, in: host) as? NSColor, NSColor.linkColor)
        XCTAssertEqual(
            attribute(.underlineStyle, at: 10, in: host) as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(host.editor.textView.styler.link(at: 10), url)
        XCTAssertEqual(host.editor.textView.styler.link(at: 4), url, "the first character of the link")
        XCTAssertEqual(host.editor.textView.styler.link(at: 24), url, "the last character of the link")
        XCTAssertNil(host.editor.textView.styler.link(at: 25), "the period after the link")
        XCTAssertNil(host.editor.textView.styler.link(at: 0))
        XCTAssertNil(attribute(.underlineStyle, at: 25, in: host))
        XCTAssertNil(
            attribute(.link, at: 10, in: host), "a link is never the AppKit link attribute: a click must not open it")
    }

    func testBulletParagraphHasHangingIndent() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "- a\n  - b\nplain\n[ ] box"
        let space = (" " as NSString).size(withAttributes: [.font: NoteTextView.noteFont]).width

        show(text, caret: 0, in: host)

        let first = attribute(.paragraphStyle, at: 0, in: host) as? NSParagraphStyle
        XCTAssertEqual(first?.headIndent ?? 0, 2 * space, accuracy: 0.01, "level 0")
        XCTAssertEqual(first?.firstLineHeadIndent ?? -1, 0, accuracy: 0.01)
        let nested = attribute(.paragraphStyle, at: utf16Range(of: "  - b", in: text).location, in: host)
        XCTAssertEqual((nested as? NSParagraphStyle)?.headIndent ?? 0, 4 * space, accuracy: 0.01, "level 1")
        let plain = attribute(.paragraphStyle, at: utf16Range(of: "plain", in: text).location, in: host)
        XCTAssertEqual((plain as? NSParagraphStyle)?.headIndent ?? 0, 0, accuracy: 0.01, "not a list line")
        let box = attribute(.paragraphStyle, at: utf16Range(of: "[ ] box", in: text).location, in: host)
        XCTAssertEqual((box as? NSParagraphStyle)?.headIndent ?? 0, 4 * space, accuracy: 0.01, "text after `[ ] `")

        XCTAssertEqual(role(at: 0, in: host), "bullet")
        XCTAssertNil(role(at: 1, in: host))
        XCTAssertEqual(attribute(.foregroundColor, at: 0, in: host) as? NSColor, NSColor.clear)
        XCTAssertEqual(role(at: utf16Range(of: "[ ]", in: text).location, in: host), "checkboxOpen")
    }

    func testCheckedLineIsStruckThrough() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "[x] done\n[ ] open"

        show(text, caret: 0, in: host)

        XCTAssertEqual(
            attribute(.strikethroughStyle, at: 4, in: host) as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(attribute(.foregroundColor, at: 4, in: host) as? NSColor, NSColor.secondaryLabelColor)
        XCTAssertEqual(role(at: 0, in: host), "checkboxChecked")
        XCTAssertEqual(role(at: 2, in: host), "checkboxChecked")
        XCTAssertNil(role(at: 3, in: host), "the space after the box")
        XCTAssertNil(attribute(.strikethroughStyle, at: 3, in: host))
        XCTAssertEqual(role(at: 9, in: host), "checkboxOpen")
        XCTAssertNil(attribute(.strikethroughStyle, at: 13, in: host), "an open item is not struck through")
        XCTAssertEqual(attribute(.foregroundColor, at: 13, in: host) as? NSColor, NSColor.textColor)

        let styler = host.editor.textView.styler!
        XCTAssertEqual(styler.checkboxMarker(at: 0), NSRange(location: 0, length: 3))
        XCTAssertEqual(styler.checkboxMarker(at: 2), NSRange(location: 0, length: 3))
        XCTAssertNil(styler.checkboxMarker(at: 3), "a click to the right of the box is not a toggle")
        XCTAssertEqual(styler.checkboxMarker(at: 9), NSRange(location: 9, length: 3))
        XCTAssertNil(styler.checkboxMarker(at: 100))
    }

    // MARK: Code blocks and unclosed markers

    func testFencedBlockIsNotStyled() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = Self.formattingBody

        show(text, caret: 0, in: host)

        let notBold = utf16Range(of: "**not bold**", in: text)
        XCTAssertTrue(isRegular(font(at: notBold.location + 2, in: host)), "the weight inside the block")
        XCTAssertNil(role(at: notBold.location, in: host))
        XCTAssertFalse(isNullGlyph(at: notBold.location, in: host))
        let notBullet = utf16Range(of: "- not a bullet", in: text)
        XCTAssertNil(role(at: notBullet.location, in: host), "no role on the dash in the block")
        XCTAssertNil(attribute(.paragraphStyle, at: notBullet.location, in: host))
        XCTAssertEqual(attribute(.foregroundColor, at: notBullet.location, in: host) as? NSColor, NSColor.textColor)

        let styler = host.editor.textView.styler!
        XCTAssertTrue(styler.isInCodeBlock(notBold.location))
        XCTAssertTrue(styler.isInCodeBlock(utf16Range(of: "```sh", in: text).location))
        XCTAssertFalse(styler.isInCodeBlock(0))
        XCTAssertFalse(styler.isInCodeBlock(utf16Range(of: "Some", in: text).location))

        // Outside the block the same markers render.
        XCTAssertEqual(role(at: 0, in: host), "bullet")
        XCTAssertTrue(isBold(font(at: utf16Range(of: "bold", in: text).location, in: host)))
        XCTAssertEqual(host.editor.currentText, text, "the block's characters are as typed")
    }

    func testMarkersInsideInlineCodeAreLiteral() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = Self.formattingBody

        show(text, caret: 0, in: host)

        let inner = utf16Range(of: "**code**", in: text)
        XCTAssertTrue(isRegular(font(at: inner.location + 2, in: host)), "the stars of inline code are not bold")
        XCTAssertNil(role(at: inner.location, in: host))
        XCTAssertEqual(
            attribute(.foregroundColor, at: inner.location, in: host) as? NSColor, MarkupColors.codeText)
    }

    func testUnclosedMarkersArePlain() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "Unclosed **star and a lone ` tick stay plain.\n**a\n`x"

        show(text, caret: 0, in: host)

        let storage = host.editor.textView.textStorage!
        storage.enumerateAttribute(.scratchMarker, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            XCTAssertNil(value, "a marker with no partner has no role")
        }
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            XCTAssertTrue(self.isRegular(value as? NSFont))
        }
        for index in 0..<storage.length { XCTAssertFalse(isNullGlyph(at: index, in: host), "character \(index)") }
    }

    func testTypingAClosingFenceTurnsTheLinesBetweenIntoCode() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "**a**\n```\n**b**\n- c\n"
        show(text, caret: text.utf16.count, in: host)
        let inside = utf16Range(of: "**b**", in: text).location
        XCTAssertTrue(isBold(font(at: inside + 2, in: host)), "an unclosed fence is no block")
        XCTAssertEqual(role(at: utf16Range(of: "- c", in: text).location, in: host), "bullet")

        insert("```", into: host)

        let closed = host.editor.currentText
        XCTAssertEqual(closed, text + "```")
        XCTAssertTrue(isRegular(font(at: inside + 2, in: host)), "the closing fence made a block")
        XCTAssertNil(role(at: inside, in: host))
        XCTAssertNil(role(at: utf16Range(of: "- c", in: text).location, in: host))
        XCTAssertTrue(isBold(font(at: 2, in: host)), "the text above the block stays styled")
        XCTAssertTrue(host.editor.textView.styler.isInCodeBlock(inside))

        host.editor.textView.deleteBackward(nil)
        host.editor.textView.deleteBackward(nil)
        host.editor.textView.deleteBackward(nil)

        XCTAssertEqual(host.editor.currentText, text)
        XCTAssertTrue(isBold(font(at: inside + 2, in: host)), "without the closing fence it is no block again")
        XCTAssertEqual(role(at: utf16Range(of: "- c", in: text).location, in: host), "bullet")
        XCTAssertFalse(host.editor.textView.styler.isInCodeBlock(inside))
    }

    func testTypingInsideABlockKeepsTheBlock() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "```\nx\n```\n**b**"
        show(text, caret: 5, in: host)

        insert("**y**", into: host)

        XCTAssertEqual(host.editor.currentText, "```\nx**y**\n```\n**b**")
        XCTAssertNil(role(at: 6, in: host), "typed inside the block: literal")
        XCTAssertTrue(isRegular(font(at: 8, in: host)))
        let styler = host.editor.textView.styler!
        XCTAssertTrue(styler.isInCodeBlock(6))
        let after = (host.editor.currentText as NSString).range(of: "**b**").location
        XCTAssertFalse(styler.isInCodeBlock(after))
        XCTAssertTrue(isBold(font(at: after + 2, in: host)), "the paragraph after the block is still styled")
        XCTAssertEqual(role(at: after, in: host), "hidden")
    }

    // MARK: Undo and copy

    func testStylingDoesNotRegisterUndo() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let undo = UndoManager()

        show(Self.formattingBody, caret: 3, undoManager: undo, in: host)
        host.editor.textView.styler.noteDidLoad(visibleRange: NSRange(location: 0, length: 0))
        host.editor.textView.setSelectedRange(NSRange(location: 20, length: 0))
        host.editor.setFontSize(18)

        XCTAssertFalse(undo.canUndo, "attribute changes are not undo steps")
    }

    func testTypingInStyledTextIsOneUndoStepThatStylesTheTextAgain() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let undo = UndoManager()
        show("a **b** c", caret: 9, undoManager: undo, in: host)

        insert("!", into: host)
        XCTAssertEqual(host.editor.currentText, "a **b** c!")
        undo.undo()

        XCTAssertEqual(host.editor.currentText, "a **b** c")
        XCTAssertTrue(isBold(font(at: 4, in: host)))
    }

    func testCopyKeepsMarkers() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "- [ ] **b** `c` https://example.com\n[x] done"
        show(text, caret: 0, in: host)
        host.editor.textView.setSelectedRange(NSRange(location: 0, length: text.utf16.count))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()

        let written = host.editor.textView.writeSelection(
            to: pasteboard, types: host.editor.textView.writablePasteboardTypes)

        XCTAssertTrue(written)
        XCTAssertEqual(pasteboard.string(forType: .string), text)
        XCTAssertFalse((pasteboard.types ?? []).contains(.rtf))
    }

    func testPastedTextRendersLikeTypedText() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("", in: host)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let rich = NSAttributedString(
            string: "- one **two**",
            attributes: [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.red])
        pasteboard.writeObjects([rich])

        XCTAssertTrue(host.editor.textView.readSelection(from: pasteboard))

        XCTAssertEqual(host.editor.currentText, "- one **two**")
        XCTAssertEqual(role(at: 0, in: host), "bullet")
        XCTAssertTrue(isBold(font(at: 9, in: host)))
        XCTAssertTrue(isRegular(font(at: 3, in: host)))
        XCTAssertEqual(attribute(.foregroundColor, at: 3, in: host) as? NSColor, NSColor.textColor)
    }

    // MARK: A long note

    /// 10,000 lines: every eighth is a bullet, a task, bold, or code and a link, and a fenced block of four lines starts
    /// at every 400th line.
    private func makeLongText() -> String {
        var lines: [String] = []
        for number in 1...10_000 {
            if number % 400 == 1 {
                lines.append(contentsOf: ["```sh", "- not a bullet \(number)", "**not bold**", "```"])
                continue
            }
            if number % 400 >= 2 && number % 400 <= 4 { continue }
            switch number % 8 {
            case 0: lines.append("- bullet \(number)")
            case 1: lines.append("[ ] task \(number)")
            case 3: lines.append("some **bold** \(number)")
            case 5: lines.append("`code` and https://example.com/\(number)")
            default: lines.append("plain line \(number) with a few words in it")
            }
        }
        return lines.joined(separator: "\n")
    }

    func testHugeNoteIsFullyStyledSoon() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = makeLongText()
        let textView = host.editor.textView
        textView.load(text)

        let clock = ContinuousClock()
        let took = clock.measure { textView.styler.noteDidLoad(visibleRange: NSRange(location: 0, length: 0)) }

        XCTAssertLessThan(took, .milliseconds(100), "the synchronous part of styling a note (Debug build)")
        XCTAssertFalse(textView.styler.isFullyStyled, "the rest is styled in chunks")
        let spinStart = clock.now
        spin(until: { textView.styler.isFullyStyled }, seconds: 1)
        let spun = clock.now - spinStart
        XCTAssertTrue(
            textView.styler.isFullyStyled, "the whole note is styled within a second of run loop time (took \(spun))")

        // The last paragraphs, which only a chunk reaches, are styled; the blocks' lines are not.
        let storage = textView.textStorage!
        let nsText = storage.string as NSString
        let lastBold = nsText.range(of: "some **bold**", options: .backwards)
        XCTAssertEqual(
            (storage.attribute(.scratchMarker, at: lastBold.location + 5, effectiveRange: nil) as? String), "hidden")
        let lastBullet = nsText.range(of: "- bullet", options: .backwards)
        XCTAssertEqual(
            (storage.attribute(.scratchMarker, at: lastBullet.location, effectiveRange: nil) as? String), "bullet")
        let lastNotBullet = nsText.range(of: "- not a bullet", options: .backwards)
        XCTAssertNil(storage.attribute(.scratchMarker, at: lastNotBullet.location, effectiveRange: nil))
        XCTAssertTrue(textView.styler.isInCodeBlock(lastNotBullet.location))
        XCTAssertEqual(textView.string, text, "styling never changes a character")
    }

    func testAnEditWhileTheRestOfANoteIsStyledKeepsTheRestRight() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        // A plain first line, so that typing there does not touch a fence.
        let text = "intro\n" + makeLongText()
        let textView = host.editor.textView
        textView.load(text)
        textView.styler.noteDidLoad(visibleRange: NSRange(location: 0, length: 0))
        XCTAssertFalse(textView.styler.isFullyStyled)

        // Typed at the top while the chunks below are still pending: everything pending moves.
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.insertText("**first** ", replacementRange: NSRange(location: NSNotFound, length: 0))
        spin(until: { textView.styler.isFullyStyled }, seconds: 2)

        XCTAssertTrue(textView.styler.isFullyStyled)
        let storage = textView.textStorage!
        XCTAssertTrue(isBold(storage.attribute(.font, at: 4, effectiveRange: nil) as? NSFont), "the typed text")
        let nsText = storage.string as NSString
        let lastBold = nsText.range(of: "some **bold**", options: .backwards)
        XCTAssertEqual(
            (storage.attribute(.scratchMarker, at: lastBold.location + 5, effectiveRange: nil) as? String), "hidden")
        XCTAssertTrue(
            isBold(storage.attribute(.font, at: lastBold.location + 8, effectiveRange: nil) as? NSFont),
            "the last paragraph that was pending")
    }

    func testABigPasteIsStyledAfterwards() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("", in: host)
        let pasted = (1...2_000).map { "- item **\($0)**" }.joined(separator: "\n")
        XCTAssertGreaterThan(pasted.utf16.count, MarkupStyler.largeEdit)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString(pasted, forType: .string)

        XCTAssertTrue(host.editor.textView.readSelection(from: pasteboard))
        spin(until: { host.editor.textView.styler.isFullyStyled }, seconds: 2)

        XCTAssertTrue(host.editor.textView.styler.isFullyStyled)
        XCTAssertEqual(host.editor.currentText, pasted)
        let last = (pasted as NSString).range(of: "- item **2000**")
        XCTAssertEqual(role(at: last.location, in: host), "bullet")
        XCTAssertTrue(isBold(font(at: last.location + 9, in: host)))
        // The caret is at the end of the pasted text, which is the end of this run: its markers are shown.
        XCTAssertEqual(role(at: last.location + 7, in: host), "revealed")
        XCTAssertEqual(role(at: (pasted as NSString).range(of: "- item **1999**").location + 7, in: host), "hidden")
    }

    func testAnEmptyNoteAndDeletingAllTextAreHandled() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }

        show("", in: host)
        XCTAssertTrue(host.editor.textView.styler.isFullyStyled)
        insert("- a", into: host)
        XCTAssertEqual(role(at: 0, in: host), "bullet")

        host.editor.textView.selectAll(nil)
        host.editor.textView.deleteBackward(nil)

        XCTAssertEqual(host.editor.currentText, "")
        XCTAssertFalse(host.editor.textView.styler.isInCodeBlock(0))
    }
}
