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

/// The tab strip: a Liquid Glass capsule in the toolbar row with one tab per open note and a "+" button after the last one
/// (spec §6.3, mockup B). It only shows what it is given and reports what the user did. `SessionCoordinator` owns the
/// tab rules.
///
/// The view (`TabStripView`) is the view of a toolbar item (`ToolbarController`, plan 6 task 7). It is 34 pt tall, like the
/// toolbar's own capsules, and has an `NSGlassEffectView` with a corner radius of 17 in it. The tabs are laid out by
/// `TabStripContentView`, by hand, so that the strip's width is known without asking Auto Layout how wide a glass view
/// wants to be: the strip is as wide as its tabs, and at most `maximumWidth`, the room that the toolbar leaves before its
/// buttons (`ToolbarController`, `TabStripLayout.maximumWidth(windowWidth:leading:)`).
final class TabStripViewController: NSViewController {
    /// Called with the index of the tab that the user clicked.
    var onSelect: ((Int) -> Void)?
    /// Called with the index of the tab whose close button the user pressed.
    var onClose: ((Int) -> Void)?
    /// Called when the user presses the "+" button.
    var onNewTab: (() -> Void)?

    /// The height of the strip in points: that of the capsules of the toolbar's buttons.
    static let height: CGFloat = 34
    /// The corner radius of the strip's glass in points: half its height, a capsule.
    static let cornerRadius: CGFloat = 17

    /// The most the strip may be wide, in points: the room that the toolbar leaves it before the buttons. The strip is as wide as
    /// its tabs want, and when that is more, the tabs share this (`TabStripLayout.widths`). It never goes below
    /// `TabStripLayout.minimumStripWidth`. Unlimited until `ToolbarController` has measured the window.
    var maximumWidth: CGFloat {
        get { stripView.maximumWidth }
        set { stripView.maximumWidth = newValue }
    }

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
        view = stripView
    }

    /// The items that the strip shows now, left to right. The tests read them.
    private(set) var shownItems: [TabStripItem] = []

    /// Shows one tab for each of `items`, left to right, with the one at `activeIndex` raised and selected for
    /// accessibility. An index outside `items` selects no tab.
    func show(_ items: [TabStripItem], activeIndex: Int) {
        loadViewIfNeeded()
        shownItems = items
        strip.show(items, activeIndex: activeIndex)
        stripView.preferredWidth = strip.preferredWidth
    }
}

/// The strip's view: a plain view whose width is the one its tabs want (`preferredWidth`) within what the toolbar leaves
/// (`maximumWidth`), and the glass (`NSGlassEffectView`) filling it. It is the view of a toolbar item, and the toolbar sizes a
/// view from its own constraints, so a required width and a required height say what it is (`width`), and
/// `intrinsicContentSize` says the same. This view sets the glass's frame itself, and the glass takes no part in the constraints
/// (see `init`).
///
/// A strip that was wider than the toolbar has room for would push the buttons out of the toolbar and into its overflow menu,
/// which is why the width is clamped here and `ToolbarController` tells the strip how much room there is.
final class TabStripView: NSView {
    /// The glass behind the tabs. Its `contentView` is the tabs.
    let glassView = NSGlassEffectView()

    /// The width that shows every tab at its natural width.
    var preferredWidth: CGFloat = 0 {
        didSet { if preferredWidth != oldValue { updateWidth() } }
    }

    /// The most the strip may be wide.
    var maximumWidth: CGFloat = .greatestFiniteMagnitude {
        didSet { if maximumWidth != oldValue { updateWidth() } }
    }

    /// The width the strip has: that of its tabs, at most `maximumWidth` and at least `TabStripLayout.minimumStripWidth`.
    var width: CGFloat {
        max(TabStripLayout.minimumStripWidth, min(preferredWidth, maximumWidth))
    }

    /// The required constraint that says how wide the strip is, which `updateWidth()` keeps at `width`.
    private var widthConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // A toolbar item's view is sized by its constraints: a required width and a required height.
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityIdentifier(AccessibilityID.tabStrip)
        let widthConstraint = widthAnchor.constraint(equalToConstant: width)
        let heightConstraint = heightAnchor.constraint(equalToConstant: TabStripViewController.height)
        NSLayoutConstraint.activate([widthConstraint, heightConstraint])
        self.widthConstraint = widthConstraint

        // The glass is outside the strip's constraints: it has no autoresizing mask, so its frame is a fixed one, which
        // `syncGlassFrame()` keeps equal to this view's bounds. Inside, the glass hosts its content in a SwiftUI hosting
        // view that is pinned to the glass and has an intrinsic width of 10 pt, hugged at priority 250. Tied to this
        // view by constraints, even by its autoresizing mask, the glass passes that on: the strip came out 10 pt wide on CI
        // when its width was only a compression resistance. The strip's width is the tabs' business.
        glassView.autoresizingMask = []
        glassView.frame = bounds
        addSubview(glassView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TabStripView is created in code")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: width, height: TabStripViewController.height)
    }

    /// Makes the width constraint say `width`. A constant that is the same already is left alone.
    private func updateWidth() {
        guard let widthConstraint, widthConstraint.constant != width else { return }
        widthConstraint.constant = width
        invalidateIntrinsicContentSize()
    }

    /// A click on the strip is for its tabs and buttons, and never moves the window, though the toolbar is the window's
    /// titlebar.
    override var mouseDownCanMoveWindow: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncGlassFrame()
    }

    override func layout() {
        super.layout()
        syncGlassFrame()
    }

    /// Makes the glass as large as this view. A frame that is the same already is left alone.
    private func syncGlassFrame() {
        if glassView.frame != bounds { glassView.frame = bounds }
    }
}

// MARK: - Layout

/// How wide each tab is when the strip has `available` points for them: the natural width of each, and when they do
/// not all fit, the widest ones cut back to a common width until they do. A tab never gets narrower than
/// `minimumWidth`, even if they then do not fit (the strip is clipped by its glass).
enum TabStripLayout {
    /// The narrowest a tab gets when the strip is crowded: enough for the close button and a few characters.
    static let minimumWidth: CGFloat = 48

    /// The narrowest the strip gets, whatever room the toolbar leaves: a tab, the "+" button and the space round them.
    static let minimumStripWidth: CGFloat = 96

    /// What the toolbar keeps free right of the strip, in points: the pin and the paperclip in one capsule, the "new note"
    /// button in another, the space between them and the margin at the window's edge are about 140 pt on macOS 26, and this
    /// leaves more than that to spare. Too little would have the toolbar move a button into its overflow menu.
    static let trailingReserve: CGFloat = 176

    /// Where the strip starts, in points from the left edge of the editor area, while the sidebar is shown: the toolbar puts
    /// the item after the tracking separator, which is at the sidebar's edge, with a little space. Rounded up.
    static let leadingMargin: CGFloat = 16

    /// Where the strip starts, from the left edge of the window, while the sidebar is hidden: the traffic lights, the
    /// sidebar button and the space round them. Rounded up.
    static let collapsedLeading: CGFloat = 150

    /// The most the strip may be wide in a window `windowWidth` wide when the strip starts `leading` points from its left
    /// edge: what is left when the buttons have `trailingReserve`, and never less than `minimumStripWidth`.
    static func maximumWidth(windowWidth: CGFloat, leading: CGFloat) -> CGFloat {
        max(minimumStripWidth, windowWidth - leading - trailingReserve)
    }

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
    private static let tabHeight: CGFloat = 28
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
            // VoiceOver says which tab the button closes (plan 6 task 8): "Close Deploy checklist". The title is cut where the
            // tab cuts it, so that the first line of a huge note never gets this far.
            closeButtons[index].setAccessibilityLabel(TabItemView.closeLabel(forTitle: item.title))
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
    /// Added to the measured width of a title, so that the label does not cut it off.
    private static let labelPadding: CGFloat = 8
    /// A title is cut to this many characters before it is laid out, so that the first line of a huge note, which can
    /// be megabytes long, never reaches the text system.
    private static let titleLimit = 120

    /// Called when the user clicks the tab.
    var onSelect: (() -> Void)?

    /// How wide the tab wants to be: its title and the space around it, within `minimumWidth` and `maximumWidth`.
    private(set) var idealWidth: CGFloat = TabItemView.minimumWidth

    /// The title, internal for the tests.
    let titleField = NSTextField(labelWithString: "")
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

    /// What VoiceOver reads for the close button of the tab titled `title`: "Close <title>".
    static func closeLabel(forTitle title: String) -> String {
        "Close \(title.prefix(titleLimit))"
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
        // The label needs more than its text measures: the first two screenshots had "Deploy check..." in a tab sized to
        // the text, by the width of the string and then by the label's own intrinsic width. `labelPadding` is the
        // slack that a text field keeps around its text, with a little to spare.
        let textWidth = titleField.intrinsicContentSize.width.rounded(.up)
        idealWidth = min(
            max(textWidth + Self.labelPadding + Self.leading + Self.trailing, Self.minimumWidth), Self.maximumWidth)

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
        // With Increase Contrast the raised tab also has an outline: the white pill and a shadow of 12% do not set it apart
        // from the glass enough for everyone (plan 6 task 8).
        let isHighContrast =
            effectiveAppearance.bestMatch(from: [
                .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua, .aqua, .darkAqua,
            ]).map { $0 == .accessibilityHighContrastAqua || $0 == .accessibilityHighContrastDarkAqua } ?? false
        layer.borderWidth = isActive && isHighContrast ? 1 : 0
        layer.borderColor = NSColor.labelColor.withAlphaComponent(0.55).cgColor
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

    /// The strip is in the toolbar, where a click on a view that does not say otherwise can drag the window.
    override var mouseDownCanMoveWindow: Bool { false }

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
