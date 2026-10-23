import Foundation

/// What ⌘B does to the text (spec §6.4: bold is typed as `**text**`, or selected and ⌘B).
public enum InlineEditing {
    private static let pairs = "**"
    private static let width = 2
    private static let star: UInt16 = 0x2A

    /// ⌘B. `paragraphs` is the text of the whole lines that cover `selection` (line breaks included) and `start` is
    /// the document offset of the first one, in UTF-16 units. A caller checks that the selection is not in a code block.
    /// Nil means that there is nothing for ⌘B to do and the key beeps.
    ///
    /// **A caret** (no selection):
    /// - In a bold run, or touching one (its content, or right outside either pair of stars): the run loses its stars, and
    ///   the caret stays at its place in the text.
    /// - Between the two pairs of an empty `****`: all four stars go.
    /// - In a word, or at either edge of one: the word is wrapped, and the caret stays at its place in the word. A word is
    ///   a run of letters and digits of any script, and an apostrophe between two of them (`don't`). A caret in the marker
    ///   of a list item (`- `, `[ ] `) acts at the start of the text after it, so the stars never go into the marker.
    /// - Anywhere else: `****` goes in and the caret between the pairs, so what is typed next is bold.
    ///
    /// **A selection of one line:**
    /// - The selection is clipped to the text after the list marker, and white space at its ends (a triple click takes
    ///   the line break too) stays outside the stars, because a run that starts or ends with white space is not bold
    ///   [call].
    /// - A selection that is exactly the content of a bold run, or a whole run with its `**`, or anything between those
    ///   two, loses the markers. The selection then covers the content.
    /// - Any other selection is wrapped in `**`, and the selection covers the content.
    /// - A selection that holds only white space (or a list marker) is nil.
    ///
    /// **A selection of several lines:** each line's part of the selection is its own run [call, plan 6]: after its list
    /// marker, white space at its ends left out, a blank line skipped. When every one of those parts is a bold run, the
    /// runs lose their stars, else the parts that are not a run yet are wrapped (as ⇧⌘L gives boxes to the lines that have
    /// none). The selection then covers the content from the first line's to the last line's. Nil when no line has text.
    public static func toggleBold(paragraphs: String, start: Int, selection: NSRange) -> TextEdit? {
        let text = ParagraphLines(paragraphs, start: start)
        guard selection.length > 0 else { return toggleBold(atCaret: selection.location, in: text) }
        guard let touched = text.touchedLines(by: selection) else { return nil }

        let parts: [(line: Int, range: NSRange)] = touched.compactMap { line in
            part(ofLine: line, in: selection, of: text).map { (line, $0) }
        }
        guard let first = parts.first, let last = parts.last else { return nil }

        if touched.count == 1 {
            if let run = run(onLine: first.line, covering: first.range, in: text) {
                return TextEdit(
                    range: run.range, replacement: text.string(in: run.content),
                    selection: NSRange(location: run.range.location, length: run.content.length))
            }
            return TextEdit(
                range: first.range, replacement: pairs + text.string(in: first.range) + pairs,
                selection: NSRange(location: first.range.location + width, length: first.range.length))
        }

        let runs = parts.map { run(onLine: $0.line, covering: $0.range, in: text) }
        let changes: [ParagraphLines.Change]
        if runs.allSatisfy({ $0 != nil }) {
            changes = runs.compactMap { $0 }.flatMap { run in
                run.markers.map { ParagraphLines.Change(location: $0.location, removed: $0.length, inserted: []) }
            }
        } else {
            changes = zip(parts, runs).filter { $0.1 == nil }.flatMap { part, _ in
                [
                    ParagraphLines.Change(location: part.range.location, removed: 0, inserted: Array(pairs.utf16)),
                    ParagraphLines.Change(location: NSMaxRange(part.range), removed: 0, inserted: Array(pairs.utf16)),
                ]
            }
        }
        let covered = NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
        return text.edit(applying: changes, selection: covered)
    }

    // MARK: A caret

    private static func toggleBold(atCaret caret: Int, in text: ParagraphLines) -> TextEdit? {
        guard let index = text.lineIndex(containing: caret) else { return nil }
        let lineStart = text.lineStart(index)
        let lineEnd = text.lineEnd(index)
        let spans = MarkupParser.parseLine(text.text(of: index), at: lineStart)

        // In a run, or touching one: it loses its stars.
        for span in spans {
            guard case .bold = span.kind, caret >= span.range.location, caret <= NSMaxRange(span.range) else {
                continue
            }
            let offset = min(max(caret - span.content.location, 0), span.content.length)
            return TextEdit(
                range: span.range, replacement: text.string(in: span.content),
                selection: NSRange(location: span.range.location + offset, length: 0))
        }

        // Between the pairs of an empty `****`: all four go.
        if caret - 2 >= lineStart, caret + 2 <= lineEnd {
            let local = caret - text.start
            if text.units[local - 2] == star, text.units[local - 1] == star, text.units[local] == star,
                text.units[local + 1] == star
            {
                return TextEdit(
                    range: NSRange(location: caret - 2, length: 4), replacement: "",
                    selection: NSRange(location: caret - 2, length: 0))
            }
        }

        // The stars never go into the marker of a list item: a caret there acts at the start of the text after it.
        let contentStart = spans.first { span in
            switch span.kind {
            case .bullet, .checkbox: return true
            default: return false
            }
        }?.content.location
        let position = min(max(caret, contentStart ?? lineStart), lineEnd)

        if let word = word(around: position, in: text, from: contentStart ?? lineStart, to: lineEnd) {
            return TextEdit(
                range: word, replacement: pairs + text.string(in: word) + pairs,
                selection: NSRange(location: position + width, length: 0))
        }
        return TextEdit(
            range: NSRange(location: position, length: 0), replacement: pairs + pairs,
            selection: NSRange(location: position + width, length: 0))
    }

    /// The word that a caret at document offset `position` is in or at the edge of, within `from..<to` (the text of one
    /// line, after its list marker), or nil when there is none. When the caret is between a word and something else it is
    /// the word's, and between two words (it cannot be: a space is no word) it would be the one that it is in.
    private static func word(around position: Int, in text: ParagraphLines, from: Int, to: Int) -> NSRange? {
        guard from < to, position >= from, position <= to else { return nil }
        let line = String(decoding: text.units[(from - text.start)..<(to - text.start)], as: UTF16.self)
        let caret = String.Index(utf16Offset: position - from, in: line)

        var lower = caret
        while lower > line.startIndex, isWordCharacter(at: line.index(before: lower), in: line) {
            lower = line.index(before: lower)
        }
        var upper = caret
        while upper < line.endIndex, isWordCharacter(at: upper, in: line) {
            upper = line.index(after: upper)
        }
        guard lower < upper else { return nil }
        let location = from + line.utf16.distance(from: line.startIndex, to: lower)
        return NSRange(location: location, length: line.utf16.distance(from: lower, to: upper))
    }

    /// A letter or a digit of any script, or an apostrophe with one on each side (`don't`, `rock'n'roll`). An apostrophe at
    /// the edge of a word is a quotation mark.
    private static func isWordCharacter(at index: String.Index, in line: String) -> Bool {
        let character = line[index]
        if isLetterOrDigit(character) { return true }
        guard character == "'" || character == "\u{2019}", index > line.startIndex else { return false }
        let next = line.index(after: index)
        return next < line.endIndex && isLetterOrDigit(line[line.index(before: index)]) && isLetterOrDigit(line[next])
    }

    private static func isLetterOrDigit(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    // MARK: A selection

    /// What ⌘B works on in line `line`: the part of `selection` that is in it, after the list marker, without white
    /// space at its ends. Nil when nothing is left.
    private static func part(ofLine line: Int, in selection: NSRange, of text: ParagraphLines) -> NSRange? {
        let contentStart = text.listItem(at: line)?.content.location ?? text.lineStart(line)
        var lower = max(selection.location, contentStart)
        var upper = min(NSMaxRange(selection), text.lineEnd(line))
        while lower < upper, text.units[lower - text.start].isMarkupWhitespace { lower += 1 }
        while upper > lower, text.units[upper - 1 - text.start].isMarkupWhitespace { upper -= 1 }
        return lower < upper ? NSRange(location: lower, length: upper - lower) : nil
    }

    /// The bold run on line `line` that `target` covers: all of its content, and nothing outside its stars. So a selection
    /// that is the content, the whole run, or the content and one of the pairs (what ⌘B leaves selected, for several
    /// lines) takes that run's stars away, and a selection inside the content is wrapped like any other.
    private static func run(onLine line: Int, covering target: NSRange, in text: ParagraphLines) -> MarkupSpan? {
        for span in MarkupParser.parseLine(text.text(of: line), at: text.lineStart(line)) {
            guard case .bold = span.kind else { continue }
            if target.location <= span.content.location, NSMaxRange(target) >= NSMaxRange(span.content),
                target.location >= span.range.location, NSMaxRange(target) <= NSMaxRange(span.range)
            {
                return span
            }
        }
        return nil
    }

    // MARK: Attachments

    /// True when `selection` touches the token line of an attachment (``AttachmentToken/lineRanges(in:within:)``): it
    /// holds a character of one (a click on an attachment selects exactly that), or it is a caret on one, at the start
    /// or the end of the line too, where a click beside a chip puts it. `paragraphs` and `start` are as for
    /// ``toggleBold(paragraphs:start:selection:)``.
    ///
    /// ⌘B must not change the text then: `**[[attachment:…]]**` is no token, the picture would be gone, and `****` on the
    /// token's line does the same. A caller beeps and leaves the text alone. A selection that ends where a token line
    /// starts, or starts where one ends, holds none of it.
    public static func touchesAttachment(paragraphs: String, start: Int, selection: NSRange) -> Bool {
        let local = NSRange(location: selection.location - start, length: selection.length)
        return !AttachmentToken.lineRanges(in: NSString(string: paragraphs), within: local).isEmpty
    }
}
