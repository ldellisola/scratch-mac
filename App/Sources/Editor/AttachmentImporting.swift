import Foundation
import ScratchCore

/// Something that is about to become an attachment (plan 5, task 5): a file that the owner pasted, dropped or chose, or an
/// image that came from the pasteboard with no file of its own, such as a screenshot.
nonisolated enum AttachmentSource: Sendable, Equatable {
    /// A file, or a folder, to copy into Scratch's storage. Its name is the name of the attachment.
    case file(URL)
    /// The bytes of an image, with the uniform type identifier they are in (`public.png`, as the editor converts every
    /// pasted image to PNG).
    case image(Data, typeIdentifier: String)
}

/// What the editor asks of the app when something is pasted, dropped or attached: to make attachments of it. The editor
/// does not know the storage; the session coordinator does (`SessionCoordinator`, through `AttachmentImporter`).
@MainActor
protocol AttachmentImporting: AnyObject {
    /// Registers each source (its row is written, with `isCopied` false), starts the copies on the storage queue and
    /// returns the ids in the order of the sources. Never copies a file on the calling thread. A source that cannot be
    /// registered (a file that is not there) has no id in the result, so the result can be shorter than `sources`.
    func importAttachments(_ sources: [AttachmentSource], into noteID: NoteID) -> [AttachmentID]
}
