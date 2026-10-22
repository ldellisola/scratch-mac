import AppKit

/// Taking an attachment's file out of a note by dragging it (spec §6.4: "dragging out of the note gives the file itself",
/// plan 5 task 6). `NoteTextView` starts the drag when the mouse has moved `threshold` points with the button down on a
/// preview or a chip, and this is what the drag is made of: the item (the stored file's URL, with the preview or the chip
/// as the picture that follows the mouse) and the source that says what may be done with it.
enum AttachmentDrag {
    /// How far, in points, the mouse has to move from where it went down on an attachment before a drag starts. A click
    /// that moved a little is still a click.
    static let threshold: CGFloat = 3

    /// What a drag of the attachment's stored file puts on the drag pasteboard: the file's URL, as an `NSURL`, which is how
    /// Finder, Mail and every app that takes a file read it. It is Scratch's own copy that is offered, never the original,
    /// which may be gone (`AttachmentStore`).
    static func pasteboardWriter(for url: URL) -> any NSPasteboardWriting {
        url as NSURL
    }

    /// The item of a drag of the attachment drawn as `mark` in `frame` (in the coordinates of the view that begins the
    /// drag): the file's URL, and a picture of the preview or the chip, which is what is drawn in the note without the
    /// outline of a selected attachment. `preview` is the decoded image of an image, or nil while it is on its way.
    static func draggingItem(for url: URL, mark: AttachmentMark, preview: NSImage?, frame: NSRect) -> NSDraggingItem {
        let item = NSDraggingItem(pasteboardWriter: pasteboardWriter(for: url))
        item.setDraggingFrame(frame, contents: dragImage(of: mark, preview: preview, size: frame.size))
        return item
    }

    /// A picture of `mark` at `size`: the preview or the chip as `AttachmentDrawing` draws them in the note. It is drawn when
    /// the picture is first needed, which can be off the main thread, so what it draws from is not tied to the main actor.
    nonisolated static func dragImage(of mark: AttachmentMark, preview: NSImage?, size: NSSize) -> NSImage {
        let contents = DragContents(mark: mark, preview: preview)
        return NSImage(size: size, flipped: true) { rect in
            AttachmentDrawing.draw(contents.mark, in: rect, preview: contents.preview, isSelected: false)
            return true
        }
    }

    /// What `dragImage(of:preview:size:)` draws, and which it may draw on any thread: both are read and never changed.
    nonisolated private struct DragContents: @unchecked Sendable {
        let mark: AttachmentMark
        let preview: NSImage?
    }
}

/// The source of a drag of an attachment: what the destination may do with the file. Only a copy: Scratch's own copy of a
/// file is never moved out of its storage by a drop in Finder, which would take it from the note (spec §6.4, "Never lose an
/// attachment"), and a drop into Scratch itself makes another attachment of its own.
nonisolated final class AttachmentDragSource: NSObject, NSDraggingSource {
    nonisolated func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}
