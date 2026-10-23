import AppKit

/// The window's content: the sidebar on the left, the editor area on the right. The sidebar item
/// is a real sidebar item, so the system gives it the Liquid Glass material (spec §8.1).
final class MainSplitViewController: NSSplitViewController {
    /// The name that the split view's layout, the sidebar's width and whether it is hidden, is saved under.
    private static let autosaveName = "MainSplit"

    private let remembersLayout: Bool

    /// Called after each layout of the split view, with where the editor area starts (in the window's coordinates), the
    /// width of the window's content and whether the sidebar is shown: the toolbar's tab strip is as wide as the room that
    /// is left before the buttons, and that depends on all three (`ToolbarController.updateTabStripWidth`, plan 6 task 7).
    /// Setting it asks for a layout, so that the first call does not wait for the window to be resized.
    var onContentLayout: ((_ contentLeading: CGFloat, _ windowWidth: CGFloat, _ isSidebarShown: Bool) -> Void)? {
        didSet { view.needsLayout = true }
    }

    /// With `remembersLayout` the sidebar's width is saved and restored (spec §6.1). An isolated data directory (tests,
    /// screenshots, benchmarks) must always start from the same layout, so it does not remember.
    init(sidebar: NSViewController, editorArea: EditorAreaViewController, remembersLayout: Bool) {
        self.remembersLayout = remembersLayout
        super.init(nibName: nil, bundle: nil)

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 220
        sidebarItem.maximumThickness = 420
        sidebarItem.canCollapse = true
        addSplitViewItem(sidebarItem)
        addSplitViewItem(NSSplitViewItem(viewController: editorArea))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MainSplitViewController is created in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if remembersLayout { splitView.autosaveName = Self.autosaveName }
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
        reportContentLayout()
    }

    private func reportContentLayout() {
        guard let onContentLayout, splitViewItems.count == 2, let window = view.window else { return }
        let area = splitViewItems[1].viewController.view
        let leading = area.convert(area.bounds, to: nil).minX
        let width = window.contentView?.bounds.width ?? view.bounds.width
        onContentLayout(leading, width, !splitViewItems[0].isCollapsed)
    }
}
