import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/attachments.md ("Opening, dragging out and copying"): a double-click on an
/// attachment opens its stored file, a single click selects it, a drag past 3 points takes the file out, Copy and Cut write
/// the file names in place of the tokens and, for a selection that is exactly one token, the file's URL and an image's PNG
/// and TIFF as well (spec §6.4, §6.5, plan 5 task 6). Every test uses a pasteboard of its own and never the real clipboard.
///
/// No test opens a file or starts a drag: `NoteTextView.openURL` and `NoteTextView.attachmentDragPresenter` are replaced in
/// every test that clicks. And a click is sent only at a point that `attachmentHit(atViewPoint:)` confirms, because a click
/// that the view does not take goes to `super.mouseDown`, which runs AppKit's tracking loop until the mouse button comes up
/// (AGENTS.md). The events go straight to the view's `mouseDown`, `mouseDragged` and `mouseUp` and never through the
/// application's queue: `LinkTests` queues a mouse up and takes it out again, and that leaves a mouse event as
/// `NSApp.currentEvent`, which the selection rules read to tell a click from a key (`snappedSelection(from:to:)`), so a test
/// that ran after it would see every selection change as a click (the first run of this class broke
/// `AttachmentEditingTests.testCaretPutInsideATokenGoesToItsEdge` that way).
@MainActor
final class AttachmentCopyTests: XCTestCase {
    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
    private static let planBytes = Data("1. stop the writers\n2. roll back\n".utf8)

    // MARK: Setting up

    /// What kind of file `makeHost` attaches.
    private enum Kind {
        case text
        case image
    }

    /// A host whose note is `before`, a line holding an attachment, and `after`, with the file copied into storage and the
    /// line drawn as what it is (a chip or a preview). The attachment is made by pasting its file, as an owner does.
    private func makeHost(
        _ kind: Kind = .text, text: String = "before\nafter", caret: Int = 7
    ) throws -> (host: AttachmentTestHost, id: AttachmentID) {
        let host = try AttachmentTestHost(text: text, caret: caret)
        let file: URL
        switch kind {
        case .text: file = try host.makeFile(named: "rollback-plan.txt", contents: Self.planBytes)
        case .image: file = try host.makePNGFile(named: "picture.png", width: 64, height: 40)
        }
        let pasteboard = host.pasteboard(files: [file])
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(host.textView.readSelection(from: pasteboard))
        let id = try XCTUnwrap(host.tokenIDs.first)
        host.waitForCopies()
        settle(host)
        return (host, id)
    }

    /// Lays the note out, and runs the loop until the line of every token is a chip or a preview and not "Copying…".
    private func settle(_ host: AttachmentTestHost) {
        host.spin(until: { self.isDrawnAsItsFile(host) })
        host.editor.view.layoutSubtreeIfNeeded()
        host.textView.layoutManager?.ensureLayout(
            forCharacterRange: NSRange(location: 0, length: host.text.utf16.count))
    }

    private func isDrawnAsItsFile(_ host: AttachmentTestHost) -> Bool {
        host.tokenIDs.allSatisfy { id in
            let mark =
                host.textView.textStorage?.attribute(
                    .scratchAttachment, at: host.tokenRange(id).location, effectiveRange: nil) as? AttachmentMark
            return mark != nil && mark?.kind != .copying
        }
    }

    /// The stored file of `id`.
    private func storedFile(_ id: AttachmentID, in host: AttachmentTestHost) throws -> URL {
        host.storage.attachments.fileURL(for: try host.row(id))
    }

    /// The rectangle that the preview or chip of `id` is drawn in, in the coordinates of the text view. The whole of the small
    /// note is laid out first: a line is placed when something asks for it, and the lines above it, laid out later, would move
    /// it from where it was measured.
    private func drawnRect(of id: AttachmentID, in host: AttachmentTestHost) -> NSRect {
        let view = host.textView
        guard let layoutManager = view.layoutManager as? MarkupLayoutManager else { return .zero }
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: host.text.utf16.count))
        guard let rect = layoutManager.attachmentRect(forTokenAt: host.tokenRange(id).location) else { return .zero }
        return rect.offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
    }

    private func centre(of rect: NSRect) -> NSPoint { NSPoint(x: rect.midX, y: rect.midY) }

    private func pasteboardURLs(_ pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []
        return objects.compactMap { url(of: $0) }
    }

    /// `object` as a URL, when it is an `NSURL` (what a pasteboard reads, and what a drag item holds).
    private func url(of object: Any?) -> URL? {
        (object as? NSURL).map { $0 as URL }
    }

    private func samePath(_ first: URL, _ second: URL) -> Bool {
        first.resolvingSymlinksInPath().path == second.resolvingSymlinksInPath().path
    }

    // MARK: Mouse events

    private func mouseEvent(
        _ type: NSEvent.EventType, at point: NSPoint, clickCount: Int = 1, in host: AttachmentTestHost
    ) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type, location: host.textView.convert(point, to: nil), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: host.window.windowNumber, context: nil,
            eventNumber: 1, clickCount: clickCount, pressure: type == .leftMouseUp ? 0 : 1)
    }

    /// Sends a mouse down at `point`, which must be on an attachment (`attachmentHit(atViewPoint:)` says so first, and
    /// nothing is sent when it does not). The mouse up is not sent: a drag follows.
    private func press(
        at point: NSPoint, clickCount: Int = 1, in host: AttachmentTestHost, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard host.textView.attachmentHit(atViewPoint: point) != nil else {
            return XCTFail("there is no attachment at \(point): nothing is clicked", file: file, line: line)
        }
        guard let down = mouseEvent(.leftMouseDown, at: point, clickCount: clickCount, in: host) else {
            return XCTFail("no mouse event", file: file, line: line)
        }
        host.textView.mouseDown(with: down)
    }

    private func release(at point: NSPoint, in host: AttachmentTestHost) {
        if let up = mouseEvent(.leftMouseUp, at: point, in: host) { host.textView.mouseUp(with: up) }
    }

    private func click(
        at point: NSPoint, clickCount: Int = 1, in host: AttachmentTestHost, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        press(at: point, clickCount: clickCount, in: host, file: file, line: line)
        release(at: point, in: host)
    }

    private func drag(to point: NSPoint, in host: AttachmentTestHost) {
        if let event = mouseEvent(.leftMouseDragged, at: point, in: host) { host.textView.mouseDragged(with: event) }
    }

    // MARK: Copy

    /// Copy puts plain text: the file's name where the token was, and the text around it as it is stored.
    func testCopyOfTextAndAttachmentNamesTheFile() throws {
        let (host, id) = try makeHost()
        defer { host.cleanUp() }
        let view = host.textView
        let token = AttachmentToken.line(for: id)
        XCTAssertEqual(host.text, "before\n\(token)\nafter")
        view.setSelectedRange(NSRange(location: 0, length: host.text.utf16.count))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))

        XCTAssertEqual(pasteboard.string(forType: .string), "before\nrollback-plan.txt\nafter")
        let types = pasteboard.types ?? []
        XCTAssertTrue(types.contains(.string), "pasteboard types: \(types)")
        XCTAssertFalse(types.contains(.fileURL), "more than one line is no attachment: \(types)")
        XCTAssertFalse(types.contains(.png) || types.contains(.tiff), "pasteboard types: \(types)")
        XCTAssertEqual(host.text, "before\n\(token)\nafter", "copying changes nothing")
    }

    /// A token that no row knows is copied as "Missing attachment", and a token in a code block is text: copied as typed.
    func testUnknownTokenAndTokenInCodeBlockAreCopiedAsTheyAre() throws {
        let unknown = AttachmentToken.line(for: AttachmentID(rawValue: "11111111-2222-4333-8444-555555555555"))
        let known = AttachmentToken.line(for: AttachmentID(rawValue: "6f9619ff-8b86-4d11-b42d-00c04fc964ff"))
        let text = "x\n\(unknown)\n```\n\(known)\n```"
        let host = try AttachmentTestHost(text: text)
        defer { host.cleanUp() }
        let view = host.textView
        view.setSelectedRange(NSRange(location: 0, length: text.utf16.count))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(view.writeSelection(to: pasteboard, types: [.string]))

        XCTAssertEqual(pasteboard.string(forType: .string), "x\nMissing attachment\n```\n\(known)\n```")
        XCTAssertEqual(pasteboard.types?.contains(.fileURL), false)
    }

    /// A selection that is exactly one image attachment also puts the stored file, its URL, and the image, as PNG and TIFF.
    func testCopyOfOneAttachmentWritesFileURLAndImage() throws {
        let (host, id) = try makeHost(.image)
        defer { host.cleanUp() }
        let view = host.textView
        view.setSelectedRange(host.tokenRange(id))
        XCTAssertEqual(view.selectedRange(), host.tokenRange(id), "the token is selected whole")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))

        XCTAssertEqual(pasteboard.string(forType: .string), "picture.png", "the text is the name of the file")
        let urls = pasteboardURLs(pasteboard)
        XCTAssertEqual(urls.count, 1)
        let stored = try storedFile(id, in: host)
        XCTAssertTrue(urls.first.map { samePath($0, stored) } ?? false, "the URL is the stored file's: \(urls)")
        let types = pasteboard.types ?? []
        XCTAssertTrue(types.contains(.png) && types.contains(.tiff), "pasteboard types: \(types)")

        let png = try XCTUnwrap(pasteboard.data(forType: .png), "the image as PNG")
        XCTAssertEqual(Array(png.prefix(4)), Self.pngSignature)
        let pngImage = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(pngImage.pixelsWide, 64)
        XCTAssertEqual(pngImage.pixelsHigh, 40)
        let tiff = try XCTUnwrap(pasteboard.data(forType: .tiff), "the image as TIFF")
        let tiffImage = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        XCTAssertEqual(tiffImage.pixelsWide, 64)
        XCTAssertEqual(tiffImage.pixelsHigh, 40)
    }

    /// A selection that is exactly one file that is not an image puts its URL and its name, and no image.
    func testCopyOfOneFileWritesFileURLOnly() throws {
        let (host, id) = try makeHost(.text)
        defer { host.cleanUp() }
        let view = host.textView
        view.setSelectedRange(host.tokenRange(id))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))

        XCTAssertEqual(pasteboard.string(forType: .string), "rollback-plan.txt")
        let urls = pasteboardURLs(pasteboard)
        XCTAssertEqual(urls.count, 1)
        let stored = try storedFile(id, in: host)
        XCTAssertTrue(urls.first.map { samePath($0, stored) } ?? false, "\(urls)")
        let types = pasteboard.types ?? []
        XCTAssertFalse(types.contains(.png) || types.contains(.tiff), "a file is no image: \(types)")
        XCTAssertNil(pasteboard.data(forType: .png))
        XCTAssertNil(pasteboard.data(forType: .tiff))
    }

    /// An attachment whose copy is not done has no file to put on the pasteboard yet: only its name goes there.
    func testCopyOfAnAttachmentThatIsStillBeingCopiedWritesTheNameOnly() throws {
        let queue = DispatchQueue(label: "ScratchAttachmentCopyTests.held")
        let host = try AttachmentTestHost(text: "", copyQueue: queue)
        defer { host.cleanUp() }
        queue.suspend()
        var isHeld = true
        defer { if isHeld { queue.resume() } }
        let file = try host.makeFile(named: "rollback-plan.txt", contents: Self.planBytes)
        let source = host.pasteboard(files: [file])
        defer { source.releaseGlobally() }
        XCTAssertTrue(host.textView.readSelection(from: source))
        let id = try XCTUnwrap(host.tokenIDs.first)
        host.textView.setSelectedRange(host.tokenRange(id))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.writeSelection(to: pasteboard, types: [.string]))

        XCTAssertEqual(pasteboard.string(forType: .string), "rollback-plan.txt")
        XCTAssertEqual(pasteboard.types?.contains(.fileURL), false, "the file is not there yet")
        queue.resume()
        isHeld = false
    }

    /// Pasting what was copied into a store that does not know the attachment (the note text names an id with no row there)
    /// makes a new attachment from the file on the pasteboard, with a copy of its own of the same bytes. The original is
    /// still there, in the note it came from. (Into the store that knows it, the paste keeps the attachment: plan 6 task 6,
    /// `testPastingCopiedTextWithATokenKeepsTheAttachment`.)
    func testPastingCopiedAttachmentMakesANewOne() throws {
        let (source, original) = try makeHost(.text)
        defer { source.cleanUp() }
        source.textView.setSelectedRange(source.tokenRange(original))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(source.textView.writeSelection(to: pasteboard, types: [.string]))
        let originalFile = try storedFile(original, in: source)

        let other = try AttachmentTestHost(text: "")
        defer { other.cleanUp() }
        XCTAssertTrue(other.textView.readSelection(from: pasteboard), "the file on the pasteboard is pasted")
        other.waitForCopies()

        let ids = other.tokenIDs
        XCTAssertEqual(ids.count, 1)
        guard let copy = ids.first else { return }
        XCTAssertEqual(other.text, AttachmentToken.line(for: copy) + "\n", "a token, and not the file's name as text")
        XCTAssertNotEqual(copy, original, "a new attachment")
        let row = try other.row(copy)
        XCTAssertEqual(row.fileName, "rollback-plan.txt")
        XCTAssertTrue(row.isCopied)
        let copiedFile = other.storage.attachments.fileURL(for: row)
        XCTAssertEqual(try Data(contentsOf: copiedFile), Self.planBytes, "the same bytes")
        XCTAssertFalse(samePath(copiedFile, originalFile), "a copy of its own")
        XCTAssertEqual(try Data(contentsOf: originalFile), Self.planBytes, "the original is untouched")

        // And into the same note, where the attachment is known: the very same attachment again, and no new copy (the
        // private type of the note's text comes before the file, plan 6 task 6).
        source.textView.setSelectedRange(NSRange(location: source.text.utf16.count, length: 0))
        XCTAssertTrue(source.textView.readSelection(from: pasteboard))
        source.waitForCopies()
        XCTAssertEqual(source.tokenIDs, [original, original], "two tokens of one attachment")
    }

    /// An image that was copied is pasted as an image attachment: the file on the pasteboard wins over the image data.
    func testPastingACopiedImageMakesANewImageAttachment() throws {
        let (source, original) = try makeHost(.image)
        defer { source.cleanUp() }
        source.textView.setSelectedRange(source.tokenRange(original))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(source.textView.writeSelection(to: pasteboard, types: [.string]))

        let other = try AttachmentTestHost(text: "")
        defer { other.cleanUp() }
        XCTAssertTrue(other.textView.readSelection(from: pasteboard))
        other.waitForCopies()

        let copy = try XCTUnwrap(other.tokenIDs.first)
        let row = try other.row(copy)
        XCTAssertTrue(row.isImage)
        XCTAssertEqual(row.pixelWidth, 64)
        XCTAssertEqual(row.pixelHeight, 40)
        XCTAssertEqual(
            try Data(contentsOf: other.storage.attachments.fileURL(for: row)),
            try Data(contentsOf: try storedFile(original, in: source)))
    }

    // MARK: The note's own text (plan 6 task 6)
    //
    // docs/features/attachments.md ("Copying"): Copy, Cut and a drag of a selection that holds a token also write the private
    // type `AttachmentPasteboard.noteTextType`, the selection exactly as stored, and Paste and a drop into Scratch read it
    // first. Other applications still see plain text only.

    private let noteTextType = AttachmentPasteboard.noteTextType

    /// Fails unless `pasteboard` holds plain text and nothing else: no private type, no rich text, no file, no image.
    private func assertPlainTextOnly(
        _ pasteboard: NSPasteboard, _ message: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let types = pasteboard.types ?? []
        XCTAssertTrue(types.contains(.string), "\(message): pasteboard types: \(types)", file: file, line: line)
        for other in [noteTextType, .rtf, .rtfd, .html, .fileURL, .png, .tiff] {
            XCTAssertFalse(types.contains(other), "\(message): \(other) in \(types)", file: file, line: line)
        }
    }

    /// The point 1 pt inside the left edge of the character at `index`, in the coordinates of the text view.
    private func pointOfCharacter(_ index: Int, in host: AttachmentTestHost) throws -> NSPoint {
        let view = host.textView
        let layoutManager = try XCTUnwrap(view.layoutManager)
        let container = try XCTUnwrap(view.textContainer)
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: host.text.utf16.count))
        let glyphs = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        let box = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        let origin = view.textContainerOrigin
        return NSPoint(x: origin.x + box.minX + 1, y: origin.y + box.midY)
    }

    /// Review Focus 2: a selection that holds a token also writes the note's text as stored, and only the private type is
    /// more than plain text. The plain text is still the names.
    func testCopyWithATokenWritesNoteText() throws {
        let (host, id) = try makeHost()
        defer { host.cleanUp() }
        let view = host.textView
        let token = AttachmentToken.line(for: id)
        view.setSelectedRange(NSRange(location: 0, length: host.text.utf16.count))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))

        XCTAssertEqual(pasteboard.string(forType: noteTextType), "before\n\(token)\nafter", "the selection as stored")
        XCTAssertEqual(pasteboard.string(forType: .string), "before\nrollback-plan.txt\nafter", "others see names")
        let types = pasteboard.types ?? []
        XCTAssertTrue(types.contains(.string) && types.contains(noteTextType), "pasteboard types: \(types)")
        for rich in [NSPasteboard.PasteboardType.rtf, .rtfd, .html, .fileURL, .png, .tiff] {
            XCTAssertFalse(types.contains(rich), "no \(rich) for a selection of several lines: \(types)")
        }

        // Exactly one attachment, selected whole: the same item holds the file, and the note's text too.
        view.setSelectedRange(host.tokenRange(id))
        XCTAssertTrue(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))
        XCTAssertEqual(pasteboard.string(forType: noteTextType), token)
        XCTAssertEqual(pasteboard.string(forType: .string), "rollback-plan.txt")
        XCTAssertEqual(pasteboardURLs(pasteboard).count, 1, "and its file")
    }

    /// The private type is written only when the selection holds a token: plain text is still plain text and nothing else.
    func testCopyWithoutATokenWritesOnlyPlainText() throws {
        let (host, id) = try makeHost()
        defer { host.cleanUp() }
        let view = host.textView
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        // The line above the token, up to the start of the token line, and the line below it.
        for range in [
            NSRange(location: 0, length: 7), NSRange(location: 7 + AttachmentToken.lineLength + 1, length: 5),
        ] {
            view.setSelectedRange(range)
            XCTAssertEqual(view.selectedRange(), range)
            XCTAssertTrue(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))
            assertPlainTextOnly(pasteboard, "a selection that holds no token, \(range)")
            XCTAssertNil(pasteboard.string(forType: noteTextType))
        }
        XCTAssertEqual(host.tokenIDs, [id])
    }

    /// A token in a code block is text: copied as typed, with nothing more than text.
    func testCopyOfATokenInACodeBlockWritesOnlyPlainText() throws {
        let token = AttachmentToken.line(for: AttachmentID(rawValue: "6f9619ff-8b86-4d11-b42d-00c04fc964ff"))
        let text = "```\n\(token)\n```"
        let host = try AttachmentTestHost(text: text)
        defer { host.cleanUp() }
        host.textView.setSelectedRange(NSRange(location: 0, length: text.utf16.count))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.writeSelection(to: pasteboard, types: [.string]))

        assertPlainTextOnly(pasteboard, "a token in a code block")
        XCTAssertEqual(pasteboard.string(forType: .string), text)
    }

    /// Review Focus 2: pasting what was copied into another note keeps the attachment: the same id in both notes, drawn as
    /// what it is, and no new copy of the file.
    func testPastingCopiedTextWithATokenKeepsTheAttachment() throws {
        let (host, id) = try makeHost(.image)
        defer { host.cleanUp() }
        let view = host.textView
        let token = AttachmentToken.line(for: id)
        view.setSelectedRange(NSRange(location: 0, length: host.text.utf16.count))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(view.writeSelection(to: pasteboard, types: [.string]))

        // Another note, in the same editor and the same storage.
        let other = Note(id: NoteID.make(), title: "", body: "", createdAt: Date(), modifiedAt: Date())
        let tab = TabState(noteID: other.id, selection: 0, scrollY: 0, scrollAnchor: nil)
        host.editor.show(other, tab: tab, undoManager: UndoManager(), isReadOnly: false)
        host.editor.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.text, "")

        XCTAssertTrue(view.readSelection(from: pasteboard))
        host.waitForCopies()

        XCTAssertEqual(host.text, "before\n\(token)\nafter", "the text as it was stored, not the file's name")
        XCTAssertEqual(host.tokenIDs, [id], "the same attachment")
        host.spin(until: {
            let mark =
                view.textStorage?.attribute(
                    .scratchAttachment, at: host.tokenRange(id).location, effectiveRange: nil) as? AttachmentMark
            return mark?.kind == .image
        })
        let mark =
            view.textStorage?.attribute(.scratchAttachment, at: host.tokenRange(id).location, effectiveRange: nil)
            as? AttachmentMark
        XCTAssertEqual(mark?.kind, .image, "it is drawn as its image")
        XCTAssertEqual(host.importer.pendingCopies, 0, "nothing was copied again")
    }

    /// The same for Paste as plain text, which is the same as Paste (spec §6.5), through `readSelection(from:type:)`, which is
    /// what AppKit calls for a drop that it handles itself.
    func testReadingPlainTextOfAPasteboardThatHasNoteTextReadsNoteText() throws {
        let (host, id) = try makeHost()
        defer { host.cleanUp() }
        let view = host.textView
        let token = AttachmentToken.line(for: id)
        view.setSelectedRange(host.tokenRange(id))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(view.writeSelection(to: pasteboard, types: [.string]))
        view.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(view.readSelection(from: pasteboard, type: .string))

        XCTAssertEqual(host.text, "\(token)\nbefore\n\(token)\nafter", "above \"before\"")
        XCTAssertEqual(host.tokenIDs, [id, id])
    }

    /// Review Focus 2: a drag that moves text within a note, as far as the drop goes: the drop inserts the note's text as
    /// stored where it landed, so the token is the same and a name of a file is never put in its place.
    func testDroppingDraggedTextWithATokenKeepsTheToken() throws {
        let (host, id) = try makeHost()
        defer { host.cleanUp() }
        let view = host.textView
        let token = AttachmentToken.line(for: id)
        let size = AttachmentToken.lineLength
        view.setSelectedRange(NSRange(location: 0, length: 7 + size))  // "before", the line break and the token
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 7 + size))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))
        XCTAssertEqual(pasteboard.string(forType: .string), "before\nrollback-plan.txt")
        let point = try pointOfCharacter(7 + size + 1, in: host)  // the "a" of "after"
        XCTAssertTrue(view.acceptsDrop(of: pasteboard), "the note's text is a drop that Scratch takes")

        XCTAssertTrue(view.performDrop(of: pasteboard, atViewPoint: point))

        XCTAssertEqual(host.text, "before\n\(token)\nbefore\n\(token)\nafter")
        XCTAssertEqual(host.tokenIDs, [id, id])
        XCTAssertEqual(host.importer.pendingCopies, 0)
    }

    /// One attachment, selected whole, carries its file, its image and the note's text. Dropped in Scratch it is the same
    /// attachment, with no new copy: the note's text comes before the file.
    func testDropOfOneSelectedAttachmentKeepsItsId() throws {
        let (host, id) = try makeHost(.image)
        defer { host.cleanUp() }
        let view = host.textView
        let token = AttachmentToken.line(for: id)
        view.setSelectedRange(host.tokenRange(id))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))
        XCTAssertEqual(pasteboardURLs(pasteboard).count, 1, "its file is on the pasteboard too")
        let point = try pointOfCharacter(7 + AttachmentToken.lineLength + 1, in: host)

        XCTAssertTrue(view.performDrop(of: pasteboard, atViewPoint: point))

        XCTAssertEqual(host.text, "before\n\(token)\n\(token)\nafter")
        XCTAssertEqual(host.tokenIDs, [id, id])
        XCTAssertEqual(host.importer.pendingCopies, 0, "no new attachment")
    }

    /// Into code a block is literal: the plain text, with the names, goes in, as before. The note's text is not used.
    func testNoteTextIntoCodeInsertsNames() throws {
        let note = "```\nx\n```\nbefore\nafter"
        let (host, id) = try makeHost(text: note, caret: (note as NSString).range(of: "after").location)
        defer { host.cleanUp() }
        let view = host.textView
        XCTAssertEqual(host.text, "```\nx\n```\nbefore\n\(AttachmentToken.line(for: id))\nafter")
        let start = (host.text as NSString).range(of: "before").location
        view.setSelectedRange(NSRange(location: start, length: host.text.utf16.count - start))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(view.writeSelection(to: pasteboard, types: [.string]))
        XCTAssertNotNil(pasteboard.string(forType: noteTextType))
        view.setSelectedRange(NSRange(location: 5, length: 0))
        XCTAssertTrue(view.styler.isInCodeBlock(5), "the caret is in the block")

        XCTAssertTrue(view.readSelection(from: pasteboard))

        XCTAssertTrue(
            host.text.hasPrefix("```\nxbefore\nrollback-plan.txt\nafter\n```"), "the names, as text: \(host.text)")
        XCTAssertEqual(host.tokenIDs, [id], "no new token")
    }

    /// A note's text that names an attachment this store does not know is not used: it would be a missing attachment, and
    /// the rest of the pasteboard, the plain text here, is what is pasted.
    func testNoteTextOfAnUnknownAttachmentPastesThePlainText() throws {
        let host = try AttachmentTestHost(text: "")
        defer { host.cleanUp() }
        let unknown = AttachmentToken.line(for: AttachmentID(rawValue: "11111111-2222-4333-8444-555555555555"))
        let pasteboard = host.pasteboard(text: "report.txt")
        defer { pasteboard.releaseGlobally() }
        pasteboard.addTypes([noteTextType], owner: nil)
        XCTAssertTrue(pasteboard.setString(unknown, forType: noteTextType))

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))

        XCTAssertEqual(host.text, "report.txt")
        XCTAssertTrue(host.tokenIDs.isEmpty)
    }

    /// A note that cannot be edited takes no note text either.
    func testReadOnlyNoteTakesNoNoteText() throws {
        let (source, id) = try makeHost()
        defer { source.cleanUp() }
        source.textView.setSelectedRange(source.tokenRange(id))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(source.textView.writeSelection(to: pasteboard, types: [.string]))
        source.editor.setReadOnly(true)
        let before = source.text

        XCTAssertFalse(source.textView.readSelection(from: pasteboard))
        XCTAssertFalse(source.textView.acceptsDrop(of: pasteboard))

        XCTAssertEqual(source.text, before)
    }

    // MARK: A copied image outlives Scratch (plan 6 task 6)

    /// Stands in for the provider of a copied image and notes that it was asked for data.
    private nonisolated final class WatchingProvider: NSObject, NSPasteboardItemDataProvider {
        var wasAsked = false

        nonisolated func pasteboard(
            _ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType
        ) {
            wasAsked = true
        }
    }

    /// Quitting while the pasteboard still holds the copy of an image: the copy is written again with the PNG and the TIFF in
    /// place of the promise, which the provider would not be there to keep. Nothing asks the provider.
    func testMaterializeWritesTheImageData() throws {
        let (host, id) = try makeHost(.image)
        defer { host.cleanUp() }
        let view = host.textView
        let watcher = WatchingProvider()
        let original = AttachmentPasteboard.makeImageProvider
        AttachmentPasteboard.makeImageProvider = { _ in watcher }
        defer { AttachmentPasteboard.makeImageProvider = original }
        view.setSelectedRange(host.tokenRange(id))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))
        XCTAssertTrue(pasteboard.types?.contains(.png) ?? false, "the image is promised")

        XCTAssertTrue(AttachmentPasteboard.materialize(on: pasteboard))

        let png = try XCTUnwrap(pasteboard.data(forType: .png), "the PNG is on the pasteboard")
        XCTAssertEqual(Array(png.prefix(4)), Self.pngSignature)
        let tiff = try XCTUnwrap(pasteboard.data(forType: .tiff), "and the TIFF")
        XCTAssertEqual(NSBitmapImageRep(data: tiff)?.pixelsWide, 64)
        XCTAssertFalse(watcher.wasAsked, "the data was not made by the promise")
        XCTAssertEqual(pasteboard.string(forType: .string), "picture.png", "the rest of the item is as it was")
        XCTAssertEqual(pasteboard.string(forType: noteTextType), AttachmentToken.line(for: id))
        let urls = pasteboardURLs(pasteboard)
        XCTAssertEqual(urls.count, 1)
        let stored = try storedFile(id, in: host)
        XCTAssertTrue(urls.first.map { samePath($0, stored) } ?? false, "the file's URL is as it was: \(urls)")
        XCTAssertFalse(AttachmentPasteboard.materialize(on: pasteboard), "once: the pasteboard holds the data now")
    }

    /// A pasteboard that something else wrote since the copy is not Scratch's to write again.
    func testMaterializeLeavesAPasteboardThatChangedAlone() throws {
        let (host, id) = try makeHost(.image)
        defer { host.cleanUp() }
        host.textView.setSelectedRange(host.tokenRange(id))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(host.textView.writeSelection(to: pasteboard, types: [.string]))
        _ = pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("something else", forType: .string))

        XCTAssertFalse(AttachmentPasteboard.materialize(on: pasteboard))

        XCTAssertEqual(pasteboard.string(forType: .string), "something else")
        XCTAssertNil(pasteboard.data(forType: .png))
    }

    /// Only the copy of an image has a promise to keep: a file's URL stays good after Scratch quits, and text is text.
    func testMaterializeHasNothingToDoForAFileOrText() throws {
        let (host, id) = try makeHost(.text)
        defer { host.cleanUp() }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        host.textView.setSelectedRange(host.tokenRange(id))
        XCTAssertTrue(host.textView.writeSelection(to: pasteboard, types: [.string]))
        XCTAssertFalse(AttachmentPasteboard.materialize(on: pasteboard), "a file")

        host.textView.setSelectedRange(NSRange(location: 0, length: 6))
        XCTAssertTrue(host.textView.writeSelection(to: pasteboard, types: [.string]))
        XCTAssertFalse(AttachmentPasteboard.materialize(on: pasteboard), "text")
        XCTAssertEqual(pasteboard.string(forType: .string), "before")
    }

    // MARK: Hitting an attachment

    /// `attachmentHit(atViewPoint:)` is the rectangle that is drawn: inside it is the token, and the padding round it, the
    /// room beside a chip and every line of text are not.
    func testAttachmentHitIsTheDrawnRectangle() throws {
        let (host, id) = try makeHost(.text)
        defer { host.cleanUp() }
        let view = host.textView
        let rect = drawnRect(of: id, in: host)
        XCTAssertEqual(rect.height, AttachmentMetrics.chipHeight, accuracy: 0.5)
        XCTAssertGreaterThan(rect.width, 100)

        for point in [
            centre(of: rect), NSPoint(x: rect.minX + 1, y: rect.minY + 1), NSPoint(x: rect.maxX - 1, y: rect.maxY - 1),
        ] {
            let hit = view.attachmentHit(atViewPoint: point)
            XCTAssertEqual(hit?.0, host.tokenRange(id), "\(point) is in \(rect)")
            XCTAssertEqual(hit?.1, id)
        }
        for point in [
            NSPoint(x: rect.maxX + 20, y: rect.midY), NSPoint(x: rect.midX, y: rect.minY - 3),
            NSPoint(x: rect.midX, y: rect.maxY + 3), NSPoint(x: rect.minX - 3, y: rect.midY),
            NSPoint(x: rect.midX, y: 2),
        ] {
            XCTAssertNil(view.attachmentHit(atViewPoint: point), "\(point) is outside \(rect)")
        }
    }

    /// The preview of an image is hit as the rectangle it is drawn in, which is smaller than its line.
    func testAttachmentHitOfAnImageIsItsPreview() throws {
        let (host, id) = try makeHost(.image)
        defer { host.cleanUp() }
        let rect = drawnRect(of: id, in: host)
        XCTAssertEqual(rect.width, 64, accuracy: 0.5)
        XCTAssertEqual(rect.height, 40, accuracy: 0.5)

        XCTAssertEqual(host.textView.attachmentHit(atViewPoint: centre(of: rect))?.1, id)
        XCTAssertNil(host.textView.attachmentHit(atViewPoint: NSPoint(x: rect.maxX + 30, y: rect.midY)))
    }

    /// A note with no attachment has none to hit.
    func testAttachmentHitInANoteWithoutAttachments() throws {
        let host = try AttachmentTestHost(text: "just text\nand more")
        defer { host.cleanUp() }

        XCTAssertNil(host.textView.attachmentHit(atViewPoint: NSPoint(x: 40, y: 20)))
    }

    // MARK: Clicking

    /// A single click selects the token (it is outlined) and opens nothing.
    func testSingleClickSelectsTheToken() throws {
        let (host, id) = try makeHost(.text)
        defer { host.cleanUp() }
        var opened: [URL] = []
        host.textView.openURL = { opened.append($0) }
        host.textView.setSelectedRange(NSRange(location: 0, length: 0))

        click(at: centre(of: drawnRect(of: id, in: host)), in: host)

        XCTAssertEqual(host.textView.selectedRange(), host.tokenRange(id))
        XCTAssertTrue(opened.isEmpty, "a single click opens nothing")
        XCTAssertEqual(host.text, "before\n\(AttachmentToken.line(for: id))\nafter", "a click changes no text")
        XCTAssertTrue(host.window.firstResponder === host.textView, "the view takes the keyboard")
    }

    /// Review Focus: a double-click opens the stored file, not the original, through the seam that tests replace.
    func testDoubleClickOpensStoredFile() throws {
        let (host, id) = try makeHost(.text)
        defer { host.cleanUp() }
        var opened: [URL] = []
        host.textView.openURL = { opened.append($0) }
        let point = centre(of: drawnRect(of: id, in: host))

        click(at: point, clickCount: 1, in: host)
        XCTAssertTrue(opened.isEmpty)
        click(at: point, clickCount: 2, in: host)

        XCTAssertEqual(opened.count, 1)
        let stored = try storedFile(id, in: host)
        XCTAssertTrue(opened.first.map { samePath($0, stored) } ?? false, "\(opened)")
        XCTAssertEqual(host.textView.selectedRange(), host.tokenRange(id), "the token is selected too")
    }

    /// A third click of the same series does not open the file a second time.
    func testTripleClickDoesNotOpenTwice() throws {
        let (host, id) = try makeHost(.text)
        defer { host.cleanUp() }
        var opened: [URL] = []
        host.textView.openURL = { opened.append($0) }
        let point = centre(of: drawnRect(of: id, in: host))

        click(at: point, clickCount: 2, in: host)
        click(at: point, clickCount: 3, in: host)

        XCTAssertEqual(opened.count, 1)
    }

    /// An image opens too: the preview is hit, and the file is the stored PNG.
    func testDoubleClickOnAnImageOpensItsStoredFile() throws {
        let (host, id) = try makeHost(.image)
        defer { host.cleanUp() }
        var opened: [URL] = []
        host.textView.openURL = { opened.append($0) }

        click(at: centre(of: drawnRect(of: id, in: host)), clickCount: 2, in: host)

        XCTAssertEqual(opened.count, 1)
        let stored = try storedFile(id, in: host)
        XCTAssertTrue(opened.first.map { samePath($0, stored) } ?? false, "\(opened)")
    }

    /// A missing attachment opens nothing (it beeps), and a click on it still selects it.
    func testDoubleClickOnAMissingAttachmentOpensNothing() throws {
        let unknown = AttachmentID(rawValue: "11111111-2222-4333-8444-555555555555")
        let token = AttachmentToken.line(for: unknown)
        let host = try AttachmentTestHost(text: "a\n\(token)\nb")
        defer { host.cleanUp() }
        host.editor.view.layoutSubtreeIfNeeded()
        var opened: [URL] = []
        host.textView.openURL = { opened.append($0) }
        let point = centre(of: drawnRect(of: unknown, in: host))

        click(at: point, clickCount: 1, in: host)
        XCTAssertEqual(host.textView.selectedRange(), host.tokenRange(unknown))
        click(at: point, clickCount: 2, in: host)

        XCTAssertTrue(opened.isEmpty, "nothing is opened for an id with no row: \(opened)")
        XCTAssertEqual(host.text, "a\n\(token)\nb")
    }

    /// A file that went from the disk after the line was drawn is not opened either: nothing asks the app to open a path that
    /// is not there.
    func testDoubleClickWhenTheFileIsGoneOpensNothing() throws {
        let (host, id) = try makeHost(.text)
        defer { host.cleanUp() }
        var opened: [URL] = []
        host.textView.openURL = { opened.append($0) }
        let point = centre(of: drawnRect(of: id, in: host))
        try FileManager.default.removeItem(at: try storedFile(id, in: host))

        click(at: point, clickCount: 2, in: host)

        XCTAssertTrue(opened.isEmpty, "\(opened)")
    }

    /// A note in Recently Deleted cannot be changed, and its attachments can still be opened, selected and dragged out.
    func testReadOnlyNoteStillOpensItsAttachments() throws {
        let (host, id) = try makeHost(.text)
        defer { host.cleanUp() }
        host.editor.setReadOnly(true)
        var opened: [URL] = []
        host.textView.openURL = { opened.append($0) }
        let before = host.text

        click(at: centre(of: drawnRect(of: id, in: host)), clickCount: 2, in: host)

        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(host.textView.selectedRange(), host.tokenRange(id))
        XCTAssertEqual(host.text, before)
    }

    // MARK: Dragging out

    /// The drag writes the stored file's URL, as the one item of the drag.
    func testDragWriterIsTheStoredFile() throws {
        let (host, id) = try makeHost(.text)
        defer { host.cleanUp() }
        let file = try storedFile(id, in: host)

        let writer = AttachmentDrag.pasteboardWriter(for: file)

        XCTAssertTrue(url(of: writer).map { samePath($0, file) } ?? false, "an NSURL of the stored file")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(pasteboard.writeObjects([writer]))
        let urls = pasteboardURLs(pasteboard)
        XCTAssertEqual(urls.count, 1)
        XCTAssertTrue(urls.first.map { samePath($0, file) } ?? false, "a file URL on the pasteboard: \(urls)")
    }

    /// A drag starts once the mouse has moved 3 points from where it went down, with the stored file as its item and the
    /// preview or chip as its image. No drag session is begun: the view hands the item to `attachmentDragPresenter`.
    func testDragStartsPastThreePoints() throws {
        let (host, id) = try makeHost(.text)
        defer { host.cleanUp() }
        var started: [NSDraggingItem] = []
        host.textView.attachmentDragPresenter = { item, _ in started.append(item) }
        let rect = drawnRect(of: id, in: host)
        let point = centre(of: rect)

        press(at: point, in: host)
        drag(to: NSPoint(x: point.x + 2, y: point.y), in: host)
        XCTAssertTrue(started.isEmpty, "2 points is a click that moved")
        drag(to: NSPoint(x: point.x + 5, y: point.y), in: host)

        XCTAssertEqual(started.count, 1)
        let item = try XCTUnwrap(started.first)
        let dragged = try XCTUnwrap(url(of: item.item), "the item is the file's URL")
        XCTAssertTrue(samePath(dragged, try storedFile(id, in: host)), "\(dragged)")
        XCTAssertEqual(item.draggingFrame.origin.x, rect.minX, accuracy: 0.5)
        XCTAssertEqual(item.draggingFrame.origin.y, rect.minY, accuracy: 0.5)
        XCTAssertEqual(item.draggingFrame.size.width, rect.width, accuracy: 0.5)
        XCTAssertEqual(item.draggingFrame.size.height, rect.height, accuracy: 0.5)
        XCTAssertFalse(item.imageComponents?.isEmpty ?? true, "the drag image is the chip")

        drag(to: NSPoint(x: point.x + 40, y: point.y), in: host)
        XCTAssertEqual(started.count, 1, "one drag for one press")
        release(at: point, in: host)
        XCTAssertEqual(host.text, "before\n\(AttachmentToken.line(for: id))\nafter", "a drag changes no text")
    }

    /// A chip that is missing has no file to take out: dragging it does nothing.
    func testNothingIsDraggedOutOfAMissingAttachment() throws {
        let unknown = AttachmentID(rawValue: "11111111-2222-4333-8444-555555555555")
        let host = try AttachmentTestHost(text: "a\n\(AttachmentToken.line(for: unknown))\nb")
        defer { host.cleanUp() }
        host.editor.view.layoutSubtreeIfNeeded()
        var started: [NSDraggingItem] = []
        host.textView.attachmentDragPresenter = { item, _ in started.append(item) }
        let point = centre(of: drawnRect(of: unknown, in: host))

        press(at: point, in: host)
        drag(to: NSPoint(x: point.x + 30, y: point.y), in: host)
        release(at: point, in: host)

        XCTAssertTrue(started.isEmpty)
    }
}
