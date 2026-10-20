import AppKit

/// The target of the menu items that belong to the app and not to a view: the font size (⌘+ and ⌘= Bigger, ⌘− Smaller,
/// ⌘0 Actual Size), the tabs (⌘N and ⌘T new note, ⌘W Close Tab, ⌃Tab and ⌃⇧Tab, ⌘1 to ⌘9), pinning (⇧⌘P) and the
/// sidebar's search (⌥⌘F). Each item sends its action here, and `AppDelegate` sets the closures that carry it out.
///
/// A menu item holds its target weakly, so whoever creates this object must keep it for as long as the menu lives
/// (`AppDelegate` does).
final class AppCommands: NSObject, NSMenuItemValidation {
    /// Called by View > Bigger (⌘+, also ⌘=).
    var onBigger: (() -> Void)?
    /// Called by View > Smaller (⌘−).
    var onSmaller: (() -> Void)?
    /// Called by View > Actual Size (⌘0).
    var onActualSize: (() -> Void)?

    /// Called by File > New Note (⌘N) and File > New Tab (⌘T): both open a new empty note in a new tab.
    var onNewNote: (() -> Void)?
    /// Called by File > Close Tab (⌘W).
    var onCloseTab: (() -> Void)?
    /// Called by Window > Show Next Tab (⌃Tab).
    var onNextTab: (() -> Void)?
    /// Called by Window > Show Previous Tab (⌃⇧Tab).
    var onPreviousTab: (() -> Void)?
    /// Called by Window > Select Tab 1 to 9 (⌘1 to ⌘9) with the number: 1 to 8 select that tab, 9 the last one.
    var onSelectTabNumber: ((Int) -> Void)?

    /// Called by File > Pin Note (⇧⌘P), which pins the note of the active tab or unpins it.
    var onTogglePin: (() -> Void)?
    /// Called by Edit > Search Notes (⌥⌘F), which puts the cursor in the sidebar's search field.
    var onFocusSearch: (() -> Void)?

    /// Whether the note of the active tab is pinned, which decides the title of the pin item: "Pin Note" or "Unpin
    /// Note". Set with `setActiveNotePin`.
    private var activeNoteIsPinned = false
    /// Whether the note of the active tab can be pinned. The item is disabled while it cannot.
    private var activeNoteCanBePinned = true

    /// Records what the pin item of the File menu shows. The menu reads it when it is opened, and when ⇧⌘P is typed.
    func setActiveNotePin(pinned: Bool, enabled: Bool) {
        activeNoteIsPinned = pinned
        activeNoteCanBePinned = enabled
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(togglePin(_:)) else { return true }
        menuItem.title = activeNoteIsPinned ? "Unpin Note" : "Pin Note"
        return activeNoteCanBePinned
    }

    @objc func bigger(_ sender: Any?) {
        onBigger?()
    }

    @objc func smaller(_ sender: Any?) {
        onSmaller?()
    }

    @objc func actualSize(_ sender: Any?) {
        onActualSize?()
    }

    @objc func newNote(_ sender: Any?) {
        onNewNote?()
    }

    @objc func closeTab(_ sender: Any?) {
        onCloseTab?()
    }

    @objc func togglePin(_ sender: Any?) {
        onTogglePin?()
    }

    @objc func focusSearch(_ sender: Any?) {
        onFocusSearch?()
    }

    @objc func nextTab(_ sender: Any?) {
        onNextTab?()
    }

    @objc func previousTab(_ sender: Any?) {
        onPreviousTab?()
    }

    /// The tab number is the menu item's `tag`.
    @objc func selectTab(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        onSelectTabNumber?(item.tag)
    }
}
