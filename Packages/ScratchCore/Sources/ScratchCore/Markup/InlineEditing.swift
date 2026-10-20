import Foundation

/// What ⌘B does to the text (spec §6.4: bold is typed as `**text**`, or selected and ⌘B).
public enum InlineEditing {
    /// ⌘B. `paragraphs` is the text of the whole lines that cover `selection` (line breaks included) and `start` is
    /// the document offset of the first one, in UTF-16 units. A caller checks that the selection is not in a code block.
    ///
    /// - A selection that is exactly the content of a bold run, or a whole run with its `**`, loses the markers. The
    ///   selection then covers the content.
    /// - Any other selection is wrapped in `**`, and the selection covers the content. White space at its ends
    ///   (a triple click takes the line break too) stays outside the stars, because a run that starts or ends with
    ///   white space is not bold [call]. A selection of only white space is wrapped as it is.
    /// - No selection: `****` goes in and the caret between the pairs.
    public static func toggleBold(paragraphs: String, start: Int, selection: NSRange) -> TextEdit {
        let pairs = "**"
        let width = pairs.utf16.count
        let insertion = TextEdit(
            range: NSRange(location: selection.location, length: 0), replacement: pairs + pairs,
            selection: NSRange(location: selection.location + width, length: 0))
        guard selection.length > 0 else { return insertion }

        let text = ParagraphLines(paragraphs, start: start)
        var lower = max(selection.location, start)
        var upper = min(NSMaxRange(selection), start + text.units.count)
        guard lower < upper else { return insertion }
        let wholeSelection = NSRange(location: lower, length: upper - lower)

        while lower < upper, text.units[lower - start].isMarkupWhitespace { lower += 1 }
        while upper > lower, text.units[upper - 1 - start].isMarkupWhitespace { upper -= 1 }
        let target = lower < upper ? NSRange(location: lower, length: upper - lower) : wholeSelection

        if let run = boldRun(in: text, matching: target) {
            return TextEdit(
                range: run.range, replacement: text.string(in: run.content),
                selection: NSRange(location: run.range.location, length: run.content.length))
        }
        return TextEdit(
            range: target, replacement: pairs + text.string(in: target) + pairs,
            selection: NSRange(location: target.location + width, length: target.length))
    }

    /// The bold run whose content, or whose content and markers, are exactly `target`.
    private static func boldRun(in text: ParagraphLines, matching target: NSRange) -> MarkupSpan? {
        for index in text.lines.indices {
            // A line that ends before `target` starts, or starts after it ends, holds no run that is `target`.
            if text.lineEnd(index) < target.location || text.lineStart(index) > NSMaxRange(target) { continue }
            for span in MarkupParser.parseLine(text.text(of: index), at: text.lineStart(index)) {
                guard case .bold = span.kind else { continue }
                if span.content == target || span.range == target { return span }
            }
        }
        return nil
    }
}
