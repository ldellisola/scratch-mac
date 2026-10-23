import AppKit
import ScratchCode
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/accessibility.md ("The context menu"): every action that only a mouse could do
/// has a menu item. A right click on the box of a checklist item offers Mark as Checked (or Unchecked), on a link Open Link,
/// on an attachment Open Attachment and in a code block a Code Block Language submenu with the items of the label's menu,
/// each only where it applies, and a note that cannot be edited offers only what does not change it (spec §6.1, plan 6
/// task 8).
///
/// No test opens a browser or a file (`NoteTextView.openURL` is replaced), and none pops a menu up: the items are asked for
/// with `EditorContextMenu.items(for:atViewPoint:)` and chosen by sending their action, as the menu would.
@MainActor
final class ContextMenuTests: XCTestCase {
    private typealias Host = (editor: EditorViewController, window: NSWindow)

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

    /// Shows `text` as a note and lays the whole of it out, so that a position that is measured is where the text is.
    private func show(_ text: String, caret: Int = 0, readOnly: Bool = false, in host: Host) {
        let note = Note(id: NoteID.make(), title: "", body: text, createdAt: Date(), modifiedAt: Date())
        let tab = TabState(noteID: note.id, selection: caret, scrollY: 0, scrollAnchor: nil)
        host.editor.show(note, tab: tab, undoManager: UndoManager(), isReadOnly: readOnly)
        host.editor.view.layoutSubtreeIfNeeded()
        host.editor.textView.layoutManager?.ensureLayout(
            forCharacterRange: NSRange(location: 0, length: (text as NSString).length))
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

    private func centre(ofCharacters range: NSRange, in host: Host) -> NSPoint {
        let rect = viewRect(ofCharacters: range, in: host)
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    private func offset(of needle: String, in text: String) -> Int {
        (text as NSString).range(of: needle).location
    }

    private func items(at point: NSPoint, in host: Host) -> [NSMenuItem] {
        EditorContextMenu.items(for: host.editor.textView, atViewPoint: point)
    }

    private func titles(_ items: [NSMenuItem]) -> [String] {
        items.filter { !$0.isSeparatorItem }.map(\.title)
    }

    /// Chooses `item` the way the menu does: its action is sent to its target.
    private func choose(_ item: NSMenuItem, file: StaticString = #filePath, line: UInt = #line) {
        guard let action = item.action else { return XCTFail("\(item.title) has no action", file: file, line: line) }
        XCTAssertTrue(
            NSApp.sendAction(action, to: item.target, from: item), "\(item.title) was not answered", file: file,
            line: line)
    }

    // MARK: Checkboxes

    func testContextMenuOnABox() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "[ ] buy milk\n[x] send the mail"
        show(text, in: host)

        let open = items(at: centre(ofCharacters: NSRange(location: 0, length: 3), in: host), in: host)
        XCTAssertEqual(titles(open), ["Mark as Checked"])
        XCTAssertTrue(open.allSatisfy(\.isEnabled))
        XCTAssertTrue(host.editor.textView.validateMenuItem(open[0]), "the text view answers for its own item")

        let ticked = items(at: centre(ofCharacters: NSRange(location: 13, length: 3), in: host), in: host)
        XCTAssertEqual(titles(ticked), ["Mark as Unchecked"])

        // Choosing it ticks the box that was clicked, wherever the caret is, as one undo step.
        host.editor.textView.setSelectedRange(NSRange(location: 20, length: 0))
        choose(open[0])
        XCTAssertEqual(host.editor.currentText, "[x] buy milk\n[x] send the mail")
        XCTAssertEqual(host.editor.textView.selectedRange(), NSRange(location: 20, length: 0), "the caret stays")
    }

    func testContextMenuAwayFromABoxHasNoItems() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("[ ] buy milk\nplain line", in: host)

        XCTAssertEqual(titles(items(at: centre(ofCharacters: NSRange(location: 6, length: 1), in: host), in: host)), [])
        XCTAssertEqual(
            titles(items(at: centre(ofCharacters: NSRange(location: 14, length: 1), in: host), in: host)), [])
    }

    // MARK: Links

    func testContextMenuOnALink() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "see https://example.com/page now"
        show(text, in: host)
        var opened: [URL] = []
        host.editor.textView.openURL = { opened.append($0) }

        let found = items(
            at: centre(ofCharacters: NSRange(location: offset(of: "example", in: text), length: 1), in: host), in: host)
        XCTAssertEqual(titles(found), ["Open Link"])
        XCTAssertTrue(host.editor.textView.validateMenuItem(found[0]))
        choose(found[0])

        XCTAssertEqual(opened, [URL(string: "https://example.com/page")!])
        XCTAssertEqual(titles(items(at: centre(ofCharacters: NSRange(location: 0, length: 1), in: host), in: host)), [])
    }

    func testReadOnlyNoteStillOffersToOpenALink() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "[ ] task https://example.com/page"
        show(text, readOnly: true, in: host)

        XCTAssertEqual(
            titles(
                items(
                    at: centre(ofCharacters: NSRange(location: offset(of: "example", in: text), length: 1), in: host),
                    in: host)),
            ["Open Link"])
        XCTAssertEqual(
            titles(items(at: centre(ofCharacters: NSRange(location: 0, length: 3), in: host), in: host)), [],
            "a note that cannot be edited cannot be ticked")
    }

    // MARK: Attachments

    func testContextMenuOnAToken() throws {
        let host = try AttachmentTestHost(text: "before\nafter", caret: 7)
        defer { host.cleanUp() }
        let file = try host.makePNGFile(named: "picture.png", width: 64, height: 40)
        let pasteboard = host.pasteboard(files: [file])
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(host.textView.readSelection(from: pasteboard))
        let id = try XCTUnwrap(host.tokenIDs.first)
        host.waitForCopies()
        host.spin(until: {
            let mark =
                host.textView.textStorage?.attribute(
                    .scratchAttachment, at: host.tokenRange(id).location, effectiveRange: nil) as? AttachmentMark
            return mark?.kind == .image
        })
        host.editor.view.layoutSubtreeIfNeeded()
        let layoutManager = try XCTUnwrap(host.textView.layoutManager as? MarkupLayoutManager)
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: host.text.utf16.count))
        let rect = try XCTUnwrap(layoutManager.attachmentRect(forTokenAt: host.tokenRange(id).location))
            .offsetBy(dx: host.textView.textContainerOrigin.x, dy: host.textView.textContainerOrigin.y)
        let point = NSPoint(x: rect.midX, y: rect.midY)
        var opened: [URL] = []
        host.textView.openURL = { opened.append($0) }

        let found = EditorContextMenu.items(for: host.textView, atViewPoint: point)
        XCTAssertEqual(titles(found), ["Open Attachment"])
        XCTAssertTrue(found.allSatisfy(\.isEnabled), "the file is there")
        choose(found[0])

        let stored = host.storage.attachments.fileURL(for: try host.row(id))
        XCTAssertEqual(opened.map { $0.resolvingSymlinksInPath().path }, [stored.resolvingSymlinksInPath().path])
        XCTAssertEqual(
            titles(EditorContextMenu.items(for: host.textView, atViewPoint: NSPoint(x: 40, y: 20))), [],
            "the first line of the note is no attachment")
    }

    // MARK: Code blocks

    private static let blockBody = [
        "intro",
        "```bash",
        "# watch the rollout",
        "kubectl rollout status deploy/api -n prod",
        "```",
        "outro",
    ].joined(separator: "\n")

    func testContextMenuInABlock() throws {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show(Self.blockBody, in: host)
        let textView = host.editor.textView
        let block = try XCTUnwrap(textView.styler.codeBlockList.first?.range)
        let inCode = centre(
            ofCharacters: NSRange(location: offset(of: "kubectl", in: Self.blockBody), length: 1), in: host)

        let found = items(at: inCode, in: host)
        XCTAssertEqual(titles(found), ["Code Block Language"])
        let submenu = try XCTUnwrap(found.first?.submenu)
        let expected = CodeBlockMenu.menu(for: block, current: .bash, target: textView).items.map(\.title)
        XCTAssertEqual(submenu.items.map(\.title), expected, "the items of the label's menu")
        XCTAssertTrue(expected.contains("Python") && expected.contains("Plain Text") && expected.contains("Not Code"))

        // Choosing a language renames the block's fence, as the label's menu does, as one edit.
        let python = try XCTUnwrap(submenu.items.first { $0.title == "Python" })
        choose(python)
        XCTAssertTrue(host.editor.currentText.contains("```python\n# watch the rollout"), host.editor.currentText)
        XCTAssertEqual(titles(items(at: centre(ofCharacters: NSRange(location: 0, length: 1), in: host), in: host)), [])
    }

    func testReadOnlyNoteHasNoCodeBlockLanguageItem() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show(Self.blockBody, readOnly: true, in: host)
        let inCode = centre(
            ofCharacters: NSRange(location: offset(of: "kubectl", in: Self.blockBody), length: 1), in: host)

        XCTAssertEqual(titles(items(at: inCode, in: host)), [])
    }

    // MARK: The menu of a right click

    func testRightClickMenuPutsTheItemsFirst() throws {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "see https://example.com/page now"
        show(text, in: host)
        let textView = host.editor.textView
        let point = centre(ofCharacters: NSRange(location: offset(of: "example", in: text), length: 1), in: host)
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .rightMouseDown, location: textView.convert(point, to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: host.window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1))

        let menu = try XCTUnwrap(textView.menu(for: event))

        XCTAssertEqual(menu.items.first?.title, "Open Link")
        if menu.items.count > 1 {
            XCTAssertTrue(menu.items[1].isSeparatorItem, "AppKit's own items follow a separator")
        }
    }
}
