import Foundation

/// Finds `http://` and `https://` links in one line (spec §6.4, Plan 3's marker table).
public enum LinkScanner {
    /// The links of `line`, whose first character is at UTF-16 offset `lineStart` of the document, in order.
    ///
    /// A link is the scheme (in any case) followed by at least one character that is not white space, up to the next
    /// white space. A link ends before trailing `.,;:!?'"` and before a trailing `)` that has no `(` to close [call].
    /// `https://example.com/a_(b)` keeps its `)`, and `(see https://x.io)` loses it.
    ///
    /// `excluding` is a list of document ranges the scan treats as blanks: no link starts inside one and a link ends
    /// where one begins. The parser passes inline code, where every character is literal, and the `**` of a bold run,
    /// which would otherwise be read as part of the URL.
    public static func links(in line: String, at lineStart: Int, excluding: [NSRange]) -> [MarkupSpan] {
        let local = excluding.map { ($0.location - lineStart)..<(NSMaxRange($0) - lineStart) }
        return links(in: Array(line.utf16), at: lineStart, excluding: local, from: 0)
    }

    /// `excluding` is in offsets of `units`. Nothing before `start` is looked at.
    static func links(in units: [UInt16], at lineStart: Int, excluding: [Range<Int>], from start: Int) -> [MarkupSpan] {
        var masked = units
        for range in excluding {
            let lower = max(range.lowerBound, 0)
            let upper = min(range.upperBound, masked.count)
            if lower < upper { masked.replaceSubrange(lower..<upper, with: repeatElement(space, count: upper - lower)) }
        }

        var spans: [MarkupSpan] = []
        var index = start
        while index < masked.count {
            guard let schemeLength = schemeLength(in: masked, at: index) else {
                index += 1
                continue
            }
            let bodyStart = index + schemeLength
            var runEnd = bodyStart
            while runEnd < masked.count, !masked[runEnd].isMarkupWhitespace { runEnd += 1 }
            let end = trimmedEnd(of: masked, from: bodyStart, to: runEnd)
            if end > bodyStart, let url = URL(string: String(decoding: units[index..<end], as: UTF16.self)) {
                let range = NSRange(location: lineStart + index, length: end - index)
                spans.append(MarkupSpan(kind: .link(url), range: range, markers: [], content: range))
            }
            // Whatever the run held after a link or a scheme with nothing behind it cannot start another link.
            index = runEnd
        }
        return spans
    }

    // MARK: The scan

    private static let space: UInt16 = 0x20
    private static let http = Array("http".utf16)
    private static let separator = Array("://".utf16)
    private static let secure: UInt16 = 0x73  // "s"
    private static let trailingPunctuation = Set(".,;:!?'\"".utf16)
    private static let openParen: UInt16 = 0x28
    private static let closeParen: UInt16 = 0x29

    /// The length of `http://` or `https://` at `index`, or nil.
    private static func schemeLength(in units: [UInt16], at index: Int) -> Int? {
        var cursor = index
        guard consume(http, in: units, at: &cursor) else { return nil }
        if cursor < units.count, lowered(units[cursor]) == secure { cursor += 1 }
        guard consume(separator, in: units, at: &cursor) else { return nil }
        return cursor - index
    }

    private static func consume(_ expected: [UInt16], in units: [UInt16], at cursor: inout Int) -> Bool {
        guard cursor + expected.count <= units.count else { return false }
        for (offset, unit) in expected.enumerated() where lowered(units[cursor + offset]) != unit { return false }
        cursor += expected.count
        return true
    }

    private static func lowered(_ unit: UInt16) -> UInt16 {
        (0x41...0x5A).contains(unit) ? unit + 0x20 : unit
    }

    /// Where the link in `units[start..<end]` ends once its trailing punctuation and unmatched `)` are dropped.
    private static func trimmedEnd(of units: [UInt16], from start: Int, to end: Int) -> Int {
        var end = end
        var unclosed = 0
        for unit in units[start..<end] {
            if unit == openParen { unclosed += 1 } else if unit == closeParen { unclosed -= 1 }
        }
        while end > start {
            let last = units[end - 1]
            if trailingPunctuation.contains(last) {
                end -= 1
            } else if last == closeParen, unclosed < 0 {
                unclosed += 1
                end -= 1
            } else {
                break
            }
        }
        return end
    }
}
