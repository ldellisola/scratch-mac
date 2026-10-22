import AppKit
import ScratchCode
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/code.md ("Rendering"): a fenced block is a tinted block whose fence lines
/// shrink to padding and show again when the caret touches them, its lines are indented, its code is coloured by
/// tree-sitter on a background queue (and a result for text that has changed since is dropped), its label says the
/// language, and a block too long to colour stays uncoloured. Nothing here changes a character of the note (spec §6.4,
/// plan 4 task 5).
@MainActor
final class CodeBlockStylerTests: XCTestCase {
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

    private func makeNote(_ text: String) -> Note {
        Note(id: NoteID.make(), title: "", body: text, createdAt: Date(), modifiedAt: Date())
    }

    /// Shows `text` as a note, with the caret at `caret`, and lays the editor out so that line heights can be measured.
    private func show(_ text: String, caret: Int = 0, undoManager: UndoManager = UndoManager(), in host: Host) {
        let note = makeNote(text)
        let tab = TabState(noteID: note.id, selection: caret, scrollY: 0, scrollAnchor: nil)
        host.editor.show(note, tab: tab, undoManager: undoManager, isReadOnly: false)
        host.editor.view.layoutSubtreeIfNeeded()
    }

    private func codeStyler(of host: Host) -> CodeBlockStyler {
        host.editor.textView.styler.codeBlockStyler
    }

    private func attribute(_ key: NSAttributedString.Key, at index: Int, in host: Host) -> Any? {
        host.editor.textView.textStorage?.attribute(key, at: index, effectiveRange: nil)
    }

    private func role(at index: Int, in host: Host) -> String? {
        attribute(.scratchMarker, at: index, in: host) as? String
    }

    /// The colour that the character at `index` is drawn in: the layout manager's temporary one, which is where the
    /// colours of code are, or else the text storage's.
    private func colour(at index: Int, in host: Host) -> NSColor? {
        let temporary = host.editor.textView.layoutManager?.temporaryAttribute(
            .foregroundColor, atCharacterIndex: index, effectiveRange: nil)
        return (temporary ?? attribute(.foregroundColor, at: index, in: host)) as? NSColor
    }

    private func paragraphStyle(at index: Int, in host: Host) -> NSParagraphStyle? {
        attribute(.paragraphStyle, at: index, in: host) as? NSParagraphStyle
    }

    /// The tail indent of the first line of code of a block whose label says `name`: the 10 pt that every line is in from the
    /// right, the width of the label (a monospaced font 2 pt smaller than the note's) and 12 pt of space. Worked out here, in
    /// the test, and not by the code it tests.
    private func firstLineTail(label name: String, noteSize: CGFloat = CGFloat(FontSize.standard)) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: noteSize - 2, weight: .regular)
        let width = (name as NSString).size(withAttributes: [.font: font]).width
        return -(10 + width + 12)
    }

    /// The tail indent of the line that starts with `needle` in `text`.
    private func tailIndent(ofLineWith needle: String, in text: String, host: Host) -> CGFloat? {
        paragraphStyle(at: (text as NSString).range(of: needle).location, in: host)?.tailIndent
    }

    private func isNullGlyph(at index: Int, in host: Host) -> Bool {
        guard let layoutManager = host.editor.textView.layoutManager else { return false }
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        return layoutManager.propertyForGlyph(at: glyph).contains(.null)
    }

    /// The height of the line that holds the character at `index`, with the whole note laid out first (a layout that
    /// stops at the line would leave it as it was before the fence lines were hidden).
    private func lineHeight(at index: Int, in host: Host) -> CGFloat {
        guard let layoutManager = host.editor.textView.layoutManager else { return -1 }
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: host.editor.currentText.utf16.count))
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).height
    }

    private func spin(until condition: () -> Bool, seconds: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    }

    /// Runs the main run loop until every highlight that was asked for has been applied (or dropped).
    private func waitForHighlights(in host: Host, file: StaticString = #filePath, line: UInt = #line) {
        let styler = codeStyler(of: host)
        spin(until: { styler.pendingHighlights == 0 })
        XCTAssertEqual(styler.pendingHighlights, 0, "the highlights are applied within seconds", file: file, line: line)
    }

    private func insert(_ text: String, into host: Host) {
        host.editor.textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    /// The red, green, blue and alpha components of `color` as it looks in the appearance `name`.
    private func components(of color: NSColor, in name: NSAppearance.Name = .aqua) -> [CGFloat] {
        var result: [CGFloat] = []
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            if let rgb = color.usingColorSpace(.sRGB) {
                result = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
            }
        }
        return result
    }

    /// True when `actual` looks like the colour of the asset `name`.
    private func isAsset(_ name: String, _ actual: NSColor?) -> Bool {
        guard let actual, let expected = NSColor(named: NSColor.Name(name)) else { return false }
        let expectedComponents = components(of: expected)
        return !expectedComponents.isEmpty && components(of: actual) == expectedComponents
    }

    private func isTextColour(_ actual: NSColor?) -> Bool {
        guard let actual else { return false }
        let expected = components(of: NSColor.textColor)
        return !expected.isEmpty && components(of: actual) == expected
    }

    private func assetName(of kind: HighlightKind) -> String {
        "Code" + kind.rawValue.prefix(1).uppercased() + String(kind.rawValue.dropFirst())
    }

    /// The body of the `typical` fixture's "Deploy checklist" (ScratchCore's `FixtureContent`): a checklist, bullets and
    /// a `bash` block.
    private static let typicalBody = [
        "[ ] bump version to `2.4.1`",
        "[x] run migrations on staging",
        "[ ] tag the release",
        "",
        "- check error rate in grafana after rollout",
        "- **don't deploy after 4pm on fridays**",
        "",
        "```bash",
        "# watch the rollout",
        "kubectl rollout status deploy/api -n prod",
        #"kubectl logs -l app=api --since=10m | grep -i "error""#,
        "```",
    ].joined(separator: "\n")

    /// A block with no name on its fence, holding JavaScript (the `code` fixture's last block).
    private static let unnamedBody = [
        "A fence with no name.",
        "```",
        #"const notes = await fetch("/notes").then((r) => r.json());"#,
        "// the newest note comes first",
        #"console.log(notes[0]?.title ?? "none", notes.length);"#,
        "```",
    ].joined(separator: "\n")

    // MARK: Blocks

    func testExistingFencesRenderAsBlocks() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = Self.typicalBody as NSString

        show(Self.typicalBody, in: host)

        // The fence lines have no glyphs and are no higher than 6 points.
        let opening = text.range(of: "```bash")
        let closing = text.range(of: "```", options: .backwards)
        XCTAssertNotEqual(opening.location, closing.location)
        for (name, fence) in [("opening", opening), ("closing", closing)] {
            for offset in 0..<fence.length {
                // The first character keeps its glyph, a clear one: null glyphs take no line fragment of their own, they
                // sit at the end of the line above, and a line of null glyphs only would have no height at all (see
                // `MarkupLayoutManager.shouldGenerateGlyphs`).
                XCTAssertEqual(
                    isNullGlyph(at: fence.location + offset, in: host), offset != 0, "\(name) fence character \(offset)"
                )
                XCTAssertEqual(role(at: fence.location + offset, in: host), "fence")
                XCTAssertEqual(colour(at: fence.location + offset, in: host), NSColor.clear, "nothing of it is drawn")
            }
            XCTAssertLessThanOrEqual(
                lineHeight(at: fence.location, in: host), 6.01, "the \(name) fence line is padding")
            XCTAssertEqual(
                paragraphStyle(at: fence.location, in: host)?.maximumLineHeight, 6, "the paragraph style says so")
        }
        XCTAssertEqual(
            lineHeight(at: opening.location - 1, in: host), 16, accuracy: 1, "the blank line above is a line")

        // The lines of the block are 10 points in from both sides, and keep the note font. The first one is further in from
        // the right: the label reaches into it (`testFirstLineOfCodeWrapsBeforeLabel`).
        for needle in ["# watch the rollout", "kubectl rollout status", "kubectl logs"] {
            let index = text.range(of: needle).location
            let style = paragraphStyle(at: index, in: host)
            XCTAssertEqual(style?.headIndent, 10, needle)
            XCTAssertEqual(style?.firstLineHeadIndent, 10, needle)
            let tail = needle == "# watch the rollout" ? firstLineTail(label: "Shell") : -10
            XCTAssertEqual(style?.tailIndent ?? 0, tail, accuracy: 0.01, needle)
            XCTAssertNil(role(at: index, in: host), "nothing in a block is a marker")
            XCTAssertGreaterThan(lineHeight(at: index, in: host), 10, "a line of code is a line of text")
            XCTAssertEqual((attribute(.font, at: index, in: host) as? NSFont)?.pointSize, CGFloat(FontSize.standard))
        }

        // The text around the block is as before (the checklist and the bullets), and nothing was changed.
        XCTAssertEqual(role(at: 0, in: host), "checkboxOpen")
        XCTAssertEqual(
            paragraphStyle(at: text.range(of: "- check").location, in: host)?.tailIndent, 0,
            "a list line is not a block line")
        XCTAssertEqual(host.editor.currentText, Self.typicalBody, "rendering never changes a character")
    }

    func testBlockLabelIsKnownAtOnceForANamedFence() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = Self.typicalBody as NSString

        show(Self.typicalBody, in: host)

        let inside = text.range(of: "kubectl rollout").location
        let language = codeStyler(of: host).language(ofBlockAt: inside)
        XCTAssertEqual(language?.0, .bash)
        XCTAssertEqual(language?.isDetected, false)
        XCTAssertEqual(language?.name, "Shell")
        XCTAssertNil(codeStyler(of: host).language(ofBlockAt: 0), "a position outside every block")
        XCTAssertEqual(
            codeStyler(of: host).language(ofBlockAt: text.range(of: "```bash").location)?.name, "Shell",
            "the opening fence line is in the block")
    }

    func testBlockIsColoured() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = Self.typicalBody as NSString
        show(Self.typicalBody, in: host)
        XCTAssertGreaterThan(codeStyler(of: host).pendingHighlights, 0, "the block was asked for in `show`")

        waitForHighlights(in: host)

        let command = text.range(of: "kubectl rollout").location
        XCTAssertFalse(isTextColour(colour(at: command, in: host)), "the command is coloured")
        XCTAssertTrue(isAsset("CodeFunction", colour(at: command, in: host)), "a command is a function")
        let comment = text.range(of: "# watch the rollout")
        for offset in [0, 5, comment.length - 1] {
            XCTAssertTrue(
                isAsset("CodeComment", colour(at: comment.location + offset, in: host)),
                "the comment, character \(offset)")
        }
        // What is not a token has the text colour, the prose above the block too.
        XCTAssertTrue(isTextColour(colour(at: text.range(of: " rollout status").location, in: host)))
        XCTAssertTrue(isTextColour(colour(at: text.range(of: "tag the release").location, in: host)))
        XCTAssertEqual(host.editor.currentText, Self.typicalBody, "colouring never changes a character")
        XCTAssertEqual(codeStyler(of: host).pendingHighlights, 0)
    }

    func testFenceRevealedWhenCaretOnIt() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = Self.typicalBody as NSString
        show(Self.typicalBody, in: host)
        let opening = text.range(of: "```bash")
        let closing = text.range(of: "```", options: .backwards)
        let textView = host.editor.textView

        // The second character: the first keeps its (clear) glyph, so that the line has a line fragment of its own.
        XCTAssertTrue(isNullGlyph(at: opening.location + 1, in: host), "hidden while the caret is away")

        textView.setSelectedRange(NSRange(location: opening.location + 3, length: 0))

        for offset in 0..<opening.length {
            XCTAssertFalse(isNullGlyph(at: opening.location + offset, in: host), "shown: character \(offset)")
            XCTAssertEqual(role(at: opening.location + offset, in: host), "revealed")
            XCTAssertEqual(colour(at: opening.location + offset, in: host), NSColor.tertiaryLabelColor)
        }
        XCTAssertGreaterThan(lineHeight(at: opening.location, in: host), 10, "shown in full")
        XCTAssertTrue(isNullGlyph(at: closing.location + 1, in: host), "the other fence stays hidden")
        XCTAssertEqual(host.editor.currentText, Self.typicalBody)

        // The caret at the end of the closing fence line touches that one, and lets go of the first.
        textView.setSelectedRange(NSRange(location: NSMaxRange(closing), length: 0))

        XCTAssertTrue(isNullGlyph(at: opening.location + 1, in: host), "hidden again")
        XCTAssertEqual(role(at: opening.location, in: host), "fence")
        XCTAssertLessThanOrEqual(lineHeight(at: opening.location, in: host), 6.01)
        XCTAssertFalse(isNullGlyph(at: closing.location + 1, in: host))
        XCTAssertEqual(role(at: closing.location, in: host), "revealed")

        // A caret on the first line of code touches neither fence.
        textView.setSelectedRange(NSRange(location: text.range(of: "# watch").location, length: 0))

        XCTAssertTrue(isNullGlyph(at: opening.location + 1, in: host))
        XCTAssertTrue(isNullGlyph(at: closing.location + 1, in: host))
    }

    func testASelectionThatHoldsTheBlockShowsItsFences() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = Self.typicalBody as NSString
        show(Self.typicalBody, in: host)
        let opening = text.range(of: "```bash")

        host.editor.textView.setSelectedRange(NSRange(location: opening.location - 4, length: 12))

        XCTAssertFalse(isNullGlyph(at: opening.location + 1, in: host), "a selection that touches the fence shows it")
        XCTAssertEqual(role(at: opening.location, in: host), "revealed")
    }

    // MARK: Colours and results that are out of date

    func testStaleHighlightIsNotApplied() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show(Self.typicalBody, in: host)
        let styler = codeStyler(of: host)
        XCTAssertGreaterThan(styler.pendingHighlights, 0, "the request is made before anything is typed")

        // Type inside the block before the result of the first request lands: the main run loop has not run since.
        let at = (Self.typicalBody as NSString).range(of: "kubectl rollout").location + 3
        host.editor.textView.setSelectedRange(NSRange(location: at, length: 0))
        insert("XY", into: host)
        let typed = host.editor.currentText
        XCTAssertTrue(typed.contains("kubXYectl rollout"))
        waitForHighlights(in: host)

        XCTAssertGreaterThanOrEqual(styler.droppedResults, 1, "the result for the text before the edit was dropped")
        XCTAssertEqual(host.editor.currentText, typed, "the characters are the ones typed")

        // The colours are those of the text as it is now, the way a fresh highlight reads it.
        let text = typed as NSString
        let start = text.range(of: "# watch the rollout").location
        let end = text.range(of: "```", options: .backwards).location - 1
        let code = text.substring(with: NSRange(location: start, length: end - start))
        let tokens = Highlighter.shared.tokens(in: code, language: .bash) ?? []
        XCTAssertGreaterThanOrEqual(tokens.count, 4)
        var expected = [String?](repeating: nil, count: (code as NSString).length)
        for token in tokens {
            for offset in token.range.location..<NSMaxRange(token.range) {
                expected[offset] = assetName(of: token.kind)
            }
        }
        for (offset, name) in expected.enumerated() {
            let actual = colour(at: start + offset, in: host)
            if let name {
                XCTAssertTrue(isAsset(name, actual), "character \(offset) is \(name)")
            } else {
                XCTAssertTrue(isTextColour(actual), "character \(offset) has the text colour")
            }
        }
    }

    func testTokenColoursSurviveAKeystroke() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = Self.typicalBody as NSString
        show(Self.typicalBody, in: host)
        waitForHighlights(in: host)
        let comment = text.range(of: "# watch the rollout")
        let command = text.range(of: "kubectl rollout").location
        XCTAssertTrue(isAsset("CodeComment", colour(at: comment.location, in: host)))

        // Typing on the line of the command, and on the line above it: the colours stay until a new result replaces them.
        host.editor.textView.setSelectedRange(NSRange(location: command + 4, length: 0))
        insert("z", into: host)

        XCTAssertTrue(isAsset("CodeComment", colour(at: comment.location, in: host)), "another line keeps its colours")
        XCTAssertTrue(isAsset("CodeFunction", colour(at: command, in: host)), "the edited line keeps its colours")
        XCTAssertEqual(paragraphStyle(at: command, in: host)?.headIndent, 10, "and its indent")
        XCTAssertNil(role(at: command, in: host))

        waitForHighlights(in: host)

        XCTAssertTrue(isAsset("CodeFunction", colour(at: command, in: host)))
        XCTAssertTrue(isAsset("CodeComment", colour(at: comment.location, in: host)))
    }

    func testUnnamedFenceUsesDetectedLanguage() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = Self.unnamedBody as NSString
        show(Self.unnamedBody, in: host)
        let inside = text.range(of: "const notes").location

        let before = codeStyler(of: host).language(ofBlockAt: inside)
        XCTAssertNil(before?.0, "nothing is known until the content has been looked at")
        XCTAssertEqual(before?.name, "")

        waitForHighlights(in: host)

        let language = codeStyler(of: host).language(ofBlockAt: inside)
        XCTAssertEqual(language?.0, .javascript)
        XCTAssertEqual(language?.isDetected, true, "a detected language is in italics")
        XCTAssertEqual(language?.name, "JavaScript")
        XCTAssertTrue(isAsset("CodeKeyword", colour(at: inside, in: host)), "const is a keyword")
        XCTAssertEqual(host.editor.currentText, Self.unnamedBody, "the fence is never edited by detection")
    }

    func testUnknownFenceNameIsUncoloured() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let body = "```ruby\nputs 'hello'\nclass Note; end\n```"
        let text = body as NSString
        show(body, in: host)

        waitForHighlights(in: host)

        let language = codeStyler(of: host).language(ofBlockAt: text.range(of: "puts").location)
        XCTAssertNil(language?.0)
        XCTAssertEqual(language?.name, "ruby", "the label is the name as written")
        XCTAssertEqual(language?.isDetected, false)
        let content = text.range(of: "puts 'hello'\nclass Note; end")
        for offset in 0..<content.length {
            XCTAssertTrue(isTextColour(colour(at: content.location + offset, in: host)), "character \(offset)")
        }
        XCTAssertEqual(paragraphStyle(at: content.location, in: host)?.headIndent, 10, "still a tinted block")
    }

    func testHugeBlockIsNotHighlighted() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let lines = (1...6_000).map { "let value\($0) = \($0)" }
        let body = "```swift\n" + lines.joined(separator: "\n") + "\n```"
        let note = makeNote(body)
        let tab = TabState(noteID: note.id, selection: 0, scrollY: 0, scrollAnchor: nil)

        let took = ContinuousClock().measure {
            host.editor.show(note, tab: tab, undoManager: UndoManager(), isReadOnly: false)
        }

        XCTAssertLessThan(took, .milliseconds(100), "`show` of a block over the cap (Debug build)")
        host.editor.view.layoutSubtreeIfNeeded()
        waitForHighlights(in: host)
        spin(until: { host.editor.textView.styler.isFullyStyled })

        let language = codeStyler(of: host).language(ofBlockAt: 20)
        XCTAssertEqual(language?.0, .swift, "the fence still says Swift")
        XCTAssertEqual(language?.name, "Swift", "a block too long to colour shows its name only")
        XCTAssertEqual(language?.isDetected, false)
        let length = (body as NSString).length
        for index in stride(from: 10, to: length - 10, by: 997) {
            XCTAssertTrue(isTextColour(colour(at: index, in: host)), "character \(index) has no token colour")
        }
        XCTAssertEqual(paragraphStyle(at: 20, in: host)?.headIndent, 10, "the block is tinted")
        XCTAssertEqual(host.editor.currentText, body)
    }

    func testNothingAboveTheWindowChangesHeightWhenTheRestOfTheNoteIsStyled() {
        // The position of a note is worked out from the layout of what is above it, so every block above the window must
        // have its final look (6 pt fence lines, indented lines) before that layout: on the CI the line at the top of a
        // note shown again was three lines off, because the chunks that styled the blocks above ran after the scroll
        // position was set.
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        var lines: [String] = []
        for block in 0..<60 {
            lines += ["prose \(block) a", "prose \(block) b", "```swift"]
            lines += (0..<6).map { "let value\($0) = \($0)" }
            lines.append("```")
        }
        let body = lines.joined(separator: "\n")
        let anchor = (body as NSString).range(of: "prose 55 a").location
        let note = makeNote(body)
        let tab = TabState(noteID: note.id, selection: 0, scrollY: 0, scrollAnchor: anchor)

        host.editor.show(note, tab: tab, undoManager: UndoManager(), isReadOnly: false)
        host.editor.view.layoutSubtreeIfNeeded()
        let layoutManager = host.editor.textView.layoutManager!
        func top(of index: Int) -> CGFloat {
            layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: index + 1))
            let glyph = layoutManager.glyphIndexForCharacter(at: index)
            return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
        }
        let before = top(of: anchor)
        XCTAssertFalse(host.editor.textView.styler.isFullyStyled, "the rest of the note is styled in chunks")

        spin(until: { host.editor.textView.styler.isFullyStyled })
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: (body as NSString).length))

        XCTAssertTrue(host.editor.textView.styler.isFullyStyled)
        XCTAssertEqual(top(of: anchor), before, accuracy: 0.5, "the line at the top has not moved")
    }

    // MARK: Several blocks and several notes

    func testTwoBlocksWithTheSameCodeAreBothColoured() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let block = "```python\n# twice\ndef f():\n    return 1\n```"
        let body = block + "\ntext in between\n" + block
        let text = body as NSString
        show(body, in: host)

        waitForHighlights(in: host)

        let first = text.range(of: "def f").location
        let second = text.range(of: "def f", options: .backwards).location
        XCTAssertNotEqual(first, second)
        for index in [first, second] {
            XCTAssertTrue(isAsset("CodeKeyword", colour(at: index, in: host)), "def at \(index)")
            XCTAssertEqual(codeStyler(of: host).language(ofBlockAt: index)?.name, "Python")
        }
        XCTAssertTrue(isTextColour(colour(at: text.range(of: "text in between").location, in: host)))
    }

    func testShowingAnotherNoteColoursItsBlocksAndTheFirstOneAgain() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show(Self.typicalBody, in: host)
        waitForHighlights(in: host)
        let other = "text\n```sql\nSELECT 1 FROM t;\n```"

        show(other, in: host)
        waitForHighlights(in: host)

        let select = (other as NSString).range(of: "SELECT").location
        XCTAssertTrue(isAsset("CodeKeyword", colour(at: select, in: host)), "the second note's block")
        XCTAssertEqual(codeStyler(of: host).language(ofBlockAt: select)?.0, .sql)

        show(Self.typicalBody, in: host)
        waitForHighlights(in: host)

        let command = (Self.typicalBody as NSString).range(of: "kubectl rollout").location
        XCTAssertTrue(isAsset("CodeFunction", colour(at: command, in: host)), "the first note again")
    }

    func testRemovingTheClosingFenceTurnsTheBlockBackIntoProse() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let body = "intro\n```bash\n# note\nls -l\n```"
        let text = body as NSString
        show(body, caret: text.length, in: host)
        waitForHighlights(in: host)
        let comment = text.range(of: "# note").location
        XCTAssertTrue(isAsset("CodeComment", colour(at: comment, in: host)))
        XCTAssertEqual(paragraphStyle(at: comment, in: host)?.headIndent, 10)

        for _ in 0..<3 { host.editor.textView.deleteBackward(nil) }
        waitForHighlights(in: host)

        XCTAssertEqual(host.editor.currentText, "intro\n```bash\n# note\nls -l\n")
        XCTAssertNil(codeStyler(of: host).language(ofBlockAt: comment), "an unclosed fence is no block")
        XCTAssertTrue(isTextColour(colour(at: comment, in: host)), "the colours went with the block")
        XCTAssertNil(paragraphStyle(at: comment, in: host), "and so did the indent")
        XCTAssertNil(role(at: text.range(of: "```bash").location, in: host), "the fence line is text again")
        XCTAssertFalse(isNullGlyph(at: text.range(of: "```bash").location + 1, in: host))
    }

    // MARK: The label never covers code (plan 5 task 7)

    /// 300 characters with no space to break at: the line wraps wherever the room ends, which is what is measured.
    private static let longLine = String(repeating: "abcdefghij", count: 30)

    /// docs/features/code.md, "The label": the first line of code of a block with a label keeps clear of the label (the indent
    /// is the label's width and 12 pt, `testOnlyTheFirstLineOfCodeReservesRoomForTheLabel`), so that long code wraps before it
    /// and a click on the end of the code is never a click on the label.
    func testFirstLineOfCodeWrapsBeforeLabel() throws {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let body = "```swift\n" + Self.longLine + "\nlet a = 1\n```"
        let text = body as NSString
        show(body, in: host)
        let layoutManager = try XCTUnwrap(host.editor.textView.layoutManager as? MarkupLayoutManager)
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: text.length))
        let label = try XCTUnwrap(layoutManager.labelRect(forBlockAt: 0), "the block says Swift")
        let line = text.range(of: Self.longLine)

        // The line fragments of the first line of code.
        var fragments: [NSRect] = []
        var glyph = layoutManager.glyphIndexForCharacter(at: line.location)
        let lastGlyph = layoutManager.glyphIndexForCharacter(at: NSMaxRange(line) - 1)
        while glyph <= lastGlyph {
            var glyphs = NSRange(location: 0, length: 0)
            fragments.append(layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: &glyphs))
            glyph = max(NSMaxRange(glyphs), glyph + 1)
        }

        XCTAssertGreaterThanOrEqual(fragments.count, 3, "300 characters take three lines or more")
        XCTAssertLessThan(label.minY, fragments[0].maxY, "the label reaches into the first line of code")
        for (index, fragment) in fragments.enumerated() {
            // 12 pt is the gap that the indent keeps. Less is asked here: how an indent is measured against the line's
            // padding is TextKit's, and the click below needs more than the label's 3 pt margin.
            XCTAssertLessThanOrEqual(fragment.maxX, label.minX - 6, "line \(index) of the code ends before the label")
        }
        // A click on the end of the first of those lines is a click on code. The label's margin is 3 pt.
        let origin = host.editor.textView.textContainerOrigin
        let click = NSPoint(x: origin.x + fragments[0].maxX - 1, y: origin.y + fragments[0].minY + 4)
        XCTAssertNil(host.editor.textView.labelHit(atViewPoint: click), "the end of the code is not the label")
        XCTAssertEqual(host.editor.currentText, body, "the note is as it was")
    }

    func testOnlyTheFirstLineOfCodeReservesRoomForTheLabel() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = Self.typicalBody as NSString
        show(Self.typicalBody, in: host)

        XCTAssertEqual(
            tailIndent(ofLineWith: "# watch the rollout", in: Self.typicalBody, host: host) ?? 0,
            firstLineTail(label: "Shell"), accuracy: 0.01, "the first line")
        XCTAssertEqual(tailIndent(ofLineWith: "kubectl rollout status", in: Self.typicalBody, host: host), -10)
        XCTAssertEqual(tailIndent(ofLineWith: "kubectl logs", in: Self.typicalBody, host: host), -10)
        XCTAssertEqual(paragraphStyle(at: text.range(of: "```bash").location, in: host)?.tailIndent, -10)
        XCTAssertEqual(
            paragraphStyle(at: text.range(of: "```", options: .backwards).location, in: host)?.tailIndent, -10)

        // Nothing else about the line changes: it is a line of the block, with the head indent of one.
        let first = text.range(of: "# watch the rollout").location
        XCTAssertEqual(paragraphStyle(at: first, in: host)?.headIndent, 10)
        XCTAssertEqual(paragraphStyle(at: first, in: host)?.firstLineHeadIndent, 10)
        XCTAssertEqual((attribute(.scratchCodeBlock, at: first, in: host) as? CodeBlockMark)?.part, .body)
        XCTAssertNil(role(at: first, in: host))
        XCTAssertEqual(host.editor.currentText, Self.typicalBody)
    }

    func testBlockWithNoLabelHasNoReserve() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let body = "```\nhello there\nand this\n```"
        show(body, in: host)

        waitForHighlights(in: host)

        XCTAssertEqual(codeStyler(of: host).language(ofBlockAt: 5)?.name, "", "prose in a fence has no label")
        XCTAssertEqual(tailIndent(ofLineWith: "hello there", in: body, host: host), -10)
        XCTAssertEqual(tailIndent(ofLineWith: "and this", in: body, host: host), -10)
    }

    func testReserveIsForTheNameAsWrittenWhenItIsNotALanguage() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let body = "```ruby\nputs 'hello'\nclass Note; end\n```"
        show(body, in: host)

        XCTAssertEqual(
            tailIndent(ofLineWith: "puts", in: body, host: host) ?? 0, firstLineTail(label: "ruby"), accuracy: 0.01)
        XCTAssertEqual(tailIndent(ofLineWith: "class Note", in: body, host: host), -10)
    }

    func testReserveFollowsTheDetectedLabel() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show(Self.unnamedBody, in: host)

        XCTAssertEqual(
            tailIndent(ofLineWith: "const notes", in: Self.unnamedBody, host: host), -10,
            "no label yet, so no room kept")

        waitForHighlights(in: host)

        XCTAssertEqual(
            codeStyler(of: host).language(ofBlockAt: (Self.unnamedBody as NSString).range(of: "const notes").location)?
                .name, "JavaScript")
        XCTAssertEqual(
            tailIndent(ofLineWith: "const notes", in: Self.unnamedBody, host: host) ?? 0,
            firstLineTail(label: "JavaScript"), accuracy: 0.01, "the detected label has its room")
        XCTAssertEqual(tailIndent(ofLineWith: "// the newest", in: Self.unnamedBody, host: host), -10)
        XCTAssertEqual(host.editor.currentText, Self.unnamedBody)
    }

    func testNamingTheFenceGivesTheFirstLineItsReserve() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("```\nhello there\nand this\n```", in: host)
        waitForHighlights(in: host)

        host.editor.textView.setSelectedRange(NSRange(location: 3, length: 0))
        insert("python", into: host)

        let body = "```python\nhello there\nand this\n```"
        XCTAssertEqual(host.editor.currentText, body)
        XCTAssertEqual(
            tailIndent(ofLineWith: "hello there", in: body, host: host) ?? 0, firstLineTail(label: "Python"),
            accuracy: 0.01)
        XCTAssertEqual(tailIndent(ofLineWith: "and this", in: body, host: host), -10)
    }

    func testSplittingTheFirstLineLeavesTheReserveOnTheFirstPartOnly() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let body = "```swift\nlet first = 1\nlet second = 2\n```"
        show(body, in: host)
        let split = (body as NSString).range(of: "let first").upperBound
        host.editor.textView.setSelectedRange(NSRange(location: split, length: 0))

        insert("\n", into: host)

        let after = "```swift\nlet first\n = 1\nlet second = 2\n```"
        XCTAssertEqual(host.editor.currentText, after)
        XCTAssertEqual(
            tailIndent(ofLineWith: "let first", in: after, host: host) ?? 0, firstLineTail(label: "Swift"),
            accuracy: 0.01)
        XCTAssertEqual(tailIndent(ofLineWith: " = 1", in: after, host: host), -10, "the rest of it is a line like any")
        XCTAssertEqual(tailIndent(ofLineWith: "let second", in: after, host: host), -10)
    }

    func testInsertingLinesAboveTheFirstLineMovesItsReserveToTheNewFirstLine() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let body = "```swift\nlet first = 1\nlet second = 2\n```"
        show(body, in: host)
        let start = (body as NSString).range(of: "let first").location
        host.editor.textView.setSelectedRange(NSRange(location: start, length: 0))

        insert("a\nb\n", into: host)

        let after = "```swift\na\nb\nlet first = 1\nlet second = 2\n```"
        XCTAssertEqual(host.editor.currentText, after)
        XCTAssertEqual(
            tailIndent(ofLineWith: "a\nb", in: after, host: host) ?? 0, firstLineTail(label: "Swift"), accuracy: 0.01,
            "the new first line")
        XCTAssertEqual(tailIndent(ofLineWith: "b\nlet", in: after, host: host), -10)
        XCTAssertEqual(
            tailIndent(ofLineWith: "let first", in: after, host: host), -10,
            "the old first line is the third now, and a line like any")
        XCTAssertEqual(tailIndent(ofLineWith: "let second", in: after, host: host), -10)
    }

    func testInsertingLinesInTheFirstLineLeavesItsReserveOnTheFirstPartOnly() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let body = "```swift\nlet first = 1\nlet second = 2\n```"
        show(body, in: host)
        let middle = (body as NSString).range(of: "let first").upperBound
        host.editor.textView.setSelectedRange(NSRange(location: middle, length: 0))

        insert("x\ny\n", into: host)

        let after = "```swift\nlet firstx\ny\n = 1\nlet second = 2\n```"
        XCTAssertEqual(host.editor.currentText, after)
        XCTAssertEqual(
            tailIndent(ofLineWith: "let firstx", in: after, host: host) ?? 0, firstLineTail(label: "Swift"),
            accuracy: 0.01)
        XCTAssertEqual(tailIndent(ofLineWith: "y\n", in: after, host: host), -10)
        XCTAssertEqual(
            tailIndent(ofLineWith: " = 1", in: after, host: host), -10, "what was left of the first line is the third")
        XCTAssertEqual(tailIndent(ofLineWith: "let second", in: after, host: host), -10)
    }

    func testDeletingTheFirstLineGivesTheReserveToTheNextOne() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let body = "```swift\nlet first = 1\nlet second = 2\nlet third = 3\n```"
        show(body, in: host)
        host.editor.textView.setSelectedRange((body as NSString).range(of: "let first = 1\n"))

        host.editor.textView.deleteBackward(nil)

        let after = "```swift\nlet second = 2\nlet third = 3\n```"
        XCTAssertEqual(host.editor.currentText, after)
        XCTAssertEqual(
            tailIndent(ofLineWith: "let second", in: after, host: host) ?? 0, firstLineTail(label: "Swift"),
            accuracy: 0.01)
        XCTAssertEqual(tailIndent(ofLineWith: "let third", in: after, host: host), -10)
    }

    func testTypingInTheFirstLineKeepsItsReserve() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let body = "```swift\nlet first = 1\nlet second = 2\n```"
        show(body, in: host)
        host.editor.textView.setSelectedRange(
            NSRange(location: (body as NSString).range(of: "= 1").upperBound, length: 0))

        insert("23", into: host)

        let after = "```swift\nlet first = 123\nlet second = 2\n```"
        XCTAssertEqual(host.editor.currentText, after)
        XCTAssertEqual(
            tailIndent(ofLineWith: "let first", in: after, host: host) ?? 0, firstLineTail(label: "Swift"),
            accuracy: 0.01)
        XCTAssertEqual(tailIndent(ofLineWith: "let second", in: after, host: host), -10)
    }

    func testReserveFollowsTheFontSize() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show(Self.typicalBody, in: host)

        host.editor.setFontSize(20)
        spin(until: { host.editor.textView.styler.isFullyStyled })

        XCTAssertEqual(
            tailIndent(ofLineWith: "# watch the rollout", in: Self.typicalBody, host: host) ?? 0,
            firstLineTail(label: "Shell", noteSize: 20), accuracy: 0.01, "the label is bigger, so its room is")
        XCTAssertEqual(tailIndent(ofLineWith: "kubectl logs", in: Self.typicalBody, host: host), -10)
    }

    func testTheOnlyLineOfABlockIsItsFirstAndAnEmptyBlockHasNone() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let body = "```swift\n```\ntext\n```go\nx := 1\n```"
        show(body, in: host)

        XCTAssertEqual(
            tailIndent(ofLineWith: "x := 1", in: body, host: host) ?? 0, firstLineTail(label: "Go"), accuracy: 0.01,
            "the one line of a block is its first")
        XCTAssertEqual(paragraphStyle(at: 0, in: host)?.tailIndent, -10, "the fence line of the empty block")
        XCTAssertNil(tailIndent(ofLineWith: "text", in: body, host: host), "text between blocks is not code")
        XCTAssertEqual(host.editor.currentText, body)
    }

    // MARK: Late first colours (plan 5 task 7)

    func testFenceNamesGiveTheLanguagesToWarmUp() {
        let text = [
            "intro", "```py", "a = 1", "```", "```JS", "b", "```", "```py", "c", "```", "```ruby", "d", "```", "```",
            "e", "```",
            "```go", "f",
        ].joined(separator: "\n")

        XCTAssertEqual(
            CodeBlockStyler.languages(namedIn: text), [.python, .javascript], "in order, once each, blocks only")
        XCTAssertEqual(CodeBlockStyler.languages(namedIn: "no fence at all"), [])
        XCTAssertEqual(CodeBlockStyler.languages(namedIn: ""), [])
        XCTAssertEqual(CodeBlockStyler.languages(namedIn: "  ```  Rust  \nfn main() {}\n```"), [.rust])
    }

    func testWarmUpCompilesOpenLanguages() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let styler = codeStyler(of: host)
        // A highlighter of its own: the shared one may have compiled these before.
        let highlighter = Highlighter()
        XCTAssertFalse(highlighter.isPrepared(.go))
        XCTAssertFalse(highlighter.isPrepared(.rust))

        styler.warmUp(
            languagesNamedIn: [
                "alpha\n```go\nx := 1\n```\n", "```Rust\nfn main() {}\n```", "```ruby\n1\n```", "no fences here",
                "```go\ny := 2\n```",
            ], using: highlighter)

        XCTAssertGreaterThan(styler.pendingWarmUps, 0, "it is asked for and done on the highlight queue")
        spin(until: { styler.pendingWarmUps == 0 })
        XCTAssertEqual(styler.pendingWarmUps, 0, "the warm-up is done within seconds")
        XCTAssertEqual(styler.warmedLanguages, [.go, .rust], "the languages that the fences name, once each")
        XCTAssertTrue(highlighter.isPrepared(.go))
        XCTAssertTrue(highlighter.isPrepared(.rust))
        XCTAssertFalse(highlighter.isPrepared(.swift), "no other language is compiled")
    }

    func testWarmUpOfALanguageThatIsReadyDoesNothingTwice() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let styler = codeStyler(of: host)
        let highlighter = Highlighter()

        styler.warmUp(languagesNamedIn: ["```go\nx := 1\n```"], using: highlighter)
        spin(until: { styler.pendingWarmUps == 0 })
        styler.warmUp(languagesNamedIn: ["```go\nx := 1\n```", "```c\nint a;\n```"], using: highlighter)
        spin(until: { styler.pendingWarmUps == 0 })

        XCTAssertEqual(styler.warmedLanguages, [.go, .c])
        XCTAssertEqual(styler.pendingWarmUps, 0)
    }

    func testWarmUpNeverBlocksTheNoteThatIsShown() {
        // The warm-up shares the highlight queue with the colours of the note on screen, and goes one language at a time, so
        // a block that is shown while it runs waits for one compile at most and is coloured.
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let styler = codeStyler(of: host)
        styler.warmUp(
            languagesNamedIn: ["```go\nx := 1\n```", "```c\nint a;\n```", "```css\na { color: red }\n```"],
            using: Highlighter())

        show(Self.typicalBody, in: host)
        waitForHighlights(in: host)

        let command = (Self.typicalBody as NSString).range(of: "kubectl rollout").location
        XCTAssertTrue(isAsset("CodeFunction", colour(at: command, in: host)), "the block on screen is coloured")
        spin(until: { styler.pendingWarmUps == 0 }, seconds: 20)
        XCTAssertEqual(styler.pendingWarmUps, 0)
    }

    // MARK: The colours

    func testDarkModeUsesDarkColours() {
        // Xcode's default light and dark themes (plan 4, "Colours").
        let expected: [HighlightKind: (light: String, dark: String)] = [
            .keyword: ("9B2393", "FC5FA3"), .string: ("C41A16", "FC6A5D"), .comment: ("5D6C79", "7F8C98"),
            .number: ("1C00CF", "D0BF69"), .type: ("0B4F79", "5DD8FF"), .function: ("326D74", "67B7A4"),
            .attribute: ("815F03", "BF8555"), .preprocessor: ("643820", "FD8F3F"),
        ]
        XCTAssertEqual(Set(expected.keys), Set(HighlightKind.allCases))
        func hex(_ components: [CGFloat]) -> String {
            guard components.count == 4 else { return "no colour" }
            return components.prefix(3).map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
        }
        for (kind, hexes) in expected {
            let name = assetName(of: kind)
            guard let color = NSColor(named: NSColor.Name(name)) else {
                XCTFail("\(name) is not in the asset catalog")
                continue
            }
            XCTAssertEqual(hex(components(of: color, in: .aqua)), hexes.light, "\(name), light")
            XCTAssertEqual(hex(components(of: color, in: .darkAqua)), hexes.dark, "\(name), dark")
        }
    }
}
