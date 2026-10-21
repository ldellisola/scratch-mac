import Foundation

/// The pieces of a fenced block, found from its range and the text: the name on the opening fence, the lines of code
/// between the fences, and where the fence lines are. All ranges are UTF-16, in the coordinates of the text.
///
/// The range of a block is what `CodeBlockIndex` gives: from the start of the opening fence line to the end of the
/// closing fence line, without its line break.
struct CodeBlockParts: Equatable {
    /// The whole block.
    let range: NSRange
    /// The opening fence line with its line break: the paragraph that carries the block's label.
    let openingParagraph: NSRange
    /// What follows the backticks of the opening fence, trimmed: the language name, or "" when the fence has none.
    let info: String
    /// The lines between the fences, without the line break that ends the last of them. Empty when there are none (two
    /// fences in a row, or one empty line between them): the content of a block is the code that is highlighted.
    let content: NSRange
    /// The closing fence line without its line break.
    let closingLine: NSRange

    /// The parts of the block at `range` in `text`, or nil when `range` is not a block of `text` (it is outside the text,
    /// or it holds no two lines).
    init?(block range: NSRange, in text: NSString) {
        guard range.location >= 0, range.length > 0, NSMaxRange(range) <= text.length else { return nil }
        var openingStart = 0
        var openingEnd = 0
        var openingContentsEnd = 0
        text.getParagraphStart(
            &openingStart, end: &openingEnd, contentsEnd: &openingContentsEnd,
            for: NSRange(location: range.location, length: 0))
        let closingStart = text.paragraphRange(for: NSRange(location: NSMaxRange(range) - 1, length: 0)).location
        guard closingStart >= openingEnd else { return nil }

        self.range = range
        openingParagraph = NSRange(location: openingStart, length: openingEnd - openingStart)
        info = Self.info(
            ofFenceLine: text.substring(
                with: NSRange(location: range.location, length: openingContentsEnd - range.location)))
        closingLine = NSRange(location: closingStart, length: NSMaxRange(range) - closingStart)

        // From the line after the opening fence to the line before the closing one, less the break that ends it.
        var contentEnd = closingStart
        if contentEnd > openingEnd {
            let last = text.character(at: contentEnd - 1)
            contentEnd -= 1
            if last == 0x0A, contentEnd > openingEnd, text.character(at: contentEnd - 1) == 0x0D { contentEnd -= 1 }
        }
        content = NSRange(location: openingEnd, length: max(contentEnd - openingEnd, 0))
    }

    /// The text after the backticks of a fence line, trimmed: `"  ```swift "` is `"swift"`, and a bare fence is `""`.
    /// A fence line is what `FenceScanner` finds: spaces, then three backticks or more.
    static func info(ofFenceLine line: String) -> String {
        var rest = Substring(line)
        rest = rest.drop { $0 == " " }
        rest = rest.drop { $0 == "`" }
        return rest.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
