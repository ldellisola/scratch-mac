import AppKit

/// The window's content area, right of the sidebar: the glass tab strip on top and the editor below it (spec §6.1,
/// mockup B). It only arranges the two. The strip and the editor know nothing of each other: the session coordinator
/// tells the strip which tabs there are and the editor which note to show.
///
/// The window has a full-size content view, so the toolbar floats over the top of this view. The strip starts below
/// it, at the top of the safe area, and the editor starts below the strip, so the editor's own safe area has no
/// toolbar in it any more (the title field sits a fixed distance below the editor's top).
final class EditorAreaViewController: NSViewController {
    /// The space between the toolbar and the strip, and between the strip and the editor, in points.
    private static let stripTopMargin: CGFloat = 8
    private static let stripBottomMargin: CGFloat = 4
    /// The space left and right of the strip. The strip is as wide as its tabs and at most as wide as the area less
    /// these margins.
    private static let stripSideMargin: CGFloat = 12

    private let tabStrip: TabStripViewController
    private let editor: EditorViewController

    init(tabStrip: TabStripViewController, editor: EditorViewController) {
        self.tabStrip = tabStrip
        self.editor = editor
        super.init(nibName: nil, bundle: nil)
        addChild(tabStrip)
        addChild(editor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EditorAreaViewController is created in code")
    }

    override func loadView() {
        let container = NSView()
        let stripView = tabStrip.view
        let editorView = editor.view
        stripView.translatesAutoresizingMaskIntoConstraints = false
        editorView.translatesAutoresizingMaskIntoConstraints = false
        // The editor first, so that the strip's glass and shadow are drawn over it.
        container.addSubview(editorView)
        container.addSubview(stripView)

        NSLayoutConstraint.activate([
            stripView.topAnchor.constraint(
                equalTo: container.safeAreaLayoutGuide.topAnchor, constant: Self.stripTopMargin),
            stripView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.stripSideMargin),
            stripView.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor, constant: -Self.stripSideMargin),
            editorView.topAnchor.constraint(equalTo: stripView.bottomAnchor, constant: Self.stripBottomMargin),
            editorView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            editorView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }
}
