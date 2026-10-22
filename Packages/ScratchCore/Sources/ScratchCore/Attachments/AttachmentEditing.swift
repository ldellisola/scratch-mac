import Foundation

/// What the keys and the pasteboard do around the token line of an attachment (spec §6.4, plan 5 task 5).
///
/// A token is a whole line, `[[attachment:<id>]]` (``AttachmentToken``), and the editor draws it as a picture or a chip. The
/// rules here keep it whole: the caret never stops inside one, a selection that covers part of one grows to cover all of
/// it, Backspace and Delete next to one select it before they delete anything, and an attachment that is pasted or dropped
/// is a line of its own. Like ``ListEditing``, a rule never touches text: it answers with a ``TextEdit`` or a ``KeyAction``
/// and the text view carries it out, as one undo step.
///
/// Every offset is in UTF-16 units of the document, as `NSTextStorage` counts, and `text` is the whole document. Nothing
/// here reads more than a token's length (51 units) either side of a position, whatever the lines of the note are like. A
/// caller that knows which tokens are not tokens, because they are in a fenced code block, passes `isLiteral`: the rules
/// leave those alone.
public enum AttachmentEditing {
    /// A token line of the text: where it is (the line without its break) and which attachment it names.
    public struct Token: Equatable, Sendable {
        /// The token's characters, `AttachmentToken.lineLength` UTF-16 units, line break excluded.
        public let range: NSRange
        public let id: AttachmentID

        public init(range: NSRange, id: AttachmentID) {
            self.range = range
            self.id = id
        }
    }

    /// What Backspace or Delete does when it is next to a token.
    public enum KeyAction: Equatable, Sendable {
        /// The token is selected and nothing is deleted: the next press of the key deletes it.
        case selectToken(NSRange)
        /// The token is deleted with its line break, so that no empty line is left where it was.
        case removeToken(TextEdit)
        /// The key would join a line of text to a token line, which would leave the token half a line. Nothing is deleted
        /// and the caret goes to the other side of the line break.
        case moveCaret(to: Int)
    }

    public enum DeletionDirection: Sendable {
        /// Backspace.
        case backward
        /// Delete (forward).
        case forward
    }

    // MARK: Finding a token

    /// The token line that `location` is in, or at either end of, or nil: a caret at `location` is on that line. A line
    /// that holds anything more than the token is text, and so is a line of any other length.
    public static func token(touching location: Int, in text: NSString) -> Token? {
        let length = text.length
        guard location >= 0, location <= length else { return nil }
        let size = AttachmentToken.lineLength
        var start = location
        while start > 0, location - start < size, !isLineBreak(text.character(at: start - 1)) { start -= 1 }
        var end = location
        while end < length, end - location < size, !isLineBreak(text.character(at: end)) { end += 1 }
        guard end - start == size else { return nil }
        // A scan that stopped at its bound did not reach the end of its line: the line is longer than a token.
        guard start == 0 || isLineBreak(text.character(at: start - 1)) else { return nil }
        guard end == length || isLineBreak(text.character(at: end)) else { return nil }
        let range = NSRange(location: start, length: size)
        guard let id = AttachmentToken.id(inLine: text.substring(with: range)) else { return nil }
        return Token(range: range, id: id)
    }

    /// The token that `location` is inside, which is not one that it is at the start or the end of.
    private static func token(strictlyInside location: Int, in text: NSString, ignoring isLiteral: (NSRange) -> Bool)
        -> Token?
    {
        guard let token = token(touching: location, in: text), !isLiteral(token.range),
            location > token.range.location, location < NSMaxRange(token.range)
        else { return nil }
        return token
    }

    // MARK: Selecting

    /// The selection that `new` is made into, when the selection is about to change from `old` to `new`: a caret is never
    /// inside a token, and a range never starts or ends inside one.
    ///
    /// - A caret inside a token goes to the token's end, or to its start when it came from further on in the text (an arrow
    ///   key or a word move to the left, or up), so that the caret steps over the token. A click (`isClick`) goes to the end.
    /// - A range whose start is inside a token starts at the token's start, and one whose end is inside a token ends at the
    ///   token's end, so a part of a token is the whole of it.
    ///
    /// Anything else, and a selection that is not in the text, is returned as it is.
    public static func snappedSelection(
        from old: NSRange, to new: NSRange, in text: NSString, isClick: Bool = false,
        ignoring isLiteral: (NSRange) -> Bool = { _ in false }
    ) -> NSRange {
        guard new.location != NSNotFound, new.location >= 0, new.length >= 0, NSMaxRange(new) <= text.length else {
            return new
        }
        if new.length == 0 {
            guard let token = token(strictlyInside: new.location, in: text, ignoring: isLiteral) else { return new }
            let steppedBack = !isClick && old.location != NSNotFound && new.location < old.location
            return NSRange(location: steppedBack ? token.range.location : NSMaxRange(token.range), length: 0)
        }
        var start = new.location
        var end = NSMaxRange(new)
        if let token = token(strictlyInside: start, in: text, ignoring: isLiteral) { start = token.range.location }
        if let token = token(strictlyInside: end, in: text, ignoring: isLiteral) { end = NSMaxRange(token.range) }
        return NSRange(location: start, length: end - start)
    }

    // MARK: Backspace and Delete

    /// What Backspace or Delete does at `selection` when a token is involved, or nil when the key is the text view's own.
    ///
    /// - **A selection that is exactly one token:** the token is deleted with its line break (`removeToken`).
    /// - **A caret right after a token** (Backspace: at the token line's end, or at the start of the line below it) **or right
    ///   before one** (Delete: at the token line's start, or at the end of the line above it): the token is selected
    ///   (`selectToken`), so that a key that was meant for a character next to a picture does not delete the picture.
    /// - **A caret where the key would join a line of text and a token line** (Backspace at the start of a token line below
    ///   a line of text, Delete at the end of a token line above one): the caret moves over the line break and nothing is
    ///   deleted (`moveCaret`). Where the other line is empty the key is the text view's own: it removes the empty line.
    ///
    /// Anything else, a selection of other text included, is nil: the text view deletes as it always does. A token that
    /// `isLiteral` says is text is not one.
    public static func deletion(
        _ direction: DeletionDirection, selection: NSRange, in text: NSString,
        ignoring isLiteral: (NSRange) -> Bool = { _ in false }
    ) -> KeyAction? {
        guard selection.location != NSNotFound, selection.location >= 0, selection.length >= 0,
            NSMaxRange(selection) <= text.length
        else { return nil }

        if selection.length > 0 {
            guard let token = token(touching: selection.location, in: text), token.range == selection,
                !isLiteral(token.range)
            else { return nil }
            return .removeToken(removal(of: token.range, in: text))
        }

        let caret = selection.location
        switch direction {
        case .backward:
            if let token = tokenRightBefore(caret, in: text, ignoring: isLiteral) { return .selectToken(token.range) }
            // The line break before a token line would join the line above to it.
            let preceding = breakLength(endingAt: caret, in: text)
            guard preceding > 0, let token = token(touching: caret, in: text), token.range.location == caret,
                !isLiteral(token.range), !isEmptyLine(endingAt: caret - preceding, in: text)
            else { return nil }
            return .moveCaret(to: caret - preceding)
        case .forward:
            if let token = tokenRightAfter(caret, in: text, ignoring: isLiteral) { return .selectToken(token.range) }
            // The line break after a token line would join the line below to it.
            let following = breakLength(at: caret, in: text)
            guard following > 0, let token = token(touching: caret, in: text),
                NSMaxRange(token.range) == caret, !isLiteral(token.range),
                !isEmptyLine(startingAt: caret + following, in: text)
            else { return nil }
            return .moveCaret(to: caret + following)
        }
    }

    /// The token that ends where the caret is, or whose line ends right above the line the caret is at the start of.
    private static func tokenRightBefore(_ caret: Int, in text: NSString, ignoring isLiteral: (NSRange) -> Bool)
        -> Token?
    {
        if let token = token(touching: caret, in: text), NSMaxRange(token.range) == caret, !isLiteral(token.range) {
            return token
        }
        let preceding = breakLength(endingAt: caret, in: text)
        guard preceding > 0, let token = token(touching: caret - preceding, in: text),
            NSMaxRange(token.range) == caret - preceding, !isLiteral(token.range)
        else { return nil }
        return token
    }

    /// The token whose line starts where the caret is, or right below the line that the caret is at the end of.
    private static func tokenRightAfter(_ caret: Int, in text: NSString, ignoring isLiteral: (NSRange) -> Bool)
        -> Token?
    {
        if let token = token(touching: caret, in: text), token.range.location == caret, !isLiteral(token.range) {
            return token
        }
        let following = breakLength(at: caret, in: text)
        guard following > 0, let token = token(touching: caret + following, in: text),
            token.range.location == caret + following, !isLiteral(token.range)
        else { return nil }
        return token
    }

    /// The edit that deletes the token at `token` with one line break: the one after it, or when it is the last line of the
    /// text the one before it, so that no empty line is left where it was. A token that is the only line goes alone. The
    /// caret goes where the token was.
    public static func removal(of token: NSRange, in text: NSString) -> TextEdit {
        let following = breakLength(at: NSMaxRange(token), in: text)
        if following > 0 {
            return TextEdit(
                range: NSRange(location: token.location, length: token.length + following), replacement: "",
                selection: NSRange(location: token.location, length: 0))
        }
        let preceding = breakLength(endingAt: token.location, in: text)
        if preceding > 0 {
            let start = token.location - preceding
            return TextEdit(
                range: NSRange(location: start, length: preceding + token.length), replacement: "",
                selection: NSRange(location: start, length: 0))
        }
        return TextEdit(range: token, replacement: "", selection: NSRange(location: token.location, length: 0))
    }

    // MARK: Inserting

    /// The edit that puts the attachments `ids` into the text over `selection`, each on a line of its own (spec §6.4).
    ///
    /// A line break goes in before the first token unless the selection starts a line, and one goes in after the last token
    /// unless a line break follows the selection already, so that what is typed next is on a line of its own and cannot join
    /// a token's line. The caret ends at the start of the line after the last token: right after the line break that was
    /// there, or the one that was put in. Several attachments are several lines.
    public static func insertion(of ids: [AttachmentID], over selection: NSRange, in text: NSString) -> TextEdit {
        guard !ids.isEmpty else {
            return TextEdit(
                range: NSRange(location: selection.location, length: 0), replacement: "", selection: selection)
        }
        let start = selection.location
        let atLineStart = start == 0 || isLineBreak(text.character(at: start - 1))
        let following = breakLength(at: NSMaxRange(selection), in: text)
        let replacement =
            (atLineStart ? "" : "\n") + ids.map { AttachmentToken.line(for: $0) }.joined(separator: "\n")
            + (following > 0 ? "" : "\n")
        return TextEdit(
            range: selection, replacement: replacement,
            selection: NSRange(location: start + replacement.utf16.count + following, length: 0))
    }

    // MARK: Lines

    private static func isLineBreak(_ unit: UInt16) -> Bool {
        unit == 0x0A || unit == 0x0D
    }

    /// The length of the line break that starts at `index`: 2 for CR LF, 1 for LF or CR, 0 when there is none.
    private static func breakLength(at index: Int, in text: NSString) -> Int {
        guard index >= 0, index < text.length else { return 0 }
        let unit = text.character(at: index)
        if unit == 0x0A { return 1 }
        guard unit == 0x0D else { return 0 }
        return index + 1 < text.length && text.character(at: index + 1) == 0x0A ? 2 : 1
    }

    /// The length of the line break that ends at `index`, which is where the next line starts.
    private static func breakLength(endingAt index: Int, in text: NSString) -> Int {
        guard index > 0, index <= text.length else { return 0 }
        let unit = text.character(at: index - 1)
        if unit == 0x0D { return 1 }
        guard unit == 0x0A else { return 0 }
        return index >= 2 && text.character(at: index - 2) == 0x0D ? 2 : 1
    }

    /// True when the line that ends at `end` (where its line break starts, or the end of the text) has no characters.
    private static func isEmptyLine(endingAt end: Int, in text: NSString) -> Bool {
        end == 0 || breakLength(endingAt: end, in: text) > 0
    }

    /// True when the line that starts at `start` has no characters: the text ends there, or a line break comes first.
    private static func isEmptyLine(startingAt start: Int, in text: NSString) -> Bool {
        start >= text.length || breakLength(at: start, in: text) > 0
    }
}
