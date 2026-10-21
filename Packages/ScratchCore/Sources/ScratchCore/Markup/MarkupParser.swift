import Foundation

/// Turns a note's text into the spans the editor renders (spec §6.4).
///
/// The parser reads text and never changes it. Every rule here is a plain-text marker, so copy, search and storage
/// need none of it. All offsets are UTF-16, as `NSTextStorage` counts.
public enum MarkupParser {
    /// The spans of one line, which has no line break and whose first character is at UTF-16 offset `lineStart` of the
    /// document, ordered by `range.location`.
    ///
    /// A list marker comes first when the line has one: `- ` is a bullet and `[ ] `, `[x] ` and `[X] ` are checkboxes,
    /// after spaces that give the level (two spaces each). `- [ ] a` is a bullet, not a checkbox [call]. The rest of
    /// the line is scanned for inline code first, then bold outside code, then links outside code and outside the `**`
    /// of bold runs. A bold run may contain inline code, and nothing inside inline code is anything else.
    ///
    /// This does not know about fenced blocks: a caller that has a whole note skips the lines in
    /// ``FenceScanner/codeBlocks(in:)`` itself, or calls ``parse(_:)``.
    public static func parseLine(_ line: String, at lineStart: Int) -> [MarkupSpan] {
        parseLine(units: Array(line.utf16), at: lineStart)
    }

    /// The spans of every line of `text` that is outside a fenced code block, ordered by `range.location`.
    public static func parse(_ text: String) -> [MarkupSpan] {
        let units = Array(text.utf16)
        let lines = TextLines.lines(in: units)
        let blocks = FenceScanner.codeBlocks(units: units, lines: lines)
        var spans: [MarkupSpan] = []
        var nextBlock = 0
        for line in lines {
            while nextBlock < blocks.count, NSMaxRange(blocks[nextBlock]) <= line.start { nextBlock += 1 }
            if nextBlock < blocks.count, blocks[nextBlock].location <= line.start { continue }
            spans.append(contentsOf: parseLine(units: Array(units[line.start..<line.end]), at: line.start))
        }
        return spans
    }

    // MARK: One line

    private static func parseLine(units: [UInt16], at lineStart: Int) -> [MarkupSpan] {
        var spans: [MarkupSpan] = []
        var inlineStart = 0
        if let list = listSpan(in: units, at: lineStart) {
            spans.append(list)
            inlineStart = list.content.location - lineStart
        }

        let code = codeRuns(in: units, from: inlineStart)
        let bold = boldRuns(in: units, from: inlineStart, outside: code)
        let literal = code + bold.flatMap { [$0.open..<($0.open + 2), $0.close..<($0.close + 2)] }
        for run in code {
            let range = NSRange(location: lineStart + run.lowerBound, length: run.count)
            spans.append(
                MarkupSpan(
                    kind: .inlineCode, range: range,
                    markers: [
                        NSRange(location: range.location, length: 1),
                        NSRange(location: NSMaxRange(range) - 1, length: 1),
                    ],
                    content: NSRange(location: range.location + 1, length: range.length - 2)))
        }
        for run in bold {
            let range = NSRange(location: lineStart + run.open, length: run.close + 2 - run.open)
            spans.append(
                MarkupSpan(
                    kind: .bold, range: range,
                    markers: [
                        NSRange(location: lineStart + run.open, length: 2),
                        NSRange(location: lineStart + run.close, length: 2),
                    ],
                    content: NSRange(location: range.location + 2, length: range.length - 4)))
        }
        spans.append(contentsOf: LinkScanner.links(in: units, at: lineStart, excluding: literal, from: inlineStart))
        spans.sort { $0.range.location < $1.range.location }
        return spans
    }

    // MARK: Lists

    private static let space: UInt16 = 0x20
    private static let dash: UInt16 = 0x2D
    private static let star: UInt16 = 0x2A
    private static let backtick: UInt16 = 0x60
    private static let openBracket: UInt16 = 0x5B
    private static let closeBracket: UInt16 = 0x5D
    private static let lowerX: UInt16 = 0x78
    private static let upperX: UInt16 = 0x58

    /// The bullet or checkbox span of the line, or nil. The indent is spaces only, two per level.
    private static func listSpan(in units: [UInt16], at lineStart: Int) -> MarkupSpan? {
        var indent = 0
        while indent < units.count, units[indent] == space { indent += 1 }
        let level = indent / 2
        let lineRange = NSRange(location: lineStart, length: units.count)

        if indent + 1 < units.count, units[indent] == dash, units[indent + 1] == space {
            return MarkupSpan(
                kind: .bullet(level: level), range: lineRange,
                markers: [NSRange(location: lineStart + indent, length: 1)],
                content: NSRange(location: lineStart + indent + 2, length: units.count - indent - 2))
        }

        guard indent + 3 < units.count, units[indent] == openBracket, units[indent + 2] == closeBracket,
            units[indent + 3] == space
        else { return nil }
        let mark = units[indent + 1]
        guard mark == space || mark == lowerX || mark == upperX else { return nil }
        return MarkupSpan(
            kind: .checkbox(checked: mark != space, level: level), range: lineRange,
            markers: [NSRange(location: lineStart + indent, length: 3)],
            content: NSRange(location: lineStart + indent + 4, length: units.count - indent - 4))
    }

    // MARK: Inline code

    /// A backtick, at least one character that is not a backtick, and a backtick, left to right and not overlapping.
    /// Each run is in offsets of `units` and includes its two backticks.
    private static func codeRuns(in units: [UInt16], from start: Int) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var index = start
        while index < units.count {
            guard units[index] == backtick else {
                index += 1
                continue
            }
            var closing = index + 1
            while closing < units.count, units[closing] != backtick { closing += 1 }
            // No backtick after this one means no later backtick can open a run either.
            guard closing < units.count else { break }
            if closing > index + 1 {
                runs.append(index..<(closing + 1))
                index = closing + 1
            } else {
                // Two backticks in a row: the second may open a run.
                index = closing
            }
        }
        return runs
    }

    // MARK: Bold

    /// `**`, content, `**`. The content is at least one character, contains no `**` outside inline code, and neither
    /// starts nor ends with white space. Inline code is skipped when looking for stars, so a run may hold code and
    /// code may hold stars. The stars need word boundaries (``opens(_:at:)``, ``closes(_:at:)``), so `x**2 + y**2` and
    /// `src/**/*.ts` are plain text. `open` and `close` are the offsets of the two `**`.
    private static func boldRuns(
        in units: [UInt16], from start: Int, outside code: [Range<Int>]
    ) -> [(open: Int, close: Int)] {
        // Inline code becomes backticks: no stars, and not white space at the edge of a run.
        var masked = units
        for run in code { masked.replaceSubrange(run, with: repeatElement(backtick, count: run.count)) }

        var runs: [(open: Int, close: Int)] = []
        var index = start
        while index + 1 < masked.count {
            guard isStarPair(masked, at: index), opens(masked, at: index) else {
                index += 1
                continue
            }
            let contentStart = index + 2
            guard contentStart < masked.count, !masked[contentStart].isMarkupWhitespace else {
                index += 1
                continue
            }
            var close = contentStart
            while close + 1 < masked.count, !isStarPair(masked, at: close) { close += 1 }
            if close + 1 < masked.count, close > contentStart, !masked[close - 1].isMarkupWhitespace,
                closes(masked, at: close)
            {
                runs.append((open: index, close: close))
                index = close + 2
            } else {
                index += 1
            }
        }
        return runs
    }

    private static func isStarPair(_ units: [UInt16], at index: Int) -> Bool {
        units[index] == star && units[index + 1] == star
    }

    // MARK: Word boundaries

    /// What stands next to a pair of stars.
    private enum Neighbour {
        /// The start or the end of the line.
        case lineEdge
        case whiteSpace
        /// `Character.isLetter` or `isNumber`, in any script.
        case letterOrDigit
        /// Anything else: punctuation, symbols, emoji, and the backticks that stand for inline code.
        case other
    }

    /// The `**` at `index` may open a run. The character before it is the line start or not a letter or a digit, so
    /// `x**2` is not bold. And the stars do not sit between two punctuation marks (`src/**/*.ts`, `(a)**(b)`): that is a
    /// glob or an operator [owner, 2026-10-21, with the second rule a [call]: see docs/decisions/0006].
    private static func opens(_ units: [UInt16], at index: Int) -> Bool {
        let outside = neighbour(before: index, in: units)
        guard outside != .letterOrDigit else { return false }
        return !(outside == .other && neighbour(at: index + 2, in: units) == .other)
    }

    /// The `**` at `index` may close a run: the same rule, mirrored. The character after it is the line end or not a
    /// letter or a digit, and the stars do not sit between two punctuation marks.
    private static func closes(_ units: [UInt16], at index: Int) -> Bool {
        let outside = neighbour(at: index + 2, in: units)
        guard outside != .letterOrDigit else { return false }
        return !(outside == .other && neighbour(before: index, in: units) == .other)
    }

    /// The character that ends `units[..<index]`, which is a whole grapheme cluster (`é` written as `e` and an accent
    /// is a letter). A window of a few dozen units holds it: a cluster longer than that is not made of letters.
    private static func neighbour(before index: Int, in units: [UInt16]) -> Neighbour {
        guard index > 0 else { return .lineEdge }
        var from = max(0, index - window)
        if from > 0, UTF16.isTrailSurrogate(units[from]) { from -= 1 }
        return classify(String(decoding: units[from..<index], as: UTF16.self).last)
    }

    /// The character that starts `units[index...]`.
    private static func neighbour(at index: Int, in units: [UInt16]) -> Neighbour {
        guard index < units.count else { return .lineEdge }
        var to = min(units.count, index + window)
        if to < units.count, UTF16.isLeadSurrogate(units[to - 1]) { to += 1 }
        return classify(String(decoding: units[index..<to], as: UTF16.self).first)
    }

    private static let window = 32

    private static func classify(_ character: Character?) -> Neighbour {
        guard let character else { return .lineEdge }
        if character.isWhitespace { return .whiteSpace }
        if character.isLetter || character.isNumber { return .letterOrDigit }
        return .other
    }
}
