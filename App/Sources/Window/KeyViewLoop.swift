import AppKit

/// The order that Tab visits the window in (plan 6 task 8, docs/features/accessibility.md, "The keyboard"): the search field,
/// the note list, the title and the editor, and from the editor back to the search field.
///
/// Left to itself AppKit works the order out from where the views are, which is not the order that a person reads the window
/// in. A text field and a list are the only stops that the keyboard makes without Full Keyboard Access, and the title hands
/// the keyboard to the editor itself (`EditorViewController.control(_:textView:doCommandBy:)`), because Tab in the title is
/// "go to the text". Tab inside the editor is a tab character, and ⌃Tab is the next tab.
enum KeyViewLoop {
    /// Makes `views` a loop: each one's `nextKeyView` is the one after it, and the last one's is the first.
    static func connect(_ views: [NSView]) {
        guard views.count > 1 else { return }
        for (index, view) in views.enumerated() {
            view.nextKeyView = views[(index + 1) % views.count]
        }
    }
}
