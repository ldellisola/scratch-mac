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
    /// Sidebar rows and tabs show this (spec §6.2, §6.3). A blank line, a fence line (three backticks) and an
    /// attachment line (`[[attachment:<id>]]`) are not words: a note that has only those has no title, and its row
    /// and tab say "Untitled" (docs/features/sidebar.md).
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

    /// The text after the title line, with blank lines, fence lines and attachment lines dropped and the rest joined by
    /// single spaces, capped at ``previewLimit`` characters. For an untitled note the first line with words in it is
    /// the title, so the preview starts at the line after it.
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

/// Calls `visit` with each line of `text` that has words in it, trimmed of whitespace, until `visit` returns false.
/// A line has none when it is blank, a fence line (``FenceScanner/isFenceLine(_:)``) or an attachment line
/// (``AttachmentToken/id(inLine:)``), which is judged as the line was typed, before it is trimmed.
///
/// Lines end at `\n`, `\r\n` or `\r`. The scan is lazy and works on UTF-8, so a multi-megabyte note costs
/// only as much as the lines actually consumed. Notes are saved often, so this must stay cheap.
private func forEachTextLine(in text: String, _ visit: (Substring) -> Bool) {
    let utf8 = text.utf8
    var start = utf8.startIndex
    while start < utf8.endIndex {
        let end = utf8[start...].firstIndex { $0 == 0x0A || $0 == 0x0D } ?? utf8.endIndex
        let typed = text[start..<end]
        let line = typed.trimmed
        if !line.isEmpty && !isStructureLine(typed) && !visit(line) { return }
        guard end < utf8.endIndex else { return }
        start = utf8.index(after: end)
        // Treat "\r\n" as one terminator. It is a single Character, so never start a line inside it.
        if utf8[end] == 0x0D, start < utf8.endIndex, utf8[start] == 0x0A {
            start = utf8.index(after: start)
        }
    }
}

/// True for a fence line or an attachment line, as typed (with its leading spaces). Most lines are neither, and the
/// first character settles that, so the scans only run for a line that starts like one.
private func isStructureLine(_ line: Substring) -> Bool {
    switch line.utf8.first(where: { $0 != 0x20 }) {
    case 0x60?: FenceScanner.isFenceLine(String(line))  // a backtick
    case 0x5B?: AttachmentToken.id(inLine: line) != nil  // an opening bracket
    default: false
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
