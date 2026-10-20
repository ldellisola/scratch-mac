import AppKit

/// The sidebar's table. It adds four things to `NSTableView`:
///
/// - **Return** (and the keypad's Enter) calls `onReturn` instead of beeping, so that the arrow keys and Return open a
///   note without the mouse.
/// - **⌘⌫** calls `onCommandDelete`, which deletes the highlighted note (spec §6.7). It is handled here, in `keyDown`,
///   and is not a menu key equivalent on purpose: a key equivalent in the menu bar would take ⌘⌫ away from the text
///   view, where it deletes to the start of the line. It only gets here when the table is the first responder, which is
///   "when the sidebar has focus".
/// - **A click that a header takes**: `takesClick` is asked first, so that a click on the Recently Deleted header can
///   show or hide its rows. A header cannot be highlighted, so the table's own click handling would not send its action.
/// - **The context menu** of a row. `menuForRow` is asked for the menu of the row under the mouse when the owner
///   right-clicks (or Control-clicks), and a click on no row has no menu.
///
/// Every other key and click is the table's own.
final class SidebarTableView: NSTableView {
    /// Called when the owner presses Return on the highlighted row.
    var onReturn: (() -> Void)?

    /// Called when the owner presses ⌘⌫. Returns whether it deleted a note: when it did not (nothing is highlighted, or
    /// the note is in Recently Deleted already), the table beeps.
    var onCommandDelete: (() -> Bool)?

    /// Called with the index of the row under the mouse when the left button goes down, before the table does anything
    /// with it. Return true to take the click: the table then neither highlights the row nor sends its action.
    var takesClick: ((Int) -> Bool)?

    /// The context menu of the row at an index, or nil for a row that has none (a group header).
    var menuForRow: ((Int) -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        // 36 is Return and 76 the keypad's Enter (kVK_Return, kVK_ANSI_KeypadEnter).
        if (event.keyCode == 36 || event.keyCode == 76) && modifiers.isEmpty {
            onReturn?()
            return
        }
        // 51 is the key labelled ⌫ (kVK_Delete). The forward delete key is 117 and is not used.
        if event.keyCode == 51 && modifiers == [.command] {
            if onCommandDelete?() != true { NSSound.beep() }
            return
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let index = row(at: convert(event.locationInWindow, from: nil))
        // A Control-click is a right click on the Mac, and it opens the context menu.
        if index >= 0, !event.modifierFlags.contains(.control), takesClick?(index) == true { return }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let index = row(at: convert(event.locationInWindow, from: nil))
        guard index >= 0 else { return nil }
        return menuForRow?(index)
    }
}
