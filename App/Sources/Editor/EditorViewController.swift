import AppKit
import ScratchCore

/// Shows one note in the plain-text editor and reports what the user types. It knows nothing about storage: the
/// session coordinator decides which note to show and when to save it.
final class EditorViewController: NSViewController, NSTextViewDelegate {
    /// Called with the whole text after each edit by the user. Not called when `show` loads a note.
    var onTextChange: ((String) -> Void)?

    /// Called when the cursor or the scroll position changed, by the user or because of typing. Not called when `show`
    /// loads a note. The new values are in `currentSelection` and `currentScrollY`. The session coordinator saves them
    /// with the session (spec §6.6: cursor and scroll position are persisted like text).
    var onViewStateChange: (() -> Void)?

    private let scrollView: NSScrollView
    private let textView: NoteTextView
    private var isLoadingNote = false
    /// The scroll offset last reported through `onViewStateChange` or set by `show`, so that a resize of the window,
    /// which also changes the clip view's bounds, does not count as scrolling.
    private var lastScrollY: Double = 0

    init(textKit: TextKitMode) {
        let editor = TextViewFactory.makeEditor(mode: textKit)
        scrollView = editor.0
        textView = editor.1
        super.init(nibName: nil, bundle: nil)
        textView.delegate = self
        textView.setAccessibilityIdentifier(AccessibilityID.editorTextView)
        textView.setAccessibilityLabel("Note")
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipViewBoundsDidChange(_:)), name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView)
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
        lastScrollY = currentScrollY
    }

    /// Makes the text view the first responder, so typing goes into the note.
    func focus() {
        view.window?.makeFirstResponder(textView)
    }

    /// The scroll view's clip view, whose bounds change when the editor scrolls (`FrameMonitor` watches it).
    var clipView: NSClipView { scrollView.contentView }

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

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isLoadingNote else { return }
        onViewStateChange?()
    }

    // MARK: Scrolling

    @objc private func clipViewBoundsDidChange(_ notification: Notification) {
        guard !isLoadingNote else { return }
        let scrollY = currentScrollY
        guard scrollY != lastScrollY else { return }
        lastScrollY = scrollY
        onViewStateChange?()
    }
}
