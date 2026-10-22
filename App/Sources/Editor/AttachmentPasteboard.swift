import AppKit
import ImageIO
import UniformTypeIdentifiers

/// What Copy and Cut put on the pasteboard when the selection is exactly one attachment (spec §6.5: "the file or image itself
/// is also put on the pasteboard", plan 5 task 6): one item that holds the file's name as text, the URL of Scratch's copy
/// of the file, and for an image its PNG and its TIFF. A text selection that holds attachments is only text, with a name in
/// place of each token (`AttachmentCopying`), and goes through `NoteTextView.writeSelection(to:types:)`.
enum AttachmentPasteboard {
    /// The item for the attachment whose stored file is at `fileURL`. The name and the URL are written at once. The image is
    /// not: decoding a full-size picture and encoding it again takes hundreds of milliseconds, which Copy must never wait
    /// for, so PNG and TIFF are promised and made by `provider` when an application asks for them (a paste somewhere
    /// else). `provider` is nil for a file that is not an image. Whoever writes the item keeps the provider alive for as long
    /// as the pasteboard may ask it.
    static func item(name: String, fileURL: URL, isImage: Bool) -> (
        item: NSPasteboardItem, provider: AttachmentImageProvider?
    ) {
        let item = NSPasteboardItem()
        _ = item.setString(name, forType: .string)
        _ = item.setString(fileURL.absoluteString, forType: .fileURL)
        guard isImage else { return (item, nil) }
        let provider = AttachmentImageProvider(fileURL: fileURL)
        _ = item.setDataProvider(provider, forTypes: [.png, .tiff])
        return (item, provider)
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
