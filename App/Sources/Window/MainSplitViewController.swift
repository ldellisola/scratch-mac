import AppKit

/// The window's content: the sidebar on the left, the editor on the right. The sidebar item is a real sidebar item,
/// so the system gives it the Liquid Glass material (spec §8.1).
final class MainSplitViewController: NSSplitViewController {
    init(sidebar: NSViewController, editor: EditorViewController) {
        super.init(nibName: nil, bundle: nil)

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 220
        sidebarItem.maximumThickness = 420
        sidebarItem.canCollapse = true
        addSplitViewItem(sidebarItem)

        // The editor starts below the toolbar and nothing scrolls under the titlebar, so AppKit's automatic titlebar
        // separator would draw a hard line across the editor. The toolbar floats over the note, with no other chrome
        // (spec 6.1).
        let editorItem = NSSplitViewItem(viewController: editor)
        editorItem.titlebarSeparatorStyle = .none
        addSplitViewItem(editorItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MainSplitViewController is created in code")
    }
}
