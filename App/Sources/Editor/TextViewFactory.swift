import AppKit
import ScratchCore

/// Builds the editor's scroll view and text view on either TextKit (plan 1 decides which one stays, task 10).
enum TextViewFactory {
    /// A scroll view whose document view is a configured `NoteTextView`.
    static func makeEditor(mode: TextKitMode) -> (NSScrollView, NoteTextView) {
        let textView = makeTextView(mode: mode)

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

    private static func makeTextView(mode: TextKitMode) -> NoteTextView {
        switch mode {
        case .one:
            // The TextKit 1 stack, built by hand: storage, then layout manager, then container, then the view.
            let storage = NSTextStorage()
            let layoutManager = NSLayoutManager()
            layoutManager.allowsNonContiguousLayout = true
            storage.addLayoutManager(layoutManager)
            let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
            container.widthTracksTextView = true
            layoutManager.addTextContainer(container)
            return NoteTextView(frame: .zero, textContainer: container)
        case .two:
            // Never touch `layoutManager` on this view: that silently switches it back to TextKit 1.
            return NoteTextView(usingTextLayoutManager: true)
        }
    }
}
