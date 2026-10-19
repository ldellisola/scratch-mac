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

    /// The trimmed title, or else the first non-empty line of the body, or else "".
    /// Sidebar rows and tabs show this (spec §6.2, §6.3).
    public var displayTitle: String {
        let trimmedTitle = title[...].trimmed
        if !trimmedTitle.isEmpty { return String(trimmedTitle) }
        var firstLine = ""
        forEachNonBlankLine(in: body) { line in
            firstLine = String(line)
            return false
        }
        return firstLine
    }

    /// The text after the title line, with blank lines dropped and the rest joined by single spaces,
    /// capped at ``previewLimit`` characters. For an untitled note the first non-empty line is the
    /// title, so the preview starts at the line after it.
    public var preview: String {
        var skipFirstLine = !hasTitle
        var text = ""
        forEachNonBlankLine(in: body) { line in
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

/// Calls `visit` with each non-blank line of `text`, trimmed of whitespace, until `visit` returns false.
///
/// Lines end at `\n`, `\r\n` or `\r`. The scan is lazy and works on UTF-8, so a multi-megabyte note costs
/// only as much as the lines actually consumed. Notes are saved often, so this must stay cheap.
private func forEachNonBlankLine(in text: String, _ visit: (Substring) -> Bool) {
    let utf8 = text.utf8
    var start = utf8.startIndex
    while start < utf8.endIndex {
        let end = utf8[start...].firstIndex { $0 == 0x0A || $0 == 0x0D } ?? utf8.endIndex
        let line = text[start..<end].trimmed
        if !line.isEmpty && !visit(line) { return }
        guard end < utf8.endIndex else { return }
        start = utf8.index(after: end)
        // Treat "\r\n" as one terminator. It is a single Character, so never start a line inside it.
        if utf8[end] == 0x0D, start < utf8.endIndex, utf8[start] == 0x0A {
            start = utf8.index(after: start)
        }
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
