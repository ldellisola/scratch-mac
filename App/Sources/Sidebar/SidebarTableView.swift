import AppKit

/// The sidebar's table. It adds two things to `NSTableView`:
///
/// - **Return** (and the keypad's Enter) calls `onReturn` instead of beeping, so that the arrow keys and Return open a
///   note without the mouse. Every other key is the table's own.
/// - **The context menu** of a row. `menuForRow` is asked for the menu of the row under the mouse when the owner
///   right-clicks (or Control-clicks), and a click on no row has no menu.
final class SidebarTableView: NSTableView {
    /// Called when the owner presses Return on the highlighted row.
    var onReturn: (() -> Void)?

    /// The context menu of the row at an index, or nil for a row that has none (a group header).
    var menuForRow: ((Int) -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        // 36 is Return and 76 the keypad's Enter (kVK_Return, kVK_ANSI_KeypadEnter).
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        if (event.keyCode == 36 || event.keyCode == 76) && modifiers.isEmpty {
            onReturn?()
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let index = row(at: convert(event.locationInWindow, from: nil))
        guard index >= 0 else { return nil }
        return menuForRow?(index)
    }
}
