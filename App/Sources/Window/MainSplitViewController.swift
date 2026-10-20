import AppKit

/// The window's content: the sidebar on the left, the editor area (tab strip and editor) on the right. The sidebar item
/// is a real sidebar item, so the system gives it the Liquid Glass material (spec §8.1).
final class MainSplitViewController: NSSplitViewController {
    /// The name that the split view's layout, the sidebar's width and whether it is hidden, is saved under.
    private static let autosaveName = "MainSplit"

    private let remembersLayout: Bool

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
    }
}
