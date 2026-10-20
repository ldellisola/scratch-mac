import Foundation

/// What a run of a note's text is rendered as (spec §6.4).
public enum MarkupKind: Equatable, Sendable {
    /// `- ` at the start of a line. `level` is the number of leading spaces divided by two.
    case bullet(level: Int)
    /// `[ ] `, `[x] ` or `[X] ` at the start of a line.
    case checkbox(checked: Bool, level: Int)
    /// `**text**`.
    case bold
    /// `` `text` ``.
    case inlineCode
    /// An `http://` or `https://` URL.
    case link(URL)
}

/// One piece of formatting found in a note, with its place in the text.
///
/// Every range is in UTF-16 units of the document, which is how `NSTextStorage` counts, so the editor applies a
/// span's ranges without converting them. The note's text is never changed: a span only says what to draw.
public struct MarkupSpan: Equatable, Sendable {
    public let kind: MarkupKind
    /// A bullet or checkbox: the line without its line break. Bold and inline code: the run with its markers. A
    /// link: the URL.
    public let range: NSRange
    /// A bullet: the `-`. A checkbox: the `[?]`. Bold: both `**`. Inline code: both backticks. A link: none.
    public let markers: [NSRange]
    /// A bullet or checkbox: the text after the marker's space. Bold and inline code: what is between the markers. A
    /// link: the URL.
    public let content: NSRange

    public init(kind: MarkupKind, range: NSRange, markers: [NSRange], content: NSRange) {
        self.kind = kind
        self.range = range
        self.markers = markers
        self.content = content
    }
}
