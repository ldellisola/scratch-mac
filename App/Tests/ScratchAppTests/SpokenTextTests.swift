import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/accessibility.md ("VoiceOver"): VoiceOver hears the rendered note and not its
/// markers. A bullet is "bullet", a box is "unchecked" or "checked", the stars of bold and the backticks of inline code are
/// not spoken, an attachment is "image, <name>", "file, <name>" or "missing attachment", and a fenced block is "code block,
/// <label>" with its code and "end of code block". `accessibilityValue` stays the stored text, so that ranges and the caret
/// agree with it (spec §6.1, plan 6 task 8).
@MainActor
final class SpokenTextTests: XCTestCase {
    private typealias Host = (editor: EditorViewController, window: NSWindow)

    private struct SetupError: Error {}

    /// An editor in an 800 x 600 window that is never shown. Keep `window` alive for as long as the editor is used.
    private func makeHostedEditor(catalog: AttachmentCatalog? = nil) -> Host {
        let editor = EditorViewController()
        editor.attachmentCatalog = catalog
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = editor
        window.setContentSize(NSSize(width: 800, height: 600))
        return (editor, window)
    }

    /// Shows `text` as a note, with the caret at `caret`, and lays the editor out. A small note is styled whole by `show`.
    private func show(_ text: String, caret: Int = 0, in host: Host) {
        let note = Note(id: NoteID.make(), title: "", body: text, createdAt: Date(), modifiedAt: Date())
        show(note, caret: caret, in: host)
    }

    private func show(_ note: Note, caret: Int = 0, in host: Host) {
        let tab = TabState(noteID: note.id, selection: caret, scrollY: 0, scrollAnchor: nil)
        host.editor.show(note, tab: tab, undoManager: UndoManager(), isReadOnly: false)
        host.editor.view.layoutSubtreeIfNeeded()
    }

    /// What the note says, all of it.
    private func spoken(in host: Host) -> String {
        let storage = host.editor.textView.textStorage ?? NSTextStorage()
        return SpokenText.spoken(storage, range: NSRange(location: 0, length: storage.length))
    }

    private func wholeRange(in host: Host) -> NSRange {
        NSRange(location: 0, length: (host.editor.currentText as NSString).length)
    }

    // MARK: Lists

    func testSpokenChecklist() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("[ ] buy milk\n[x] send the mail", in: host)

        XCTAssertEqual(spoken(in: host), "unchecked buy milk\nchecked send the mail")
        // The text view answers VoiceOver's question with the same words.
        XCTAssertEqual(
            host.editor.textView.accessibilityString(for: wholeRange(in: host)),
            "unchecked buy milk\nchecked send the mail")
        XCTAssertEqual(host.editor.currentText, "[ ] buy milk\n[x] send the mail", "nothing is changed in the note")
    }

    func testSpokenBulletsAndNestedItems() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("- first\n  - nested\n  [ ] a task under it", in: host)

        XCTAssertEqual(spoken(in: host), "bullet first\n  bullet nested\n  unchecked a task under it")
    }

    // MARK: Bold and inline code

    func testSpokenBoldHasNoStars() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "a **bold** word and `code` here"
        show(text, caret: 0, in: host)
        XCTAssertEqual(spoken(in: host), "a bold word and code here", "the markers are hidden while the caret is away")

        // With the caret in the run the stars and the backticks are shown, dimmed, and are still not spoken.
        host.editor.textView.setSelectedRange(NSRange(location: 6, length: 0))
        host.editor.textView.styler.selectionDidChange(host.editor.textView.selectedRange())
        XCTAssertEqual(spoken(in: host), "a bold word and code here", "revealed markers are silent too")
        host.editor.textView.setSelectedRange(NSRange(location: 22, length: 0))
        host.editor.textView.styler.selectionDidChange(host.editor.textView.selectedRange())
        XCTAssertEqual(spoken(in: host), "a bold word and code here")
        XCTAssertEqual(host.editor.currentText, text)
    }

    func testSpokenRangesAreClippedToTheRange() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("[ ] buy milk", in: host)
        let storage = host.editor.textView.textStorage ?? NSTextStorage()

        XCTAssertEqual(SpokenText.spoken(storage, range: NSRange(location: 4, length: 8)), "buy milk")
        XCTAssertEqual(SpokenText.spoken(storage, range: NSRange(location: 4, length: 100)), "buy milk", "past the end")
        XCTAssertEqual(SpokenText.spoken(storage, range: NSRange(location: 0, length: 5)), "unchecked b")
        // A range that starts inside the box has nothing to say for it: the box was not asked for.
        XCTAssertEqual(SpokenText.spoken(storage, range: NSRange(location: 1, length: 5)), " bu")
        XCTAssertEqual(SpokenText.spoken(storage, range: NSRange(location: 3, length: 0)), "")
        XCTAssertEqual(SpokenText.spoken(storage, range: NSRange(location: 99, length: 3)), "")
    }

    // MARK: Attachments

    func testSpokenToken() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScratchSpokenTextTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try ScratchStorage.open(
            LaunchOptions(dataDirectory: directory, isIsolated: true, fixture: .attachments))
        guard let tab = try storage.session.load()?.tabs.first, let fixture = try storage.notes.note(tab.noteID) else {
            throw SetupError()
        }
        // The fixture's note: a line, an image, a line and a text file. And a token that no row knows.
        let unknown = AttachmentToken.line(for: AttachmentID.make())
        let note = Note(
            id: fixture.id, title: "", body: fixture.body + "\n" + unknown, createdAt: Date(), modifiedAt: Date())
        let host = makeHostedEditor(catalog: AttachmentCatalog(store: storage.attachments))
        defer { withExtendedLifetime(host.window) {} }
        show(note, in: host)

        let expected = [
            "The dashboard after the deploy.", "image, dashboard.png", "The steps to roll it back.",
            "file, rollback-plan.txt", "missing attachment",
        ].joined(separator: "\n")
        XCTAssertEqual(spoken(in: host), expected)
        XCTAssertEqual(host.editor.textView.accessibilityString(for: wholeRange(in: host)), expected)
        XCTAssertTrue(host.editor.currentText.contains("[[attachment:"), "the tokens are still in the text")
    }

    // MARK: Code blocks

    func testSpokenCodeBlock() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "```swift\nlet x = 1\n```"
        let expected = "code block, Swift\nlet x = 1\nend of code block"

        // The caret on the opening fence shows the fence line, and the words are the same.
        show(text, caret: 0, in: host)
        XCTAssertEqual(spoken(in: host), expected)
        XCTAssertEqual(host.editor.textView.accessibilityString(for: wholeRange(in: host)), expected)
        // With the caret in the code both fences are hidden.
        host.editor.textView.setSelectedRange(NSRange(location: 14, length: 0))
        host.editor.textView.styler.selectionDidChange(host.editor.textView.selectedRange())
        XCTAssertEqual(spoken(in: host), expected)
        XCTAssertEqual(host.editor.currentText, text)
    }

    func testSpokenCodeBlockWithNoLabel() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("before\n```\nplain words\nmore words\n```\nafter", caret: 0, in: host)

        XCTAssertEqual(
            spoken(in: host), "before\ncode block\nplain words\nmore words\nend of code block\nafter",
            "a fence with no name and no detected language has no label to read")
    }

    func testTextInsideABlockIsNotMarkup() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("```text\n- not a bullet\n[ ] not a box\n**not bold**\n```", caret: 0, in: host)

        XCTAssertEqual(
            spoken(in: host), "code block, text\n- not a bullet\n[ ] not a box\n**not bold**\nend of code block")
    }

    // MARK: The value

    func testAccessibilityValueIsTheStoredText() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "[ ] buy **milk**\n- a `thing`\n```swift\nlet x = 1\n```"
        show(text, caret: 0, in: host)

        XCTAssertEqual(host.editor.textView.accessibilityValue() as? String, text, "the value is the stored text")
        XCTAssertEqual(host.editor.currentText, text)
        XCTAssertNotEqual(spoken(in: host), text, "while what is read for a range is not")
    }

    func testAttributedStringIsTheSameWords() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("[x] done\nplain line", in: host)

        let attributed = host.editor.textView.accessibilityAttributedString(for: wholeRange(in: host))
        XCTAssertEqual(attributed?.string, "checked done\nplain line")
        // A range with nothing to replace is AppKit's own.
        let plain = host.editor.textView.accessibilityAttributedString(for: NSRange(location: 9, length: 10))
        XCTAssertEqual(plain?.string, "plain line")
    }
}
