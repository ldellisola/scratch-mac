import AppKit

/// What the tab strip shows for one tab: the note in it, as far as the strip cares (spec §6.3).
struct TabStripItem: Equatable {
    /// The note's display title (its title, or else its first line), or "Untitled" when it has neither.
    let title: String
    /// True when the note has a title of its own. A titled tab is bold, an untitled one shows its first line in the
    /// note font, like the sidebar row of the same note (spec §6.3: tab titles follow the rule of the sidebar rows).
    let hasTitle: Bool
    /// True for a note in Recently Deleted, which the strip dims (plan 2 task 9).
    let isDeleted: Bool
}

/// The tab strip: a Liquid Glass bar above the editor with one tab per open note and a "+" button after the last one
/// (spec §6.3, mockup B). It only shows what it is given and reports what the user did. `SessionCoordinator` owns the
/// tab rules.
///
/// The view (`TabStripView`) is 32 pt tall and has an `NSGlassEffectView` with a corner radius of 14 in it. The tabs are
/// laid out by `TabStripContentView`, by hand, so that the strip's width is known without asking Auto Layout how wide a
/// glass view wants to be: the strip is as wide as its tabs, and at most as wide as the editor area lets it be
/// (`EditorAreaViewController`).
final class TabStripViewController: NSViewController {
    /// Called with the index of the tab that the user clicked.
    var onSelect: ((Int) -> Void)?
    /// Called with the index of the tab whose close button the user pressed.
    var onClose: ((Int) -> Void)?
    /// Called when the user presses the "+" button.
    var onNewTab: (() -> Void)?

    /// The height of the strip in points.
    static let height: CGFloat = 32
    /// The corner radius of the strip's glass in points.
    static let cornerRadius: CGFloat = 14

    private let stripView = TabStripView()
    private let strip = TabStripContentView()

    init() {
        super.init(nibName: nil, bundle: nil)
        strip.onSelect = { [weak self] index in self?.onSelect?(index) }
        strip.onClose = { [weak self] index in self?.onClose?(index) }
        strip.onNewTab = { [weak self] in self?.onNewTab?() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TabStripViewController is created in code")
    }

    override func loadView() {
        stripView.glassView.cornerRadius = Self.cornerRadius
        stripView.glassView.contentView = strip
        stripView.translatesAutoresizingMaskIntoConstraints = false
        stripView.heightAnchor.constraint(equalToConstant: Self.height).isActive = true
        view = stripView
    }

    /// Shows one tab for each of `items`, left to right, with the one at `activeIndex` raised and selected for
    /// accessibility. An index outside `items` selects no tab.
    func show(_ items: [TabStripItem], activeIndex: Int) {
        loadViewIfNeeded()
        strip.show(items, activeIndex: activeIndex)
        stripView.preferredWidth = strip.preferredWidth
    }
}

/// The strip's view: a plain view that has the width its tabs want (`preferredWidth`) as its intrinsic width, and the
/// glass (`NSGlassEffectView`) pinned to all its edges. The glass gets its size from the pins, and not from its own
/// content or its own intrinsic size (see `init`).
///
/// A view that is as wide as its tabs may not push the window wider than the user made it, and may not stop the window
/// from becoming narrower: a split view item takes its minimum width from the constraints in its view. The strip
/// therefore resists compression with a priority below the one that Auto Layout uses to find a view's fitting size
/// (`NSLayoutConstraint.Priority.fittingSizeCompression`, 50), and the editor area limits the strip to its own width
/// with a required constraint (`EditorAreaViewController`). Many tabs then share a narrower strip
/// (`TabStripLayout.widths`).
final class TabStripView: NSView {
    /// The glass behind the tabs. Its `contentView` is the tabs.
    let glassView = NSGlassEffectView()

    /// The width that shows every tab at its natural width.
    var preferredWidth: CGFloat = 0 {
        didSet {
            guard preferredWidth != oldValue else { return }
            invalidateIntrinsicContentSize()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setContentHuggingPriority(NSLayoutConstraint.Priority(750), for: .horizontal)
        setContentCompressionResistancePriority(NSLayoutConstraint.Priority(40), for: .horizontal)

        // The glass has an intrinsic width of its own: a strip that left it alone came out 10 pt wide on CI, whatever
        // width the tabs wanted. It hugs that width at the default priority (250), which is stronger than this view's
        // resistance to compression (40), and the glass is pinned to this view. The strip's width is the tabs'
        // business, so the glass neither hugs nor resists.
        for axis in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            glassView.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: axis)
            glassView.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: axis)
        }
        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)
        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TabStripView is created in code")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredWidth, height: TabStripViewController.height)
    }
}

// MARK: - Layout

/// How wide each tab is when the strip has `available` points for them: the natural width of each, and when they do
/// not all fit, the widest ones cut back to a common width until they do. A tab never gets narrower than
/// `minimumWidth`, even if they then do not fit (the strip is clipped by its glass).
enum TabStripLayout {
    /// The narrowest a tab gets when the strip is crowded: enough for the close button and a few characters.
    static let minimumWidth: CGFloat = 48

    static func widths(ideal: [CGFloat], available: CGFloat) -> [CGFloat] {
        guard let widest = ideal.max(), ideal.reduce(0, +) > available else { return ideal }
        // Find the common width `cap` for which the tabs that are wider than it, cut to it, fill what is available.
        var low: CGFloat = 0
        var high = widest
        for _ in 0..<32 {
            let middle = (low + high) / 2
            let total = ideal.reduce(0) { $0 + min($1, middle) }
            if total > available { high = middle } else { low = middle }
        }
        return ideal.map { max(minimumWidth, min($0, low)) }
    }
}

/// The glass strip's content: the tab views, a close button over the right end of each, and the "+" button. It lays
/// them out in `layout()` and holds no constraints.
///
/// The close buttons are siblings of the tabs and not their subviews, so that each tab is a single accessibility
/// element, a button that UI tests can find and click.
final class TabStripContentView: NSView {
    /// The space around the tabs inside the glass.
    private static let inset: CGFloat = 3
    private static let spacing: CGFloat = 2
    private static let tabHeight: CGFloat = 26
    private static let newTabWidth: CGFloat = 28
    private static let closeSize: CGFloat = 16

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNewTab: (() -> Void)?

    private var tabViews: [TabItemView] = []
    private var closeButtons: [NSButton] = []
    private let newTabButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        newTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        newTabButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        newTabButton.imagePosition = .imageOnly
        newTabButton.isBordered = false
        newTabButton.contentTintColor = .secondaryLabelColor
        newTabButton.refusesFirstResponder = true
        newTabButton.toolTip = "New Tab"
        newTabButton.target = self
        newTabButton.action = #selector(newTabClicked(_:))
        newTabButton.setAccessibilityIdentifier(AccessibilityID.tabNew)
        newTabButton.setAccessibilityLabel("New Tab")
        addSubview(newTabButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TabStripContentView is created in code")
    }

    /// The width that shows every tab at its natural width, the "+" button and the space around them.
    var preferredWidth: CGFloat {
        let tabs = tabViews.reduce(0) { $0 + $1.idealWidth + Self.spacing }
        return Self.inset * 2 + tabs + Self.newTabWidth
    }

    /// Makes the strip show `items`. Views are reused, so a title that changes does not rebuild the tab: the
    /// accessibility elements UI tests hold stay the same.
    func show(_ items: [TabStripItem], activeIndex: Int) {
        while tabViews.count < items.count { addTab() }
        while tabViews.count > items.count { removeLastTab() }
        for (index, item) in items.enumerated() {
            tabViews[index].configure(item, isActive: index == activeIndex)
            tabViews[index].onSelect = { [weak self] in self?.onSelect?(index) }
            closeButtons[index].tag = index
            closeButtons[index].contentTintColor = item.isDeleted ? .tertiaryLabelColor : .secondaryLabelColor
        }
        needsLayout = true
    }

    private func addTab() {
        let tab = TabItemView(frame: .zero)
        let close = NSButton()
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")
        close.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        close.imagePosition = .imageOnly
        close.isBordered = false
        close.refusesFirstResponder = true
        close.toolTip = "Close Tab"
        close.target = self
        close.action = #selector(closeClicked(_:))
        close.setAccessibilityIdentifier(AccessibilityID.tabClose)
        close.setAccessibilityLabel("Close Tab")
        addSubview(tab)
        addSubview(close)
        tabViews.append(tab)
        closeButtons.append(close)
    }

    private func removeLastTab() {
        tabViews.removeLast().removeFromSuperview()
        closeButtons.removeLast().removeFromSuperview()
    }

    @objc private func closeClicked(_ sender: NSButton) {
        onClose?(sender.tag)
    }

    @objc private func newTabClicked(_ sender: Any?) {
        onNewTab?()
    }

    override func layout() {
        super.layout()
        let gaps = CGFloat(tabViews.count) * Self.spacing
        let available = bounds.width - Self.inset * 2 - Self.newTabWidth - gaps
        let widths = TabStripLayout.widths(ideal: tabViews.map(\.idealWidth), available: max(available, 0))
        let y = ((bounds.height - Self.tabHeight) / 2).rounded()
        var x = Self.inset
        for (index, tab) in tabViews.enumerated() {
            tab.frame = NSRect(x: x, y: y, width: widths[index], height: Self.tabHeight)
            closeButtons[index].frame = NSRect(
                x: tab.frame.maxX - TabItemView.closeTrailing - Self.closeSize,
                y: y + ((Self.tabHeight - Self.closeSize) / 2).rounded(), width: Self.closeSize, height: Self.closeSize)
            x += widths[index] + Self.spacing
        }
        newTabButton.frame = NSRect(x: x, y: y, width: Self.newTabWidth, height: Self.tabHeight)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }
}

// MARK: - One tab

/// One tab: a rounded label, raised when it is the active tab. It is one accessibility element, a button with the
/// identifier `AccessibilityID.tabItem` whose label is the title and which is selected for the active tab. A click
/// anywhere on it selects it, except on the close button over its right end (`TabStripContentView`).
final class TabItemView: NSView {
    /// A tab is at least this wide and at most `maximumWidth`, whatever its title (spec's tab strip: 120 to 200 pt).
    static let minimumWidth: CGFloat = 120
    static let maximumWidth: CGFloat = 200
    /// The space left of the title.
    private static let leading: CGFloat = 12
    /// The space between the right edge and the close button, which `TabStripContentView` places.
    static let closeTrailing: CGFloat = 8
    /// The room that the close button and the space around it take at the right end.
    private static let trailing: CGFloat = 30
    /// A title is cut to this many characters before it is laid out, so that the first line of a huge note, which can
    /// be megabytes long, never reaches the text system.
    private static let titleLimit = 120

    /// Called when the user clicks the tab.
    var onSelect: (() -> Void)?

    /// How wide the tab wants to be: its title and the space around it, within `minimumWidth` and `maximumWidth`.
    private(set) var idealWidth: CGFloat = TabItemView.minimumWidth

    private let titleField = NSTextField(labelWithString: "")
    private var item: TabStripItem?
    private var isActive = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = TabStripViewController.cornerRadius - 3
        layer?.cornerCurve = .continuous

        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.usesSingleLineMode = true
        // The tab is the one element: its label already says the title.
        titleField.setAccessibilityElement(false)
        addSubview(titleField)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier(AccessibilityID.tabItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TabItemView is created in code")
    }

    /// Shows `item`, raised when `isActive`. Does nothing when it already shows exactly that.
    func configure(_ item: TabStripItem, isActive: Bool) {
        guard item != self.item || isActive != self.isActive else { return }
        self.item = item
        self.isActive = isActive

        let title = String(item.title.prefix(Self.titleLimit))
        let font = item.hasTitle ? NSFont.boldSystemFont(ofSize: 12) : NoteTextView.noteFont
        titleField.font = font
        titleField.stringValue = title
        titleField.textColor = item.isDeleted ? .tertiaryLabelColor : (isActive ? .labelColor : .secondaryLabelColor)
        let textWidth = NSAttributedString(string: title, attributes: [.font: font]).size().width.rounded(.up)
        idealWidth = min(max(textWidth + Self.leading + Self.trailing, Self.minimumWidth), Self.maximumWidth)

        toolTip = title
        setAccessibilityLabel(title)
        setAccessibilityTitle(title)
        setAccessibilitySelected(isActive)
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let height = titleField.intrinsicContentSize.height
        titleField.frame = NSRect(
            x: Self.leading, y: ((bounds.height - height) / 2).rounded(),
            width: max(bounds.width - Self.leading - Self.trailing, 0),
            height: height)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    // MARK: Look

    override var wantsUpdateLayer: Bool { true }

    /// The raised look of the active tab: a white pill in the light appearance, a lighter one in the dark appearance,
    /// with a soft shadow, as in the mockup. Other tabs have no background, so the glass shows.
    override func updateLayer() {
        guard let layer else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fill = isDark ? NSColor(white: 1, alpha: 0.16) : NSColor.white
        layer.backgroundColor = isActive ? fill.cgColor : NSColor.clear.cgColor
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = isActive ? (isDark ? 0.3 : 0.12) : 0
        layer.shadowRadius = 1.5
        layer.shadowOffset = CGSize(width: 0, height: -1)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: Mouse and accessibility

    /// A click on the tab, but not on the label inside it, so that the tab gets `mouseDown` itself.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    /// A tab switches on mouse down, like the tabs of a browser, and a click in an inactive window works at once.
    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func accessibilityPerformPress() -> Bool {
        onSelect?()
        return true
    }
}
