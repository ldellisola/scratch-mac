import Foundation

/// A note's identity: a lowercase UUID string. Stored as plain TEXT, encoded as a bare JSON string.
public struct NoteID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func make() -> NoteID {
        NoteID(rawValue: UUID().uuidString.lowercased())
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One scratch note: an optional title and a plain-text body (spec §6.4).
///
/// Dates are plain values. The stores decide when they change.
public struct Note: Equatable, Sendable {
    /// Longest `preview`, in `Character`s.
    public static let previewLimit = 120

    public let id: NoteID
    public var title: String
    public var body: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var pinnedAt: Date?
    public var deletedAt: Date?

    public init(
        id: NoteID,
        title: String,
        body: String,
        createdAt: Date,
        modifiedAt: Date,
        pinnedAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.pinnedAt = pinnedAt
        self.deletedAt = deletedAt
    }

    /// True when the note has neither a title nor any text beyond whitespace.
    public var isEmpty: Bool {
        !hasTitle && !body.contains { !$0.isWhitespace }
    }

    /// True when the user typed a title. Untitled notes show their first non-empty line instead.
    public var hasTitle: Bool {
        title.contains { !$0.isWhitespace }
    }

    /// The trimmed title, or else the first line of the body that has words in it, or else "".
    /// Sidebar rows and tabs show this (spec §6.2, §6.3). A blank line, a fence line (three backticks), an
    /// attachment line (`[[attachment:<id>]]`) and a line of markers alone (`- `, `[ ] `, `****`) are not words: a note
    /// that has only those has no title, and its row and tab say "Untitled" (docs/features/sidebar.md).
    ///
    /// A body line is shown as the editor shows it outside a fenced block, without its list marker, its `**` or its
    /// backticks (``PlainLine``), and as typed inside one. The title the owner typed is shown as typed.
    public var displayTitle: String {
        let trimmedTitle = title[...].trimmed
        if !trimmedTitle.isEmpty { return String(trimmedTitle) }
        var firstLine = ""
        forEachTextLine(in: body) { line in
            firstLine = String(line)
            return false
        }
        return firstLine
    }

    /// The text after the title line, with blank lines, fence lines, attachment lines and lines of markers alone dropped
    /// and the rest, each without its markers like ``displayTitle``, joined by single spaces, capped at ``previewLimit``
    /// characters. For an untitled note the first line with words in it is the title, so the preview starts at the line
    /// after it.
    public var preview: String {
        var skipFirstLine = !hasTitle
        var text = ""
        forEachTextLine(in: body) { line in
            if skipFirstLine {
                skipFirstLine = false
                return true
            }
            if !text.isEmpty {
                guard text.count + 1 < Self.previewLimit else { return false }
                text.append(" ")
            }
            text.append(contentsOf: line.prefix(Self.previewLimit - text.count))
            return text.count < Self.previewLimit
        }
        return text
    }
}

/// Calls `visit` with each line of `text` that has words in it, as the editor shows it and trimmed of white space, until
/// `visit` returns false. A line has none when it is blank, a fence line (``FenceScanner/isFenceLine(_:)``), an
/// attachment line (``AttachmentToken/id(inLine:)``) or only markers (``PlainLine``). A fence or an attachment line is
/// judged as the line was typed, before it is trimmed.
///
/// Outside a fenced block a line loses its markers (``PlainLine/text(of:)``), and inside one it is as typed. The blocks
/// are the ones ``FenceScanner/codeBlocks(in:)`` finds: fences pair from the top, so a fence with no partner after it is
/// no block and the lines after it are outside one (``hasFenceLine(from:in:)`` looks for the partner). An attachment line
/// is skipped inside a block too, as it was before blocks were told apart: it is a line with no words either way.
///
/// Lines end at `\n`, `\r\n` or `\r`. The scan is lazy and works on UTF-8, so a multi-megabyte note costs only as much as
/// the lines actually consumed, and the look for a fence's partner, which ends at the next fence line. Notes are saved
/// often, so this must stay cheap.
private func forEachTextLine(in text: String, _ visit: (Substring) -> Bool) {
    let utf8 = text.utf8
    var start = utf8.startIndex
    var isInBlock = false
    while start < utf8.endIndex {
        let end = utf8[start...].firstIndex { $0 == 0x0A || $0 == 0x0D } ?? utf8.endIndex
        let typed = text[start..<end]
        let next = nextLineStart(after: end, in: text)
        switch structure(of: typed) {
        case .fence:
            // A fence closes the block it is in, and otherwise opens one when another fence follows.
            isInBlock = isInBlock ? false : hasFenceLine(from: next, in: text)
        case .attachment:
            break
        case .words:
            let line = (isInBlock ? typed : PlainLine.text(of: typed)).trimmed
            if !line.isEmpty && !visit(line) { return }
        }
        guard end < utf8.endIndex else { return }
        start = next
    }
}

/// Where the line that follows the one that ends at `end` starts. "\r\n" is one terminator, and a line never starts
/// inside it (it is a single `Character`).
private func nextLineStart(after end: String.Index, in text: String) -> String.Index {
    let utf8 = text.utf8
    guard end < utf8.endIndex else { return end }
    var next = utf8.index(after: end)
    if utf8[end] == 0x0D, next < utf8.endIndex, utf8[next] == 0x0A { next = utf8.index(after: next) }
    return next
}

/// True when a line from `start` on, which is the start of a line, is a fence line: the partner of the opening fence
/// before it. A note that starts with a fence and has none after it, or a long block, makes this read to the end of the
/// note, so the bytes are searched for backticks with `memchr` and only a line that has three in a row is looked at.
private func hasFenceLine(from start: String.Index, in text: String) -> Bool {
    let offset = text.utf8.distance(from: text.utf8.startIndex, to: start)
    var contiguous = text  // shares the storage of a native string, which is what a note's body is
    return contiguous.withUTF8 { containsFenceLine(in: $0, from: offset) }
}

/// ``hasFenceLine(from:in:)`` over the bytes of a string: a run of three backticks or more that has only spaces before it
/// on its line, from the line that starts at `lineStart`.
private func containsFenceLine(in bytes: UnsafeBufferPointer<UInt8>, from lineStart: Int) -> Bool {
    let backtick: UInt8 = 0x60
    guard let base = bytes.baseAddress else { return false }
    var index = lineStart
    while index < bytes.count {
        guard let hit = memchr(base + index, Int32(backtick), bytes.count - index) else { return false }
        let runStart = UnsafeRawPointer(base).distance(to: UnsafeRawPointer(hit))
        var runEnd = runStart
        while runEnd < bytes.count, bytes[runEnd] == backtick { runEnd += 1 }
        if runEnd - runStart >= 3 {
            var first = runStart
            while first > lineStart, bytes[first - 1] == 0x20 { first -= 1 }
            if first == lineStart || bytes[first - 1] == 0x0A || bytes[first - 1] == 0x0D { return true }
        }
        index = runEnd
    }
    return false
}

private enum LineStructure {
    case fence
    case attachment
    case words
}

/// Whether a line is a fence line, an attachment line or neither, as typed (with its leading spaces). Most lines are
/// neither, and the first character settles that, so the scans only run for a line that starts like one.
private func structure(of line: Substring) -> LineStructure {
    switch line.utf8.first(where: { $0 != 0x20 }) {
    case 0x60?: FenceScanner.isFenceLine(String(line)) ? .fence : .words  // a backtick
    case 0x5B?: AttachmentToken.id(inLine: line) != nil ? .attachment : .words  // an opening bracket
    default: .words
    }
}

extension Substring {
    /// The substring without leading and trailing whitespace. Only scans the whitespace it removes.
    fileprivate var trimmed: Substring {
        guard let first = firstIndex(where: { !$0.isWhitespace }),
            let last = lastIndex(where: { !$0.isWhitespace })
        else { return self[endIndex...] }
        return self[first...last]
    }
}
