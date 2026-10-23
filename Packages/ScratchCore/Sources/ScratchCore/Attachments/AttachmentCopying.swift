import Foundation

/// What Copy and Cut put on the pasteboard when the selection holds attachments (spec §6.5, plan 5 task 6).
///
/// The note's text holds a token line for an attachment (``AttachmentToken``), and a token is no use to anything outside
/// the note. So the text that is copied has the name of the file where the token was ("its file name appears in the
/// text"), and when the selection is exactly one token the file itself goes on the pasteboard as well ("the file or image
/// itself is also put on the pasteboard"): ``soleAttachment(in:of:ignoring:)`` says which. Like the other rules of the
/// core it reads text and answers with values, and the text view writes the pasteboard.
///
/// Every offset is in UTF-16 units of the document, as `NSTextStorage` counts. A caller that knows which tokens are not
/// tokens, because they are in a fenced code block, passes `isLiteral`: every character of a block is literal (spec
/// §6.4), so a token there is copied as it was typed.
public enum AttachmentCopying {
    /// The text of `range` of `text` as Copy puts it on the pasteboard: the text exactly as it is stored, with each token
    /// line that the range touches replaced by `name` of its id (the line break after it stays). A range that cuts a token
    /// copies the name of the whole token and no piece of it, which the editor never makes (a selection grows to hold a
    /// whole token), and a range that reaches past the end of `text` is cut to it. An empty range, or one that starts
    /// outside the text, copies nothing.
    public static func text(
        of range: NSRange, in text: NSString, name: (AttachmentID) -> String,
        ignoring isLiteral: (NSRange) -> Bool = { _ in false }
    ) -> String {
        guard range.location != NSNotFound, range.location >= 0, range.length > 0, range.location < text.length else {
            return ""
        }
        let end = min(NSMaxRange(range), text.length)
        var result = ""
        var cursor = range.location
        for (token, id) in AttachmentToken.lineRanges(in: text, within: range) where !isLiteral(token) {
            if token.location > cursor {
                result += text.substring(with: NSRange(location: cursor, length: token.location - cursor))
            }
            result += name(id)
            cursor = max(cursor, min(NSMaxRange(token), end))
        }
        if cursor < end { result += text.substring(with: NSRange(location: cursor, length: end - cursor)) }
        return result
    }

    /// Whether `range` of `text` holds a token line that is an attachment: the range has at least one character of it, and
    /// `isLiteral` does not say it is text (a token in a fenced block). Copy and Cut also write the selection exactly as it is
    /// stored, on a private type, when this is true, so that a paste or a drop into Scratch keeps the attachment, and
    /// write nothing more when it is not (docs/features/attachments.md, "Copying"). An empty range, one that starts outside
    /// the text and a text with no `[[attachment:` in or next to the range hold none. A range that reaches past the end of
    /// `text` is cut to it.
    public static func holdsAttachment(
        in range: NSRange, of text: NSString, ignoring isLiteral: (NSRange) -> Bool = { _ in false }
    ) -> Bool {
        guard range.location != NSNotFound, range.location >= 0, range.length > 0, range.location < text.length else {
            return false
        }
        // Most notes have no token: say so with one search, which may start in the middle of a token that the range cuts.
        let reach = AttachmentToken.lineLength - 1
        let searchStart = max(range.location - reach, 0)
        let searchEnd = min(range.location + min(range.length, text.length - range.location) + reach, text.length)
        guard
            text.range(
                of: "[[attachment:", options: .literal,
                range: NSRange(location: searchStart, length: searchEnd - searchStart)
            ).location != NSNotFound
        else { return false }
        return AttachmentToken.lineRanges(in: text, within: range).contains { !isLiteral($0.0) }
    }

    /// The attachment that `selection` is exactly: one token line, its line break excluded, and nothing more or less. That
    /// selection is what clicking a picture or a chip makes, and what Backspace makes next to one. Nil for any other
    /// selection, an empty one included, and for a token that `isLiteral` says is text.
    public static func soleAttachment(
        in selection: NSRange, of text: NSString, ignoring isLiteral: (NSRange) -> Bool = { _ in false }
    ) -> AttachmentID? {
        guard selection.length == AttachmentToken.lineLength,
            let token = AttachmentEditing.token(touching: selection.location, in: text),
            token.range == selection, !isLiteral(token.range)
        else { return nil }
        return token.id
    }
}
