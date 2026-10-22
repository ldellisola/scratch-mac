import Foundation

/// The whole lines an editing rule is given, with their offsets in the document.
///
/// The text view passes the paragraphs that cover the selection (line breaks included) and the document offset of the
/// first one, never the whole note, so that a keystroke does not copy a 5 MB string. Everything here is UTF-16.
struct ParagraphLines {
    /// The text of the paragraphs.
    let units: [UInt16]
    /// The document offset of `units[0]`.
    let start: Int
    /// The lines of `units`, in offsets of `units`. A text that ends with a line break has an empty last line.
    let lines: [TextLine]

    init(_ paragraphs: String, start: Int) {
        units = Array(paragraphs.utf16)
        self.start = start
        lines = TextLines.lines(in: units)
    }

    // MARK: Lines

    /// The document offset of the first character of line `index`.
    func lineStart(_ index: Int) -> Int {
        start + lines[index].start
    }

    /// The document offset where line `index` ends: its line break begins there, or the text ends.
    func lineEnd(_ index: Int) -> Int {
        start + lines[index].end
    }

    /// The line a caret at document offset `offset` is in, from before its first character to after its last, or nil
    /// when the offset is outside the paragraphs or inside a line break.
    func lineIndex(containing offset: Int) -> Int? {
        let local = offset - start
        return lines.firstIndex { local >= $0.start && local <= $0.end }
    }

    /// The lines `selection` touches. A caret touches its own line. A selection touches the line it starts in and
    /// every line that starts before it ends, so one that ends where a line begins leaves that line out.
    func touchedLines(by selection: NSRange) -> ClosedRange<Int>? {
        guard let first = lineIndex(containing: selection.location) else { return nil }
        var last = first
        if selection.length > 0 {
            let end = NSMaxRange(selection) - start
            while last + 1 < lines.count, lines[last + 1].start < end { last += 1 }
        }
        return first...last
    }

    /// True when the line has nothing but white space in it, or nothing at all.
    func isBlank(_ index: Int) -> Bool {
        units[lines[index].start..<lines[index].end].allSatisfy { $0.isMarkupWhitespace }
    }

    /// True when line `index` is the token line of an attachment and nothing else (`AttachmentToken.id(inLine:)`: the line as
    /// typed, with no white space around it). A rule that edits whole lines leaves such a line alone, or the token would
    /// be text and the picture would be gone.
    func isAttachmentLine(_ index: Int) -> Bool {
        let line = lines[index]
        // Only a line of exactly the length of a token can be one, so never copy a longer line.
        guard line.end - line.start == AttachmentToken.lineLength else { return false }
        return AttachmentToken.id(inLine: text(of: index)) != nil
    }

    /// The text of line `index` without its line break.
    func text(of index: Int) -> String {
        String(decoding: units[lines[index].start..<lines[index].end], as: UTF16.self)
    }

    /// The text of the document range `range`, which lies inside the paragraphs.
    func string(in range: NSRange) -> String {
        String(decoding: units[(range.location - start)..<(NSMaxRange(range) - start)], as: UTF16.self)
    }

    // MARK: List items

    /// The bullet or checkbox that line `index` is, or nil.
    func listItem(at index: Int) -> ListItem? {
        let spans = MarkupParser.parseLine(text(of: index), at: lineStart(index))
        for span in spans {
            switch span.kind {
            case .bullet(let level):
                return ListItem(span: span, level: level, isCheckbox: false)
            case .checkbox(_, let level):
                return ListItem(span: span, level: level, isCheckbox: true)
            default:
                continue
            }
        }
        return nil
    }

    // MARK: Changes

    /// One edit of the text of a line, in document offsets.
    struct Change {
        let location: Int
        let removed: Int
        let inserted: [UInt16]
    }

    /// One `TextEdit` for all of `changes` (in document offsets, ascending, not overlapping), and the selection moved
    /// with the text. The edit replaces the text from the first change to the end of the last one, so lines outside
    /// them are not part of it. With no changes the edit replaces nothing with nothing and keeps the selection.
    func edit(applying changes: [Change], selection: NSRange) -> TextEdit {
        guard let first = changes.first, let last = changes.last else {
            return TextEdit(
                range: NSRange(location: selection.location, length: 0), replacement: "", selection: selection)
        }
        let from = first.location
        let to = last.location + last.removed
        var result: [UInt16] = []
        var cursor = from
        for change in changes {
            result.append(contentsOf: units[(cursor - start)..<(change.location - start)])
            result.append(contentsOf: change.inserted)
            cursor = change.location + change.removed
        }
        result.append(contentsOf: units[(cursor - start)..<(to - start)])

        let newStart = Self.offset(selection.location, after: changes, isSelectionEnd: false)
        let newSelection: NSRange
        if selection.length == 0 {
            newSelection = NSRange(location: newStart, length: 0)
        } else {
            let newEnd = Self.offset(NSMaxRange(selection), after: changes, isSelectionEnd: true)
            newSelection = NSRange(location: newStart, length: max(newEnd - newStart, 0))
        }
        return TextEdit(
            range: NSRange(location: from, length: to - from),
            replacement: String(decoding: result, as: UTF16.self),
            selection: newSelection)
    }

    /// Where the document offset `offset` is once `changes` are applied.
    ///
    /// - An offset before a change does not move, and one after it moves by the change's growth.
    /// - An offset inside text a change removes goes to the end of what replaces it (to its start when nothing does).
    /// - An offset at the start of removed text stays at the start.
    /// - An offset exactly at an insertion moves behind it, so a caret there ends up after the inserted text. The end
    ///   of a selection does not: it stays in front of the text inserted where it ends.
    static func offset(_ offset: Int, after changes: [Change], isSelectionEnd: Bool) -> Int {
        var delta = 0
        for change in changes {
            if change.removed == 0 {
                if offset < change.location || (offset == change.location && isSelectionEnd) { break }
                delta += change.inserted.count
                continue
            }
            if offset <= change.location { break }
            if offset < change.location + change.removed { return change.location + delta + change.inserted.count }
            delta += change.inserted.count - change.removed
        }
        return offset + delta
    }
}

/// A line that is a bullet or a checkbox.
struct ListItem {
    let span: MarkupSpan
    /// Leading spaces divided by two.
    let level: Int
    let isCheckbox: Bool

    /// The `-` of a bullet, or the `[?]` of a checkbox.
    var marker: NSRange { span.markers[0] }
    /// What follows the marker's space.
    var content: NSRange { span.content }
}

extension ParagraphLines {
    /// The document offset of the first character of line `index` that is not a space: where a marker goes after the
    /// indentation.
    func firstNonSpace(of index: Int) -> Int {
        let line = lines[index]
        var cursor = line.start
        while cursor < line.end, units[cursor] == 0x20 { cursor += 1 }
        return start + cursor
    }
}
