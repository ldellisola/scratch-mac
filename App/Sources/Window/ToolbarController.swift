import AppKit

/// The window's toolbar (spec §6.1, §6.3, §6.4, mockup B): the sidebar button over the sidebar and, over the editor, the
/// tab strip at the left and the buttons at the right in two glass groups, the pin and the paperclip and then "new note".
/// The system draws every plain toolbar item on Liquid Glass (spec §8.1), and the tab strip is a capsule of its own.
///
/// The toolbar keeps its delegate weakly, so whoever creates this controller must keep it alive for as long as the
/// window lives (`AppDelegate` does).
final class ToolbarController: NSObject, NSToolbarDelegate {
    /// Called when the user presses the "new note" button, which opens a new empty note in a new tab.
    var onNewNote: (() -> Void)?

    /// Called when the user presses the pin button, which pins the note of the active tab or unpins it.
    var onTogglePin: (() -> Void)?

    /// Called when the user presses the paperclip, which asks for files to attach to the note (spec §6.4).
    var onAttach: (() -> Void)?

    private static let tabStripItem = NSToolbarItem.Identifier(AccessibilityID.tabStrip)
    private static let newNoteItem = NSToolbarItem.Identifier(AccessibilityID.newNoteButton)
    private static let pinItem = NSToolbarItem.Identifier(AccessibilityID.pinButton)
    private static let attachItem = NSToolbarItem.Identifier(AccessibilityID.attachButton)

    /// The items from left to right. The tracking separator makes the items after it line up with the editor, the strip
    /// follows it, and the flexible space pushes the buttons to the right edge. The fixed space between the paperclip and the
    /// "new note" button ends the glass group of the first two, so that they are two capsules and not one (mockup B).
    static let defaultItemIdentifiers: [NSToolbarItem.Identifier] = [
        .toggleSidebar, .sidebarTrackingSeparator, tabStripItem, .flexibleSpace, pinItem, attachItem, .space,
        newNoteItem,
    ]

    /// The strip that is the view of the tab strip's item. The toolbar holds the item, and the item holds the view, but
    /// the view's controller is held here.
    private let tabStrip: TabStripViewController
    /// The tab strip's item, once the toolbar has asked for it: the toolbar can ask more than once, and a view has one
    /// superview, so there is one item.
    private var tabStripToolbarItem: NSToolbarItem?

    init(tabStrip: TabStripViewController) {
        self.tabStrip = tabStrip
        super.init()
    }

    /// The paperclip, once the toolbar has asked for it, and whether it works: it does not for a note in Recently Deleted.
    private var attachButton: NSToolbarItem?
    private var isAttachEnabled = true
    /// The pin button, once the toolbar has asked for it.
    private var pinButton: NSToolbarItem?
    /// What the pin button shows: whether the note of the active tab is pinned, and whether the button works.
    private var isPinned = false
    private var isPinEnabled = true

    /// A new toolbar that this controller serves. Assign it to the window's `toolbar`.
    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("MainToolbar"))
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.defaultItemIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.defaultItemIdentifiers
    }

    /// Only the tab strip, paperclip, pin and "new note" items are made here. AppKit makes the standard ones (sidebar
    /// button, separators, spaces).
    ///
    /// They are plain items with an image, not custom views, so that the system draws them on a Liquid Glass capsule
    /// like every other toolbar item: a custom `NSButton` view got no capsule, bordered item or not (screenshots, plan
    /// 1 task 9). A view-less item has no view to carry an accessibility identifier, so its item identifier is
    /// `AccessibilityID.newNoteButton` (or `pinButton`), and UI tests find the button by that, its label or its title.
    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if itemIdentifier == Self.tabStripItem { return makeTabStripItem(forPalette: !flag) }
        if itemIdentifier == Self.pinItem { return makePinItem() }
        if itemIdentifier == Self.attachItem { return makeAttachItem() }
        guard itemIdentifier == Self.newNoteItem else { return nil }

        let description = "New Note"
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: description)
        item.label = description
        item.paletteLabel = description
        item.toolTip = description
        item.isBordered = true
        // The buttons are never moved into the overflow menu: the strip is made to fit before they would be.
        item.visibilityPriority = .user
        item.target = self
        item.action = #selector(newNote(_:))
        return item
    }

    // MARK: The tab strip

    /// The tab strip's item: the strip is its view, with no border and no glass from the toolbar, because the strip is a
    /// capsule of its own (a second one round it would be glass on glass). It is the item that is kept when the toolbar is
    /// short of room, and it is never wider than the room that is left before the buttons (`updateTabStripWidth`).
    private func makeTabStripItem(forPalette: Bool) -> NSToolbarItem {
        if let tabStripToolbarItem, !forPalette { return tabStripToolbarItem }
        let item = NSToolbarItem(itemIdentifier: Self.tabStripItem)
        // A view has one superview: the item that is only for a palette has none (there is no customization, so none is made).
        if !forPalette { item.view = tabStrip.view }
        item.label = "Tabs"
        item.paletteLabel = "Tabs"
        item.isBordered = false
        item.visibilityPriority = .high
        if !forPalette { tabStripToolbarItem = item }
        return item
    }

    /// Tells the strip how much room the toolbar leaves it. `contentLeading` is where the editor area starts, in the window's
    /// coordinates, `windowWidth` is the width of the window's content, and `isSidebarShown` says whether the sidebar is.
    /// The strip starts after the tracking separator, a little inside the editor area, and with the sidebar hidden after the
    /// traffic lights and the sidebar button; the buttons take `TabStripLayout.trailingReserve` at the right.
    func updateTabStripWidth(contentLeading: CGFloat, windowWidth: CGFloat, isSidebarShown: Bool) {
        let leading = isSidebarShown ? contentLeading + TabStripLayout.leadingMargin : TabStripLayout.collapsedLeading
        tabStrip.maximumWidth = TabStripLayout.maximumWidth(windowWidth: windowWidth, leading: leading)
    }

    @objc private func newNote(_ sender: Any?) {
        onNewNote?()
    }

    // MARK: The paperclip

    /// Whether the paperclip works: it does not for a note in Recently Deleted, which takes no attachments.
    func setAttachEnabled(_ enabled: Bool) {
        isAttachEnabled = enabled
        attachButton?.isEnabled = enabled
    }

    private func makeAttachItem() -> NSToolbarItem {
        let description = "Attach File"
        let item = NSToolbarItem(itemIdentifier: Self.attachItem)
        item.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: description)
        item.label = description
        item.paletteLabel = description
        item.toolTip = description
        item.isBordered = true
        item.visibilityPriority = .user
        item.target = self
        item.action = #selector(attach(_:))
        // `setAttachEnabled` decides, and AppKit must not undo it by validating the item itself.
        item.autovalidates = false
        item.isEnabled = isAttachEnabled
        attachButton = item
        return item
    }

    @objc private func attach(_ sender: Any?) {
        onAttach?()
    }

    // MARK: The pin button

    /// Shows whether the note of the active tab is pinned (a filled pin, and the label "Unpin") or not (an outlined
    /// pin, "Pin"), and whether the button works: it does not for a note in Recently Deleted.
    func setPinned(_ pinned: Bool, enabled: Bool) {
        guard pinned != isPinned || enabled != isPinEnabled else { return }
        isPinned = pinned
        isPinEnabled = enabled
        if let pinButton { showPinState(in: pinButton) }
    }

    private func makePinItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.pinItem)
        item.isBordered = true
        item.visibilityPriority = .user
        item.target = self
        item.action = #selector(togglePin(_:))
        // The state is set by `setPinned`, and AppKit must not undo it by validating the item itself.
        item.autovalidates = false
        showPinState(in: item)
        pinButton = item
        return item
    }

    private func showPinState(in item: NSToolbarItem) {
        let description = isPinned ? "Unpin" : "Pin"
        item.image = NSImage(systemSymbolName: isPinned ? "pin.fill" : "pin", accessibilityDescription: description)
        item.label = description
        item.paletteLabel = description
        item.toolTip = description
        item.isEnabled = isPinEnabled
    }

    @objc private func togglePin(_ sender: Any?) {
        onTogglePin?()
    }
}
