import Foundation

/// A line of a note as the editor shows it outside a fenced block, which is what a sidebar row and a tab show of it
/// (docs/features/sidebar.md). The text itself is never changed: this reads the spans of ``MarkupParser`` and leaves out
/// the characters that the editor hides.
enum PlainLine {
    /// `line` without its markers, which are:
    /// - for a bullet or a checkbox, everything before the text: the indent, the `-` or the `[?]`, and the space after it;
    /// - for bold, the two `**` at each end of the run, and for inline code, the backtick at each end.
    ///
    /// A link and everything the parser does not make a span of stay as typed: `src/**/*.ts` and `x**2` are not bold
    /// (docs/decisions/0006), and `- [ ] a` is a bullet whose text is `[ ] a`. A line that holds only markers (`- `, `[ ] `,
    /// and the empty pair `****` that ⌘B makes) has no text and gives an empty substring.
    ///
    /// `line` is the line as typed, before it is trimmed: the indent that makes a list line is made of spaces, so a line
    /// that a tab indents is plain text. The result is `line` itself when there is nothing to take out, and a substring of
    /// a new string otherwise. It is not trimmed.
    static func text(of line: Substring) -> Substring {
        let units = Array(line.utf16)
        guard MarkupParser.mayHaveSpans(in: units[...]) else { return line }

        var removed = Array(repeating: false, count: units.count)
        var removedCount = 0
        func remove(_ range: NSRange) {
            let lower = max(range.location, 0)
            let upper = min(NSMaxRange(range), units.count)
            guard lower < upper else { return }
            for index in lower..<upper where !removed[index] {
                removed[index] = true
                removedCount += 1
            }
        }
        for span in MarkupParser.parseLine(units: units, at: 0) {
            switch span.kind {
            case .bullet, .checkbox: remove(NSRange(location: 0, length: span.content.location))
            case .bold, .inlineCode: span.markers.forEach(remove)
            case .link: break
            }
        }

        let kept = removedCount == 0 ? units : zip(units, removed).filter { !$0.1 }.map(\.0)
        if isEmptyPair(kept) { return line[line.endIndex...] }
        guard removedCount > 0 else { return line }
        return Substring(String(decoding: kept, as: UTF16.self))
    }

    /// True for `****` with nothing but white space around it: what ⌘B leaves when the caret is in an empty line. It is
    /// not a bold run (a run has at least one character), so the editor shows its four stars, but a title of four stars
    /// is not a title.
    private static func isEmptyPair(_ units: [UInt16]) -> Bool {
        let star: UInt16 = 0x2A
        guard let first = units.firstIndex(where: { !$0.isMarkupWhitespace }),
            let last = units.lastIndex(where: { !$0.isMarkupWhitespace })
        else { return false }
        return last - first == 3 && units[first...last].allSatisfy { $0 == star }
    }
}
