import AppKit
import ScratchCore

/// Shows one note in the plain-text editor and reports what the user types. It knows nothing about storage: the
/// session coordinator (plan 1, task 8) decides which note to show and when to save it.
final class EditorViewController: NSViewController, NSTextViewDelegate {
    /// Called with the whole text after each edit by the user. Not called when `show` loads a note.
    var onTextChange: ((String) -> Void)?

    private let scrollView: NSScrollView
    private let textView: NoteTextView
    private var isLoadingNote = false

    init(textKit: TextKitMode) {
        let editor = TextViewFactory.makeEditor(mode: textKit)
        scrollView = editor.0
        textView = editor.1
        super.init(nibName: nil, bundle: nil)
        textView.delegate = self
        textView.setAccessibilityIdentifier(AccessibilityID.editorTextView)
        textView.setAccessibilityLabel("Note")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EditorViewController is created in code")
    }

    override func loadView() {
        view = scrollView
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // The text view is at least as tall as the visible area, so that a click below a short note still lands in it.
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
    }

    // MARK: Showing a note

    /// Replaces what the editor shows with `note`'s text. `selection` is a saved UTF-16 cursor offset and may be stale:
    /// it is clamped to a valid position. `scrollY` is a saved scroll offset (the clip view's origin y, 0 for the
    /// top). The undo history of the previous text is dropped.
    func show(_ note: Note, selection: Int, scrollY: Double) {
        isLoadingNote = true
        defer { isLoadingNote = false }

        textView.load(note.body)
        let offset = TextOffset.clamp(selection, in: note.body)
        textView.setSelectedRange(NSRange(location: offset, length: 0))
        textView.undoManager?.removeAllActions()

        // 0 means the top, which lies above y = 0 when the toolbar overlaps the scroll view (content insets).
        let topY = -scrollView.contentInsets.top
        let clipView = scrollView.contentView
        clipView.scroll(to: NSPoint(x: 0, y: scrollY == 0 ? topY : max(scrollY, topY)))
        scrollView.reflectScrolledClipView(clipView)
    }

    /// Makes the text view the first responder, so typing goes into the note.
    func focus() {
        view.window?.makeFirstResponder(textView)
    }

    /// The editor's whole text.
    var currentText: String { textView.string }

    /// The cursor position as a UTF-16 offset.
    var currentSelection: Int { textView.selectedRange().location }

    /// The scroll offset to save: the clip view's origin y.
    var currentScrollY: Double { Double(scrollView.contentView.bounds.origin.y) }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard !isLoadingNote else { return }
        onTextChange?(textView.string)
    }
}
