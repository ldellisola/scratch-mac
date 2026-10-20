import Foundation

/// One change to a note that an editing rule asks the text view to make.
///
/// The rules in ``ListEditing`` and ``InlineEditing`` never touch text themselves. They answer an action of the owner
/// (Return, Tab, ⇧Tab, ⇧⌘L, ⌘B, a click on a checkbox) with a `TextEdit`, and the editor applies it as one undo step.
/// Every offset is in UTF-16 units of the document, as `NSTextStorage` counts.
public struct TextEdit: Equatable, Sendable {
    /// The document range to replace.
    public let range: NSRange
    /// What goes in its place.
    public let replacement: String
    /// The selection once the edit is applied, in document coordinates (the text after the edit).
    public let selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }
}
