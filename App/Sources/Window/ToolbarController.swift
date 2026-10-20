import AppKit

/// The window's toolbar: the sidebar button over the sidebar and, over the editor, the pin button and the "new note"
/// button at the right (spec §6.1). The system draws every toolbar item on Liquid Glass (spec §8.1).
///
/// The toolbar keeps its delegate weakly, so whoever creates this controller must keep it alive for as long as the
/// window lives (`AppDelegate` does).
final class ToolbarController: NSObject, NSToolbarDelegate {
    /// Called when the user presses the "new note" button, which opens a new empty note in a new tab.
    var onNewNote: (() -> Void)?

    /// Called when the user presses the pin button, which pins the note of the active tab or unpins it.
    var onTogglePin: (() -> Void)?

    private static let newNoteItem = NSToolbarItem.Identifier(AccessibilityID.newNoteButton)
    private static let pinItem = NSToolbarItem.Identifier(AccessibilityID.pinButton)

    /// The items from left to right. The tracking separator makes the items after it line up with the editor, and the
    /// flexible space pushes the pin and "new note" buttons to the right edge.
    private static let itemIdentifiers: [NSToolbarItem.Identifier] = [
        .toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, pinItem, newNoteItem,
    ]

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
        Self.itemIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.itemIdentifiers
    }

    /// Only the pin and "new note" items are made here. AppKit makes the standard ones (sidebar button, separator,
    /// space).
    ///
    /// They are plain items with an image, not custom views, so that the system draws them on a Liquid Glass capsule
    /// like every other toolbar item: a custom `NSButton` view got no capsule, bordered item or not (screenshots, plan
    /// 1 task 9). A view-less item has no view to carry an accessibility identifier, so its item identifier is
    /// `AccessibilityID.newNoteButton` (or `pinButton`), and UI tests find the button by that, its label or its title.
    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if itemIdentifier == Self.pinItem { return makePinItem() }
        guard itemIdentifier == Self.newNoteItem else { return nil }

        let description = "New Note"
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: description)
        item.label = description
        item.paletteLabel = description
        item.toolTip = description
        item.isBordered = true
        item.target = self
        item.action = #selector(newNote(_:))
        return item
    }

    @objc private func newNote(_ sender: Any?) {
        onNewNote?()
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
