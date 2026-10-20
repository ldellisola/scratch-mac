import Foundation

/// A line of a text, in UTF-16 offsets.
struct TextLine: Equatable {
    /// Where the line's first character is.
    let start: Int
    /// Where its line break begins, or the end of the text: `start..<end` is the line without its break.
    let end: Int
    /// Where the next line starts: `end` plus the length of the break, and `end` for the last line.
    let next: Int
}

/// Line splitting for the markup rules.
///
/// A line ends at `\n`, `\r\n` or `\r` (AGENTS.md: Swift treats `"\r\n"` as one `Character`, so the scan is over UTF-16
/// units, as `NSTextStorage` counts). A text that ends with a break has an empty last line, as `split` with
/// `omittingEmptySubsequences: false` would give.
enum TextLines {
    static func lines(in units: [UInt16]) -> [TextLine] {
        let lineFeed: UInt16 = 0x0A
        let carriageReturn: UInt16 = 0x0D
        var lines: [TextLine] = []
        var start = 0
        var index = 0
        while index < units.count {
            let unit = units[index]
            guard unit == lineFeed || unit == carriageReturn else {
                index += 1
                continue
            }
            let isCRLF = unit == carriageReturn && index + 1 < units.count && units[index + 1] == lineFeed
            let next = index + (isCRLF ? 2 : 1)
            lines.append(TextLine(start: start, end: index, next: next))
            start = next
            index = next
        }
        lines.append(TextLine(start: start, end: units.count, next: units.count))
        return lines
    }
}

extension UInt16 {
    /// True for a UTF-16 unit that is a Unicode white space character. A surrogate never is.
    var isMarkupWhitespace: Bool {
        if self < 0x80 {
            return self == 0x20 || (0x09...0x0D).contains(self)
        }
        return Unicode.Scalar(self)?.properties.isWhitespace ?? false
    }
}
