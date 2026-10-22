import Foundation

/// The line of plain text that stands for an attachment in a note: `[[attachment:<id>]]` (spec §6.4).
///
/// The stored note stays plain text, like every other marker. A line is a token only when it is exactly the token: the
/// brackets and the word `attachment`, a lowercase UUID, and nothing else on the line, not even a space. A line that
/// holds anything more is text. Lines end at `\n`, `\r\n` or `\r`, as everywhere in the markup rules.
///
/// Fenced code blocks do not matter here. A token inside a block is still a token to ``ids(in:)``, because counting
/// one as a reference can only ever keep a file, which is the safe side of "never lose an attachment".
public enum AttachmentToken {
    private static let prefix = Array("[[attachment:".utf8)
    private static let suffix = Array("]]".utf8)
    private static let idLength = 36
    private static let lineLength = 13 + 36 + 2

    /// The line that stands for `id`, without a line break.
    public static func line(for id: AttachmentID) -> String {
        "[[attachment:\(id.rawValue)]]"
    }

    /// The id of an attachment when `line` is a token and nothing else, or nil. `line` has no line break.
    public static func id(inLine line: some StringProtocol) -> AttachmentID? {
        // Only a line of exactly the length of a token can be one, so never copy more than that.
        let bytes = Array(line.utf8.prefix(lineLength + 1))
        guard bytes.count == lineLength else { return nil }
        return parse(bytes)
    }

    /// The ids of the tokens in `text`, in order, with duplicates kept.
    public static func ids(in text: String) -> [AttachmentID] {
        let lineFeed: UInt8 = 0x0A
        let carriageReturn: UInt8 = 0x0D
        var text = text
        return text.withUTF8 { bytes in
            var found: [AttachmentID] = []
            var start = 0
            while start < bytes.count {
                var end = start
                while end < bytes.count, bytes[end] != lineFeed, bytes[end] != carriageReturn { end += 1 }
                if end - start == lineLength, let id = parse(UnsafeBufferPointer(rebasing: bytes[start..<end])) {
                    found.append(id)
                }
                guard end < bytes.count else { break }
                start = end + 1
                // "\r\n" is one line break.
                if bytes[end] == carriageReturn, start < bytes.count, bytes[start] == lineFeed { start += 1 }
            }
            return found
        }
    }

    /// The ids whose token, `[[attachment:<id>]]`, appears anywhere in `text`: on a line of its own, in the middle of a
    /// sentence, inside a fenced block. This is what keeps a stored file (``AttachmentStore``), and it reads wider than
    /// ``ids(in:)`` on purpose: a line that holds the token and more is text, not an attachment, but it can become one
    /// again with one edit, and the file must still be there when it does. Reading wider can only ever keep a file.
    public static func referencedIDs(in text: String) -> Set<AttachmentID> {
        let openingBracket: UInt8 = 0x5B
        var text = text
        return text.withUTF8 { bytes in
            var found: Set<AttachmentID> = []
            let lastStart = bytes.count - lineLength
            var index = 0
            while index <= lastStart {
                if bytes[index] == openingBracket, bytes[index + 1] == openingBracket,
                    let id = parse(UnsafeBufferPointer(rebasing: bytes[index..<index + lineLength]))
                {
                    found.insert(id)
                    index += lineLength
                } else {
                    index += 1
                }
            }
            return found
        }
    }

    /// The token lines that `range` touches, in order, with their ids. Each range is in UTF-16 units, as `NSTextStorage`
    /// counts, and holds the token without its line break.
    ///
    /// A token is touched when `range` has at least one character of it. A range that is empty (a caret) touches the
    /// token whose line it is on: inside it, and at either edge of it. A range that holds only a line break next to a
    /// token touches nothing. A range that reaches past the text is cut to the text.
    public static func lineRanges(in text: NSString, within range: NSRange) -> [(NSRange, AttachmentID)] {
        let length = text.length
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0, range.location <= length else {
            return []
        }
        let upperBound = range.length > length - range.location ? length : range.location + range.length

        // Widen the scan to whole lines. A line is bounded by the core's line breaks, which are not NSString's own.
        var scanStart = range.location
        while scanStart > 0, !isLineBreak(text.character(at: scanStart - 1)) { scanStart -= 1 }
        var scanEnd = upperBound
        while scanEnd < length, !isLineBreak(text.character(at: scanEnd)) { scanEnd += 1 }

        var units = [unichar](repeating: 0, count: scanEnd - scanStart)
        text.getCharacters(&units, range: NSRange(location: scanStart, length: scanEnd - scanStart))

        var found: [(NSRange, AttachmentID)] = []
        var start = 0
        while start <= units.count {
            var end = start
            while end < units.count, !isLineBreak(units[end]) { end += 1 }
            if end - start == lineLength {
                let lineStart = scanStart + start
                let touched =
                    range.length == 0
                    ? range.location >= lineStart && range.location <= lineStart + lineLength
                    : range.location < lineStart + lineLength && upperBound > lineStart
                if touched, let id = parse(units[start..<end]) {
                    found.append((NSRange(location: lineStart, length: lineLength), id))
                }
            }
            guard end < units.count else { break }
            start = end + 1
            if units[end] == 0x0D, start < units.count, units[start] == 0x0A { start += 1 }
        }
        return found
    }

    private static func isLineBreak(_ unit: UInt16) -> Bool {
        unit == 0x0A || unit == 0x0D
    }

    /// The id in `units`, which are the UTF-8 bytes or the UTF-16 units of a whole line, when they are a token.
    private static func parse<Units: RandomAccessCollection>(_ units: Units) -> AttachmentID?
    where Units.Element: UnsignedInteger {
        guard units.count == lineLength else { return nil }
        var index = units.startIndex
        for expected in prefix {
            guard units[index] == Units.Element(expected) else { return nil }
            index = units.index(after: index)
        }
        var id: [UInt8] = []
        id.reserveCapacity(idLength)
        for position in 0..<idLength {
            let unit = units[index]
            index = units.index(after: index)
            guard unit < 0x80 else { return nil }
            let byte = UInt8(truncatingIfNeeded: unit)
            let isDash = position == 8 || position == 13 || position == 18 || position == 23
            let isLowercaseHex = (0x30...0x39).contains(byte) || (0x61...0x66).contains(byte)
            guard isDash ? byte == 0x2D : isLowercaseHex else { return nil }
            id.append(byte)
        }
        for expected in suffix {
            guard units[index] == Units.Element(expected) else { return nil }
            index = units.index(after: index)
        }
        return AttachmentID(rawValue: String(decoding: id, as: UTF8.self))
    }
}
