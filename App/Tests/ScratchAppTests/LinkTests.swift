import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/formatting.md ("Links open with ⌘-click"): a ⌘-click on a link opens its URL,
/// a plain click only places the caret, a ⌘-click anywhere else is the text view's own, nothing in inline code or in a
/// fenced block is a link, and the pointing hand shows while ⌘ is held over a link (spec §6.4, plan 3 task 6).
///
/// No test opens a browser: every test replaces `NoteTextView.openURL`.
///
/// A click that `NoteTextView.mouseDown` does not handle goes to `super.mouseDown`, which runs AppKit's tracking loop
/// until the mouse button is released. `click(at:modifiers:in:)` therefore queues the matching mouse up before it sends
/// the click, so that the loop ends at once, and takes it out of the queue again when `mouseDown` did not use it (a
/// ⌘-click on a link returns without the loop).
@MainActor
final class LinkTests: XCTestCase {
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

    /// Shows `text` as a note, with the caret at `caret`, and lays the editor out so that positions can be measured.
    private func show(_ text: String, caret: Int = 0, readOnly: Bool = false, in host: Host) {
        let note = Note(id: NoteID.make(), title: "", body: text, createdAt: Date(), modifiedAt: Date())
        let tab = TabState(noteID: note.id, selection: caret, scrollY: 0, scrollAnchor: nil)
        host.editor.show(note, tab: tab, undoManager: UndoManager(), isReadOnly: readOnly)
        host.editor.view.layoutSubtreeIfNeeded()
    }

    /// The body of the `formatting` fixture (ScratchCore's `FixtureContent`): its fifth line holds the link.
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

    /// The link of the fixture: its trailing period is not part of it.
    private static let fixtureLink = "https://example.com/a_(b)?q=1"

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

    /// The middle of the character at `index`, in the coordinates of the text view.
    private func point(ofCharacterAt index: Int, in host: Host) -> NSPoint {
        let rect = viewRect(ofCharacters: NSRange(location: index, length: 1), in: host)
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    /// The offset of the first `needle` in `text`, in UTF-16 units.
    private func offset(of needle: String, in text: String) -> Int {
        (text as NSString).range(of: needle).location
    }

    /// Sends a left click at `point` (in the coordinates of the text view) to the text view's `mouseDown`.
    private func click(
        at point: NSPoint, modifiers: NSEvent.ModifierFlags = [], in host: Host, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let textView = host.editor.textView
        XCTAssertGreaterThan(textView.frame.width, 100, "the editor is laid out", file: file, line: line)
        let location = textView.convert(point, to: nil)
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: host.window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
        }
        guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else {
            XCTFail("no mouse event", file: file, line: line)
            return
        }
        NSApp.postEvent(up, atStart: false)
        textView.mouseDown(with: down)
        // What `mouseDown` did not take, so that it cannot end the tracking loop of a later click.
        while NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true) != nil {}
    }

    // MARK: ⌘-click

    func testCommandClickOpensLink() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show(Self.formattingBody, in: host)
        var opened: [URL] = []
        host.editor.textView.openURL = { opened.append($0) }
        let start = offset(of: Self.fixtureLink, in: Self.formattingBody)

        click(at: point(ofCharacterAt: start + 10, in: host), modifiers: .command, in: host)

        XCTAssertEqual(
            opened, [URL(string: Self.fixtureLink)!], "the link without the period after it, and with its brackets")
        XCTAssertEqual(
            host.editor.textView.selectedRange(), NSRange(location: 0, length: 0), "a ⌘-click places no caret")
        XCTAssertEqual(host.editor.currentText, Self.formattingBody)
    }

    func testCommandClickOpensTheLinkUnderTheClick() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "see https://a.example.com and https://b.example.com/x ok"
        show(text, in: host)
        var opened: [URL] = []
        host.editor.textView.openURL = { opened.append($0) }

        click(
            at: point(ofCharacterAt: offset(of: "b.example", in: text), in: host), modifiers: .command, in: host)
        click(
            at: point(ofCharacterAt: offset(of: "a.example", in: text), in: host), modifiers: .command, in: host)

        XCTAssertEqual(opened, [URL(string: "https://b.example.com/x")!, URL(string: "https://a.example.com")!])
    }

    func testCommandClickOnTheEdgesOfALinkOpensIt() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "see https://example.com/a. now"
        show(text, in: host)
        var opened: [URL] = []
        host.editor.textView.openURL = { opened.append($0) }
        let url = URL(string: "https://example.com/a")!

        click(at: point(ofCharacterAt: 4, in: host), modifiers: .command, in: host)
        click(at: point(ofCharacterAt: 24, in: host), modifiers: .command, in: host)

        XCTAssertEqual(opened, [url, url], "the first and the last character of the link")
    }

    func testCommandClickOnTheWrappedPartOfALinkOpensIt() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        // Longer than a line of the 800 point window, so that the end of the link is on the next line.
        let link = "https://example.com/" + String(repeating: "a", count: 150)
        let text = "go to \(link) now"
        show(text, in: host)
        var opened: [URL] = []
        host.editor.textView.openURL = { opened.append($0) }
        let last = offset(of: link, in: text) + link.utf16.count - 1

        click(at: point(ofCharacterAt: last, in: host), modifiers: .command, in: host)

        XCTAssertEqual(opened, [URL(string: link)!])
    }

    func testCommandClickOpensLinkInAReadOnlyNote() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("see https://example.com/a now", readOnly: true, in: host)
        var opened: [URL] = []
        host.editor.textView.openURL = { opened.append($0) }

        click(at: point(ofCharacterAt: 10, in: host), modifiers: .command, in: host)

        XCTAssertEqual(opened, [URL(string: "https://example.com/a")!], "a note in Recently Deleted keeps its links")
    }

    // MARK: Clicks that do not open

    func testPlainClickDoesNotOpen() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show(Self.formattingBody, in: host)
        var opened: [URL] = []
        host.editor.textView.openURL = { opened.append($0) }
        let start = offset(of: Self.fixtureLink, in: Self.formattingBody)

        click(at: point(ofCharacterAt: start + 10, in: host), in: host)

        XCTAssertTrue(opened.isEmpty, "a click places the caret and nothing else: \(opened)")
        XCTAssertEqual(host.editor.currentText, Self.formattingBody)
    }

    func testClickWithOtherModifiersDoesNotOpen() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show(Self.formattingBody, in: host)
        var opened: [URL] = []
        host.editor.textView.openURL = { opened.append($0) }
        let start = offset(of: Self.fixtureLink, in: Self.formattingBody)
        let link = point(ofCharacterAt: start + 10, in: host)

        click(at: link, modifiers: .shift, in: host)
        click(at: link, modifiers: .option, in: host)

        XCTAssertTrue(opened.isEmpty, "only ⌘ opens a link: \(opened)")
    }

    func testCommandClickOutsideLinkDoesNothing() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show(Self.formattingBody, in: host)
        var opened: [URL] = []
        host.editor.textView.openURL = { opened.append($0) }
        let start = offset(of: Self.fixtureLink, in: Self.formattingBody)

        click(at: point(ofCharacterAt: 1, in: host), modifiers: .command, in: host)
        click(
            at: point(ofCharacterAt: offset(of: "bold", in: Self.formattingBody), in: host), modifiers: .command,
            in: host)
        click(
            at: point(ofCharacterAt: start + Self.fixtureLink.utf16.count, in: host), modifiers: .command, in: host)
        let line = viewRect(ofCharacters: NSRange(location: start + 28, length: 1), in: host)
        click(at: NSPoint(x: line.maxX + 200, y: line.midY), modifiers: .command, in: host)

        XCTAssertTrue(
            opened.isEmpty, "text, bold text, the period after the link and the space after the line: \(opened)")
        XCTAssertEqual(host.editor.currentText, Self.formattingBody)
    }

    func testLinkInsideInlineCodeIsNotOpened() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "run `https://example.com/a` now"
        show(text, in: host)
        var opened: [URL] = []
        host.editor.textView.openURL = { opened.append($0) }
        let inside = point(ofCharacterAt: offset(of: "example", in: text), in: host)

        XCTAssertNil(host.editor.textView.link(atViewPoint: inside), "inline code is literal")
        click(at: inside, modifiers: .command, in: host)

        XCTAssertTrue(opened.isEmpty, "\(opened)")
    }

    func testLinkInsideAFencedBlockIsNotOpened() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "```\nhttps://example.com/a\n```"
        show(text, in: host)
        var opened: [URL] = []
        host.editor.textView.openURL = { opened.append($0) }
        let inside = point(ofCharacterAt: offset(of: "example", in: text), in: host)

        XCTAssertNil(host.editor.textView.link(atViewPoint: inside), "a fenced block is literal")
        click(at: inside, modifiers: .command, in: host)

        XCTAssertTrue(opened.isEmpty, "\(opened)")
    }

    // MARK: Where a link is

    func testLinkIsFoundOnlyOverItsOwnText() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "see https://example.com/a. now\nhttps://example.com/b"
        show(text, in: host)
        let textView = host.editor.textView

        XCTAssertEqual(
            textView.link(atViewPoint: point(ofCharacterAt: 4, in: host)), URL(string: "https://example.com/a"),
            "the first character of the link")
        XCTAssertEqual(
            textView.link(atViewPoint: point(ofCharacterAt: 24, in: host)), URL(string: "https://example.com/a"),
            "its last character")
        XCTAssertNil(textView.link(atViewPoint: point(ofCharacterAt: 25, in: host)), "the period after the link")
        XCTAssertNil(textView.link(atViewPoint: point(ofCharacterAt: 0, in: host)), "the text before it")
        XCTAssertNil(textView.link(atViewPoint: point(ofCharacterAt: 28, in: host)), "the text after it")

        // A link that ends its line: the space to the right of it is not the link, though the nearest character is.
        let last = viewRect(ofCharacters: NSRange(location: (text as NSString).length - 1, length: 1), in: host)
        XCTAssertEqual(
            textView.link(atViewPoint: NSPoint(x: last.midX, y: last.midY)), URL(string: "https://example.com/b"))
        XCTAssertNil(
            textView.link(atViewPoint: NSPoint(x: last.maxX + 40, y: last.midY)), "right of the end of the line")
        XCTAssertNil(textView.link(atViewPoint: NSPoint(x: last.midX, y: last.maxY + 60)), "below the last line")
        XCTAssertNil(textView.link(atViewPoint: NSPoint(x: 2, y: last.midY)), "the margin left of the line")
    }

    // MARK: The cursor

    func testPointingHandShowsOnlyWhileCommandIsHeldOverALink() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let text = "see https://example.com/a now"
        show(text, in: host)
        let textView = host.editor.textView
        let overLink = point(ofCharacterAt: 10, in: host)
        let overText = point(ofCharacterAt: 0, in: host)

        XCTAssertNil(
            textView.updateLinkCursor(atViewPoint: overLink, modifiers: []), "without ⌘ the cursor is not touched")
        XCTAssertNil(textView.updateLinkCursor(atViewPoint: overText, modifiers: .command), "⌘ over text: not touched")
        XCTAssertEqual(textView.updateLinkCursor(atViewPoint: overLink, modifiers: .command), NSCursor.pointingHand)
        XCTAssertEqual(
            textView.updateLinkCursor(atViewPoint: overLink, modifiers: .command), NSCursor.pointingHand,
            "it is set again on every move")
        XCTAssertEqual(
            textView.updateLinkCursor(atViewPoint: overLink, modifiers: []), NSCursor.iBeam, "⌘ was let go")
        XCTAssertNil(textView.updateLinkCursor(atViewPoint: overLink, modifiers: []), "and the I-beam is already back")

        XCTAssertEqual(
            textView.updateLinkCursor(atViewPoint: overLink, modifiers: [.command, .shift]), NSCursor.pointingHand)
        XCTAssertEqual(
            textView.updateLinkCursor(atViewPoint: overText, modifiers: .command), NSCursor.iBeam,
            "the mouse moved off the link")
    }

    func testTheViewTracksMouseMoves() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("text", in: host)
        let textView = host.editor.textView

        textView.updateTrackingAreas()
        let area = textView.linkTrackingArea
        textView.updateTrackingAreas()

        XCTAssertNotNil(area, "the view asked for mouse moves")
        XCTAssertTrue((area?.owner as? NoteTextView) === textView)
        XCTAssertTrue(area?.options.contains(.mouseMoved) ?? false)
        XCTAssertTrue(area?.options.contains(.inVisibleRect) ?? false, "it follows what is scrolled into view")
        XCTAssertTrue(textView.linkTrackingArea === area, "the area is made once, however often AppKit updates them")
        XCTAssertEqual(textView.trackingAreas.filter { $0 === area }.count, 1)
    }
}
