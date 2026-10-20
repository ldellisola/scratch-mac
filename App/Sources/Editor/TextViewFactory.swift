import AppKit

/// Builds the editor's scroll view and text view on the TextKit 1 stack (ADR 0001: TextKit 2 missed the keystroke
/// budget in a 10,000-line note by a factor of three).
///
/// An `NSTextView` made in any other way (`NSTextView()`, `NSTextView(frame:)`, a nib) is a TextKit 2 view on macOS 26,
/// so every editor is made here.
enum TextViewFactory {
    /// A scroll view whose document view is a configured `NoteTextView`.
    static func makeEditor() -> (NSScrollView, NoteTextView) {
        let textView = makeTextView()

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        scrollView.documentView = textView

        textView.applyScratchConfiguration()
        return (scrollView, textView)
    }

    /// The TextKit 1 stack, built by hand: storage, then layout manager, then container, then the view.
    private static func makeTextView() -> NoteTextView {
        let storage = NSTextStorage()
        let layoutManager = MarkupLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let textView = NoteTextView(frame: .zero, textContainer: container)
        // The view does not own the storage, and the storage is what keeps the layout manager alive.
        textView.ownedTextStorage = storage
        // The layout manager hides markers through its own delegate methods. It is set after the text view is made,
        // which sets the delegate itself, and the delegate is weak: a manager that is its own is not kept alive twice.
        layoutManager.delegate = layoutManager
        // The text storage does not keep its delegate alive either: the view does.
        let styler = MarkupStyler(textView: textView)
        storage.delegate = styler
        textView.styler = styler
        return textView
    }
}
