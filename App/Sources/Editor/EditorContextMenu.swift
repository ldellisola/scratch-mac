import AppKit

/// The items that the editor's context menu adds for what is under the pointer (plan 6 task 8): the keyboard-free ways to
/// what a click does, each only where it applies.
enum EditorContextMenu {
    /// The items for the place at `point`, in the coordinates of `textView`: none when nothing there has one.
    static func items(for textView: NoteTextView, atViewPoint point: NSPoint) -> [NSMenuItem] {
        []
    }
}
