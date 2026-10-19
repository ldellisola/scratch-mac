import AppKit

/// The window's toolbar: the sidebar button over the sidebar and, over the editor, the "new note" button at the right.
/// The system draws every toolbar item on Liquid Glass (spec §8.1).
///
/// The toolbar keeps its delegate weakly, so whoever creates this controller must keep it alive for as long as the
/// window lives (`AppDelegate` does).
final class ToolbarController: NSObject, NSToolbarDelegate {
    /// Called when the user presses the "new note" button.
    var onNewNote: (() -> Void)?

    private static let newNoteItem = NSToolbarItem.Identifier(AccessibilityID.newNoteButton)

    /// The items from left to right. The tracking separator makes the items after it line up with the editor, and the
    /// flexible space pushes the "new note" button to the right edge.
    private static let itemIdentifiers: [NSToolbarItem.Identifier] = [
        .toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, newNoteItem,
    ]

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

    /// Only the "new note" item is made here. AppKit makes the standard ones (sidebar button, separator, space).
    ///
    /// It is a plain item with an image, not a custom view, so that the system draws it on a Liquid Glass capsule like
    /// every other toolbar item: a custom `NSButton` view got no capsule, bordered item or not (screenshots, plan 1
    /// task 9). A view-less item has no view to carry an accessibility identifier, so its item identifier is
    /// `AccessibilityID.newNoteButton`, and UI tests find the button by that, its label or its title.
    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
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
}
