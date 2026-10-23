import AppKit
import ImageIO
import UniformTypeIdentifiers

/// What Copy and Cut put on the pasteboard when the selection is exactly one attachment (spec §6.5: "the file or image itself
/// is also put on the pasteboard", plan 5 task 6): one item that holds the file's name as text, the URL of Scratch's copy
/// of the file, and for an image its PNG and its TIFF. A text selection that holds attachments is only text, with a name in
/// place of each token (`AttachmentCopying`), and goes through `NoteTextView.writeSelection(to:types:)`.
///
/// Both also write `noteTextType` when the selection holds a token (plan 6 task 6): the selection exactly as stored, which
/// only Scratch reads, so that a paste or a drop into a note keeps the attachment. Other applications see the text and the
/// file they always saw.
enum AttachmentPasteboard {
    /// The private type of the note's own text: the selection that was copied, token lines and all, exactly as it is stored.
    /// Only Scratch writes it and reads it (`NoteTextView.writeSelection(to:types:)`, `readSelection(from:type:)`), and only
    /// when the selection holds a token. Nothing else of the note's reaches the pasteboard.
    static let noteTextType = NSPasteboard.PasteboardType("io.github.ldellisola.Scratch.note-text")

    /// Makes the data provider that is asked for the PNG and the TIFF of an image copy when an application pastes them. The
    /// tests replace it, to see that data that was written when Scratch quit was not made by it.
    static var makeImageProvider: (URL) -> any NSPasteboardItemDataProvider = { AttachmentImageProvider(fileURL: $0) }

    /// The copy of one image that was written last, and where: what `materialize(on:)` needs to write it again.
    private struct ImageCopy {
        let pasteboardName: NSPasteboard.Name
        let changeCount: Int
        let name: String
        let fileURL: URL
        let noteText: String?
    }

    private static var lastImageCopy: ImageCopy?

    /// The item for the attachment whose stored file is at `fileURL`. The name, the URL and the note's text (`noteText`, when
    /// the selection has one) are written at once. The image is not: decoding a full-size picture and encoding it again takes
    /// hundreds of milliseconds, which Copy must never wait for, so PNG and TIFF are promised and made by `provider` when an
    /// application asks for them (a paste somewhere else). `provider` is nil for a file that is not an image. Whoever writes the
    /// item keeps the provider alive for as long as the pasteboard may ask it.
    static func item(name: String, fileURL: URL, isImage: Bool, noteText: String? = nil) -> (
        item: NSPasteboardItem, provider: (any NSPasteboardItemDataProvider)?
    ) {
        let item = NSPasteboardItem()
        _ = item.setString(name, forType: .string)
        _ = item.setString(fileURL.absoluteString, forType: .fileURL)
        if let noteText { _ = item.setString(noteText, forType: noteTextType) }
        guard isImage else { return (item, nil) }
        let provider = makeImageProvider(fileURL)
        _ = item.setDataProvider(provider, forTypes: [.png, .tiff])
        return (item, provider)
    }

    /// Writes `item(name:fileURL:isImage:noteText:)` as everything that `pasteboard` holds, and remembers a copy of an image
    /// for `materialize(on:)`. Returns whether the pasteboard took it, and the provider that the caller keeps alive.
    static func write(
        name: String, fileURL: URL, isImage: Bool, noteText: String?, to pasteboard: NSPasteboard
    ) -> (written: Bool, provider: (any NSPasteboardItemDataProvider)?) {
        let made = item(name: name, fileURL: fileURL, isImage: isImage, noteText: noteText)
        _ = pasteboard.clearContents()
        let written = pasteboard.writeObjects([made.item])
        lastImageCopy =
            written && isImage
            ? ImageCopy(
                pasteboardName: pasteboard.name, changeCount: pasteboard.changeCount, name: name, fileURL: fileURL,
                noteText: noteText)
            : nil
        return (written, made.provider)
    }

    /// When `pasteboard` still holds the item of the last copy of one image (its name and change count: nothing has been
    /// written to it since), writes it again with the PNG and the TIFF in place of the promise, and returns true. The promise
    /// is kept by the provider, which goes when Scratch quits, and an image that cannot be pasted after the app is gone would
    /// be lost (plan 6 task 6); the app calls this when it quits (`AppDelegate.applicationWillTerminate`), so that decoding
    /// the picture is not on the way of Copy. A pasteboard that something else has written to since, the copy of a file, text,
    /// and an image whose stored file is gone or cannot be read are left alone, and the answer is false.
    static func materialize(on pasteboard: NSPasteboard) -> Bool {
        guard let copy = lastImageCopy, copy.pasteboardName == pasteboard.name,
            copy.changeCount == pasteboard.changeCount,
            let png = AttachmentImageProvider.imageData(at: copy.fileURL, as: .png),
            let tiff = AttachmentImageProvider.imageData(at: copy.fileURL, as: .tiff)
        else { return false }
        let item = NSPasteboardItem()
        _ = item.setString(copy.name, forType: .string)
        _ = item.setString(copy.fileURL.absoluteString, forType: .fileURL)
        if let noteText = copy.noteText { _ = item.setString(noteText, forType: noteTextType) }
        _ = item.setData(png, forType: .png)
        _ = item.setData(tiff, forType: .tiff)
        // The pasteboard's change count moves on whatever happens next, so this copy is never written twice.
        lastImageCopy = nil
        _ = pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}

/// Makes the PNG or the TIFF of an image attachment's stored file when the pasteboard asks for it. Not tied to an actor: the
/// pasteboard calls it on the main thread, and it reads a file and runs ImageIO, which are thread-safe, and nothing else.
nonisolated final class AttachmentImageProvider: NSObject, NSPasteboardItemDataProvider {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init()
    }

    nonisolated func pasteboard(
        _ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType
    ) {
        let wanted: UTType = type == .tiff ? .tiff : .png
        guard let data = Self.imageData(at: fileURL, as: wanted) else { return }
        _ = item.setData(data, forType: type)
    }

    /// The image in the file at `url` as `type` (PNG or TIFF), or nil when the file is not an image that ImageIO can read.
    /// A PNG file is its own PNG, byte for byte. Anything else is decoded at its own size, rotated as the image says
    /// (the size that the row of the attachment holds) and encoded again.
    nonisolated static func imageData(at url: URL, as type: UTType) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            return nil
        }
        if type == .png, CGImageSourceGetType(source) as String? == UTType.png.identifier {
            return try? Data(contentsOf: url)
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, width > 0, height > 0
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output as CFMutableData, type.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
