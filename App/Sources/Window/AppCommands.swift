import AppKit

/// The target of the menu items that belong to the app and not to a view: ⌘+ and ⌘= (Bigger), ⌘− (Smaller) and ⌘0
/// (Actual Size). Each item sends its action here, and `AppDelegate` sets the closures that carry it out.
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

    @objc func bigger(_ sender: Any?) {
        onBigger?()
    }

    @objc func smaller(_ sender: Any?) {
        onSmaller?()
    }

    @objc func actualSize(_ sender: Any?) {
        onActualSize?()
    }
}
