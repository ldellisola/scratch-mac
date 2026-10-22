import Foundation

/// A file that a note holds: what is known of it, and whether Scratch's own copy of it is in place (spec §6.4).
///
/// The note holds the file as a line `[[attachment:<id>]]` (``AttachmentToken``). The row is in the `attachments` table
/// and the copy is `<data directory>/attachments/<id>/<file name>` (``AttachmentStore/fileURL(for:)``).
public struct Attachment: Equatable, Sendable {
    public let id: AttachmentID
    /// The note the file was added to. For debugging and the index: what keeps a file is a note that names its id.
    public let noteID: NoteID
    /// The file's name as the owner knows it, which is what the note shows. The copy on disk is named by
    /// ``AttachmentStore/sanitisedFileName(_:)`` of this.
    public let fileName: String
    /// A uniform type identifier, such as `public.png` or `public.plain-text`.
    public let typeIdentifier: String
    public let byteSize: Int64
    /// The size in pixels of an image, nil for any other file.
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let createdAt: Date
    /// Whether the copy is in place. False from the moment the row is registered until ``AttachmentStore/copyIn(_:from:)``
    /// or ``AttachmentStore/writeIn(_:data:)`` has finished.
    public let isCopied: Bool

    public init(
        id: AttachmentID, noteID: NoteID, fileName: String, typeIdentifier: String, byteSize: Int64,
        pixelWidth: Int?, pixelHeight: Int?, createdAt: Date, isCopied: Bool
    ) {
        self.id = id
        self.noteID = noteID
        self.fileName = fileName
        self.typeIdentifier = typeIdentifier
        self.byteSize = byteSize
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.createdAt = createdAt
        self.isCopied = isCopied
    }

    /// The type identifiers that are shown as a picture. Anything else is a chip with the file's icon.
    private static let imageTypeIdentifiers: Set<String> = [
        "public.png", "public.jpeg", "public.heic", "public.tiff", "com.compuserve.gif", "public.image",
    ]

    /// Whether the file is an image that the note draws as a preview: PNG, JPEG, HEIC, TIFF, GIF or `public.image`.
    public var isImage: Bool {
        Self.imageTypeIdentifiers.contains(typeIdentifier)
    }
}
