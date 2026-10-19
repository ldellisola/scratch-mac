import AppKit

/// The window's toolbar: the sidebar button over the sidebar and, over the editor, the "new note" button at the right.
/// The system draws every toolbar item on Liquid Glass (spec §8.1).
///
/// The toolbar keeps its delegate weakly, so whoever creates this controller must keep it alive for as long as the
/// window lives (`AppDelegate` does).
final class ToolbarController: NSObject, NSToolbarDelegate {
    /// Called when the user presses the "new note" button.
    var onNewNote: (() -> Void)?

    private static let newNoteItem = NSToolbarItem.Identifier("io.github.ldellisola.Scratch.newNote")

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
    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.newNoteItem else { return nil }

        // A button as the item's view, so that UI tests find it by its accessibility identifier.
        let description = "New Note"
        let button = NSButton(
            image: NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: description)
                ?? NSImage(),
            target: self, action: #selector(newNote(_:)))
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.toolTip = description
        button.setAccessibilityIdentifier(AccessibilityID.newNoteButton)
        button.setAccessibilityLabel(description)

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        // A custom view gets no glass background unless the item is bordered. The button's own border stays off, so
        // the system's glass capsule is the only one.
        item.isBordered = true
        item.label = description
        item.paletteLabel = description
        item.toolTip = description
        item.view = button
        return item
    }

    @objc private func newNote(_ sender: Any?) {
        onNewNote?()
    }
}
