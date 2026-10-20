import Foundation

/// Where positions of a text go when part of it is replaced, so that ranges kept from before an edit (the fenced
/// blocks of a note, the paragraphs the editor has still to style) can be carried over it.
///
/// All offsets are UTF-16 units, as `NSTextStorage` counts. The mapping is lenient on purpose: a position inside the
/// replaced text goes to the start or to the end of its replacement, whichever keeps a range around the new text.
public struct EditMapping: Equatable, Sendable {
    /// The range of the old text that the edit replaced. It is empty for an insertion.
    public let replaced: NSRange
    /// The number of units that replaced it. Zero for a deletion.
    public let newLength: Int

    public init(replaced: NSRange, newLength: Int) {
        self.replaced = replaced
        self.newLength = newLength
    }

    /// From what a text storage reports after an edit (`textStorage(_:didProcessEditing:range:changeInLength:)`):
    /// `editedRange` is the range of the new text the edit touched and `delta` is the change in the text's length.
    /// The storage may widen the range to whole paragraphs, so `replaced` can cover more than the edit changed. That is
    /// the safe side for every use here.
    public init(editedRange: NSRange, changeInLength delta: Int) {
        self.init(
            replaced: NSRange(location: editedRange.location, length: max(editedRange.length - delta, 0)),
            newLength: editedRange.length)
    }

    /// How many units longer the text is.
    public var delta: Int { newLength - replaced.length }

    /// Where the start of a range that began at `position` before the edit begins now. A position inside the replaced
    /// text moves to the start of the new text.
    public func mapStart(_ position: Int) -> Int {
        if position <= replaced.location { return position }
        if position >= NSMaxRange(replaced) { return position + delta }
        return replaced.location
    }

    /// Where the end of a range that ended at `position` before the edit ends now. A position inside the replaced text
    /// moves to the end of the new text, and one at the start of an insertion stays in front of it.
    public func mapEnd(_ position: Int) -> Int {
        if position <= replaced.location { return position }
        if position >= NSMaxRange(replaced) { return position + delta }
        return replaced.location + newLength
    }

    /// `range` after the edit. A range the edit lies in grows or shrinks with it, and one that began or ended inside
    /// the replaced text takes in the new text. The result is empty when the edit swallowed the range.
    public func mapped(_ range: NSRange) -> NSRange {
        let start = mapStart(range.location)
        let end = max(mapEnd(NSMaxRange(range)), start)
        return NSRange(location: start, length: end - start)
    }
}
