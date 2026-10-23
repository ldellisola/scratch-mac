import AppKit
import ScratchCore
import UniformTypeIdentifiers
import XCTest

@testable import Scratch

/// Hosted in the app. Covers docs/features/attachments.md ("Pasting and dropping") and docs/features/paste-and-copy.md
/// ("Paste order"): file references become attachments, any text wins over an image, an image with no text becomes a PNG
/// attachment, each attachment is a line of its own, a note that cannot be edited takes nothing, a paste into code inserts
/// the file names, and one paste is one undo step (spec §6.5, plan 5 task 5). Every paste goes through
/// `readSelection(from:)` with a pasteboard of its own, which is what Paste runs, and never touches the real clipboard.
///
/// What ⌘Z does after an autosave is `AttachmentUITests`: an undo group ends with the run loop turn, and a test method is
/// one turn.
@MainActor
final class AttachmentPasteTests: XCTestCase {
    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]

    // MARK: Files

    /// Paste order 1: a file reference becomes an attachment, a line of its own, and the file is copied into Scratch's
    /// storage off the main thread.
    func testFileURLPastesAsAttachmentLine() throws {
        let host = try AttachmentTestHost()
        defer { host.cleanUp() }
        let contents = Data("1. stop the writers\n2. roll back\n".utf8)
        let file = try host.makeFile(named: "rollback-plan.txt", contents: contents)
        let pasteboard = host.pasteboard(files: [file])
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))

        let ids = host.tokenIDs
        XCTAssertEqual(ids.count, 1)
        guard let id = ids.first else { return }
        XCTAssertEqual(
            host.text, AttachmentToken.line(for: id) + "\n", "the token is a line, and a line break follows it")
        XCTAssertEqual(
            host.textView.selectedRange(), NSRange(location: host.text.utf16.count, length: 0),
            "the caret is on the line after the token")

        var row = try host.row(id)
        XCTAssertEqual(row.noteID, host.noteID)
        XCTAssertEqual(row.fileName, "rollback-plan.txt")
        XCTAssertEqual(row.byteSize, Int64(contents.count))
        XCTAssertTrue(UTType(row.typeIdentifier)?.conforms(to: .text) == true, "type: \(row.typeIdentifier)")
        XCTAssertFalse(row.isImage)

        host.waitForCopies()
        row = try host.row(id)
        XCTAssertTrue(row.isCopied)
        XCTAssertEqual(
            try Data(contentsOf: host.storage.attachments.fileURL(for: row)), contents, "the copy is the file")
        XCTAssertEqual(host.textView.pendingPasteClassifications, 0, "the tokens are not classified as code")
    }

    /// The row of an image file knows its pixel size and type, which is what the preview is sized from.
    func testImageFileRowHasPixelSizeAndType() throws {
        let host = try AttachmentTestHost()
        defer { host.cleanUp() }
        let file = try host.makePNGFile(named: "picture.png", width: 64, height: 40)
        let pasteboard = host.pasteboard(files: [file])
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))

        let row = try host.row(try XCTUnwrap(host.tokenIDs.first))
        XCTAssertEqual(row.typeIdentifier, "public.png")
        XCTAssertTrue(row.isImage)
        XCTAssertEqual(row.pixelWidth, 64)
        XCTAssertEqual(row.pixelHeight, 40)
        XCTAssertEqual(row.fileName, "picture.png")
    }

    /// Finder puts the file's name on the pasteboard as text too: the file wins (spec §6.5, 1 before 2).
    func testFileWinsOverItsNameAsText() throws {
        let host = try AttachmentTestHost()
        defer { host.cleanUp() }
        let file = try host.makeFile(named: "notes.txt", contents: Data("x".utf8))
        let pasteboard = host.pasteboard(files: [file], text: "notes.txt")
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))

        XCTAssertEqual(host.tokenIDs.count, 1)
        XCTAssertFalse(host.text.contains("notes.txt"), "the name is not pasted as text: \(host.text)")
    }

    /// A file that is not there (a reference that went stale) is not an attachment: nothing is inserted for it.
    func testMissingFileIsLeftOut() throws {
        let host = try AttachmentTestHost()
        defer { host.cleanUp() }
        let there = try host.makeFile(named: "there.txt", contents: Data("x".utf8))
        let gone = try host.makeFile(named: "gone.txt", contents: Data("y".utf8))
        let pasteboard = host.pasteboard(files: [gone, there])
        defer { pasteboard.releaseGlobally() }
        try FileManager.default.removeItem(at: gone)

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))

        let ids = host.tokenIDs
        XCTAssertEqual(ids.count, 1)
        XCTAssertEqual(try host.row(try XCTUnwrap(ids.first)).fileName, "there.txt")
    }

    func testTwoFilesTwoLines() throws {
        let host = try AttachmentTestHost()
        defer { host.cleanUp() }
        let first = try host.makeFile(named: "one.txt", contents: Data("1".utf8))
        let second = try host.makeFile(named: "two.txt", contents: Data("22".utf8))
        let pasteboard = host.pasteboard(files: [first, second])
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))

        let ids = host.tokenIDs
        XCTAssertEqual(ids.count, 2)
        guard ids.count == 2 else { return }
        XCTAssertEqual(host.text, AttachmentToken.line(for: ids[0]) + "\n" + AttachmentToken.line(for: ids[1]) + "\n")
        XCTAssertEqual(try host.row(ids[0]).fileName, "one.txt", "in the order of the pasteboard")
        XCTAssertEqual(try host.row(ids[1]).fileName, "two.txt")
        host.waitForCopies()
        XCTAssertTrue(try host.row(ids[0]).isCopied)
        XCTAssertTrue(try host.row(ids[1]).isCopied)
    }

    /// Global Constraints, "Tokens": an inserted attachment always gets its own line.
    func testPasteMidLineGetsOwnLine() throws {
        let host = try AttachmentTestHost(text: "abcdef", caret: 3)
        defer { host.cleanUp() }
        let file = try host.makeFile(named: "a.txt", contents: Data("a".utf8))
        let pasteboard = host.pasteboard(files: [file])
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))

        let id = try XCTUnwrap(host.tokenIDs.first)
        XCTAssertEqual(host.text, "abc\n" + AttachmentToken.line(for: id) + "\ndef")
        XCTAssertEqual(
            host.textView.selectedRange(), NSRange(location: 4 + AttachmentToken.lineLength + 1, length: 0),
            "the caret is at the start of the text that followed")
    }

    /// An attachment pasted over a selection replaces it.
    func testPasteReplacesTheSelection() throws {
        let host = try AttachmentTestHost(text: "keep\nreplace me\nkeep")
        defer { host.cleanUp() }
        host.textView.setSelectedRange(NSRange(location: 5, length: 10))
        let file = try host.makeFile(named: "a.txt", contents: Data("a".utf8))
        let pasteboard = host.pasteboard(files: [file])
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))

        let id = try XCTUnwrap(host.tokenIDs.first)
        XCTAssertEqual(host.text, "keep\n" + AttachmentToken.line(for: id) + "\nkeep")
    }

    // MARK: Images

    /// Paste order 3: an image with no text is an image attachment, stored as PNG. PNG data is stored as it is.
    func testImageOnlyPastesAsPNGAttachment() throws {
        let host = try AttachmentTestHost()
        defer { host.cleanUp() }
        let png = try AttachmentTestHost.imageData(width: 64, height: 40, type: .png)
        let pasteboard = host.pasteboard(png: png)
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))

        let id = try XCTUnwrap(host.tokenIDs.first)
        var row = try host.row(id)
        XCTAssertEqual(row.typeIdentifier, "public.png")
        XCTAssertTrue(row.isImage)
        XCTAssertEqual(row.pixelWidth, 64)
        XCTAssertEqual(row.pixelHeight, 40)
        XCTAssertTrue(row.fileName.hasSuffix(".png"), "name: \(row.fileName)")
        host.waitForCopies()
        row = try host.row(id)
        XCTAssertTrue(row.isCopied)
        XCTAssertEqual(try Data(contentsOf: host.storage.attachments.fileURL(for: row)), png)
        XCTAssertEqual(host.textView.pendingPasteClassifications, 0)
    }

    /// An image that is only a TIFF on the pasteboard is converted: what is stored is a PNG.
    func testTIFFOnlyIsStoredAsPNG() throws {
        let host = try AttachmentTestHost()
        defer { host.cleanUp() }
        let tiff = try AttachmentTestHost.imageData(width: 50, height: 30, type: .tiff)
        let pasteboard = host.pasteboard(tiff: tiff)
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))

        let id = try XCTUnwrap(host.tokenIDs.first)
        host.waitForCopies()
        let row = try host.row(id)
        XCTAssertEqual(row.typeIdentifier, "public.png")
        XCTAssertEqual(row.pixelWidth, 50)
        XCTAssertEqual(row.pixelHeight, 30)
        XCTAssertTrue(row.fileName.hasSuffix(".png"), "name: \(row.fileName)")
        let stored = try Data(contentsOf: host.storage.attachments.fileURL(for: row))
        XCTAssertEqual(Array(stored.prefix(4)), Self.pngSignature, "the stored file is a PNG")
    }

    /// A TIFF reaches the importer as it came: the editor decodes and encodes nothing on the main thread, where a full-size
    /// picture would take hundreds of milliseconds (spec §4, "Visible lag"). The importer makes the PNG on the storage queue.
    func testTIFFPasteHandsTheImporterTheBytesUnconverted() throws {
        let host = try AttachmentTestHost()
        defer { host.cleanUp() }
        let spy = SpyImporter()
        host.textView.attachmentImporter = spy
        let tiff = try AttachmentTestHost.imageData(width: 50, height: 30, type: .tiff)
        let pasteboard = host.pasteboard(tiff: tiff)
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))

        XCTAssertEqual(spy.calls.count, 1)
        guard case .image(let data, let typeIdentifier)? = spy.calls.first?.first else {
            return XCTFail("no image source: \(spy.calls)")
        }
        XCTAssertEqual(typeIdentifier, UTType.tiff.identifier)
        XCTAssertEqual(data, tiff, "the pasteboard's own bytes")
        XCTAssertNotEqual(Array(data.prefix(4)), Self.pngSignature, "not a PNG made on the way")
    }

    /// The row of a TIFF says PNG from the start, and nothing of the copy is done by the paste: with the copy queue held, the
    /// paste has returned, the file is not there, and when the queue runs the file that is written is a PNG of the same size
    /// whose size the row then holds.
    func testTIFFIsConvertedOnTheCopyQueue() throws {
        let queue = DispatchQueue(label: "ScratchAttachmentTests.heldCopies")
        let host = try AttachmentTestHost(copyQueue: queue)
        defer { host.cleanUp() }
        let release = DispatchSemaphore(value: 0)
        queue.async { release.wait() }
        defer { release.signal() }  // before `cleanUp()`, which waits for the copies
        let tiff = try AttachmentTestHost.imageData(width: 50, height: 30, type: .tiff)
        let pasteboard = host.pasteboard(tiff: tiff)
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))

        let id = try XCTUnwrap(host.tokenIDs.first)
        var row = try host.row(id)
        XCTAssertEqual(row.typeIdentifier, "public.png")
        XCTAssertTrue(row.fileName.hasSuffix(".png"), "name: \(row.fileName)")
        XCTAssertEqual(row.pixelWidth, 50)
        XCTAssertEqual(row.pixelHeight, 30)
        XCTAssertEqual(row.byteSize, Int64(tiff.count), "until it is converted, the size of what came")
        XCTAssertFalse(row.isCopied)
        let file = host.storage.attachments.fileURL(for: row)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "nothing is written by the paste")
        XCTAssertEqual(host.importer.pendingCopies, 1)

        release.signal()
        host.waitForCopies()

        row = try host.row(id)
        XCTAssertTrue(row.isCopied)
        let stored = try Data(contentsOf: file)
        XCTAssertEqual(Array(stored.prefix(4)), Self.pngSignature, "the stored file is a PNG")
        XCTAssertEqual(row.byteSize, Int64(stored.count), "the row holds the size of the file that is there")
        let image = try XCTUnwrap(NSBitmapImageRep(data: stored))
        XCTAssertEqual(image.pixelsWide, 50)
        XCTAssertEqual(image.pixelsHigh, 30)
    }

    /// Review Focus 3: Excel, Word and browsers put an image of the selection next to its text, and the text is what is
    /// pasted (spec §6.5, 2 before 3).
    func testTextAndImagePastesText() throws {
        let host = try AttachmentTestHost()
        defer { host.cleanUp() }
        let spy = SpyImporter()
        host.textView.attachmentImporter = spy
        let tiff = try AttachmentTestHost.imageData(width: 40, height: 40, type: .tiff)
        let png = try AttachmentTestHost.imageData(width: 40, height: 40, type: .png)
        let pasteboard = host.pasteboard(text: "Q3\t1,204\nQ4\t1,377", png: png, tiff: tiff)
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))

        XCTAssertEqual(host.text, "Q3\t1,204\nQ4\t1,377", "the text, as it is")
        XCTAssertTrue(spy.calls.isEmpty, "the image is not imported")
        XCTAssertTrue(host.tokenIDs.isEmpty)
    }

    // MARK: Where an attachment cannot go

    /// Global Constraints, "Excluded": inside a code block a block is literal, so the names of the files are inserted.
    func testPasteIntoCodeBlockPastesNames() throws {
        let text = "```\nx\n```"
        let host = try AttachmentTestHost(text: text, caret: 5)
        defer { host.cleanUp() }
        XCTAssertTrue(host.textView.styler.isInCodeBlock(5), "the caret is in the block")
        let spy = SpyImporter()
        host.textView.attachmentImporter = spy
        let first = try host.makeFile(named: "one.txt", contents: Data("1".utf8))
        let second = try host.makeFile(named: "two.png", contents: Data("2".utf8))
        let pasteboard = host.pasteboard(files: [first, second])
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))

        XCTAssertEqual(host.text, "```\nxone.txt\ntwo.png\n```", "the names, one on each line")
        XCTAssertTrue(spy.calls.isEmpty, "no attachment is made")
        XCTAssertEqual(host.textView.pendingPasteClassifications, 0)
    }

    /// An image has no name to insert into a block: nothing happens.
    func testImageIntoCodeBlockInsertsNothing() throws {
        let text = "```\nx\n```"
        let host = try AttachmentTestHost(text: text, caret: 5)
        defer { host.cleanUp() }
        let spy = SpyImporter()
        host.textView.attachmentImporter = spy
        let pasteboard = host.pasteboard(png: try AttachmentTestHost.imageData(width: 8, height: 8, type: .png))
        defer { pasteboard.releaseGlobally() }

        XCTAssertFalse(host.textView.readSelection(from: pasteboard))

        XCTAssertEqual(host.text, text)
        XCTAssertTrue(spy.calls.isEmpty)
    }

    /// A note in Recently Deleted takes nothing: not a file, not an image, not text.
    func testReadOnlyIgnoresFiles() throws {
        let host = try AttachmentTestHost(text: "kept", isReadOnly: true)
        defer { host.cleanUp() }
        let spy = SpyImporter()
        host.textView.attachmentImporter = spy
        let file = try host.makeFile(named: "a.txt", contents: Data("a".utf8))
        let pasteboard = host.pasteboard(files: [file], text: "a.txt")
        defer { pasteboard.releaseGlobally() }

        XCTAssertFalse(host.textView.readSelection(from: pasteboard))

        XCTAssertEqual(host.text, "kept")
        XCTAssertTrue(spy.calls.isEmpty)
        XCTAssertFalse(
            host.textView.acceptsDrop(of: pasteboard), "and a drop of the file is not accepted either")
    }

    /// Without an importer (a view that is not wired to the app's storage) a paste is the text paste it always was.
    func testPasteWithoutImporterPastesText() throws {
        let host = try AttachmentTestHost()
        defer { host.cleanUp() }
        host.textView.attachmentImporter = nil
        let file = try host.makeFile(named: "notes.txt", contents: Data("x".utf8))
        let pasteboard = host.pasteboard(files: [file], text: "notes.txt")
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))

        XCTAssertEqual(host.text, "notes.txt")
    }

    /// Plain text is still pasted as plain text: no pasteboard types that the attachments added get in its way.
    func testPlainTextPasteIsUnchanged() throws {
        let host = try AttachmentTestHost(text: "ab", caret: 1)
        defer { host.cleanUp() }
        let pasteboard = host.pasteboard(text: "XYZ")
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))

        XCTAssertEqual(host.text, "aXYZb")
        XCTAssertEqual(host.textView.selectedRange(), NSRange(location: 4, length: 0))
    }

    // MARK: Text next to a token (plan 6 task 6)

    private let tokenID = AttachmentID(rawValue: "6f9619ff-8b86-4d11-b42d-00c04fc964ff")
    private var token: String { AttachmentToken.line(for: tokenID) }
    private let tokenSize = AttachmentToken.lineLength

    /// Review Focus 2: a paste of text at either edge of a token line puts the line break into the paste's own edit, so the
    /// token is a line of its own after it. The caret is after the pasted text.
    func testPastingTextAtATokenEdgeKeepsTheToken() throws {
        let host = try AttachmentTestHost(text: "abc\n\(token)\ndef", caret: 4 + tokenSize)
        defer { host.cleanUp() }
        let view = host.textView
        let first = host.pasteboard(text: "XYZ")
        defer { first.releaseGlobally() }

        XCTAssertTrue(view.readSelection(from: first))

        XCTAssertEqual(host.text, "abc\n\(token)\nXYZ\ndef", "below the token")
        XCTAssertEqual(host.tokenIDs, [tokenID])
        XCTAssertEqual(view.selectedRange(), NSRange(location: 4 + tokenSize + 1 + 3, length: 0))

        view.setSelectedRange(NSRange(location: 4, length: 0))
        let second = host.pasteboard(text: "Q\nR")
        defer { second.releaseGlobally() }
        XCTAssertTrue(view.readSelection(from: second))

        XCTAssertEqual(host.text, "abc\nQ\nR\n\(token)\nXYZ\ndef", "above the token")
        XCTAssertEqual(host.tokenIDs, [tokenID])
        XCTAssertEqual(view.selectedRange(), NSRange(location: 4 + 3, length: 0), "in front of the line break")
    }

    /// A paste of text that is a token line itself, in the middle of a line, is a line of its own.
    func testPastingATokenLineMidLineGetsLinesOfItsOwn() throws {
        let host = try AttachmentTestHost(text: "abcdef", caret: 3)
        defer { host.cleanUp() }
        let pasteboard = host.pasteboard(text: token)
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))

        XCTAssertEqual(host.text, "abc\n\(token)\ndef")
        XCTAssertEqual(host.tokenIDs, [tokenID])
        XCTAssertEqual(host.textView.selectedRange(), NSRange(location: 4 + tokenSize + 1, length: 0))
    }

    /// Paste into code is not changed: a token there is text.
    func testPastingTextAtATokenEdgeInACodeBlockIsPlain() throws {
        let text = "```\n\(token)\n```"
        let host = try AttachmentTestHost(text: text, caret: 4 + tokenSize)
        defer { host.cleanUp() }
        let pasteboard = host.pasteboard(text: "XYZ")
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))

        XCTAssertEqual(host.text, "```\n\(token)XYZ\n```")
    }

    /// Code that is pasted next to a token is still wrapped in a fence, on its own lines, and the token stays whole.
    func testCodePastedAtATokenEdgeIsStillWrapped() throws {
        // The sample of `CodePasteTests`: Python that `CodeDetector` calls code.
        let python = "import os\n\ndef main():\n    path = os.getcwd()   \n    print(path)\n\tx = 1"
        let host = try AttachmentTestHost(text: "abc\n\(token)\ndef", caret: 4 + tokenSize)
        defer { host.cleanUp() }
        let pasteboard = host.pasteboard(text: python)
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))
        XCTAssertEqual(host.text, "abc\n\(token)\n" + python + "\ndef", "the plain paste comes first")
        host.spin(until: { host.textView.pendingPasteClassifications == 0 })

        XCTAssertEqual(host.textView.pendingPasteClassifications, 0)
        XCTAssertEqual(host.text, "abc\n\(token)\n```python\n" + python + "\n```\ndef")
        XCTAssertEqual(host.tokenIDs, [tokenID])
    }

    // MARK: Speed and undo

    /// Global Constraints, "Performance": inserting a 50 MB file returns to the run loop in under 100 ms, because the file
    /// is copied on the storage queue and what the main thread does depends on nothing but the file's attributes. One
    /// small file is attached first, so that what the first attachment makes ready (the icon services, say) is not counted.
    func testFiftyMegabyteFileReturnsQuickly() throws {
        let host = try AttachmentTestHost()
        defer { host.cleanUp() }
        let warmUp = try host.makeFile(named: "small.txt", contents: Data("warm".utf8))
        let warmUpBoard = host.pasteboard(files: [warmUp])
        defer { warmUpBoard.releaseGlobally() }
        XCTAssertTrue(host.textView.readSelection(from: warmUpBoard))
        host.waitForCopies()

        // A sparse file: 50 MB long, with no data written to it.
        let big = try host.makeFile(named: "big.bin", contents: Data())
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: 50 * 1_024 * 1_024)
        try handle.close()
        let pasteboard = host.pasteboard(files: [big])
        defer { pasteboard.releaseGlobally() }

        let start = Date()
        let didRead = host.textView.readSelection(from: pasteboard)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertTrue(didRead)
        XCTAssertLessThan(elapsed, 0.1, "readSelection took \(Int(elapsed * 1_000)) ms")
        let ids = host.tokenIDs
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(try host.row(try XCTUnwrap(ids.last)).byteSize, 50 * 1_024 * 1_024)
        host.waitForCopies()
        XCTAssertTrue(try host.row(try XCTUnwrap(ids.last)).isCopied)
    }

    /// Two files pasted at once are one undo step.
    func testOneUndoStepRemovesInsertedTokens() throws {
        let host = try AttachmentTestHost(text: "before")
        defer { host.cleanUp() }
        XCTAssertFalse(host.undo.canUndo, "showing a note is no undo step")
        let first = try host.makeFile(named: "one.txt", contents: Data("1".utf8))
        let second = try host.makeFile(named: "two.txt", contents: Data("2".utf8))
        host.textView.setSelectedRange(NSRange(location: 6, length: 0))
        let pasteboard = host.pasteboard(files: [first, second])
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(host.textView.readSelection(from: pasteboard))
        XCTAssertEqual(host.tokenIDs.count, 2)
        XCTAssertTrue(host.undo.canUndo)

        host.undo.undo()

        XCTAssertEqual(host.text, "before", "one undo takes both tokens and their line breaks away")
        XCTAssertFalse(host.undo.canUndo, "the paste was one undo step")
        XCTAssertTrue(host.undo.canRedo)
    }

    // MARK: Drops

    /// A file dropped on the note goes in where it was dropped, as a line of its own (spec §6.4).
    func testDropOfAFileInsertsItAtThePoint() throws {
        let host = try AttachmentTestHost(text: "abc\ndef")
        defer { host.cleanUp() }
        let file = try host.makeFile(named: "dropped.txt", contents: Data("d".utf8))
        let pasteboard = host.pasteboard(files: [file])
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(host.textView.acceptsDrop(of: pasteboard))

        // Just inside the left edge of the "d" of the second line.
        guard let layoutManager = host.textView.layoutManager, let container = host.textView.textContainer else {
            return XCTFail("no TextKit 1 stack")
        }
        let glyph = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: 4, length: 1), actualCharacterRange: nil)
        let box = layoutManager.boundingRect(forGlyphRange: glyph, in: container)
        let origin = host.textView.textContainerOrigin
        let point = NSPoint(x: origin.x + box.minX + 1, y: origin.y + box.midY)

        XCTAssertTrue(host.textView.performDrop(of: pasteboard, atViewPoint: point))

        let id = try XCTUnwrap(host.tokenIDs.first)
        XCTAssertEqual(host.text, "abc\n" + AttachmentToken.line(for: id) + "\ndef")
        XCTAssertEqual(try host.row(id).fileName, "dropped.txt")
    }

    /// A drag is judged by the types on its pasteboard and never by its data: `draggingUpdated(_:)` runs on every move of the
    /// mouse, and reading or converting a picture each time would stutter. A pasteboard that declares an image and has no
    /// bytes yet is a drag that makes an attachment, and the drop, which is where the data is read, finds nothing.
    func testDragIsJudgedByItsTypesAndNotByItsData() throws {
        let host = try AttachmentTestHost()
        defer { host.cleanUp() }
        let spy = SpyImporter()
        host.textView.attachmentImporter = spy
        let declared = NSPasteboard.withUniqueName()
        defer { declared.releaseGlobally() }
        _ = declared.declareTypes([.tiff], owner: nil)

        XCTAssertTrue(host.textView.wouldMakeAttachments(from: declared))
        XCTAssertTrue(host.textView.acceptsDrop(of: declared))
        XCTAssertNil(host.textView.attachmentSources(from: declared), "there are no bytes to make an attachment of")
        XCTAssertFalse(host.textView.performDrop(of: declared, atViewPoint: .zero))
        XCTAssertTrue(spy.calls.isEmpty)
        XCTAssertEqual(host.text, "")
    }

    /// The same answers for what a drag really holds: files, and an image with no text, are attachments, and an image next to
    /// text, or text, is not.
    func testDragOfFilesAndImagesIsAnAttachmentDragAndTextWins() throws {
        let host = try AttachmentTestHost()
        defer { host.cleanUp() }
        let file = try host.makeFile(named: "a.txt", contents: Data("a".utf8))
        let png = try AttachmentTestHost.imageData(width: 8, height: 8, type: .png)
        let tiff = try AttachmentTestHost.imageData(width: 8, height: 8, type: .tiff)
        let boards: [(String, NSPasteboard, Bool)] = [
            ("a file", host.pasteboard(files: [file]), true),
            ("a file and its name", host.pasteboard(files: [file], text: "a.txt"), true),
            ("a PNG", host.pasteboard(png: png), true),
            ("a TIFF", host.pasteboard(tiff: tiff), true),
            ("cells and their picture", host.pasteboard(text: "Q3\t1", png: png, tiff: tiff), false),
            ("text", host.pasteboard(text: "just text"), false),
            ("nothing", host.pasteboard(), false),
        ]
        defer {
            for (_, board, _) in boards { board.releaseGlobally() }
        }

        for (name, board, makesAttachments) in boards {
            XCTAssertEqual(host.textView.wouldMakeAttachments(from: board), makesAttachments, name)
            XCTAssertEqual(host.textView.acceptsDrop(of: board), makesAttachments, name)
            XCTAssertEqual(
                host.textView.attachmentSources(from: board) != nil, makesAttachments, "what the drop reads: \(name)")
        }
    }

    /// A drop of text is not ours: it is the text view's own.
    func testDropOfTextIsNotAnAttachmentDrop() throws {
        let host = try AttachmentTestHost()
        defer { host.cleanUp() }
        let pasteboard = host.pasteboard(text: "just text")
        defer { pasteboard.releaseGlobally() }

        XCTAssertNil(host.textView.attachmentSources(from: pasteboard))
        XCTAssertFalse(host.textView.acceptsDrop(of: pasteboard))
    }
}
