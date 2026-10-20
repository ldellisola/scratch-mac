/// Offsets into a note's text, counted in UTF-16 units as `NSTextView` does (spec §6.6).
public enum TextOffset {
    /// The nearest valid cursor position at or before `utf16Offset` in `text`.
    ///
    /// A saved cursor can be stale: the text may have been edited elsewhere or be shorter now. A negative offset
    /// becomes 0, and an offset past the end becomes the text's length. An offset inside a `Character` (a surrogate
    /// pair, an emoji sequence, a letter and its accent, a CRLF) moves back to the start of that `Character`, so the
    /// cursor never splits one.
    ///
    /// The cost does not depend on the length of the text. A walk over every `Character` would take about 0.3 s
    /// for a 5 MB note, and the restore runs inside the launch budget.
    public static func clamp(_ utf16Offset: Int, in text: String) -> Int {
        guard utf16Offset > 0 else { return 0 }
        let utf16 = text.utf16
        guard var position = utf16.index(utf16.startIndex, offsetBy: utf16Offset, limitedBy: utf16.endIndex),
            position < utf16.endIndex
        else { return utf16.count }

        // Inside a surrogate pair: step back to the start of its scalar.
        if position.samePosition(in: text.unicodeScalars) == nil {
            position = utf16.index(before: position)
        }
        if position.samePosition(in: text) != nil { return position.utf16Offset(in: text) }

        // Inside a Character, so `position` is past the start of the text. The last Character of the text before
        // `position` is the one that contains it, and it starts where the Character does.
        let before = text[..<position]
        return before.index(before: before.endIndex).utf16Offset(in: text)
    }
}
