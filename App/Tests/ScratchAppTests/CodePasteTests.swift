import AppKit
import ScratchCode
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/code.md ("Pasting code") and docs/features/paste-and-copy.md ("Paste order"):
/// a paste of two lines or more that `CodeDetector` calls code is wrapped in a fence with its language on the next turn
/// of the main run loop, with every pasted character unchanged inside; prose, a single line, a paste into code and a paste
/// with a fence line of its own stay as they are (spec §6.4, §6.5, plan 4 task 6). Every paste goes through
/// `readSelection(from:)` with a pasteboard of its own, which is what Paste runs, and never touches the real clipboard.
///
/// What ⌘Z does with the wrap cannot be tested here (an undo group ends with the run loop turn, and a test method is one
/// turn): `CodePasteUITests` presses the keys.
@MainActor
final class CodePasteTests: XCTestCase {
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
    private func show(_ text: String, caret: Int = 0, isReadOnly: Bool = false, in host: Host) {
        let note = Note(id: NoteID.make(), title: "", body: text, createdAt: Date(), modifiedAt: Date())
        let tab = TabState(noteID: note.id, selection: caret, scrollY: 0, scrollAnchor: nil)
        host.editor.show(note, tab: tab, undoManager: UndoManager(), isReadOnly: isReadOnly)
        host.editor.view.layoutSubtreeIfNeeded()
    }

    /// What Paste runs, with `text` on a pasteboard of its own. Returns what `readSelection(from:)` said.
    @discardableResult
    private func paste(_ text: String, into host: Host) -> Bool {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return host.editor.textView.readSelection(from: pasteboard)
    }

    private func spin(until condition: () -> Bool, seconds: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    }

    /// Runs the main run loop until the paste has had its turn: it is wrapped, or it was left as it is.
    private func waitForClassification(in host: Host, file: StaticString = #filePath, line: UInt = #line) {
        let view = host.editor.textView
        spin(until: { view.pendingPasteClassifications == 0 })
        XCTAssertEqual(view.pendingPasteClassifications, 0, "the paste is classified at once", file: file, line: line)
    }

    private func waitForHighlights(in host: Host, file: StaticString = #filePath, line: UInt = #line) {
        let styler = host.editor.textView.styler.codeBlockStyler
        spin(until: { styler.pendingHighlights == 0 })
        XCTAssertEqual(styler.pendingHighlights, 0, "the highlights are applied within seconds", file: file, line: line)
    }

    private func text(of host: Host) -> String { host.editor.textView.string }

    // MARK: Samples

    /// Python with a line that ends in white space and one that starts with a tab: the paste keeps both.
    private static let python = "import os\n\ndef main():\n    path = os.getcwd()   \n    print(path)\n\tx = 1"

    /// Ruby, which `CodeDetector` knows is code and has no language for.
    private static let ruby = [
        "class Greeter", "  def initialize(name)", "    @name = name", "  end", "", "  def greet",
        "    puts \"Hello, #{@name}!\"", "  end", "end", "", "Greeter.new(\"Ada\").greet",
    ].joined(separator: "\n")

    // Prose of the corpus (`Packages/ScratchCode/Tests/ScratchCodeTests/Corpus/prose`, written for it): none is code.
    private static let prose: [String] = [
        [
            "Hi Marta,", "",
            "Thanks for sending the draft over. I read it on the train and the structure works for me. Two small things: "
                + "the budget paragraph still mentions last year's figure, and the timeline needs a date for the review.",
            "", "Could we talk on Thursday afternoon? Anything after 2 pm suits me.", "", "Best regards,", "Tomas Berg",
            "Operations Coordinator", "Harbour & Finch Ltd", "tel: +44 20 5550 0147", "",
            "> On Tue, 14 Oct, Marta Ilves wrote:",
            "> Hello Tomas, the draft is attached. Please tell me what you think",
            "> before Friday, because the printer needs the files on Monday.",
        ].joined(separator: "\n"),
        [
            "Team sync - Tuesday", "10:00 \u{2013} welcome and quick round",
            "10:15 \u{2013} launch checklist with Anika",
            "10:45 \u{2013} open questions on pricing", "11:15 \u{2013} wrap up, assign owners",
        ].joined(separator: "\n"),
        [
            "1. Wash the car", "2. Return the library books", "3. Call the dentist about Thursday",
            "4. Pick up the dry cleaning", "5. Plan dinner for Saturday",
        ].joined(separator: "\n"),
        [
            "2026-03-02 08:14:07 INFO  backup started for volume photos",
            "2026-03-02 08:14:09 INFO  copied 312 files (1.4 GB)",
            "2026-03-02 08:14:31 WARN  slow disk, retrying chunk 17",
            "2026-03-02 08:14:44 INFO  backup finished in 37 s",
        ].joined(separator: "\n"),
        [
            "# Weekend plan", "", "**Saturday** \u{2013} market in the morning, then lunch with Ines.",
            "**Sunday** \u{2013} long walk if the weather holds, otherwise the museum.", "",
            "Remember to *book* the table for **six** people.",
        ].joined(separator: "\n"),
    ]

    // MARK: The paste is wrapped

    /// docs/features/code.md, "Pasting code": the fence names the language, and the pasted characters are inside it as
    /// they came (white space, tab and all).
    func testMultiLinePythonPasteIsFenced() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("", in: host)

        XCTAssertTrue(paste(Self.python, into: host))
        XCTAssertEqual(text(of: host), Self.python, "the plain paste comes first")
        waitForClassification(in: host)

        let expected = "```python\n" + Self.python + "\n```"
        XCTAssertEqual(text(of: host), expected)
        XCTAssertTrue(text(of: host).contains(Self.python), "the pasted characters are byte-identical inside the fence")
        XCTAssertEqual(host.editor.textView.selectedRange(), NSRange(location: expected.utf16.count, length: 0))
    }

    func testWrappedBlockIsColouredAndLabelledWithItsLanguage() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("", in: host)

        paste(Self.python, into: host)
        waitForClassification(in: host)
        waitForHighlights(in: host)

        let language = host.editor.textView.styler.codeBlockStyler.language(ofBlockAt: 0)
        XCTAssertEqual(language?.0, .python)
        XCTAssertEqual(language?.isDetected, false, "the fence names the language: it is not shown as detected")
        XCTAssertEqual(language?.name, "Python")
    }

    func testPasteMidLineGetsFenceOnItsOwnLines() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("before after", caret: 7, in: host)

        paste(Self.python, into: host)
        waitForClassification(in: host)

        XCTAssertEqual(text(of: host), "before \n```python\n" + Self.python + "\n```\nafter")
    }

    func testPasteAtTheStartOfALineNeedsNoLineBreakBeforeTheFence() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("intro\nrest", caret: 6, in: host)

        paste(Self.python, into: host)
        waitForClassification(in: host)

        XCTAssertEqual(text(of: host), "intro\n```python\n" + Self.python + "\n```\nrest")
    }

    /// A paste that ends with a line break has that break before the closing fence, not a blank line in the block.
    func testPasteEndingWithALineBreakHasNoBlankLineInTheBlock() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("", in: host)
        let go = "package main\n\nfunc main() {\n\tfmt.Println(\"hi\")\n}\n"

        paste(go, into: host)
        waitForClassification(in: host)

        XCTAssertEqual(text(of: host), "```go\n" + go + "```")
    }

    func testUnknownLanguageGetsUnnamedFence() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("", in: host)

        paste(Self.ruby, into: host)
        waitForClassification(in: host)

        XCTAssertEqual(text(of: host), "```\n" + Self.ruby + "\n```")
    }

    // MARK: The paste stays plain

    func testSingleLinePasteStaysPlain() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("", in: host)

        paste("let answer = 42;", into: host)
        waitForClassification(in: host)
        XCTAssertEqual(text(of: host), "let answer = 42;")

        show("", in: host)
        paste("let answer = 42;\n", into: host)
        waitForClassification(in: host)
        XCTAssertEqual(text(of: host), "let answer = 42;\n", "a line and its line break are one line")
    }

    func testPasteInsideBlockIsNotFenced() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("```swift\nlet a = 1\n```", caret: 18, in: host)

        paste(Self.python, into: host)
        waitForClassification(in: host)

        XCTAssertEqual(text(of: host), "```swift\nlet a = 1" + Self.python + "\n```")
    }

    func testPasteIntoTheFenceLinesIsNotFencedEither() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("```swift\nlet a = 1\n```", caret: 0, in: host)

        paste(Self.python, into: host)
        waitForClassification(in: host)

        XCTAssertEqual(text(of: host), Self.python + "```swift\nlet a = 1\n```")
    }

    func testPasteInsideInlineCodeIsNotFenced() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("run `foo bar` now", caret: 8, in: host)

        paste(Self.python, into: host)
        waitForClassification(in: host)

        XCTAssertEqual(text(of: host), "run `foo" + Self.python + " bar` now")
    }

    func testPasteNextToInlineCodeIsFenced() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("run `foo` now", caret: 9, in: host)

        paste(Self.python, into: host)
        waitForClassification(in: host)

        XCTAssertEqual(text(of: host), "run `foo`\n```python\n" + Self.python + "\n```\n now")
    }

    func testPasteWithFencesStaysAsIs() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("", in: host)
        let fenced = "```python\n" + Self.python + "\n```"

        paste(fenced, into: host)
        waitForClassification(in: host)

        XCTAssertEqual(text(of: host), fenced)
    }

    /// The owner is typing a block: a fence and no partner yet. The wrap's fences would pair with it.
    func testPasteBelowAnUnmatchedFenceStaysPlain() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("```\n", caret: 4, in: host)

        paste(Self.python, into: host)
        waitForClassification(in: host)

        XCTAssertEqual(text(of: host), "```\n" + Self.python)
    }

    func testPasteBelowAClosedBlockIsFenced() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let block = "```swift\nlet a = 1\n```\n"
        show(block, caret: block.utf16.count, in: host)

        paste(Self.python, into: host)
        waitForClassification(in: host)

        XCTAssertEqual(text(of: host), block + "```python\n" + Self.python + "\n```")
    }

    func testProseSampleStaysPlain() {
        for sample in Self.prose {
            let host = makeHostedEditor()
            defer { withExtendedLifetime(host.window) {} }
            show("", in: host)

            paste(sample, into: host)
            waitForClassification(in: host)

            XCTAssertEqual(text(of: host), sample, "prose stays prose: \(sample.prefix(40))")
        }
    }

    /// The wrap is for the text that was pasted: typing in the turn between them cancels it.
    func testEditBetweenThePasteAndTheWrapSkipsTheWrap() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("", in: host)

        paste(Self.python, into: host)
        host.editor.textView.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        waitForClassification(in: host)

        XCTAssertEqual(text(of: host), Self.python + "x")
    }

    func testReadOnlyNoteTakesNoPasteAndClassifiesNothing() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("deleted note", isReadOnly: true, in: host)

        XCTAssertFalse(paste(Self.python, into: host))
        XCTAssertEqual(host.editor.textView.pendingPasteClassifications, 0)
        XCTAssertEqual(text(of: host), "deleted note")
    }

    // MARK: The signpost interval

    /// What a handler of `whenHighlighted` saw. A main-actor class, so that a closure may change it.
    @MainActor private final class Observed {
        var pendingWhenCalled: Int?
    }

    /// `paste-code` ends when the colours are written (`CodeBlockStyler.whenHighlighted`), not before.
    func testHighlightedHandlerRunsAfterTheColoursAreWritten() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("", in: host)
        let styler = host.editor.textView.styler.codeBlockStyler
        let observed = Observed()

        paste(Self.python, into: host)
        waitForClassification(in: host)
        styler.whenHighlighted { observed.pendingWhenCalled = styler.pendingHighlights }
        spin(until: { observed.pendingWhenCalled != nil })

        XCTAssertEqual(observed.pendingWhenCalled, 0)
    }

    func testHighlightedHandlerRunsWhenNothingIsPending() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("plain", in: host)
        let observed = Observed()

        host.editor.textView.styler.codeBlockStyler.whenHighlighted { observed.pendingWhenCalled = 0 }
        spin(until: { observed.pendingWhenCalled != nil })

        XCTAssertEqual(observed.pendingWhenCalled, 0)
    }

    // MARK: PasteClassifier.wrap

    /// What the edit of `PasteClassifier.wrap` makes of `pasted`, which was pasted after the text `prefix` and before the
    /// text `suffix`: the text, and the selection.
    private func wrapped(
        _ pasted: String, after prefix: String = "", before suffix: String = "", isInCode: Bool = false
    ) -> (text: String, selection: NSRange)? {
        let whole = (prefix + pasted + suffix) as NSString
        let range = NSRange(location: prefix.utf16.count, length: pasted.utf16.count)
        guard let edit = PasteClassifier.wrap(pasted: pasted, at: range, in: whole, isInCode: isInCode) else {
            return nil
        }
        XCTAssertEqual(edit.range, range, "the edit replaces the pasted text")
        return (whole.replacingCharacters(in: edit.range, with: edit.replacement), edit.selection)
    }

    func testWrapEditIsTheFenceAroundThePastedText() throws {
        let result = try XCTUnwrap(wrapped(Self.python))
        XCTAssertEqual(result.text, "```python\n" + Self.python + "\n```")
        XCTAssertEqual(result.selection, NSRange(location: result.text.utf16.count, length: 0))
    }

    func testWrapIsNilWhenTheCallerSaysTheyAreInCode() {
        XCTAssertNil(wrapped(Self.python, isInCode: true))
    }

    func testWrapNeedsTwoLines() {
        XCTAssertNil(wrapped("print(1)"))
        XCTAssertNil(wrapped("print(1)\n"))
        XCTAssertNil(wrapped(""))
    }

    func testWrapRefusesAPasteThatHasAFenceLine() {
        XCTAssertNil(wrapped("```\n" + Self.python))
        XCTAssertNil(wrapped(Self.python + "\n   ```"))
        XCTAssertNotNil(wrapped(Self.python + "\nx = '```'"), "backticks in a line are not a fence line")
    }

    func testWrapRefusesAPasteBelowAFenceWithoutAPartner() {
        XCTAssertNil(wrapped(Self.python, after: "```swift\nlet a = 1\n"))
        XCTAssertNotNil(wrapped(Self.python, after: "```swift\nlet a = 1\n```\n"))
        XCTAssertNil(wrapped(Self.python, after: "```a\n```\n```\n"))
    }

    func testWrapDoesNotCutACRLFInTwo() {
        let pasted = Self.python + "\r"
        let range = NSRange(location: 0, length: pasted.utf16.count)

        let cut = (pasted + "\nx") as NSString
        XCTAssertNil(
            PasteClassifier.wrap(pasted: pasted, at: range, in: cut, isInCode: false), "the paste ends inside a CRLF")

        let whole = (pasted + "x") as NSString
        XCTAssertNotNil(
            PasteClassifier.wrap(pasted: pasted, at: range, in: whole, isInCode: false),
            "a carriage return alone ends a line")
    }

    func testLinesAreCountedByTheirBreaks() {
        XCTAssertFalse(PasteClassifier.hasTwoLines(""))
        XCTAssertFalse(PasteClassifier.hasTwoLines("a"))
        XCTAssertFalse(PasteClassifier.hasTwoLines("a\n"))
        XCTAssertFalse(PasteClassifier.hasTwoLines("a\r\n"))
        XCTAssertTrue(PasteClassifier.hasTwoLines("a\nb"))
        XCTAssertTrue(PasteClassifier.hasTwoLines("a\r\nb"))
        XCTAssertTrue(PasteClassifier.hasTwoLines("a\rb"))
        XCTAssertTrue(PasteClassifier.hasTwoLines("\n\n"))
    }

    func testFenceLinesAboveAreCounted() {
        let text = "```a\nx\n```\n  ``` \nfoo ``` bar\n``````\n" as NSString
        XCTAssertEqual(PasteClassifier.fenceLineCount(before: text.length, in: text), 4)
        XCTAssertEqual(PasteClassifier.fenceLineCount(before: 0, in: text), 0)
    }
}
