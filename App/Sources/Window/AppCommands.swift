import AppKit

/// The target of the menu items that belong to the app and not to a view: the font size (⌘+ and ⌘= Bigger, ⌘− Smaller,
/// ⌘0 Actual Size) and the tabs (⌘N and ⌘T new note, ⌘W Close Tab, ⌃Tab and ⌃⇧Tab, ⌘1 to ⌘9). Each item sends its
/// action here, and `AppDelegate` sets the closures that carry it out.
///
/// A menu item holds its target weakly, so whoever creates this object must keep it for as long as the menu lives
/// (`AppDelegate` does).
final class AppCommands: NSObject {
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
