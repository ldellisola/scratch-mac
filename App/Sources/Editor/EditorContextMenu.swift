import AppKit

/// The items that the editor's context menu adds for what is under the pointer (plan 6 task 8, docs/features/accessibility.md,
/// "The context menu"): every action that only a mouse could do has an item, each one only where it applies.
///
/// | Under the pointer | Item | What a click does |
/// |---|---|---|
/// | the box of a checklist item | Mark as Checked, or Mark as Unchecked | a click on the box |
/// | a link | Open Link | ⌘-click |
/// | an attachment | Open Attachment | double-click |
/// | a line of a code block | Code Block Language, a submenu | a click on the label |
///
/// A note that cannot be edited (Recently Deleted) offers only what leaves it as it is: Open Link and Open Attachment. The
/// items are the text view's own (`NoteTextView.menu(for:)` puts them in front of AppKit's), they do the same as the click
/// does (`toggleCheckbox(at:)`, `openURL`, `openAttachment`, `applyCodeBlockAction`), and the keyboard has the others too:
/// Format > Mark as Checked is ⇧⌘U, and the label's menu opens with a click.
enum EditorContextMenu {
    static let markAsChecked = "Mark as Checked"
    static let markAsUnchecked = "Mark as Unchecked"
    static let openLink = "Open Link"
    static let openAttachment = "Open Attachment"
    static let codeBlockLanguage = "Code Block Language"

    /// The items for the place at `point`, in the coordinates of `textView`, in the order of the table above: none when nothing
    /// there has one.
    static func items(for textView: NoteTextView, atViewPoint point: NSPoint) -> [NSMenuItem] {
        [
            checkboxItem(in: textView, atViewPoint: point), linkItem(in: textView, atViewPoint: point),
            attachmentItem(in: textView, atViewPoint: point), codeBlockItem(in: textView, atViewPoint: point),
        ].compactMap { $0 }
    }

    // MARK: The items

    private static func checkboxItem(in textView: NoteTextView, atViewPoint point: NSPoint) -> NSMenuItem? {
        guard textView.isEditable, let marker = textView.checkboxMarker(atViewPoint: point) else { return nil }
        // `[x]` and `[X]` are ticked, `[ ]` is not: the character between the brackets.
        let text = textView.string as NSString
        let isChecked = marker.length == 3 && text.character(at: marker.location + 1) != 0x20
        let item = makeItem(
            isChecked ? markAsUnchecked : markAsChecked, #selector(NoteTextView.toggleCheckboxFromMenu(_:)),
            for: textView)
        item.representedObject = NSValue(range: marker)
        return item
    }

    private static func linkItem(in textView: NoteTextView, atViewPoint point: NSPoint) -> NSMenuItem? {
        guard let url = textView.link(atViewPoint: point) else { return nil }
        let item = makeItem(openLink, #selector(NoteTextView.openLinkFromMenu(_:)), for: textView)
        item.representedObject = url
        return item
    }

    /// Open Attachment is there for every attachment and is disabled when there is no file to open (a missing attachment, one
    /// that is still being copied), where a double-click would only beep.
    private static func attachmentItem(in textView: NoteTextView, atViewPoint point: NSPoint) -> NSMenuItem? {
        guard let mark = textView.attachmentMark(atViewPoint: point) else { return nil }
        let item = makeItem(openAttachment, #selector(NoteTextView.openAttachmentFromMenu(_:)), for: textView)
        item.representedObject = mark
        item.isEnabled = textView.storedFile(of: mark) != nil
        return item
    }

    /// The submenu is the label's menu (`CodeBlockMenu.menu`), made for the block under the pointer: the languages with the
    /// current one ticked, Plain Text and Not Code. Its items change the fence lines, so a note that cannot be edited has none.
    private static func codeBlockItem(in textView: NoteTextView, atViewPoint point: NSPoint) -> NSMenuItem? {
        guard textView.isEditable, let block = textView.codeBlock(atViewPoint: point),
            let storage = textView.textStorage
        else { return nil }
        let mark = storage.attribute(.scratchCodeBlock, at: block.range.location, effectiveRange: nil) as? CodeBlockMark
        let item = NSMenuItem(title: codeBlockLanguage, action: nil, keyEquivalent: "")
        item.submenu = CodeBlockMenu.menu(for: block.range, current: mark?.language, target: textView)
        return item
    }

    /// An enabled item that sends `action` to the text view.
    private static func makeItem(_ title: String, _ action: Selector, for textView: NoteTextView) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = textView
        item.isEnabled = true
        return item
    }
}
