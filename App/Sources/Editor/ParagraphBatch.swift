import AppKit
import ScratchCore

/// A run of whole paragraphs of the editor's text, read in one go.
///
/// The styler walks a note by paragraph. Asking the text storage for each paragraph's characters one at a time is slow
/// in a note of 10,000 lines, so a batch finds the paragraphs with `paragraphRange(for:)` and then copies all of their
/// UTF-16 units with one call. All ranges are in the document's coordinates.
struct ParagraphBatch {
    /// Each paragraph, with its line break.
    let paragraphs: [NSRange]
    /// From the start of the first paragraph to the end of the last. Empty when the batch has no paragraph.
    let range: NSRange
    /// The units of `range`.
    private let units: [UInt16]

    /// The paragraphs that start in `start..<end`, at most `maxParagraphs` of them, beginning with the paragraph that
    /// holds `start`. A batch with a `deadline` stops at the first paragraph after it (the clock is read every 32
    /// paragraphs). The last, empty paragraph of a text that ends with a line break is not a paragraph here.
    init(
        in text: NSString, from start: Int, upTo end: Int, maxParagraphs: Int, deadline: ContinuousClock.Instant? = nil
    ) {
        let length = text.length
        var cursor = min(max(start, 0), length)
        if cursor < length { cursor = text.paragraphRange(for: NSRange(location: cursor, length: 0)).location }
        let first = cursor
        let limit = min(end, length)
        var found: [NSRange] = []
        while cursor < limit, found.count < maxParagraphs {
            let paragraph = text.paragraphRange(for: NSRange(location: cursor, length: 0))
            guard paragraph.length > 0 else { break }
            found.append(paragraph)
            cursor = NSMaxRange(paragraph)
            if let deadline, found.count % 32 == 0, ContinuousClock.now >= deadline { break }
        }

        let covered = NSRange(location: first, length: cursor - first)
        var buffer = [UInt16](repeating: 0, count: covered.length)
        if covered.length > 0 {
            buffer.withUnsafeMutableBufferPointer { pointer in
                text.getCharacters(pointer.baseAddress!, range: covered)
            }
        }
        paragraphs = found
        range = covered
        units = buffer
    }

    /// The units of paragraph `index` without its line break.
    func line(at index: Int) -> ArraySlice<UInt16> {
        let paragraph = paragraphs[index]
        let start = paragraph.location - range.location
        var end = start + paragraph.length
        while end > start, Self.isLineBreak(units[end - 1]) { end -= 1 }
        return units[start..<end]
    }

    /// True when some line of the batch is a fence line (`FenceScanner.isFenceLine`). Only a line with three backticks in
    /// a row is looked at closely.
    func containsFenceLine() -> Bool {
        paragraphs.indices.contains { index in
            let content = line(at: index)
            return Self.hasThreeBackticks(content)
                && FenceScanner.isFenceLine(String(decoding: content, as: UTF16.self))
        }
    }

    // MARK: Units

    /// What ends a paragraph for `NSString.paragraphRange(for:)`: a line feed, a carriage return, the paragraph
    /// separator and the next line character.
    private static func isLineBreak(_ unit: UInt16) -> Bool {
        unit == 0x0A || unit == 0x0D || unit == 0x2029 || unit == 0x85
    }

    private static func hasThreeBackticks(_ line: ArraySlice<UInt16>) -> Bool {
        var run = 0
        for unit in line {
            run = unit == 0x60 ? run + 1 : 0
            if run == 3 { return true }
        }
        return false
    }
}
