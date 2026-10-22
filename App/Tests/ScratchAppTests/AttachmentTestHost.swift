import AppKit
import ScratchCore
import XCTest

@testable import Scratch

/// An importer that only records what it is asked for, for the tests that check that nothing is imported: a paste of text
/// and an image, and a paste into a note that cannot be edited.
@MainActor
final class SpyImporter: AttachmentImporting {
    private(set) var calls: [[AttachmentSource]] = []

    func importAttachments(_ sources: [AttachmentSource], into noteID: NoteID) -> [AttachmentID] {
        calls.append(sources)
        return sources.map { _ in AttachmentID.make() }
    }
}

/// What the hosted tests of pasting, dropping and editing around attachments (plan 5 task 5) share: an editor in a window
/// that is never shown, on a real storage in a directory of its own, with a catalog and the real importer, showing a note
/// of the given text. Nothing here touches real data or the real pasteboard.
///
/// Keep the host alive for as long as the editor is used (the text view holds its importer weakly) and call `cleanUp()`.
@MainActor
final class AttachmentTestHost {
    struct SetupError: Error {}

    let editor: EditorViewController
    let window: NSWindow
    let storage: ScratchStorage
    let catalog: AttachmentCatalog
    let importer: AttachmentImporter
    let undo: UndoManager
    let noteID: NoteID
    /// The folder of the test: the data directory is `data` in it and the files that the tests attach are in `files`.
    let directory: URL

    var textView: NoteTextView { editor.textView }
    var text: String { editor.currentText }

    /// Shows `text` as a note, with the caret at `caret` (the start by default). `isReadOnly` shows it as a note of
    /// Recently Deleted. `copyQueue` is the queue that the copies run on, which a test can hold to see what has not been done
    /// yet.
    init(
        text: String = "", caret: Int = 0, isReadOnly: Bool = false,
        copyQueue: DispatchQueue = DispatchQueue(label: "ScratchAttachmentTests.copies")
    ) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScratchAttachmentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("files", isDirectory: true), withIntermediateDirectories: true)
        let options = LaunchOptions(
            dataDirectory: directory.appendingPathComponent("data", isDirectory: true), isIsolated: true)
        let storage = try ScratchStorage.open(options)
        let catalog = AttachmentCatalog(store: storage.attachments)
        let importer = AttachmentImporter(store: storage.attachments, queue: copyQueue, catalog: catalog)

        let noteID = NoteID.make()
        let undo = UndoManager()
        let editor = EditorViewController()
        editor.attachmentCatalog = catalog
        editor.attachmentImporter = importer
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = editor
        window.setContentSize(NSSize(width: 800, height: 600))
        let note = Note(id: noteID, title: "", body: text, createdAt: Date(), modifiedAt: Date())
        let tab = TabState(noteID: noteID, selection: caret, scrollY: 0, scrollAnchor: nil)
        editor.show(note, tab: tab, undoManager: undo, isReadOnly: isReadOnly)
        editor.view.layoutSubtreeIfNeeded()

        self.noteID = noteID
        self.undo = undo
        self.directory = directory
        self.storage = storage
        self.catalog = catalog
        self.importer = importer
        self.editor = editor
        self.window = window
    }

    func cleanUp() {
        waitForCopies()
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Files and pasteboards

    /// A file called `name` in the host's own `files` folder.
    func makeFile(named name: String, contents: Data) throws -> URL {
        let url = directory.appendingPathComponent("files", isDirectory: true).appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    /// A PNG of `width` x `height` pixels in one colour, as a file in the `files` folder.
    func makePNGFile(named name: String, width: Int = 64, height: Int = 40) throws -> URL {
        try makeFile(named: name, contents: try Self.imageData(width: width, height: height, type: .png))
    }

    /// The bytes of an image of `width` x `height` pixels in one colour, as `type` (PNG or TIFF).
    static func imageData(width: Int, height: Int, type: NSBitmapImageRep.FileType) throws -> Data {
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
        guard let data = rep.representation(using: type, properties: [:]) else { throw SetupError() }
        return data
    }

    /// A pasteboard of its own with what the arguments say, in the way the sources put it there: a file URL on an item of its
    /// own for each file, as Finder does, and the text and the images on the first item (the file's, as Finder puts the
    /// file's name there) or on an item of their own. Release it with `releaseGlobally()` when the test is done.
    func pasteboard(
        files: [URL] = [], text: String? = nil, png: Data? = nil, tiff: Data? = nil
    ) -> NSPasteboard {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        var items: [NSPasteboardItem] = files.map { url in
            let item = NSPasteboardItem()
            _ = item.setString(url.absoluteString, forType: .fileURL)
            return item
        }
        if text != nil || png != nil || tiff != nil {
            let item = items.first ?? NSPasteboardItem()
            if let text { _ = item.setString(text, forType: .string) }
            if let png { _ = item.setData(png, forType: .png) }
            if let tiff { _ = item.setData(tiff, forType: .tiff) }
            if items.isEmpty { items.append(item) }
        }
        _ = pasteboard.writeObjects(items)
        return pasteboard
    }

    // MARK: Waiting and looking

    func spin(until condition: () -> Bool, seconds: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    }

    /// Runs the main run loop until every copy that the importer started is over.
    func waitForCopies() {
        spin(until: { self.importer.pendingCopies == 0 })
    }

    /// The ids of the tokens in the text, in order.
    var tokenIDs: [AttachmentID] { AttachmentToken.ids(in: text) }

    /// The stored row of `id`.
    func row(_ id: AttachmentID) throws -> Attachment {
        guard let row = try storage.attachments.attachment(id) else { throw SetupError() }
        return row
    }

    /// The range of the token of `id` in the text.
    func tokenRange(_ id: AttachmentID) -> NSRange {
        (text as NSString).range(of: AttachmentToken.line(for: id))
    }
}
