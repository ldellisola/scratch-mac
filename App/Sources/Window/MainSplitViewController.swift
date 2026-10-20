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
        addSplitViewItem(NSSplitViewItem(viewController: editor))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MainSplitViewController is created in code")
    }

    // The titlebar's scroll pocket is made by AppKit, when the window shows and when the layout changes (a resize, the
    // sidebar), so it is hidden after each of those (`TitlebarPocket`).

    override func viewDidAppear() {
        super.viewDidAppear()
        TitlebarPocket.hide(in: splitView)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        TitlebarPocket.hide(in: splitView)
    }
}
