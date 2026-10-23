import AppKit

/// The window's content area, right of the sidebar: the editor and nothing else (spec §6.1, mockup B). The tab strip is in
/// the toolbar now (`ToolbarController`, plan 6 task 7), so this only holds the editor, which fills it.
///
/// The window has a full-size content view, so the toolbar floats over the top of this view and the editor starts at its very
/// top. The toolbar is in the editor's safe area, and the editor's title field sits a fixed distance below that
/// (`EditorViewController.loadView`), with no band between the toolbar and the title.
final class EditorAreaViewController: NSViewController {
    private let editor: EditorViewController

    init(editor: EditorViewController) {
        self.editor = editor
        super.init(nibName: nil, bundle: nil)
        addChild(editor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EditorAreaViewController is created in code")
    }

    override func loadView() {
        let container = NSView()
        let editorView = editor.view
        editorView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(editorView)

        NSLayoutConstraint.activate([
            editorView.topAnchor.constraint(equalTo: container.topAnchor),
            editorView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            editorView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }
}
