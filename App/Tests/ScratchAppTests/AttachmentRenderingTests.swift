import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/attachments.md ("Display"): a line `[[attachment:<id>]]` is drawn as a scaled
/// preview with rounded corners (an image) or as a chip with an icon, a name and a size (any other file), "Copying…"
/// while the copy runs and "Missing attachment" for an unknown id, a missing file or an image that cannot be decoded;
/// the token's characters are null glyphs but the first, the line is as high as what is drawn on it, previews are
/// decoded off the main thread and change only the display, and a change of the text width sizes the lines again
/// (spec §6.4, plan 5 task 4). Nothing here changes a character of the note.
@MainActor
final class AttachmentRenderingTests: XCTestCase {
    private struct SetupError: Error {}

    @MainActor
    private struct Host {
        let editor: EditorViewController
        let window: NSWindow
        let storage: ScratchStorage
        let catalog: AttachmentCatalog
        let directory: URL
        let note: Note

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: Setting up

    /// A storage in a directory of its own, with `fixture` seeded when there is one.
    private func openStorage(fixture: Fixture? = nil) throws -> (storage: ScratchStorage, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScratchAttachmentRenderingTests-\(UUID().uuidString)", isDirectory: true)
        let options = LaunchOptions(dataDirectory: directory, isIsolated: true, fixture: fixture)
        return (try ScratchStorage.open(options), directory)
    }

    /// The note that the `attachments` fixture opens in its tab.
    private func fixtureNote(in storage: ScratchStorage) throws -> Note {
        guard let tab = try storage.session.load()?.tabs.first, let note = try storage.notes.note(tab.noteID) else {
            throw SetupError()
        }
        return note
    }

    private func saveNote(_ body: String, id: NoteID = NoteID.make(), in storage: ScratchStorage) throws -> Note {
        let note = Note(id: id, title: "", body: body, createdAt: Date(), modifiedAt: Date())
        try storage.notes.save(note)
        return note
    }

    /// An editor in an 800 x 600 window that is never shown, with a catalog on `storage`, showing `note` from its top, or
    /// scrolled to `scrollAnchor`. The run loop is let turn for a moment afterwards (the lines are sized again when the
    /// text view has its width) unless `settles` is false, which leaves the note as `show` and the first layout made it:
    /// the chunks that style a long note have not run.
    private func makeHost(
        storage: ScratchStorage, directory: URL, note: Note, scrollAnchor: Int? = nil, settles: Bool = true
    ) -> Host {
        let editor = EditorViewController()
        let catalog = AttachmentCatalog(store: storage.attachments)
        editor.attachmentCatalog = catalog
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = editor
        window.setContentSize(NSSize(width: 800, height: 600))
        let tab = TabState(noteID: note.id, selection: 0, scrollY: 0, scrollAnchor: scrollAnchor)
        editor.show(note, tab: tab, undoManager: UndoManager(), isReadOnly: false)
        editor.view.layoutSubtreeIfNeeded()
        // Whatever the layout asks for a turn later (the lines are sized again when the text view has its width).
        if settles { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        return Host(
            editor: editor, window: window, storage: storage, catalog: catalog, directory: directory, note: note)
    }

    /// A host on the `attachments` fixture: "Screenshots", a PNG of 64 x 40 pixels and a text file.
    private func makeFixtureHost(beforeShowing prepare: (ScratchStorage, Note) throws -> Void = { _, _ in }) throws
        -> Host
    {
        let (storage, directory) = try openStorage(fixture: .attachments)
        let note = try fixtureNote(in: storage)
        try prepare(storage, note)
        return makeHost(storage: storage, directory: directory, note: note)
    }

    /// A PNG of `width` x `height` pixels in one colour.
    private func pngData(width: Int, height: Int) throws -> Data {
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else { throw SetupError() }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.systemOrange.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { throw SetupError() }
        return data
    }

    /// Adds an image attachment of `width` x `height` pixels to `noteID`, with its row and its file, and returns it.
    private func addImage(width: Int, height: Int, noteID: NoteID, to storage: ScratchStorage) throws -> AttachmentID {
        let id = AttachmentID.make()
        let data = try pngData(width: width, height: height)
        _ = try storage.attachments.register(
            id: id, noteID: noteID, fileName: "picture-\(width)x\(height).png", typeIdentifier: "public.png",
            byteSize: Int64(data.count), pixelSize: (width: width, height: height), now: Date())
        try storage.attachments.writeIn(id, data: data)
        return id
    }

    // MARK: Looking

    private func tokenRange(_ id: AttachmentID, in host: Host) -> NSRange {
        (host.editor.currentText as NSString).range(of: AttachmentToken.line(for: id))
    }

    private func attachmentMark(at index: Int, in host: Host) -> AttachmentMark? {
        host.editor.textView.textStorage?.attribute(.scratchAttachment, at: index, effectiveRange: nil)
            as? AttachmentMark
    }

    private func role(at index: Int, in host: Host) -> String? {
        host.editor.textView.textStorage?.attribute(.scratchMarker, at: index, effectiveRange: nil) as? String
    }

    private func isNullGlyph(at index: Int, in host: Host) -> Bool {
        guard let layoutManager = host.editor.textView.layoutManager else { return false }
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        return layoutManager.propertyForGlyph(at: glyph).contains(.null)
    }

    /// The height of the line that holds the character at `index`, with the whole note laid out first.
    private func lineHeight(at index: Int, in host: Host) -> CGFloat {
        guard let layoutManager = host.editor.textView.layoutManager else { return -1 }
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: host.editor.currentText.utf16.count))
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).height
    }

    /// The width that an image can be as wide as: the text's, which is the container's less its padding on each side.
    private func availableWidth(in host: Host) -> CGFloat {
        guard let container = host.editor.textView.textContainer else { return 0 }
        return container.size.width - 2 * container.lineFragmentPadding
    }

    private func spin(until condition: () -> Bool, seconds: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    }

    /// Runs the main run loop until the preview of `id` has been decoded.
    private func waitForPreview(of id: AttachmentID, in host: Host, file: StaticString = #filePath, line: UInt = #line)
    {
        let previews = host.editor.textView.styler.previews
        spin(until: { previews.cachedImage(forID: id, minPixelSize: 1) != nil })
        XCTAssertNotNil(
            previews.cachedImage(forID: id, minPixelSize: 1), "the preview is decoded within seconds", file: file,
            line: line)
    }

    /// The text view drawn into a bitmap, for the part of it in `rect` (the view's coordinates).
    private func render(_ rect: NSRect, in host: Host) -> NSBitmapImageRep? {
        let textView = host.editor.textView
        guard let rep = textView.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        textView.cacheDisplay(in: rect, to: rep)
        return rep
    }

    /// The colour of the pixel of `rep` (drawn from `rect`) that is at `point`, in the view's coordinates.
    private func colour(at point: NSPoint, in rep: NSBitmapImageRep, from rect: NSRect) -> NSColor? {
        let scale = CGFloat(rep.pixelsWide) / rect.width
        let x = Int((point.x - rect.minX) * scale)
        let y = Int((point.y - rect.minY) * scale)
        guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh else { return nil }
        return rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
    }

    /// The rectangle that the preview or chip of the token at `location` is drawn in, in the text view's coordinates.
    private func drawnRect(ofTokenAt location: Int, in host: Host) -> NSRect {
        let textView = host.editor.textView
        guard let layoutManager = textView.layoutManager as? MarkupLayoutManager,
            let rect = layoutManager.attachmentRect(forTokenAt: location)
        else { return .zero }
        return rect.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
    }

    // MARK: The token line

    /// docs/features/attachments.md, "Display": the characters of the token but the first have no glyph, the first keeps
    /// a clear one so that the line is a fragment of its own, and the line is as high as its preview and 12 pt more.
    func testTokenLineHasNullGlyphsAndPreviewHeight() throws {
        let host = try makeFixtureHost()
        defer { host.cleanUp() }
        let ids = AttachmentToken.ids(in: host.note.body)
        XCTAssertEqual(ids.count, 2, "the fixture has two attachments")
        let token = tokenRange(ids[0], in: host)
        XCTAssertEqual(token.length, 51)

        XCTAssertNil(role(at: token.location, in: host), "the first character is no hidden marker")
        XCTAssertEqual(role(at: token.location + 1, in: host), "attachment")
        XCTAssertFalse(isNullGlyph(at: token.location, in: host), "the first character keeps its glyph")
        XCTAssertTrue(
            (1..<token.length).allSatisfy { isNullGlyph(at: token.location + $0, in: host) },
            "every other character of the token has no glyph")

        let mark = try XCTUnwrap(attachmentMark(at: token.location, in: host))
        XCTAssertEqual(mark.id, ids[0])
        XCTAssertEqual(mark.kind, .image)
        XCTAssertEqual(mark.displaySize.width, 64, accuracy: 0.5, "an image is not made bigger than it is")
        XCTAssertEqual(mark.displaySize.height, 40, accuracy: 0.5)
        XCTAssertEqual(lineHeight(at: token.location, in: host), 40 + 12, accuracy: 0.5)
        XCTAssertLessThan(lineHeight(at: 0, in: host), 30, "a line of text is one line high")
    }

    /// docs/features/attachments.md, "Display" (images): as wide as the text, up to their own width, and at most 240 pt
    /// high, in the proportions of the image.
    func testImageIsScaledToWidthAndCap() throws {
        let (storage, directory) = try openStorage()
        let noteID = NoteID.make()
        let tall = try addImage(width: 1200, height: 900, noteID: noteID, to: storage)
        let wide = try addImage(width: 3000, height: 100, noteID: noteID, to: storage)
        let small = try addImage(width: 64, height: 40, noteID: noteID, to: storage)
        let body = [tall, wide, small].map { AttachmentToken.line(for: $0) }.joined(separator: "\n")
        let host = makeHost(storage: storage, directory: directory, note: try saveNote(body, id: noteID, in: storage))
        defer { host.cleanUp() }
        let available = availableWidth(in: host)
        XCTAssertGreaterThan(available, 400, "the editor is laid out")

        let tallMark = try XCTUnwrap(attachmentMark(at: tokenRange(tall, in: host).location, in: host))
        XCTAssertEqual(tallMark.displaySize.height, 240, accuracy: 1, "capped at 240 pt")
        XCTAssertEqual(tallMark.displaySize.width, 320, accuracy: 1, "in the proportions of the image")

        let wideMark = try XCTUnwrap(attachmentMark(at: tokenRange(wide, in: host).location, in: host))
        XCTAssertEqual(wideMark.displaySize.width, available, accuracy: 1, "as wide as the text")
        XCTAssertEqual(wideMark.displaySize.height, 100 * available / 3000, accuracy: 1)

        let smallMark = try XCTUnwrap(attachmentMark(at: tokenRange(small, in: host).location, in: host))
        XCTAssertEqual(smallMark.displaySize.width, 64, accuracy: 0.5)
        XCTAssertEqual(smallMark.displaySize.height, 40, accuracy: 0.5)

        for (id, expected) in [(tall, tallMark), (wide, wideMark), (small, smallMark)] {
            XCTAssertEqual(
                lineHeight(at: tokenRange(id, in: host).location, in: host), expected.displaySize.height + 12,
                accuracy: 1, "the line is as high as the preview and 6 pt above and below it")
        }
    }

    /// docs/features/attachments.md, "Display" (other files): a chip 44 pt high with the file's name and size.
    func testFileChipHeightAndName() throws {
        let host = try makeFixtureHost()
        defer { host.cleanUp() }
        let ids = AttachmentToken.ids(in: host.note.body)
        let token = tokenRange(ids[1], in: host)
        let mark = try XCTUnwrap(attachmentMark(at: token.location, in: host))
        XCTAssertEqual(mark.kind, .file)
        XCTAssertEqual(mark.fileName, "rollback-plan.txt")
        XCTAssertEqual(mark.byteSize, host.catalog.attachment(ids[1])?.byteSize)
        XCTAssertGreaterThan(mark.byteSize ?? 0, 0)
        XCTAssertEqual(mark.displaySize.height, 44, accuracy: 0.5)
        XCTAssertLessThanOrEqual(mark.displaySize.width, 360)
        XCTAssertEqual(lineHeight(at: token.location, in: host), 44 + 12, accuracy: 0.5)
        XCTAssertTrue(
            (1..<token.length).allSatisfy { isNullGlyph(at: token.location + $0, in: host) },
            "a chip's token has no glyphs either")
    }

    // MARK: Attachments that cannot be shown

    /// docs/features/attachments.md, "Display" (missing): a file that is gone draws as a "Missing attachment" chip, and
    /// nothing removes the row or the text.
    func testMissingFileDrawsMissingChip() throws {
        var imageID: AttachmentID?
        let host = try makeFixtureHost { storage, note in
            let id = try XCTUnwrap(AttachmentToken.ids(in: note.body).first)
            imageID = id
            let attachment = try XCTUnwrap(try storage.attachments.attachment(id))
            try FileManager.default.removeItem(at: storage.attachments.fileURL(for: attachment))
        }
        defer { host.cleanUp() }
        let id = try XCTUnwrap(imageID)
        let token = tokenRange(id, in: host)
        let mark = try XCTUnwrap(attachmentMark(at: token.location, in: host))
        XCTAssertEqual(mark.kind, .missing)
        XCTAssertEqual(mark.displaySize.height, 44, accuracy: 0.5)
        XCTAssertEqual(lineHeight(at: token.location, in: host), 44 + 12, accuracy: 0.5)
        XCTAssertNotNil(try host.storage.attachments.attachment(id), "the row stays")
        XCTAssertEqual(host.editor.currentText, host.note.body, "and so does the token")
    }

    /// docs/features/attachments.md, "Display" (missing): a token that someone typed, with an id that has no row.
    func testUnknownIDDrawsMissingChip() throws {
        let (storage, directory) = try openStorage()
        let id = AttachmentID.make()
        let body = "before\n\(AttachmentToken.line(for: id))\nafter"
        let host = makeHost(storage: storage, directory: directory, note: try saveNote(body, in: storage))
        defer { host.cleanUp() }
        let token = tokenRange(id, in: host)
        XCTAssertEqual(token.length, 51)
        let mark = try XCTUnwrap(attachmentMark(at: token.location, in: host))
        XCTAssertEqual(mark.kind, .missing)
        XCTAssertEqual(mark.id, id)
        XCTAssertEqual(lineHeight(at: token.location, in: host), 44 + 12, accuracy: 0.5)
        XCTAssertTrue((1..<token.length).allSatisfy { isNullGlyph(at: token.location + $0, in: host) })
        XCTAssertEqual(host.editor.currentText, body)
    }

    /// docs/features/attachments.md, "Display" (missing): an image that cannot be decoded is first drawn as an image, and
    /// as a chip once the decoding has failed. The file stays.
    func testCorruptImageDrawsChip() throws {
        var imageID: AttachmentID?
        var imageURL: URL?
        let host = try makeFixtureHost { storage, note in
            let id = try XCTUnwrap(AttachmentToken.ids(in: note.body).first)
            imageID = id
            let attachment = try XCTUnwrap(try storage.attachments.attachment(id))
            let url = storage.attachments.fileURL(for: attachment)
            imageURL = url
            try Data("this is not a png".utf8).write(to: url)
        }
        defer { host.cleanUp() }
        let id = try XCTUnwrap(imageID)
        let token = tokenRange(id, in: host)
        spin(until: { self.attachmentMark(at: token.location, in: host)?.kind == .missing })
        XCTAssertEqual(
            attachmentMark(at: token.location, in: host)?.kind, .missing, "the decoding failed within seconds")
        XCTAssertEqual(lineHeight(at: token.location, in: host), 44 + 12, accuracy: 0.5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(imageURL).path), "the file stays")
        XCTAssertEqual(host.editor.currentText, host.note.body)
    }

    /// docs/features/attachments.md, "Display" (copying): a row whose copy is under way is a "Copying…" chip, and becomes
    /// the image once the copy is done. A row with no file that nothing is copying is missing.
    func testCopyingAttachmentDrawsChipUntilCopied() throws {
        let (storage, directory) = try openStorage()
        let noteID = NoteID.make()
        let id = AttachmentID.make()
        let data = try pngData(width: 80, height: 60)
        _ = try storage.attachments.register(
            id: id, noteID: noteID, fileName: "photo.png", typeIdentifier: "public.png",
            byteSize: Int64(data.count), pixelSize: (width: 80, height: 60), now: Date())
        let host = makeHost(
            storage: storage, directory: directory,
            note: try saveNote("a\n\(AttachmentToken.line(for: id))\nb", id: noteID, in: storage))
        defer { host.cleanUp() }
        let token = tokenRange(id, in: host)
        XCTAssertEqual(
            attachmentMark(at: token.location, in: host)?.kind, .missing, "nothing copies it, and it has no file")

        host.catalog.markCopying(id)
        XCTAssertEqual(attachmentMark(at: token.location, in: host)?.kind, .copying)
        XCTAssertEqual(attachmentMark(at: token.location, in: host)?.fileName, "photo.png")
        XCTAssertEqual(lineHeight(at: token.location, in: host), 44 + 12, accuracy: 0.5)

        try storage.attachments.writeIn(id, data: data)
        host.catalog.markCopied(id)
        XCTAssertEqual(attachmentMark(at: token.location, in: host)?.kind, .image)
        XCTAssertEqual(lineHeight(at: token.location, in: host), 60 + 12, accuracy: 0.5)
    }

    // MARK: Drawing

    /// docs/features/attachments.md, "Display" (previews): the decoded preview is what is drawn in the line's rectangle.
    func testPreviewPixelsAreDrawn() throws {
        let host = try makeFixtureHost()
        defer { host.cleanUp() }
        let id = try XCTUnwrap(AttachmentToken.ids(in: host.note.body).first)
        waitForPreview(of: id, in: host)
        let token = tokenRange(id, in: host)
        let target = drawnRect(ofTokenAt: token.location, in: host)
        XCTAssertEqual(target.width, 64, accuracy: 0.5)
        XCTAssertEqual(target.height, 40, accuracy: 0.5)

        let rect = target.insetBy(dx: -8, dy: -8)
        let rep = try XCTUnwrap(render(rect, in: host))
        // The fixture's picture is a blue gradient with a white window on it: most of its pixels are much bluer than red,
        // and no tint or background is.
        var bluish = 0
        var total = 0
        let inside = target.insetBy(dx: 1, dy: 1)
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let point = NSPoint(
                    x: rect.minX + (CGFloat(x) + 0.5) * rect.width / CGFloat(rep.pixelsWide),
                    y: rect.minY + (CGFloat(y) + 0.5) * rect.height / CGFloat(rep.pixelsHigh))
                guard inside.contains(point), let pixel = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                total += 1
                if pixel.blueComponent - pixel.redComponent > 0.2 { bluish += 1 }
            }
        }
        XCTAssertGreaterThan(total, 1000)
        XCTAssertGreaterThan(bluish * 4, total, "a quarter of the rectangle is the picture's blue")
    }

    /// The pixels of the chip of the token at `location` that are not the chip's own tint: in the icon's square and in the
    /// part of the chip where the name and the size are. Both are drawn in colours far from the tint, whatever the
    /// appearance. Also the difference between the tint and what is just outside the chip.
    private func chipInk(
        atTokenAt location: Int, in host: Host
    ) throws -> (icon: Int, text: Int, tintDistance: CGFloat) {
        let target = drawnRect(ofTokenAt: location, in: host)
        XCTAssertEqual(target.height, 44, accuracy: 0.5)
        let rect = target.insetBy(dx: -8, dy: -8)
        let rep = try XCTUnwrap(render(rect, in: host))
        func distance(_ first: NSColor, _ second: NSColor) -> CGFloat {
            abs(first.redComponent - second.redComponent) + abs(first.greenComponent - second.greenComponent)
                + abs(first.blueComponent - second.blueComponent)
        }
        // Nothing is drawn at the right end of a chip, where the tint shows.
        let tint = try XCTUnwrap(colour(at: NSPoint(x: target.maxX - 6, y: target.midY), in: rep, from: rect))
        let outside = try XCTUnwrap(colour(at: NSPoint(x: target.maxX + 4, y: target.midY), in: rep, from: rect))
        func ink(in area: NSRect) -> Int {
            var count = 0
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    let point = NSPoint(
                        x: rect.minX + (CGFloat(x) + 0.5) * rect.width / CGFloat(rep.pixelsWide),
                        y: rect.minY + (CGFloat(y) + 0.5) * rect.height / CGFloat(rep.pixelsHigh))
                    guard area.contains(point), let pixel = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                        continue
                    }
                    if distance(pixel, tint) > 0.25 { count += 1 }
                }
            }
            return count
        }
        let icon = NSRect(x: target.minX + 8, y: target.minY + 6, width: 32, height: 32)
        let text = NSRect(x: target.minX + 48, y: target.minY + 4, width: 160, height: 36)
        return (ink(in: icon), ink(in: text), distance(tint, outside))
    }

    /// docs/features/attachments.md, "Display" (other files): the chip is a tint with the file's icon, its name and its size
    /// drawn on it.
    func testFileChipDrawsIconAndText() throws {
        let host = try makeFixtureHost()
        defer { host.cleanUp() }
        let id = try XCTUnwrap(AttachmentToken.ids(in: host.note.body).last)
        let ink = try chipInk(atTokenAt: tokenRange(id, in: host).location, in: host)
        XCTAssertGreaterThan(ink.tintDistance, 0.05, "the chip is tinted")
        XCTAssertGreaterThan(ink.icon, 20, "the icon is drawn")
        XCTAssertGreaterThan(ink.text, 50, "the name and the size are drawn")
    }

    /// docs/features/attachments.md, "Display" (missing): the chip of a missing attachment has a symbol and its words.
    func testMissingChipDrawsSymbolAndText() throws {
        let (storage, directory) = try openStorage()
        let id = AttachmentID.make()
        let note = try saveNote("above\n\(AttachmentToken.line(for: id))\nbelow", in: storage)
        let host = makeHost(storage: storage, directory: directory, note: note)
        defer { host.cleanUp() }
        let ink = try chipInk(atTokenAt: tokenRange(id, in: host).location, in: host)
        XCTAssertGreaterThan(ink.tintDistance, 0.05, "the chip is tinted")
        XCTAssertGreaterThan(ink.icon, 20, "the symbol is drawn")
        XCTAssertGreaterThan(ink.text, 50, "the words are drawn")
    }

    /// docs/features/attachments.md, "Display" (previews): a preview that arrives changes only what is drawn: no line is
    /// laid out again, and the text and its attributes are what they were.
    func testPreviewArrivalKeepsTheLayout() throws {
        let host = try makeFixtureHost()
        defer { host.cleanUp() }
        let id = try XCTUnwrap(AttachmentToken.ids(in: host.note.body).first)
        let token = tokenRange(id, in: host)
        let before = lineHeight(at: token.location, in: host)
        let markBefore = try XCTUnwrap(attachmentMark(at: token.location, in: host))
        waitForPreview(of: id, in: host)
        spin(until: { host.editor.textView.styler.previews.pendingCount == 0 })
        XCTAssertEqual(lineHeight(at: token.location, in: host), before, accuracy: 0.01)
        XCTAssertTrue(attachmentMark(at: token.location, in: host) === markBefore, "the line was not styled again")
        XCTAssertEqual(host.editor.currentText, host.note.body)
    }

    /// docs/features/attachments.md, "Display" (selected): a selected token has a 2 pt outline in the accent colour round
    /// its preview, which a token that is not selected does not.
    func testSelectedTokenDrawsOutline() throws {
        let host = try makeFixtureHost()
        defer { host.cleanUp() }
        let id = try XCTUnwrap(AttachmentToken.ids(in: host.note.body).first)
        waitForPreview(of: id, in: host)
        let token = tokenRange(id, in: host)
        let target = drawnRect(ofTokenAt: token.location, in: host)
        let rect = target.insetBy(dx: -8, dy: -8)
        let ring = NSPoint(x: target.midX, y: target.minY - 1)

        let plain = try XCTUnwrap(render(rect, in: host))
        let plainPixel = try XCTUnwrap(colour(at: ring, in: plain, from: rect))
        host.editor.textView.setSelectedRange(token)
        let selected = try XCTUnwrap(render(rect, in: host))
        let selectedPixel = try XCTUnwrap(colour(at: ring, in: selected, from: rect))
        let distance =
            abs(plainPixel.redComponent - selectedPixel.redComponent)
            + abs(plainPixel.greenComponent - selectedPixel.greenComponent)
            + abs(plainPixel.blueComponent - selectedPixel.blueComponent)
        XCTAssertGreaterThan(distance, 0.3, "the outline is drawn just outside the preview")
    }

    /// docs/features/attachments.md, "Display": styling never edits the text.
    func testTextIsUnchanged() throws {
        let host = try makeFixtureHost()
        defer { host.cleanUp() }
        XCTAssertEqual(host.editor.textView.string, host.note.body)
        XCTAssertEqual(host.editor.currentText, host.note.body)
        let id = try XCTUnwrap(AttachmentToken.ids(in: host.note.body).first)
        waitForPreview(of: id, in: host)
        XCTAssertEqual(host.editor.textView.string, host.note.body, "and nothing that arrives later does")
    }

    // MARK: The text width

    /// docs/features/attachments.md, "Display" (width changes): the height of an image depends on the width of the text,
    /// so a change of the width sizes the lines of the tokens again.
    func testWidthChangeRestylesTokenLines() throws {
        let (storage, directory) = try openStorage()
        let noteID = NoteID.make()
        let wide = try addImage(width: 3000, height: 100, noteID: noteID, to: storage)
        let host = makeHost(
            storage: storage, directory: directory,
            note: try saveNote("text\n\(AttachmentToken.line(for: wide))\nmore", id: noteID, in: storage))
        defer { host.cleanUp() }
        let token = tokenRange(wide, in: host)
        let widthBefore = try XCTUnwrap(attachmentMark(at: token.location, in: host)).displaySize.width
        XCTAssertEqual(widthBefore, availableWidth(in: host), accuracy: 1)

        host.window.setContentSize(NSSize(width: 500, height: 600))
        host.editor.view.layoutSubtreeIfNeeded()
        spin(until: {
            abs((self.attachmentMark(at: token.location, in: host)?.displaySize.width ?? 0) - widthBefore) > 10
        })

        let after = try XCTUnwrap(attachmentMark(at: token.location, in: host))
        XCTAssertLessThan(after.displaySize.width, widthBefore - 10, "the text is narrower, so is the image")
        XCTAssertEqual(after.displaySize.width, availableWidth(in: host), accuracy: 1)
        XCTAssertEqual(after.displaySize.height, 100 * availableWidth(in: host) / 3000, accuracy: 1)
        XCTAssertEqual(
            lineHeight(at: token.location, in: host), after.displaySize.height + 12, accuracy: 1,
            "the line is as high as the preview that is drawn in it")
    }

    // MARK: The scroll position

    /// The 1-based number of the line that holds the UTF-16 offset `offset` of `text`.
    private func lineNumber(ofOffset offset: Int, in text: String) -> Int {
        text.utf16.prefix(offset).filter { $0 == 0x0A }.count + 1
    }

    /// AGENTS.md, "Blocks above the window are styled whole at load": a position is worked out from the layout of what is
    /// above it, and a token line is 252 pt high where a line of text is 17, so a token line above the window that a chunk
    /// styled after the scroll was set moved the note under the reader. At `show` the token line is styled already, and
    /// when the chunks have run the line at the top is the one that was.
    func testTokenLineFarAboveTheAnchorIsStyledBeforeTheScroll() throws {
        let (storage, directory) = try openStorage()
        let noteID = NoteID.make()
        let tall = try addImage(width: 1_200, height: 900, noteID: noteID, to: storage)
        var lines = (1...1_500).map { "text line \($0)" }
        lines[9] = AttachmentToken.line(for: tall)
        let body = lines.joined(separator: "\n")
        let anchor = (body as NSString).range(of: "text line 1400").location
        XCTAssertNotEqual(anchor, NSNotFound)
        let host = makeHost(
            storage: storage, directory: directory, note: try saveNote(body, id: noteID, in: storage),
            scrollAnchor: anchor, settles: false)
        defer { host.cleanUp() }
        let styler = host.editor.textView.styler
        XCTAssertFalse(styler.isFullyStyled, "the text above the window is still to be styled in chunks")
        XCTAssertEqual(
            lineNumber(ofOffset: host.editor.currentScrollAnchor, in: body), 1_400, "the note is at its anchor")

        let token = tokenRange(tall, in: host)
        XCTAssertEqual(lineNumber(ofOffset: token.location, in: body), 10)
        XCTAssertEqual(lineNumber(ofOffset: anchor, in: body), 1_400, "far above the paragraphs styled at once")
        let mark = try XCTUnwrap(
            attachmentMark(at: token.location, in: host), "the token line above the window has its look at once")
        XCTAssertEqual(mark.kind, .image)
        XCTAssertEqual(mark.displaySize.height, 240, accuracy: 1)
        let style =
            host.editor.textView.textStorage?.attribute(.paragraphStyle, at: token.location, effectiveRange: nil)
            as? NSParagraphStyle
        XCTAssertEqual(style?.minimumLineHeight ?? 0, 240 + 12, accuracy: 1)
        XCTAssertEqual(style?.maximumLineHeight ?? 0, 240 + 12, accuracy: 1)

        // The layout of what is above `index`, which is all that the scroll position is worked out from.
        let layoutManager = try XCTUnwrap(host.editor.textView.layoutManager)
        func fragment(at index: Int) -> NSRect {
            layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: index + 1))
            let glyph = layoutManager.glyphIndexForCharacter(at: index)
            return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        }
        XCTAssertEqual(fragment(at: token.location).height, 240 + 12, accuracy: 1, "and its height is laid out")
        let before = fragment(at: anchor).minY

        spin(until: { styler.isFullyStyled })

        XCTAssertTrue(styler.isFullyStyled)
        XCTAssertEqual(fragment(at: anchor).minY, before, accuracy: 0.5, "the line at the top has not moved")
        XCTAssertEqual(
            lineNumber(ofOffset: host.editor.currentScrollAnchor, in: body), 1_400,
            "and it is still the line at the top of the window")
        XCTAssertEqual(host.editor.currentText, body)
    }

    // MARK: The catalog

    /// The catalog reads what the store knows: a row, its file's place, and nothing for an id with no row.
    func testCatalogKnowsFixtureAttachments() throws {
        let host = try makeFixtureHost()
        defer { host.cleanUp() }
        let ids = AttachmentToken.ids(in: host.note.body)
        XCTAssertEqual(host.catalog.attachment(ids[0])?.fileName, "dashboard.png")
        XCTAssertEqual(host.catalog.attachment(ids[0])?.pixelWidth, 64)
        XCTAssertEqual(host.catalog.attachment(ids[1])?.fileName, "rollback-plan.txt")
        let url = try XCTUnwrap(host.catalog.fileURL(ids[1]))
        XCTAssertEqual(url.lastPathComponent, "rollback-plan.txt")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, ids[1].rawValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let unknown = AttachmentID.make()
        XCTAssertNil(host.catalog.attachment(unknown))
        XCTAssertNil(host.catalog.fileURL(unknown))
    }

    /// The catalog says which attachment changed when a copy starts or ends, so that the line of the token is styled again.
    func testCatalogReportsCopyingAndCopied() throws {
        let host = try makeFixtureHost()
        defer { host.cleanUp() }
        let id = try XCTUnwrap(AttachmentToken.ids(in: host.note.body).first)
        var changed: [AttachmentID] = []
        let previous = host.catalog.onChange
        host.catalog.onChange = { id in
            changed.append(id)
            previous?(id)
        }
        host.catalog.markCopying(id)
        host.catalog.markCopied(id)
        XCTAssertEqual(changed, [id, id])
    }
}
