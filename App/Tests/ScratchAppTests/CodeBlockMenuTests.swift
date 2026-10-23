import AppKit
import ScratchCode
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/code.md ("The language label menu" and "Blocks typed by hand"): the label of a
/// block is a menu that renames the language on the opening fence, turns the block into plain text, or takes the fences
/// away and keeps the lines of code, each as one undo step; a block typed by hand has its language detected from what is in
/// it (spec §6.4 "Code highlighting", plan 4 task 7).
///
/// `NSMenu.popUp(positioning:at:in:)` runs a tracking loop of its own until the menu is dismissed, and a click that
/// `NoteTextView.mouseDown` does not handle goes to `super.mouseDown`, which waits for a mouse up: neither may run in a
/// test. So the tests that send a click first check that the point is on a label (`labelHit`), and replace
/// `NoteTextView.codeBlockMenuPresenter`; the cases that are not a click on a label ask `labelHit` and
/// `showCodeBlockMenu(atViewPoint:)` instead of sending one.
@MainActor
final class CodeBlockMenuTests: XCTestCase {
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

    /// Shows `text` as a note, with the caret at `caret`, and lays the whole of it out, so that a position that is measured
    /// is where the text is when a click arrives.
    private func show(
        _ text: String, caret: Int = 0, readOnly: Bool = false, undoManager: UndoManager = UndoManager(),
        in host: Host
    ) {
        let note = Note(id: NoteID.make(), title: "", body: text, createdAt: Date(), modifiedAt: Date())
        let tab = TabState(noteID: note.id, selection: caret, scrollY: 0, scrollAnchor: nil)
        host.editor.show(note, tab: tab, undoManager: undoManager, isReadOnly: readOnly)
        host.editor.view.layoutSubtreeIfNeeded()
        host.editor.textView.layoutManager?.ensureLayout(
            forCharacterRange: NSRange(location: 0, length: (text as NSString).length))
    }

    private func codeStyler(of host: Host) -> CodeBlockStyler {
        host.editor.textView.styler.codeBlockStyler
    }

    private func attribute(_ key: NSAttributedString.Key, at index: Int, in host: Host) -> Any? {
        host.editor.textView.textStorage?.attribute(key, at: index, effectiveRange: nil)
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

    /// The red, green, blue and alpha components of `color` as it looks in the light appearance.
    private func components(of color: NSColor) -> [CGFloat] {
        var result: [CGFloat] = []
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
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

    /// A note with one block between two lines of prose: a `bash` block of two lines.
    private static let body = [
        "intro",
        "```bash",
        "# watch the rollout",
        "kubectl rollout status deploy/api -n prod",
        "```",
        "outro",
    ].joined(separator: "\n")

    /// The block of `body` or of any text with one block: from the start of its opening fence line to the end of its
    /// closing one.
    private func onlyBlock(in text: String) -> NSRange {
        let blocks = FenceScanner.codeBlocks(in: text)
        XCTAssertEqual(blocks.count, 1, "the text has one block")
        return blocks.first ?? NSRange(location: 0, length: 0)
    }

    /// The text after the edit.
    private func applying(_ edit: TextEdit, to text: String) -> String {
        (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    /// The item with this title in a menu.
    private func menuItem(titled title: String, in menu: NSMenu, file: StaticString = #filePath, line: UInt = #line)
        throws -> NSMenuItem
    {
        try XCTUnwrap(menu.items.first { $0.title == title }, "the menu has \(title)", file: file, line: line)
    }

    /// The rectangle of the label of the block that starts at `location`, in the coordinates of the text view.
    private func labelRect(ofBlockAt location: Int, in host: Host) throws -> NSRect {
        let textView = host.editor.textView
        let layoutManager = try XCTUnwrap(textView.layoutManager as? MarkupLayoutManager)
        var rect = try XCTUnwrap(layoutManager.labelRect(forBlockAt: location), "the block has a label")
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        return rect
    }

    // MARK: Menu choices

    func testSetLanguageRewritesFence() throws {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let undo = UndoManager()
        show(Self.body, undoManager: undo, in: host)
        let textView = host.editor.textView
        let block = onlyBlock(in: Self.body)
        XCTAssertFalse(undo.canUndo, "showing a note is no undo step")

        // The edit replaces the name on the opening fence and nothing else.
        let edit = CodeBlockMenu.edit(for: .setLanguage(.python), block: block, in: Self.body as NSString)
        XCTAssertEqual(edit.range, NSRange(location: block.location + 3, length: 4), "only the name is replaced")
        XCTAssertEqual(edit.replacement, "python")

        let menu = CodeBlockMenu.menu(for: block, current: .bash, target: textView)
        try textView.chooseCodeBlockAction(menuItem(titled: "Python", in: menu))

        let expected = Self.body.replacingOccurrences(of: "```bash", with: "```python")
        XCTAssertEqual(host.editor.currentText, expected, "the name changed and the content is as it was")
        XCTAssertTrue(undo.canUndo)
        let language = codeStyler(of: host).language(ofBlockAt: block.location + 10)
        XCTAssertEqual(language?.0, .python)
        XCTAssertEqual(language?.isDetected, false, "a language that is on the fence is not in italics")
        XCTAssertEqual(language?.name, "Python")
        waitForHighlights(in: host)
        XCTAssertEqual(host.editor.currentText, expected, "colouring never changes a character")

        undo.undo()

        XCTAssertEqual(host.editor.currentText, Self.body, "one undo gives the fence back")
        XCTAssertFalse(undo.canUndo, "the change was one undo step")
        XCTAssertTrue(undo.canRedo)
        XCTAssertEqual(codeStyler(of: host).language(ofBlockAt: block.location + 10)?.0, .bash)
    }

    func testChoosingTheLanguageThatIsThereChangesNothing() throws {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let undo = UndoManager()
        show(Self.body, caret: 2, undoManager: undo, in: host)
        let block = onlyBlock(in: Self.body)

        let menu = CodeBlockMenu.menu(for: block, current: .bash, target: host.editor.textView)
        try host.editor.textView.chooseCodeBlockAction(menuItem(titled: "Shell", in: menu))

        XCTAssertEqual(host.editor.currentText, Self.body)
        XCTAssertFalse(undo.canUndo, "nothing was changed, so there is no step to undo")
        XCTAssertEqual(host.editor.textView.selectedRange(), NSRange(location: 2, length: 0))
    }

    func testPlainTextKeepsBlockUncoloured() throws {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let undo = UndoManager()
        show(Self.body, undoManager: undo, in: host)
        let text = Self.body as NSString
        let command = text.range(of: "kubectl rollout").location
        waitForHighlights(in: host)
        XCTAssertFalse(isTextColour(colour(at: command, in: host)), "the block is coloured before")
        let block = onlyBlock(in: Self.body)

        let menu = CodeBlockMenu.menu(for: block, current: .bash, target: host.editor.textView)
        try host.editor.textView.chooseCodeBlockAction(menuItem(titled: "Plain Text", in: menu))
        waitForHighlights(in: host)

        let expected = Self.body.replacingOccurrences(of: "```bash", with: "```text")
        XCTAssertEqual(host.editor.currentText, expected)
        let code = (expected as NSString).range(of: "# watch the rollout\nkubectl rollout status deploy/api -n prod")
        for offset in 0..<code.length {
            XCTAssertTrue(isTextColour(colour(at: code.location + offset, in: host)), "character \(offset) is plain")
        }
        XCTAssertEqual(paragraphStyle(at: code.location, in: host)?.headIndent, 10, "the block is still tinted")
        let language = codeStyler(of: host).language(ofBlockAt: code.location)
        XCTAssertNil(language?.0, "text is no language")
        XCTAssertEqual(language?.name, "text", "its label is the name on the fence")

        let again = CodeBlockMenu.menu(for: block, current: nil, target: host.editor.textView)
        XCTAssertEqual(again.items.filter { $0.state == .on }.map(\.title), ["Plain Text"], "the menu knows it")

        undo.undo()

        XCTAssertEqual(host.editor.currentText, Self.body, "one undo gives the fence back")
        XCTAssertFalse(undo.canUndo)
    }

    func testNotCodeRemovesFencesOnly() throws {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let undo = UndoManager()
        let text = Self.body as NSString
        let caret = text.range(of: "kubectl rollout").location + 4
        show(Self.body, caret: caret, undoManager: undo, in: host)
        waitForHighlights(in: host)
        let block = onlyBlock(in: Self.body)

        let menu = CodeBlockMenu.menu(for: block, current: .bash, target: host.editor.textView)
        try host.editor.textView.chooseCodeBlockAction(menuItem(titled: "Not Code", in: menu))
        waitForHighlights(in: host)

        let expected = "intro\n# watch the rollout\nkubectl rollout status deploy/api -n prod\noutro"
        XCTAssertEqual(
            host.editor.currentText, expected, "the fence lines are gone and the lines of code are as they were")
        XCTAssertEqual(
            host.editor.textView.selectedRange(), NSRange(location: caret - "```bash\n".utf16.count, length: 0),
            "the caret stays in the same place of the code")
        let comment = (expected as NSString).range(of: "# watch the rollout").location
        XCTAssertNil(codeStyler(of: host).language(ofBlockAt: comment), "it is not a block any more")
        let style = paragraphStyle(at: comment, in: host)
        XCTAssertEqual(style?.headIndent ?? 0, 0, "its lines are not indented")
        XCTAssertEqual(style?.firstLineHeadIndent ?? 0, 0)
        XCTAssertEqual(style?.tailIndent ?? 0, 0)
        XCTAssertTrue(isTextColour(colour(at: comment, in: host)), "and not coloured")
        XCTAssertTrue(isTextColour(colour(at: (expected as NSString).range(of: "kubectl").location, in: host)))

        undo.undo()

        XCTAssertEqual(host.editor.currentText, Self.body, "one undo gives the block back")
        XCTAssertFalse(undo.canUndo, "taking the fences away was one undo step")
    }

    func testChoicesAreIgnoredInAReadOnlyNote() throws {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        let undo = UndoManager()
        show(Self.body, readOnly: true, undoManager: undo, in: host)
        let block = onlyBlock(in: Self.body)

        let menu = CodeBlockMenu.menu(for: block, current: .bash, target: host.editor.textView)
        try host.editor.textView.chooseCodeBlockAction(menuItem(titled: "Not Code", in: menu))
        try host.editor.textView.chooseCodeBlockAction(menuItem(titled: "Python", in: menu))

        XCTAssertEqual(host.editor.currentText, Self.body)
    }

    // MARK: The edits

    func testEditsOfEveryAction() {
        let cases: [(String, CodeBlockAction, String)] = [
            ("```bash\nls\n```", .setLanguage(.python), "```python\nls\n```"),
            ("```\nls\n```", .setLanguage(.sql), "```sql\nls\n```"),
            ("  ``` shell  \nls\n```", .setLanguage(.go), "  ```go\nls\n```"),
            ("````ts\nx\n````", .plainText, "````text\nx\n````"),
            ("```python\nx\n```", .setLanguage(.python), "```python\nx\n```"),
            ("```bash\r\nls\r\n```", .notCode, "ls"),
            ("a\n```swift\nlet x = 1\n\nlet y = 2\n```\nb", .notCode, "a\nlet x = 1\n\nlet y = 2\nb"),
            ("a\n```\n\n```\nb", .notCode, "a\n\nb"),
            ("a\n```\n```\nb", .notCode, "a\nb"),
            ("a\n```\n```", .notCode, "a"),
            ("```\n```", .notCode, ""),
        ]
        for (text, action, expected) in cases {
            let blocks = FenceScanner.codeBlocks(in: text)
            guard blocks.count == 1 else {
                XCTFail("\(text.debugDescription) has \(blocks.count) blocks")
                continue
            }
            let edit = CodeBlockMenu.edit(for: action, block: blocks[0], in: text as NSString)
            XCTAssertEqual(applying(edit, to: text), expected, "\(action) on \(text.debugDescription)")
        }
    }

    func testTheSelectionFollowsTheEdit() {
        let text = "```bash\nls -l\n```"
        let ns = text as NSString
        let block = FenceScanner.codeBlocks(in: text)[0]
        func selection(_ action: CodeBlockAction, _ before: NSRange) -> NSRange {
            CodeBlockMenu.edit(for: action, block: block, in: ns, selection: before).selection
        }

        // "bash" becomes "python": two units longer.
        XCTAssertEqual(
            selection(.setLanguage(.python), NSRange(location: 12, length: 0)), NSRange(location: 14, length: 0))
        XCTAssertEqual(
            selection(.setLanguage(.python), NSRange(location: 0, length: 0)), NSRange(location: 0, length: 0))
        XCTAssertEqual(
            selection(.setLanguage(.python), NSRange(location: 7, length: 0)), NSRange(location: 9, length: 0))
        XCTAssertEqual(
            selection(.setLanguage(.python), NSRange(location: 5, length: 0)), NSRange(location: 9, length: 0),
            "a caret in the name goes to the end of the new one")
        XCTAssertEqual(
            selection(.setLanguage(.python), NSRange(location: 8, length: 5)), NSRange(location: 10, length: 5),
            "a selection of the code is the same code")

        // The text is "ls -l" afterwards, which starts where the opening fence did.
        XCTAssertEqual(selection(.notCode, NSRange(location: 12, length: 0)), NSRange(location: 4, length: 0))
        XCTAssertEqual(selection(.notCode, NSRange(location: 3, length: 0)), NSRange(location: 0, length: 0))
        XCTAssertEqual(selection(.notCode, NSRange(location: 16, length: 0)), NSRange(location: 5, length: 0))
        XCTAssertEqual(selection(.notCode, NSRange(location: 8, length: 5)), NSRange(location: 0, length: 5))

        // Without a selection the caret goes to the end of the new name, or to the start of what is left.
        XCTAssertEqual(
            CodeBlockMenu.edit(for: .setLanguage(.python), block: block, in: ns).selection,
            NSRange(location: 9, length: 0))
        XCTAssertEqual(
            CodeBlockMenu.edit(for: .notCode, block: block, in: ns).selection, NSRange(location: 0, length: 0))
    }

    func testTheMenuLooksForTheBlockItIsGiven() {
        // A range that is not a block of the text changes nothing and moves nothing.
        let text = "one\ntwo" as NSString
        let edit = CodeBlockMenu.edit(for: .notCode, block: NSRange(location: 0, length: 3), in: text)
        XCTAssertEqual(edit.replacement, "")
        XCTAssertEqual(edit.range.length, 0)
        let far = CodeBlockMenu.edit(for: .plainText, block: NSRange(location: 50, length: 9), in: text)
        XCTAssertEqual(far.range.length, 0)
        XCTAssertLessThanOrEqual(NSMaxRange(far.range), text.length)
    }

    // MARK: The menu

    func testMenuListsEveryLanguageWithCurrentTicked() {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show(Self.body, in: host)
        let textView = host.editor.textView
        let block = onlyBlock(in: Self.body)
        let count = CodeLanguage.allCases.count
        XCTAssertEqual(count, 17)

        let menu = CodeBlockMenu.menu(for: block, current: .python, target: textView)

        XCTAssertEqual(menu.items.count, count + 3, "the languages, a separator, Plain Text and Not Code")
        let languages = Array(menu.items.prefix(count))
        XCTAssertEqual(Set(languages.map(\.title)), Set(CodeLanguage.allCases.map(\.label)), "every language, once")
        XCTAssertEqual(
            languages.map(\.title),
            languages.map(\.title).sorted { $0.caseInsensitiveCompare($1) == .orderedAscending },
            "in the order of their names")
        XCTAssertEqual(menu.items.filter { $0.state == .on }.map(\.title), ["Python"], "the current language only")
        XCTAssertTrue(menu.items[count].isSeparatorItem)
        XCTAssertEqual(menu.items[count + 1].title, "Plain Text")
        XCTAssertEqual(menu.items[count + 2].title, "Not Code")
        for item in menu.items where !item.isSeparatorItem {
            XCTAssertTrue(item.target === textView, "\(item.title) goes to the editor")
            XCTAssertNotNil(item.action)
            XCTAssertTrue(item.isEnabled)
        }

        let none = CodeBlockMenu.menu(for: block, current: nil, target: textView)
        XCTAssertTrue(none.items.allSatisfy { $0.state != .on }, "a block with no language has no tick")
    }

    // MARK: The label

    func testLabelHitTest() throws {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show(Self.body, in: host)
        let textView = host.editor.textView
        XCTAssertGreaterThan(textView.frame.width, 100, "the editor is laid out")
        let block = onlyBlock(in: Self.body)
        let rect = try labelRect(ofBlockAt: block.location, in: host)
        XCTAssertGreaterThan(rect.width, 20, "the label has a width")
        XCTAssertGreaterThan(rect.height, 5, "and a height")

        let container = try XCTUnwrap(textView.textContainer)
        let right =
            container.size.width - container.lineFragmentPadding - CodeBlockMetrics.inset
            + textView.textContainerOrigin.x
        XCTAssertEqual(rect.maxX, right, accuracy: 0.5, "the label ends one inset from the right edge of the block")

        let centre = NSPoint(x: rect.midX, y: rect.midY)
        XCTAssertEqual(textView.labelHit(atViewPoint: centre), block, "the centre of the label is the block's label")
        XCTAssertEqual(
            textView.labelHit(atViewPoint: NSPoint(x: rect.minX + 1, y: rect.minY + 1)), block, "and so are its corners"
        )
        XCTAssertNil(
            textView.labelHit(atViewPoint: NSPoint(x: rect.minX - 30, y: rect.midY)), "30 points left of it is code")
        XCTAssertNil(textView.labelHit(atViewPoint: NSPoint(x: rect.maxX + 30, y: rect.midY)), "30 points right of it")
        XCTAssertNil(textView.labelHit(atViewPoint: NSPoint(x: rect.midX, y: rect.maxY + 30)), "a line below it")
        XCTAssertNil(
            textView.labelHit(atViewPoint: NSPoint(x: rect.midX, y: rect.minY - 30)), "the line above the block")
        XCTAssertNil(textView.labelHit(atViewPoint: NSPoint(x: 30, y: 10)), "the text of the note")
    }

    func testBlockWithoutLabelHasNoLabelHit() throws {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        // One line of words is not code, so the block has no language and no label.
        let body = "intro\n```\nplain words\n```\noutro"
        show(body, in: host)
        waitForHighlights(in: host)
        let textView = host.editor.textView
        let layoutManager = try XCTUnwrap(textView.layoutManager as? MarkupLayoutManager)
        let block = onlyBlock(in: body)

        XCTAssertNil(layoutManager.labelRect(forBlockAt: block.location), "there is no label to click")
        XCTAssertNil(codeStyler(of: host).language(ofBlockAt: block.location + 5)?.0)
        for y in stride(from: CGFloat(0), to: 120, by: 6) {
            XCTAssertNil(textView.labelHit(atViewPoint: NSPoint(x: 700, y: y)), "no label at y = \(y)")
        }
        XCTAssertFalse(textView.showCodeBlockMenu(atViewPoint: NSPoint(x: 700, y: 60)))
    }

    func testClickOnLabelOpensMenuWithoutPlacingTheCaret() throws {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show(Self.body, caret: 2, in: host)
        let textView = host.editor.textView
        let block = onlyBlock(in: Self.body)
        let rect = try labelRect(ofBlockAt: block.location, in: host)
        let point = NSPoint(x: rect.midX, y: rect.midY)
        var presented: [(menu: NSMenu, anchor: NSPoint)] = []
        textView.codeBlockMenuPresenter = { menu, anchor in presented.append((menu, anchor)) }

        // A click that is not on the label would end in `super.mouseDown`: it is sent only when it is on it.
        guard textView.labelHit(atViewPoint: point) == block else {
            XCTFail("\(point) is not on the label: a click there would run AppKit's tracking loop")
            return
        }
        guard
            let event = NSEvent.mouseEvent(
                with: .leftMouseDown, location: textView.convert(point, to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: host.window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)
        else {
            XCTFail("no mouse event")
            return
        }
        textView.mouseDown(with: event)

        XCTAssertEqual(presented.count, 1, "the click opened the menu")
        XCTAssertEqual(presented.first?.menu.items.count, CodeLanguage.allCases.count + 3)
        XCTAssertEqual(
            presented.first?.menu.items.filter { $0.state == .on }.map(\.title), ["Shell"],
            "the block's language is ticked")
        XCTAssertEqual(presented.first?.anchor.x ?? 0, rect.minX, accuracy: 0.5, "it opens under the label")
        XCTAssertEqual(presented.first?.anchor.y ?? 0, rect.maxY, accuracy: 0.5)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0), "no caret was placed")
        XCTAssertEqual(host.editor.currentText, Self.body)
    }

    func testReadOnlyShowsNoMenu() throws {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show(Self.body, readOnly: true, in: host)
        let textView = host.editor.textView
        let block = onlyBlock(in: Self.body)
        let rect = try labelRect(ofBlockAt: block.location, in: host)
        var presented = 0
        textView.codeBlockMenuPresenter = { _, _ in presented += 1 }

        XCTAssertFalse(textView.showCodeBlockMenu(atViewPoint: NSPoint(x: rect.midX, y: rect.midY)))

        XCTAssertEqual(presented, 0, "a note that cannot be edited has no menu")
        XCTAssertEqual(host.editor.currentText, Self.body)
    }

    // MARK: Blocks typed by hand

    func testTypedBlockGetsDetectedLabel() throws {
        let host = makeHostedEditor()
        defer { withExtendedLifetime(host.window) {} }
        show("intro\n", caret: 6, in: host)
        let sql = [
            "SELECT id, name",
            "FROM users",
            "WHERE active = 1",
            "ORDER BY name;",
        ].joined(separator: "\n")

        // The fence is typed, then the lines, then the closing fence: the block exists when the last one is complete.
        insert("```\n", into: host)
        insert(sql + "\n", into: host)
        insert("```", into: host)
        waitForHighlights(in: host)

        let text = host.editor.currentText
        XCTAssertEqual(text, "intro\n```\n" + sql + "\n```", "detection never edits the fence")
        let inside = (text as NSString).range(of: "SELECT").location
        let language = codeStyler(of: host).language(ofBlockAt: inside)
        XCTAssertEqual(language?.0, .sql)
        XCTAssertEqual(language?.isDetected, true, "a detected language is in italics")
        XCTAssertEqual(language?.name, "SQL")
        XCTAssertTrue(isAsset("CodeKeyword", colour(at: inside, in: host)), "SELECT is a keyword")
        let opening = (text as NSString).range(of: "```").location
        XCTAssertNotNil(
            (host.editor.textView.layoutManager as? MarkupLayoutManager)?.labelRect(forBlockAt: opening),
            "the label is drawn, and can be clicked")

        // The label is a menu for it as for any other block: choosing a language writes the name on the fence.
        let menu = CodeBlockMenu.menu(for: onlyBlock(in: text), current: language?.0, target: host.editor.textView)
        try host.editor.textView.chooseCodeBlockAction(menuItem(titled: "SQL", in: menu))
        XCTAssertEqual(host.editor.currentText, "intro\n```sql\n" + sql + "\n```")
        XCTAssertEqual(codeStyler(of: host).language(ofBlockAt: inside)?.isDetected, false, "now it is the owner's")
    }
}
