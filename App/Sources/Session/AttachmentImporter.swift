import AppKit
import ImageIO
import ScratchCore
import UniformTypeIdentifiers

/// Makes attachments of what the owner pasted, dropped or chose (plan 5, task 5, spec §6.4): a row for each (written at
/// once, `isCopied` false), then Scratch's own copy of the file on the storage queue, so the original can be moved or
/// deleted and the main thread never waits for a copy, whatever the size of the file.
///
/// The row needs what the note's line is drawn from before the copy is there: the name, the type, the size, and for an image
/// its pixel size. A file's size comes from its attributes and an image's pixel size from the header of the image
/// (`CGImageSource`, which reads the header and not the pixels), both quick and both on the calling thread. The catalog is told
/// when a copy starts and when it ends (`AttachmentCatalog.markCopying`, `markCopied`), so the line says "Copying…" until the
/// file is in place.
///
/// Created by `SessionCoordinator`, which owns the storage queue, and by the hosted tests, which pass a queue of their own.
@MainActor
final class AttachmentImporter: AttachmentImporting {
    private let store: AttachmentStore
    private let queue: DispatchQueue
    private weak var catalog: AttachmentCatalog?

    /// How many copies are queued or under way. Zero when every file that was imported is in place (or has failed).
    private(set) var pendingCopies = 0

    /// `queue` is the serial queue that the copies run on: the storage queue, so that `persistNow()` and quitting wait for
    /// the files as they do for everything else that is written.
    init(store: AttachmentStore, queue: DispatchQueue, catalog: AttachmentCatalog?) {
        self.store = store
        self.queue = queue
        self.catalog = catalog
    }

    // MARK: Importing

    func importAttachments(_ sources: [AttachmentSource], into noteID: NoteID) -> [AttachmentID] {
        var ids: [AttachmentID] = []
        for source in sources {
            guard let description = Self.describe(source) else { continue }
            let id = AttachmentID.make()
            do {
                _ = try store.register(
                    id: id, noteID: noteID, fileName: description.fileName,
                    typeIdentifier: description.typeIdentifier, byteSize: description.byteSize,
                    pixelSize: description.pixelSize, now: Date())
            } catch {
                report("cannot register an attachment of note \(noteID.rawValue): \(error)")
                continue
            }
            ids.append(id)
            catalog?.markCopying(id)
            startCopy(of: source, as: id)
        }
        return ids
    }

    /// Copies the file, or writes the image, on the queue, and tells the catalog when that is over. A TIFF is made into the PNG
    /// that its row says it is here, on the queue, with the rest of the work on the picture: the main thread never decodes or
    /// encodes one. A copy that fails is reported, and leaves a row with no file, which the line draws as a missing attachment.
    private func startCopy(of source: AttachmentSource, as id: AttachmentID) {
        pendingCopies += 1
        let store = self.store
        queue.async { [weak self, store] in
            do {
                switch source {
                case .file(let url):
                    try store.copyIn(id, from: url)
                case .image(let data, let typeIdentifier):
                    if let stored = AttachmentImporter.imageDataToStore(data, typeIdentifier: typeIdentifier) {
                        try store.writeIn(id, data: stored)
                    } else {
                        report("cannot convert the image of attachment \(id.rawValue) to PNG")
                    }
                }
            } catch {
                report("cannot copy attachment \(id.rawValue): \(error)")
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.pendingCopies -= 1
                    self.catalog?.markCopied(id)
                }
            }
        }
    }

    // MARK: What a source is

    /// What the row of an attachment holds, of a source.
    private struct Description {
        let fileName: String
        let typeIdentifier: String
        let byteSize: Int64
        let pixelSize: (width: Int, height: Int)?
    }

    /// The type identifiers that a note draws as a preview (`Attachment.isImage`).
    private static let previewTypeIdentifiers: Set<String> = [
        "public.png", "public.jpeg", "public.heic", "public.tiff", "com.compuserve.gif",
    ]

    private static func describe(_ source: AttachmentSource) -> Description? {
        switch source {
        case .file(let url): return describeFile(at: url)
        case .image(let data, let typeIdentifier): return describeImage(data, typeIdentifier: typeIdentifier)
        }
    }

    /// A file's name, type and size, and for an image that ImageIO can read its pixel size. Nil for a file that is not there.
    private static func describeFile(at url: URL) -> Description? {
        // A link is followed: the attachment is the file and not the link, as `AttachmentStore.copyIn` copies it.
        let original = url.resolvingSymlinksInPath()
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: original.path) else { return nil }
        let byteSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let type =
            (try? original.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: original.pathExtension) ?? .data
        if type.conforms(to: .image), let pixelSize = pixelSize(of: CGImageSourceCreateWithURL(original as CFURL, nil))
        {
            return Description(
                fileName: url.lastPathComponent, typeIdentifier: previewTypeIdentifier(of: type), byteSize: byteSize,
                pixelSize: pixelSize)
        }
        return Description(
            fileName: url.lastPathComponent, typeIdentifier: type.identifier, byteSize: byteSize, pixelSize: nil)
    }

    /// An image that has no file, such as a screenshot: named for the moment it came, "Image 2026-10-22 at 10.42.13.png".
    /// Only its header is read here, for the pixel size. A TIFF is stored as PNG (`imageDataToStore(_:typeIdentifier:)`, on the
    /// queue), so its row and its name say PNG from the start, and a TIFF whose header cannot be read, which the conversion
    /// could not decode either, is no attachment.
    private static func describeImage(_ data: Data, typeIdentifier: String) -> Description? {
        guard !data.isEmpty else { return nil }
        let size = pixelSize(of: CGImageSourceCreateWithData(data as CFData, nil))
        let storedAsPNG = isTIFF(typeIdentifier)
        if storedAsPNG, size == nil { return nil }
        let type = storedAsPNG ? UTType.png : (UTType(typeIdentifier) ?? .png)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Image \(formatter.string(from: Date())).\(type.preferredFilenameExtension ?? "png")"
        return Description(
            fileName: name, typeIdentifier: previewTypeIdentifier(of: type), byteSize: Int64(data.count),
            pixelSize: size)
    }

    // MARK: What an image is stored as

    private nonisolated static func isTIFF(_ typeIdentifier: String) -> Bool {
        UTType(typeIdentifier)?.conforms(to: .tiff) ?? false
    }

    /// The bytes that are written for an image that came from the pasteboard: the bytes as they are, except for a TIFF, which
    /// is stored as PNG (spec §6.4). Nil when a TIFF cannot be converted. Runs on the queue: decoding and encoding a full-size
    /// picture takes hundreds of milliseconds.
    nonisolated static func imageDataToStore(_ data: Data, typeIdentifier: String) -> Data? {
        isTIFF(typeIdentifier) ? pngData(from: data) : data
    }

    /// `imageData`, any image that ImageIO reads, as PNG (`CGImageSource` to `CGImageDestination`): its first image at its own
    /// size with its orientation applied, which is the size that the row was given from the header (`pixelSize(of:)`).
    private nonisolated static func pngData(from imageData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let size = pixelSize(of: source)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// The identifier that an image of `type` is stored with: its own when a note knows how to draw it (PNG, JPEG, HEIC, TIFF,
    /// GIF), and `public.image` for any other image that ImageIO reads.
    private static func previewTypeIdentifier(of type: UTType) -> String {
        previewTypeIdentifiers.contains(type.identifier) ? type.identifier : UTType.image.identifier
    }

    /// The size of the image in `source` as it is shown: the pixel size of its first image, with the sides swapped when its
    /// orientation turns it on its side. Reads the header only. Nil for a source that is not an image.
    private nonisolated static func pixelSize(of source: CGImageSource?) -> (width: Int, height: Int)? {
        guard let source, CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, width > 0, height > 0
        else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation) ? (height, width) : (width, height)
    }
}

/// Storage errors have nowhere to go in a window that never asks anything, so they go to the standard error stream.
private nonisolated func report(_ message: String) {
    FileHandle.standardError.write(Data("Scratch: \(message)\n".utf8))
}
