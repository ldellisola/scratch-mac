import AppKit
import ScratchCore
import UniformTypeIdentifiers

/// What the editor knows of the attachments that the notes it shows hold: the rows of `AttachmentStore`, read when a token
/// line is styled and kept, and which of the files are being copied or cannot be decoded (plan 5, task 4).
///
/// The note's text holds only a token, `[[attachment:<id>]]`. What the line draws (a preview, a chip, "Copying…" or
/// "Missing attachment") and how high it is come from here, through `MarkupStyler`. Reads happen on the main thread, one
/// query for all the tokens of a batch of paragraphs (`preload(_:)`), and an id is read once: the store never changes a
/// row but through `markCopying(_:)` and `markCopied(_:)`, which forget it.
///
/// The catalog is the place where the rest of the app tells the editor that an attachment changed. `onChange` is called,
/// on the main thread, with the id, and the styler styles the lines of that attachment again.
@MainActor
final class AttachmentCatalog {
    private let store: AttachmentStore
    private var known: [AttachmentID: Attachment] = [:]
    /// Ids that were read and have no row. A token that someone typed, or a row that was removed.
    private var unknown: Set<AttachmentID> = []
    /// Attachments whose copy is being made: their rows are there and their files are not yet.
    private var copying: Set<AttachmentID> = []
    /// Images that were found to be undecodable: they are drawn as missing, and not asked for again.
    private var undecodable: Set<AttachmentID> = []
    private var icons: [String: NSImage] = [:]

    /// Called with the id of an attachment whose state changed, which the styler answers by styling its lines again.
    var onChange: ((AttachmentID) -> Void)?

    init(store: AttachmentStore) {
        self.store = store
    }

    // MARK: What is known

    /// The attachment with this id, or nil when there is no row for it (an id that someone typed, or one that was
    /// removed). Read from the store the first time and kept.
    func attachment(_ id: AttachmentID) -> Attachment? {
        if let found = known[id] { return found }
        if unknown.contains(id) { return nil }
        load([id])
        return known[id]
    }

    /// Reads the attachments among `ids` that are not known yet, with one query. The styler asks for the tokens of a batch
    /// of paragraphs before it styles them, so that a note with many attachments is not many reads.
    func preload(_ ids: [AttachmentID]) {
        let wanted = ids.filter { known[$0] == nil && !unknown.contains($0) }
        guard !wanted.isEmpty else { return }
        load(wanted)
    }

    /// Where Scratch's copy of the file is (or will be: the file may not be there), or nil for an id with no row.
    func fileURL(_ id: AttachmentID) -> URL? {
        attachment(id).map { store.fileURL(for: $0) }
    }

    /// True while the copy of this attachment is being made (`markCopying(_:)` until `markCopied(_:)`).
    func isCopying(_ id: AttachmentID) -> Bool {
        copying.contains(id)
    }

    /// True when the image of this attachment was found not to be decodable (`markUndecodable(_:)`).
    func isUndecodable(_ id: AttachmentID) -> Bool {
        undecodable.contains(id)
    }

    // MARK: What changes

    /// The row of `id` has just been written (`AttachmentStore.register`) and its copy is being made: the line of its token
    /// says "Copying…". The row is read again, because the id may have been unknown until now.
    func markCopying(_ id: AttachmentID) {
        forget(id)
        copying.insert(id)
        undecodable.remove(id)
        onChange?(id)
    }

    /// The copy of `id` is over, whether it worked or not: the row is read again (`isCopied`), and the line is styled as
    /// what the file is, or as a missing attachment when the copy failed and there is no file.
    func markCopied(_ id: AttachmentID) {
        forget(id)
        copying.remove(id)
        undecodable.remove(id)
        onChange?(id)
    }

    /// The image of `id` could not be decoded, so its lines are drawn as a missing attachment from now on. The file and
    /// the row stay: nothing removes an attachment because it cannot be drawn.
    func markUndecodable(_ id: AttachmentID) {
        guard undecodable.insert(id).inserted else { return }
        onChange?(id)
    }

    // MARK: Icons

    /// The icon of the file of `attachment`: its Finder icon when `fileURL` is given (the copy is in place), and the icon of
    /// its type otherwise. Kept, because the call is not free.
    func icon(for attachment: Attachment, fileURL: URL?) -> NSImage {
        let key = attachment.id.rawValue + (fileURL == nil ? "|type" : "|file")
        if let icon = icons[key] { return icon }
        let icon: NSImage
        if let fileURL {
            icon = NSWorkspace.shared.icon(forFile: fileURL.path)
        } else {
            icon = NSWorkspace.shared.icon(for: UTType(attachment.typeIdentifier) ?? .data)
        }
        icons[key] = icon
        return icon
    }

    // MARK: Reading

    private func forget(_ id: AttachmentID) {
        known[id] = nil
        unknown.remove(id)
        icons["\(id.rawValue)|type"] = nil
        icons["\(id.rawValue)|file"] = nil
    }

    /// Reads `ids` from the store: those it has are known, the others are unknown. A read that fails is not remembered, so
    /// that the next question asks again.
    private func load(_ ids: [AttachmentID]) {
        guard let found = try? store.attachments(ids) else { return }
        for id in ids {
            if let attachment = found[id] {
                known[id] = attachment
            } else {
                unknown.insert(id)
            }
        }
    }
}
