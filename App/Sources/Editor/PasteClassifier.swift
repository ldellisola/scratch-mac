import Foundation
import ScratchCode
import ScratchCore

/// Decides whether a paste that was just inserted is code, and how to put it in a fence (spec §6.4 "Code highlighting",
/// §6.5 paste order; plan 4, task 6).
///
/// The paste itself is always the plain one: `NoteTextView` inserts the pasteboard's text as it always did and asks
/// here on the next turn of the main run loop, so that the wrap is an undo step of its own. ⌘Z once leaves exactly the
/// text that was pasted, and ⌘Z again takes it away. Nothing is trimmed, re-indented or converted: the edit this
/// answers with has the pasted characters in it unchanged, with the fence lines around them.
///
/// Prose stays prose. A paste is a candidate only when it has two lines or more, is not pasted into code (a fenced block
/// or inline code), holds no fence line of its own, and is in no danger of pairing with a fence that is in the note
/// already; and then `CodeDetector` has the last word.
enum PasteClassifier {
    /// The edit that wraps a paste that was just inserted at `range` of `text` (which has the paste in it) in a fence, or
    /// nil to leave it plain.
    ///
    /// - `pasted` is the text at `range`, as it was pasted.
    /// - `isInCode` is true when the paste went into a fenced block or into inline code. It is asked before the paste: a
    ///   multi-line paste splits the line that inline code was on.
    ///
    /// The edit replaces `range` with the pasted text between two fence lines. The opening fence names the detected
    /// language (a fence with no name for code of a language that Scratch does not know) and has a line break in front of
    /// it when the paste did not start a line. The closing fence has a line break in front of it unless the paste ended
    /// with one itself, so that the block holds no line that was not pasted, and a line break behind it when the paste did
    /// not end a line. The selection afterwards is behind everything that was inserted, where the caret was.
    ///
    /// Nil also for a paste that would split a CRLF, and for one pasted below a fence line that has no partner (a block
    /// the owner is still typing): the new fences would pair with it and take the note's blocks apart.
    static func wrap(pasted: String, at range: NSRange, in text: NSString, isInCode: Bool) -> TextEdit? {
        guard !isInCode, range.location >= 0, range.length > 0, NSMaxRange(range) <= text.length else { return nil }
        guard pasted.utf16.count == range.length, hasTwoLines(pasted), !containsFenceLine(pasted) else { return nil }
        guard !splitsCRLF(range, in: text), fenceLineCount(before: range.location, in: text).isMultiple(of: 2) else {
            return nil
        }
        guard let detection = CodeDetector.detect(pasted) else { return nil }

        let end = NSMaxRange(range)
        let startsLine = range.location == 0 || isLineBreak(text.character(at: range.location - 1))
        let endsWithBreak = isLineBreak(text.character(at: end - 1))
        let endsLine = end == text.length || isLineBreak(text.character(at: end))

        let opening = (startsLine ? "" : "\n") + "```" + (detection.language?.fenceName ?? "") + "\n"
        let closing = (endsWithBreak ? "" : "\n") + "```" + (endsLine ? "" : "\n")
        let replacement = opening + pasted + closing
        return TextEdit(
            range: range, replacement: replacement,
            selection: NSRange(location: range.location + replacement.utf16.count, length: 0))
    }

    // MARK: Reading the paste

    /// True when `text` has two lines or more. The line break that ends the last line does not start another: `"a\n"` is
    /// one line, `"a\nb"` and `"a\nb\n"` are two. A line break is a line feed, a carriage return or both together.
    static func hasTwoLines(_ text: String) -> Bool {
        var lines = 0
        var isInLine = false
        var previousWasCarriageReturn = false
        for byte in text.utf8 {
            switch byte {
            case 0x0D:
                lines += 1
                isInLine = false
                previousWasCarriageReturn = true
            case 0x0A:
                if !previousWasCarriageReturn { lines += 1 }
                isInLine = false
                previousWasCarriageReturn = false
            default:
                isInLine = true
                previousWasCarriageReturn = false
            }
            if lines + (isInLine ? 1 : 0) >= 2 { return true }
        }
        return false
    }

    /// True when a line of `text` is a fence line (`FenceScanner`: spaces and three backticks or more).
    static func containsFenceLine(_ text: String) -> Bool {
        guard text.contains("```") else { return false }
        return text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).contains {
            FenceScanner.isFenceLine(String($0))
        }
    }

    /// How many lines that start before `location` are fence lines. An odd number means that the last of them has no
    /// partner above it, and a fence typed below it would be its partner.
    static func fenceLineCount(before location: Int, in text: NSString) -> Int {
        var count = 0
        var searchStart = 0
        let limit = min(max(location, 0), text.length)
        while searchStart < limit {
            let found = text.range(
                of: "```", options: .literal, range: NSRange(location: searchStart, length: limit - searchStart))
            guard found.location != NSNotFound else { break }
            searchStart = found.location + 3
            // A fence line has nothing but spaces in front of its backticks. The other backticks of a line that was
            // counted have backticks (or text) in front of them.
            var index = found.location
            while index > 0, text.character(at: index - 1) == 0x20 { index -= 1 }
            if index == 0 || isLineBreak(text.character(at: index - 1)) { count += 1 }
        }
        return count
    }

    /// True when the paste cuts a CRLF in two: it ends with a carriage return that a line feed follows, or starts with a
    /// line feed that a carriage return precedes.
    private static func splitsCRLF(_ range: NSRange, in text: NSString) -> Bool {
        let end = NSMaxRange(range)
        if end < text.length, text.character(at: end - 1) == 0x0D, text.character(at: end) == 0x0A { return true }
        if range.location > 0, text.character(at: range.location) == 0x0A,
            text.character(at: range.location - 1) == 0x0D
        {
            return true
        }
        return false
    }

    private static func isLineBreak(_ unit: unichar) -> Bool {
        unit == 0x0A || unit == 0x0D
    }
}
